#!/usr/bin/env python3
"""treediff.py SOURCE TARGET [KNOWN]: what copying the SOURCE shell tree over TARGET would change, as JSON.
treediff.py --files TREE: the shell files of TREE, one path per line (what a deploy puts in place).

  {"new": [...], "changed": [...], "removed": [...], "unknown": [...]}   paths relative to the tree root, sorted

new: in SOURCE only. changed: in both, different bytes. removed: in TARGET only and a known shell file (listed in the
file KNOWN, one path per line: what git tracks in the live checkout or an earlier deploy put in place), so the
candidate dropped it. unknown: in TARGET only and not known: never removed, only reported (the live tree is the
repository checkout, which holds files that are not the shell's). Without KNOWN nothing is removable. Never listed:
the user's state files (sleepysettings.toml, settings.json and their copies) and the repository's own files (.git,
.github/, .claude/, tests/, docs/, gallery/, assets/, tools/, __pycache__ and the root documents; the same lists as
REPO_DIRS/REPO_FILES in env.sh). Reads only."""
import fnmatch
import json
import sys
from pathlib import Path

STATE = ["sleepysettings.toml", "sleepysettings.toml.*", "settings.json", "settings.json.*"]
SKIP_DIRS = {".git", ".github", ".claude", "tests", "docs", "gallery", "assets", "tools", "__pycache__"}
REPO_FILES = {"README.md", "TASKS.md", "LICENSE", "SECURITY.md", "CLAUDE.md", "CLAUDE.local.md", ".gitignore",
              "install.sh", ".worktreeinclude"}


def files(root):
    out = {}
    for p in root.rglob("*"):
        if not p.is_file() or p.is_symlink():
            continue
        rel = p.relative_to(root)
        if SKIP_DIRS & set(rel.parts):
            continue
        if len(rel.parts) == 1 and (rel.name in REPO_FILES or any(fnmatch.fnmatch(rel.name, g) for g in STATE)):
            continue
        out[str(rel)] = p
    return out


def diff(src, dst, known):
    a, b = files(src), files(dst)
    only = sorted(k for k in b if k not in a)
    return {
        "new": sorted(k for k in a if k not in b),
        "changed": sorted(k for k in a if k in b and a[k].read_bytes() != b[k].read_bytes()),
        "removed": [k for k in only if k in known],
        "unknown": [k for k in only if k not in known],
    }


def tree(arg):
    d = Path(arg).resolve()
    if not (d / "shell.qml").is_file():
        sys.exit(f"treediff: {d} is not a sleepyshell tree (no shell.qml)")
    return d


if __name__ == "__main__":
    if sys.argv[1] == "--files":
        print("\n".join(sorted(files(tree(sys.argv[2])))))
        sys.exit(0)
    src, dst = tree(sys.argv[1]), tree(sys.argv[2])
    known = set()
    if len(sys.argv) > 3:
        known = {ln.strip() for ln in open(sys.argv[3]) if ln.strip()}
    print(json.dumps(diff(src, dst, known), indent=1))
