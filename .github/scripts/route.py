"""Picks the reviewer model and its effort for a push from its diff stats alone (file names and line counts).

The code first sorts the push (survey): the generated icon index, media files, pure renames and pure deletions are
not counted as size; a push of only media and generated files gets no AI review at all (media.py checks the files
instead). What the reviewer reads besides the diff is chosen in context.py.

Fable 5.1 then picks the tier and the effort the push needs. A floor in code lifts the choice to at least Opus
and at least `high` effort when a security-sensitive path changed or a changed file runs commands, writes
files, talks over IPC or asks for privileges; the model's answer can never lower that.
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
# every level each reviewer model accepts (Haiku 5.5, Sonnet 5.5, Opus 5.5 and Fable 5.1 all take low to max)
EFFORTS = ["low", "medium", "high", "xhigh", "max"]
FLOOR_TIER = "opus"
FLOOR_EFFORT = "high"

# files that are written by a script, never by hand: their size says nothing about the push
GENERATED = frozenset({"data/icons.json"})
MEDIA_EXT = (".webp", ".png", ".jpg", ".jpeg", ".gif", ".mp4", ".webm")
DOC_EXT = (".md",)
DOC_FILES = frozenset({"LICENSE"})
DOC_DIRS = ("gallery/", "docs/")

SCHEMA = {
    "type": "object",
    "properties": {
        "tier": {"type": "string", "enum": TIERS},
        "effort": {"type": "string", "enum": EFFORTS},
        "reason": {"type": "string"},
    },
    "required": ["tier", "effort", "reason"],
    "additionalProperties": False,
}


def sensitive_lines() -> list[tuple[str, list[str]]]:
    """(heading, patterns) groups of the sensitive-paths file, in its order."""
    if not SENSITIVE_FILE.exists():
        return []
    groups: list[tuple[str, list[str]]] = []
    heading = ""
    for raw in SENSITIVE_FILE.read_text().splitlines():
        line = raw.strip()
        if line.startswith("#"):
            heading = line.lstrip("#").strip()
            continue
        pat = line.split("#", 1)[0].strip()
        if not pat:
            continue
        if groups and groups[-1][0] == heading:
            groups[-1][1].append(pat)
        else:
            groups.append((heading, [pat]))
    return groups


def project_map() -> str:
    # the sensitive part is read from the same file the floor uses, so the prompt and the floor cannot drift apart
    sens = "\n".join(f"- {h}: {', '.join(p)}" for h, p in sensitive_lines())
    return (
        "Security-sensitive or core (from .github/review/sensitive-paths):\n"
        f"{sens}\n"
        "Ordinary: the bar's widgets, islands and popups (sleepybar/), the settings tabs and their components "
        "(sleepysettings/), shared components (components/), Theme.qml.\n"
        "Cosmetic or data: colour themes (themes/), templates (templates/), docs (*.md, gallery/), the test "
        "kit's suites (tests/)."
    )


SYSTEM = f"""You route a code review for sleepyshell, a desktop shell for Hyprland in Quickshell (QML and
JavaScript) with Python and shell scripts. You see the diff statistics of one push: changed file names and
line counts. Pick the reviewer model and its effort.

The project:
{project_map()}

Already left out of the statistics and not counted as size: the generated icon index (data/icons.json),
media files, pure renames and pure deletions. They are named on one line so you know they exist.

Model:
- haiku: trivial pushes such as a typo or a few lines of docs.
- sonnet: ordinary small or medium changes in one area.
- opus: large or cross-cutting changes, anything that touches how the shell runs commands, writes files,
  parses input, talks over its socket or IPC, or handles authentication.
- fable: very complex pushes: many subsystems at once, a new socket or IPC surface, authentication or
  installer changes, or roughly 3,000 or more changed lines of code.
Pick the model this push needs, no higher and no lower. A push that changes only tests or only docs is
judged by what it touches, not by its size.

Effort (how much the reviewer thinks): low, medium, high, xhigh or max. Quality comes first; never lower it
to save money. low or medium only for a trivial push, high for ordinary changes, xhigh for security-sensitive
or complex ones, max when a missed problem would be costly and the change is hard to judge. When unsure
between two effort levels, take the higher.

Security-sensitive changes get at least opus and high effort from a separate check in code, so judge the
push on its own content. Give the reason in two or three sentences."""


@dataclass
class Survey:
    """What the code decides about a push before any API call."""

    rows: list            # every numstat row (added, deleted, name)
    kept: list            # the rows counted as size
    excluded: dict        # reason -> paths left out of the size
    media: list           # media paths present at head (checked by media.py)
    generated: list       # generated paths present at head (checked by media.py)
    kind: str             # "code", "tests-only", "docs-only" or "no-code"
    skip_ai: bool         # only media and generated files: no AI review


@dataclass
class Route:
    model: str
    tier: str
    effort: str
    reason: str
    floor: list[str] = field(default_factory=list)
    router: Result | None = None
    lifted: list[str] = field(default_factory=list)   # what the floor raised ("model", "effort")
    survey: Survey | None = None


def numstat(base: str, head: str) -> list[tuple[str, str, str]]:
    rows = []
    for line in git("diff", "--numstat", "--find-renames", base, head).splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            rows.append((parts[0], parts[1], parts[2]))
    return rows


def statuses(base: str, head: str) -> dict[str, str]:
    """{path at head (the new name for a rename, the old one for a deletion): status} with the rename score,
    e.g. "M", "A", "D", "R100", "R087"."""
    out = git("diff", "--name-status", "-z", "--find-renames", base, head, check=False)
    parts = out.split("\0")
    res: dict[str, str] = {}
    i = 0
    while i < len(parts) and parts[i]:
        st = parts[i]
        if st[:1] in ("R", "C"):
            if i + 2 >= len(parts):
                break
            res[parts[i + 2]] = st
            i += 3
        else:
            if i + 1 >= len(parts):
                break
            res[parts[i + 1]] = st
            i += 2
    return res


def sensitive_patterns() -> list[str]:
    return [p for _, pats in sensitive_lines() for p in pats]


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


def is_media(path: str) -> bool:
    return path.lower().endswith(MEDIA_EXT)


def is_doc(path: str) -> bool:
    return path.endswith(DOC_EXT) or path in DOC_FILES or path.startswith(DOC_DIRS)


def survey(base: str, head: str, rows=None, status=None) -> Survey:
    rows = numstat(base, head) if rows is None else rows
    status = statuses(base, head) if status is None else status
    kept, media, generated = [], [], []
    excluded: dict[str, list[str]] = {"generated": [], "media": [], "renamed": [], "deleted": []}
    paths = []
    for row in rows:
        added, deleted, name = row
        path = _path_of(name)
        paths.append(path)
        st = status.get(path, "M")
        gone = st.startswith("D")
        if path in GENERATED:
            excluded["generated"].append(path)
            if not gone:
                generated.append(path)
        elif is_media(path):
            excluded["media"].append(path)
            if not gone:
                media.append(path)
        elif gone:
            excluded["deleted"].append(path)
        elif st.startswith("R") and added == "0" and deleted == "0":
            excluded["renamed"].append(path)
        else:
            kept.append(row)
    excluded = {k: v for k, v in excluded.items() if v}
    plain = [p for p in paths if p not in GENERATED and not is_media(p)]
    skip_ai = bool(paths) and not plain
    if not plain:
        kind = "no-code"
    elif all(is_doc(p) for p in plain):
        kind = "docs-only"
    elif all(p.startswith("tests/") for p in plain):
        kind = "tests-only"
    else:
        kind = "code"
    return Survey(rows, kept, excluded, media, generated, kind, skip_ai)


def floor_reasons(rows, head: str) -> list[str]:
    """Why this push must get at least Opus and high effort (empty when it need not)."""
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


KIND_TEXT = {
    "code": "",
    "tests-only": "This push changes only the test kit.",
    "docs-only": "This push changes only documentation.",
    "no-code": "This push changes no code.",
}


def excluded_line(sv: Survey) -> str:
    if not sv.excluded:
        return ""
    names = {"generated": "generated", "media": "media", "renamed": "pure renames", "deleted": "pure deletions"}
    parts = []
    for k, paths in sv.excluded.items():
        shown = ", ".join(paths[:12]) + (f" and {len(paths) - 12} more" if len(paths) > 12 else "")
        parts.append(f"{names[k]}: {shown}")
    return "Left out of the size: " + "; ".join(parts) + "."


def stats_text(sv: Survey) -> str:
    rows = sv.kept
    total_add = sum(int(a) for a, _, _ in rows if a.isdigit())
    total_del = sum(int(d) for _, d, _ in rows if d.isdigit())
    lines = [line for line in (KIND_TEXT[sv.kind], excluded_line(sv)) if line]
    lines += [f"{len(rows)} files counted, {total_add} insertions, {total_del} deletions", ""]
    lines += [f"{a:>6} {d:>6}  {name}" for a, d, name in rows]
    return "\n".join(lines)


def decide(cl, base: str, head: str, sv: Survey | None = None) -> Route:
    sv = survey(base, head) if sv is None else sv
    res = call_json(cl, ROUTER_MODEL, "medium", SYSTEM, stats_text(sv), SCHEMA, 16000)
    tier = res.data["tier"]
    effort = res.data.get("effort", FLOOR_EFFORT)
    if effort not in EFFORTS:
        effort = FLOOR_EFFORT
    floor = floor_reasons(sv.rows, head)
    lifted = []
    if floor and TIERS.index(tier) < TIERS.index(FLOOR_TIER):
        tier = FLOOR_TIER
        lifted.append("model")
    if floor and EFFORTS.index(effort) < EFFORTS.index(FLOOR_EFFORT):
        effort = FLOOR_EFFORT
        lifted.append("effort")
    return Route(MODELS[tier], tier, effort, res.data["reason"], floor, res, lifted, sv)


def summary_md(route: Route) -> str:
    lines = [
        f"**Reviewer:** `{route.model}` at effort `{route.effort}` (router: `{ROUTER_MODEL}`)",
        "",
        f"**Router's reason:** {route.reason}",
    ]
    if route.floor:
        shown = "; ".join(route.floor[:8]) + (f"; and {len(route.floor) - 8} more" if len(route.floor) > 8 else "")
        raised = f" (raised the {' and the '.join(route.lifted)})" if route.lifted else ""
        lines.append(f"\n**Floor applies** (at least `{FLOOR_TIER}`, effort `{FLOOR_EFFORT}`){raised}: {shown}")
    if route.survey and route.survey.excluded:
        lines.append(f"\n{excluded_line(route.survey)}")
    if route.router:
        lines.append(f"\nRouter usage: {route.router.usage_line()}")
    return "\n".join(lines)
