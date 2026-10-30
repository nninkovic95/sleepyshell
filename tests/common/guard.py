#!/usr/bin/env python3
"""guard.py snapshot NAME | verify NAME | targets

The checksum guard: proof that a test run changed none of the user's real files. `snapshot` records a
sha256 of every file under the targets before a run, `verify` compares after it, lists every file that
was added, removed or changed, and exits 1 when there is one. `targets` prints what is watched.

The targets are every real place a sleepyshell test could reach if a sandbox patch were missing: the
live shell with its settings file, the Hyprland config (keybinds, monitors, hypridle, night light), the
matugen config and the colours it renders, the folder-colour icon overlay and the default apps list.
All of them are found from the XDG variables (with the standard fallbacks), never a fixed home folder,
so the kit runs on any machine. Snapshots go to RUN/guard/NAME.json. Reads only, apart from that file."""
import hashlib
import json
import os
import sys
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state")
DATA = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
KIT = Path(__file__).resolve().parent.parent
OUT = KIT / "run" / "guard"

TARGETS = [
    CONFIG / "quickshell" / "sleepyshell",
    CONFIG / "hypr",
    CONFIG / "matugen",
    STATE / "quickshell" / "colors.json",
    DATA / "icons" / "Sleepytheme-Folders",
    CONFIG / "mimeapps.list",
]
# the repository's folders inside the shell folder (same list as REPO_DIRS in env.sh): the kit writes
# under tests/ and git under .git/, so neither can count as a real file a test touched
SKIP_DIRS = {".git", "tests", "docs", "__pycache__"}


def sums():
    out = {}
    for t in TARGETS:
        if t.is_file():
            out[str(t)] = digest(t)
        elif t.is_dir():
            for p in sorted(t.rglob("*")):
                if p.is_file() and not p.is_symlink() and not (SKIP_DIRS & set(p.relative_to(t).parts)):
                    out[str(p)] = digest(p)
    return out


def digest(p):
    try:
        return hashlib.sha256(p.read_bytes()).hexdigest()
    except OSError as e:
        return "unreadable: " + e.strerror


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("snapshot", "verify", "targets"):
        sys.exit(__doc__.split("\n\n")[0])
    if sys.argv[1] == "targets":
        for t in TARGETS:
            print(t, "" if t.exists() else "(missing)")
        return
    name = sys.argv[2] if len(sys.argv) > 2 else "run"
    snap = OUT / (name + ".json")
    if sys.argv[1] == "snapshot":
        OUT.mkdir(parents=True, exist_ok=True)
        s = sums()
        snap.write_text(json.dumps(s, indent=0))
        print(f"guard: snapshot {name}, {len(s)} files")
        return
    if not snap.is_file():
        sys.exit(f"guard: no snapshot named {name}")
    before, after = json.loads(snap.read_text()), sums()
    added = sorted(set(after) - set(before))
    removed = sorted(set(before) - set(after))
    changed = sorted(k for k in before.keys() & after.keys() if before[k] != after[k])
    for label, items in (("added", added), ("removed", removed), ("changed", changed)):
        for k in items:
            print(f"guard: {label} {k}")
    n = len(added) + len(removed) + len(changed)
    print(f"guard: {len(before)} files checked, {n} differ" + ("" if n == 0 else " (a test touched a real file)"))
    sys.exit(1 if n else 0)


if __name__ == "__main__":
    main()
