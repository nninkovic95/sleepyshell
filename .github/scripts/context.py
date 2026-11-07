"""What a later review reads besides the diff: the files it needs to judge the change, not the whole codebase.

The first review (no completed review yet) reads the whole codebase; the weekly audit always does. A later
review gets, chosen here in code with no API call:

1. always: the full text of every changed file, README.md and SECURITY.md (the promises the checklist checks
   against), the test kit's README when the kit changed, and the list of every path;
2. the whole group of a sensitive path that changed (.github/review/sensitive-paths: the socket with its
   window end and the settings parser, the lock files, ...);
3. names in the changed lines that wire things through strings (settings keys, `sleepyshell:` events,
   functions and properties, socket message types) and, in changed docs, what they quote in backticks: the
   files that use or define them;
4. one step out by file name: files that use a changed file (a QML type or singleton by its name, a script or
   JS library by its file name) and files a changed file uses.

Files are ranked in that order. Past CAP_TOKENS the lowest ranks are left out; a selection past FULL_SHARE of
the whole codebase is replaced by the whole codebase (a change that wide deserves the full read, and the
saving would be small). Token sizes here are estimates; the review call counts exactly before it is sent.
"""

from __future__ import annotations

import fnmatch
import re
import subprocess
from dataclasses import dataclass, field

from claude import REPO_ROOT, git

CHARS_PER_TOKEN = 2.5          # this codebase with line numbers, measured against the API's count
CAP_TOKENS = 350_000
FULL_SHARE = 0.5
MAX_USERS = 8                  # a name used by more files than this is too common to follow
MIN_NAME = 5
ALWAYS = ("README.md", "SECURITY.md")
CODE_DIRS_FOR_NAMES = (".qml", ".js", ".py", ".sh", ".lua")

RANKS = ["changed", "always", "group", "name", "doc", "uses", "used-by"]
WHY = {
    "changed": "changed in this push",
    "always": "the promises the review checks against",
    "group": "same sensitive group as a changed file",
    "name": "uses a name the change touches",
    "doc": "named by a changed doc",
    "uses": "used by a changed file",
    "used-by": "uses a changed file",
}


@dataclass
class Selection:
    files: list = field(default_factory=list)      # [(path, rank)] in rank order
    whole: bool = False                            # send the whole codebase instead
    note: str = ""
    left_out: list = field(default_factory=list)   # paths dropped by the cap
    tokens: int = 0                                # estimate of the selected files

    def summary_md(self) -> str:
        if self.whole:
            return f"**Context:** the whole codebase ({self.note})."
        by_rank: dict[str, list[str]] = {}
        for path, rank in self.files:
            by_rank.setdefault(rank, []).append(path)
        lines = [f"**Context:** the diff and {len(self.files)} files (about {self.tokens:,} tokens, estimated):"]
        for rank in RANKS:
            if rank in by_rank:
                shown = ", ".join(f"`{p}`" for p in by_rank[rank][:25])
                more = f" and {len(by_rank[rank]) - 25} more" if len(by_rank[rank]) > 25 else ""
                lines.append(f"- {WHY[rank]}: {shown}{more}")
        if self.left_out:
            lines.append(f"- left out by the size cap: {len(self.left_out)} files")
        return "\n".join(lines)


def texts(rev: str, skip_dirs, skip_files) -> dict[str, str]:
    """{path: text} of every text file of rev outside the skipped folders and files."""
    out = {}
    for path in git("ls-tree", "-r", "--name-only", "--full-tree", rev).splitlines():
        if path in skip_files or path.startswith(tuple(skip_dirs)):
            continue
        raw = subprocess.run(["git", "cat-file", "blob", f"{rev}:{path}"], cwd=REPO_ROOT, capture_output=True).stdout
        if b"\0" in raw[:8192]:
            continue
        try:
            out[path] = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue
    return out


def changed_lines(diff: str) -> dict[str, list[str]]:
    """{path: added and removed lines} from a unified diff."""
    res: dict[str, list[str]] = {}
    cur = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            cur = line[6:]
            res.setdefault(cur, [])
        elif line.startswith("--- a/") and cur is None:
            continue
        elif line.startswith("diff --git"):
            m = re.match(r"diff --git a/(.*) b/(.*)", line)
            cur = m.group(2) if m else None
            if cur:
                res.setdefault(cur, [])
        elif cur and line[:1] in "+-" and not line.startswith(("+++", "---")):
            res[cur].append(line[1:])
    return res


NAME_PATTERNS = [
    re.compile(r"\bfunction\s+([A-Za-z_]\w*)"),
    re.compile(r"\bproperty\s+[\w.<>]+\s+([A-Za-z_]\w*)"),
    re.compile(r"\bsignal\s+([A-Za-z_]\w*)"),
    re.compile(r"^\s*def\s+([A-Za-z_]\w*)"),
    re.compile(r"^\s*([A-Za-z_]\w*)\s*\(\)\s*\{"),                 # sh function
    re.compile(r"^\s*([a-z][A-Za-z0-9]+)\s*:\s*\{\s*tab\s*:"),        # a settings schema key
    re.compile(r"(sleepyshell:[\w:-]+)"),                            # Hyprland custom events
    re.compile(r"""["']type["']\s*:\s*["'](\w+)["']"""),              # socket message types
    re.compile(r"""\btype\s*===?\s*["'](\w+)["']"""),
]


STRING_WIRED = 5   # NAME_PATTERNS from here on (schema keys, events, message types) are followed as found


def distinctive(name: str) -> bool:
    """A name worth searching for: camelCase or snake_case; a plain word ("label", "audio") matches everywhere."""
    return bool(re.search(r"[a-z][A-Z]|_[a-z]", name))


def names_in(lines) -> set[str]:
    found = set()
    for line in lines:
        for i, pat in enumerate(NAME_PATTERNS):
            for m in pat.finditer(line):
                name = m.group(1)
                if len(name) >= MIN_NAME and (i >= STRING_WIRED or distinctive(name)):
                    found.add(name)
    return found


def doc_names(lines) -> set[str]:
    """What changed doc lines quote in backticks: paths, script names, flags, keys, events."""
    found = set()
    for line in lines:
        for q in re.findall(r"`([^`\n]{3,120})`", line):
            for word in re.split(r"[\s=,()\[\]]+", q):
                word = word.strip(".:;'\"")
                if len(word) < MIN_NAME or word.startswith("<") or not re.search(r"[A-Za-z]", word):
                    continue
                # a path or file name, a flag, an event or a distinctive name; a plain word matches everywhere
                if ("/" in word or re.search(r"\.\w{1,4}$", word) or word.startswith("--")
                        or word.startswith("sleepyshell:") or distinctive(word)):
                    found.add(word)
    return found


def users_of(name: str, files: dict[str, str], exclude: set[str]) -> list[str] | None:
    """Files that contain name as a whole word, or None when too many do (a common word)."""
    pat = re.compile(r"(?<![\w-])" + re.escape(name) + r"(?![\w-])")
    hits = [p for p, t in files.items() if p not in exclude and pat.search(t)]
    return None if len(hits) > MAX_USERS else hits


def type_name(path: str) -> str:
    """How other files name this file: a QML type by its stem, anything else by its file name."""
    base = path.rsplit("/", 1)[-1]
    return base[:-4] if base.endswith(".qml") else base


def select(diff: str, changed: list[str], head_files: dict[str, str], sensitive_groups, whole_chars: int,
           tests_changed: bool = False) -> Selection:
    picked: dict[str, str] = {}

    def add(path: str, rank: str):
        if path in head_files and path not in picked:
            picked[path] = rank

    for p in changed:
        add(p, "changed")
    for p in ALWAYS + (("tests/README.md",) if tests_changed else ()):
        add(p, "always")

    for _, pats in sensitive_groups:
        if any(fnmatch.fnmatchcase(c, pat) for c in changed for pat in pats):
            for p in head_files:
                if any(fnmatch.fnmatchcase(p, pat) for pat in pats):
                    add(p, "group")

    lines = changed_lines(diff)
    code_lines = [l for p, ls in lines.items() if p.endswith(CODE_DIRS_FOR_NAMES) for l in ls]
    doc_lines = [l for p, ls in lines.items() if p.endswith(".md") for l in ls]
    for name in sorted(names_in(code_lines)):
        for p in users_of(name, head_files, set(picked)) or []:
            add(p, "name")
    for word in sorted(doc_names(doc_lines)):
        if word in head_files:
            add(word, "doc")
            continue
        for p in users_of(word, {k: v for k, v in head_files.items() if not k.endswith(".md")}, set(picked)) or []:
            add(p, "doc")

    names = {type_name(p): p for p in head_files if p.endswith(CODE_DIRS_FOR_NAMES)}
    # one step out by file name, for code only: a changed doc's own references are its changed lines (above)
    for c in (c for c in changed if c.endswith(CODE_DIRS_FOR_NAMES)):
        text = head_files.get(c, "")
        for name, p in names.items():
            if p != c and len(name) >= 3 and re.search(r"(?<![\w-])" + re.escape(name) + r"(?![\w-])", text):
                add(p, "uses")
        if c.endswith(CODE_DIRS_FOR_NAMES):
            for p in users_of(type_name(c), head_files, set(picked)) or []:
                add(p, "used-by")

    ordered = sorted(picked.items(), key=lambda kv: RANKS.index(kv[1]))
    total = sum(len(head_files[p]) for p, _ in ordered)
    if total > FULL_SHARE * whole_chars:
        return Selection(whole=True, note=f"the change reaches {total * 100 // max(whole_chars, 1)}% of it")
    sel = Selection()
    used = 0
    for path, rank in ordered:
        size = len(head_files[path])
        if rank != "changed" and (used + size) / CHARS_PER_TOKEN > CAP_TOKENS:
            sel.left_out.append(path)
            continue
        sel.files.append((path, rank))
        used += size
    sel.tokens = int(used / CHARS_PER_TOKEN)
    return sel


def dry_run(base: str, head: str) -> Selection:
    """The selection for base..head as a later review would make it; no API call."""
    import route
    from claude import REVIEW_SKIP_DIRS, REVIEW_SKIP_FILES

    sv = route.survey(base, head)
    files = texts(head, REVIEW_SKIP_DIRS, REVIEW_SKIP_FILES)
    gone = set(sv.excluded.get("deleted", []))
    changed = [route._path_of(n) for _, _, n in sv.rows]
    changed = [p for p in changed if p in files and p not in gone]
    diff = git("diff", "-U10", "--find-renames", base, head, "--", ".", ":(exclude)data/icons.json")
    whole = sum(len(t) for t in files.values())
    sel = select(diff, changed, files, route.sensitive_lines(), whole,
                 tests_changed=any(p.startswith("tests/") for p in changed))
    print(sel.summary_md())
    print(f"\ndiff: about {int(len(diff) / CHARS_PER_TOKEN):,} tokens; whole codebase: about "
          f"{int(whole / CHARS_PER_TOKEN):,} tokens (estimates)")
    return sel


def render(paths, files: dict[str, str]) -> str:
    """The chosen files with line numbers, in the codebase's <file> form."""
    parts = []
    for path in paths:
        numbered = "\n".join(f"{i}\t{line}" for i, line in enumerate(files[path].splitlines(), 1))
        parts.append(f'<file path="{path}">\n{numbered}\n</file>')
    return "\n".join(parts)


if __name__ == "__main__":
    import sys

    if len(sys.argv) != 3:
        sys.exit("usage: context.py BASE HEAD   (print what a later review of BASE..HEAD would read)")
    dry_run(sys.argv[1], sys.argv[2])
