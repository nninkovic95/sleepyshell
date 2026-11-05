#!/bin/bash
# settings/broken-file.sh [TREE]: while sleepysettings.toml does not parse, nothing is applied from the defaults.
#
# Tier 2 (a broken desktop): with a syntax error in the settings file, Apply on the Idle or Theme tab (and the bar's
# rewrite on a change of power source, the wallpaper picker and timer) ran the scripts, which read the file as empty
# and wrote hypridle.conf and the theme from the default values. In one sandbox, with every outside program stubbed:
# idle.py, theme.py and appearance.py must refuse a broken file (exit 9) and change nothing, tell the user (a
# notification, except for --print and for appearance.py, which answers the window), and still work with a valid
# file; idle.py --find and theme.py --list-presets still answer. The bar (Settings, PowerActions; offscreen) must not
# run idle.py while its file is broken and must say why once per kind of action.
# Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
NAME=broken-file-$$
D=$RUN/$NAME
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT

python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
copy_tree "$TREE" "$D/s"
rm -f "$D"/s/sleepysettings.toml* "$D"/s/settings.json*
cp "$KIT/settings/broken-harness.qml" "$D/s/"
# the mistake is on line 3; the valid file sets values the defaults do not have
printf '[idle]\nidleDimMin = 7\nidleLockMin = = 12\n' >"$D/bad.toml"
printf '[idle]\nidleDimMin = 7\n\n[theme]\nwallpaperDir = "%s/walls"\n' "$D" >"$D/good.toml"
printf '[config]\n' >"$D/matugen.toml"
python3 -I -c 'import struct,sys,zlib
def c(t,d): return struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d))
raw=b"".join(b"\0"+b"\x30\x60\x90\xff"*2 for _ in range(2))
open(sys.argv[1],"wb").write(b"\x89PNG\r\n\x1a\n"+c(b"IHDR",struct.pack(">IIBBBBB",2,2,8,6,0,0,0))+c(b"IDAT",zlib.compress(raw))+c(b"IEND",b""))' "$D/pic.png"

timeout 150 bash "$KIT/common/sandbox.sh" "$D" bash "$KIT/settings/broken-file-inner.sh" "$D"

python3 -I - "$D" <<'CHECK_BROKEN_FILE_PY'
import json, sys
from pathlib import Path
D = Path(sys.argv[1])
fails = 0
def check(ok, what, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or not detail else f": {detail}"))
    fails += 0 if ok else 1
codes = dict(l.split() for l in (D / "cases.txt").read_text().splitlines()) if (D / "cases.txt").exists() else {}
def calls(case):
    f = D / f"calls-{case}.log"
    return [l.split()[0] for l in f.read_text().splitlines()] if f.exists() else None
def out(case, ext="out"):
    f = D / f"{case}.{ext}"
    return f.read_text(errors="replace") if f.exists() else ""

for case in ("idle-apply", "idle-background"):
    check(codes.get(case) == "9" and calls(case) == ["notify-send"], f"idle.py ({case}) refuses the broken file and says why in a notification",
          f"exit {codes.get(case)}, calls {calls(case)}, stderr {out(case, 'err')[-200:]!r}")
check(codes.get("idle-print") == "9" and out("idle-print").strip() == "" and calls("idle-print") == [],
      "idle.py --print refuses quietly (its output is what the window shows)", f"exit {codes.get('idle-print')}, out {out('idle-print')[:80]!r}, calls {calls('idle-print')}")
before = (D / "conf-before.sha").read_text().split()[0] if (D / "conf-before.sha").exists() else "?"
after = (D / "conf-after-bad.sha").read_text().split()[0] if (D / "conf-after-bad.sha").exists() else "!"
check(before == after, "hypridle.conf is unchanged after the refused runs")
try:
    found = json.loads(out("idle-find"))
except ValueError:
    found = None
check(codes.get("idle-find") == "0" and found is not None, "idle.py --find still answers", f"exit {codes.get('idle-find')}, out {out('idle-find')[:120]!r}")
good = (D / "conf-after-good").read_text() if (D / "conf-after-good").exists() else ""
check(codes.get("idle-good") == "0" and "timeout = 420" in good, "idle.py still writes from a valid file (control)", f"exit {codes.get('idle-good')}")

for case in ("theme-auto", "theme-pick", "theme-preset"):
    check(codes.get(case) == "9" and calls(case) == ["notify-send"], f"theme.py ({case}) refuses the broken file, runs nothing, says why",
          f"exit {codes.get(case)}, calls {calls(case)}, stderr {out(case, 'err')[-200:]!r}")
check(codes.get("theme-list") == "0", "theme.py --list-presets still answers", f"exit {codes.get('theme-list')}")
gc = calls("theme-good") or []
check(any(c in gc for c in ("awww", "swww", "matugen", "magick")), "theme.py still runs from a valid file (control)", f"calls {gc}")
try:
    app = json.loads(out("appearance"))
except ValueError:
    app = None
check(codes.get("appearance") == "9" and app is not None and app.get("ok") is False and "mistake" in " ".join(app.get("errors", []))
      and calls("appearance") == [], "appearance.py apply refuses with a plain error and runs nothing",
      f"exit {codes.get('appearance')}, out {out('appearance')[:200]!r}, calls {calls('appearance')}")

log = (D / "bar.log").read_text(errors="replace") if (D / "bar.log").exists() else ""
line = next((l for l in log.splitlines() if "RESULT {" in l), None)
r = json.loads(line[line.index("RESULT {") + 7:]) if line else None
check(r is not None and r["broken"] and r["line"] == 3, "the bar sees the broken file and its line", f"{r}" if r else "\n".join(log.splitlines()[-10:]))
if r:
    check(not r["wallpaper1"] and not r["wallpaper2"] and not r["power"], "the bar runs no script while the file is broken", f"{r}")
    check("line 3" in r["note"] and "default settings" in r["note"], "the reason names the line, in plain words", r["note"])
bar = calls("bar") or []
check("idle.py" not in bar, "the power-source rewrite did not run idle.py", f"calls {bar}")
check(bar.count("notify-send") == 2, "one notification per kind of action (wallpaper once, power source once)", f"calls {bar}")
sys.exit(1 if fails else 0)
CHECK_BROKEN_FILE_PY
rc=$?

if python3 -I "$KIT/common/guard.py" verify "$NAME" >/dev/null; then
    echo "PASS no real file changed"
else
    echo "FAIL a real file changed:"
    python3 -I "$KIT/common/guard.py" verify "$NAME" | sed 's/^/    /'
    rc=1
fi
trap - EXIT
bash "$KIT/common/cleanup.sh" "$D" >/dev/null && echo "PASS nothing left running, run folder deleted" || { echo "FAIL processes, windows or files left"; rc=1; }
exit $rc
