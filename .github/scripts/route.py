"""Picks the reviewer model for a push from its diff stats alone (file names and line counts).

Fable 5.1 picks the tier the push needs. A floor in code then lifts the choice to at least Opus when a
security-sensitive path changed or a changed file runs commands, writes files, talks over IPC or asks for
privileges; the model's answer can never lower that.
"""

from __future__ import annotations

import fnmatch
import re
from dataclasses import dataclass, field

from claude import MODELS, REPO_ROOT, TIERS, Result, call_json, git

ROUTER_MODEL = MODELS["fable"]
SENSITIVE_FILE = REPO_ROOT / ".github/review/sensitive-paths"
RISKY = re.compile(
    r"IpcHandler|LocalSocket|SocketServer|\bSocket\s*\{|\bProcess\s*\{|execDetached|startDetached|"
    r"FileView|setText\(|writeAdapter|subprocess|os\.replace|os\.rename|shutil\.|open\([^)]*['\"][wa]|"
    r"\beval\b|\bexec\(|\bsudo\b|\bpkexec\b|polkit|PamContext|>\s*\"?\$|\btee\b|\bmv\b|\brm\b"
)

SCHEMA = {
    "type": "object",
    "properties": {
        "tier": {"type": "string", "enum": TIERS},
        "reason": {"type": "string"},
    },
    "required": ["tier", "reason"],
    "additionalProperties": False,
}

SYSTEM = """You route a code review for sleepyshell, a Quickshell desktop shell for Hyprland (QML, JavaScript,
Python and shell scripts). You see only the diff statistics of one push: changed file names and line
counts. Pick the reviewer model:

- haiku (Claude Haiku 5.5, $0.10/$0.50 per million tokens): trivial pushes such as typo fixes or a few
  lines of docs.
- sonnet (Claude Sonnet 5.5, $2/$10): ordinary small or medium changes in one area.
- opus (Claude Opus 5.5, $4/$20): large or cross-cutting changes, anything that touches how the shell
  runs commands, writes files, parses input, talks over its socket or IPC, or handles authentication.
- fable (Claude Fable 5.1, $10/$50): very complex pushes: many subsystems at once, a new socket or IPC
  surface, authentication or installer changes, or roughly 3,000 or more changed lines of code.

Pick the tier this push needs, no higher and no lower. Security-sensitive files are lifted to at least
opus by a separate check in code, so judge the push on its own content. Explain the reason in two or
three sentences."""


@dataclass
class Route:
    model: str
    tier: str
    reason: str
    floor: list[str] = field(default_factory=list)
    router: Result | None = None


def numstat(base: str, head: str) -> list[tuple[str, str, str]]:
    rows = []
    for line in git("diff", "--numstat", "--find-renames", base, head).splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            rows.append((parts[0], parts[1], parts[2]))
    return rows


def sensitive_patterns() -> list[str]:
    if not SENSITIVE_FILE.exists():
        return []
    pats = []
    for line in SENSITIVE_FILE.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            pats.append(line)
    return pats


def _path_of(name: str) -> str:
    # numstat shows a rename as "dir/{old => new}/file" or "old => new"
    if "=>" not in name:
        return name
    m = re.match(r"(.*)\{(.*) => (.*)\}(.*)", name)
    if m:
        return (m.group(1) + m.group(3) + m.group(4)).replace("//", "/")
    return name.split("=>")[-1].strip()


CODE_EXT = (".qml", ".js", ".mjs", ".py", ".sh", ".bash", ".lua", ".fish", ".zsh", ".desktop", ".service")


def is_code(path: str, blob: str) -> bool:
    """Files whose contents run: code by extension, or any file that starts with a shebang."""
    return path.endswith(CODE_EXT) or blob.startswith("#!")


def floor_reasons(rows, head: str) -> list[str]:
    """Why this push must get at least Opus (empty when it need not)."""
    pats = sensitive_patterns()
    reasons = []
    for _, _, name in rows:
        path = _path_of(name)
        hit = next((p for p in pats if fnmatch.fnmatchcase(path, p)), None)
        if hit:
            reasons.append(f"`{path}` matches sensitive path `{hit}`")
            continue
        blob = git("show", f"{head}:{path}", check=False)
        if not is_code(path, blob):  # prose ("rm", "sudo" in a task list) says nothing about risk
            continue
        m = RISKY.search(blob) if blob else None
        if m:
            reasons.append(f"`{path}` contains `{m.group(0).strip()}`")
    return reasons


def stats_text(rows) -> str:
    total_add = sum(int(a) for a, _, _ in rows if a.isdigit())
    total_del = sum(int(d) for _, d, _ in rows if d.isdigit())
    lines = [f"{len(rows)} files changed, {total_add} insertions, {total_del} deletions", ""]
    lines += [f"{a:>6} {d:>6}  {name}" for a, d, name in rows]
    return "\n".join(lines)


def decide(cl, base: str, head: str) -> Route:
    rows = numstat(base, head)
    res = call_json(cl, ROUTER_MODEL, "medium", SYSTEM, stats_text(rows), SCHEMA, 16000)
    tier = res.data["tier"]
    floor = floor_reasons(rows, head)
    if floor and TIERS.index(tier) < TIERS.index("opus"):
        tier = "opus"
    return Route(MODELS[tier], tier, res.data["reason"], floor, res)


def summary_md(route: Route) -> str:
    lines = [f"**Reviewer:** `{route.model}` (router: `{ROUTER_MODEL}`)", "", f"**Router's reason:** {route.reason}"]
    if route.floor:
        shown = "; ".join(route.floor[:8]) + (f"; and {len(route.floor) - 8} more" if len(route.floor) > 8 else "")
        lines.append(f"\n**Opus floor applies:** {shown}")
    if route.router:
        lines.append(f"\nRouter usage: {route.router.usage_line()}")
    return "\n".join(lines)
