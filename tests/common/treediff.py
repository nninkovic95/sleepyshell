#!/usr/bin/env python3
"""treediff.py SOURCE TARGET: what copying the SOURCE shell tree over TARGET would change, as JSON.

  {"new": [...], "changed": [...], "removed": [...]}   paths relative to the tree root, sorted

new: in SOURCE only. changed: in both, different bytes. removed: in TARGET only (a file that moved or
went away in SOURCE). Never listed: the user's state files (sleepysettings.toml, settings.json and
their copies) and the repository's own files (.git, tests/, docs/, __pycache__ and the root documents;
the same lists as REPO_DIRS/REPO_FILES in env.sh). Reads only."""
import fnmatch
import json
import sys
from pathlib import Path

STATE = ["sleepysettings.toml", "sleepysettings.toml.*", "settings.json", "settings.json.*"]
SKIP_DIRS = {".git", "tests", "docs", "__pycache__"}
REPO_FILES = {"README.md", "TASKS.md", "LICENSE", "SECURITY.md", "CLAUDE.md", "CLAUDE.local.md", ".gitignore"}


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


def diff(src, dst):
    a, b = files(src), files(dst)
    return {
        "new": sorted(k for k in a if k not in b),
        "changed": sorted(k for k in a if k in b and a[k].read_bytes() != b[k].read_bytes()),
        "removed": sorted(k for k in b if k not in a),
    }


if __name__ == "__main__":
    src, dst = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    for d in (src, dst):
        if not (d / "shell.qml").is_file():
            sys.exit(f"treediff: {d} is not a sleepyshell tree (no shell.qml)")
    print(json.dumps(diff(src, dst), indent=1))
