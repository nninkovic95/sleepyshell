#!/bin/bash
# settings/keyreport-writer.test.sh [TREE]: the writer of the key reporter's line refuses whatever it cannot do safely.
#
# Tier 1 (hyprland.lua changed without a yes, or damaged): hyprconf.py add-keyreport, in the sandbox, on scratch
# configs. A hash other than the shown line's writes nothing (exit 6); a hyprland.conf is refused; a hyprland.lua whose
# string does not close is refused and left alone; a commented-out loader line does not count as loaded; a second add
# changes nothing; a link to the main file is written through, the link kept. The window's side (the question, the
# line shown, Cancel) is checked by settings/shell-shortcuts.test.py. Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
NAME=keyreport-writer-$$
D=$RUN/$NAME
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT
python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
mkdir -p "$D/s/scripts" "$D/s/data"
cp "$TREE/scripts/hyprconf.py" "$D/s/scripts/"
cp "$TREE/data/keyreport.lua" "$D/s/data/"

timeout 60 bash "$KIT/common/sandbox.sh" "$D" python3 -I - "$D" <<'KEYREPORT_WRITER_PY'
import json, os, subprocess, sys
from pathlib import Path
D = Path(sys.argv[1])
H = D / "s/scripts/hyprconf.py"
fails = 0
def check(ok, what, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or not detail else f": {detail}"))
    fails += 0 if ok else 1
def run(*args):
    r = subprocess.run([sys.executable, "-I", str(H), *args], capture_output=True, text=True)
    try:
        return r.returncode, json.loads(r.stdout)
    except ValueError:
        return r.returncode, {"raw": r.stdout + r.stderr}
def cfg(name, text, fname="hyprland.lua"):
    d = D / name
    d.mkdir()
    (d / fname).write_text(text)
    return d
baks = lambda d: sorted(p.name for p in d.iterdir() if ".bak-" in p.name)

ok_dir = cfg("ok", "-- mine\nrequire(\"modules.binds\")\n")
code, st = run("keyreport-state", "--root", str(ok_dir))
check(code == 0 and st["line"].startswith("pcall(dofile, ") and st["line"].endswith('data/keyreport.lua")') and not st["loaded"],
      "the state names the line and says it is not loaded", st)
code, r = run("add-keyreport", "--expect", "0" * 64, "--root", str(ok_dir))
check(code == 6 and (ok_dir / "hyprland.lua").read_text() == "-- mine\nrequire(\"modules.binds\")\n" and not baks(ok_dir),
      "another hash writes nothing (exit 6)", f"exit {code}")
code, r = run("add-keyreport", "--expect", st["sha"], "--root", str(ok_dir))
text = (ok_dir / "hyprland.lua").read_text()
check(code == 0 and text == "-- mine\n" + st["line"] + "\nrequire(\"modules.binds\")\n" and len(baks(ok_dir)) == 1,
      "the shown hash adds the line above the first statement, after one backup", text)
code, r = run("add-keyreport", "--expect", st["sha"], "--root", str(ok_dir))
check(code == 0 and r.get("changed") is False and len(baks(ok_dir)) == 1, "a second add changes nothing", r)

conf = cfg("conf", "source = binds.conf\n", "hyprland.conf")
code, st2 = run("keyreport-state", "--root", str(conf))
code, r = run("add-keyreport", "--expect", st2.get("sha", ""), "--root", str(conf))
check(code == 1 and (conf / "hyprland.conf").read_text() == "source = binds.conf\n" and not baks(conf), "a hyprland.conf is refused", r)

broken = cfg("broken", "local x = \"never closed\nrequire(\"modules.binds\")\n")
code, st3 = run("keyreport-state", "--root", str(broken))
code, r = run("add-keyreport", "--expect", st3.get("sha", ""), "--root", str(broken))
check(code == 1 and not baks(broken) and (broken / "hyprland.lua").read_text().startswith("local x"), "a file whose string does not close is refused, untouched", r)

commented = cfg("commented", "-- pcall(dofile, os.getenv(\"HOME\") .. \"/x/data/keyreport.lua\")\nrequire(\"modules.binds\")\n")
code, st4 = run("keyreport-state", "--root", str(commented))
check(code == 0 and st4["loaded"] is False, "a commented-out loader does not count as loaded", st4)

real = cfg("real", "require(\"modules.binds\")\n")
link = D / "linked"
link.mkdir()
os.symlink(real / "hyprland.lua", link / "hyprland.lua")
code, st5 = run("keyreport-state", "--root", str(link))
code, r = run("add-keyreport", "--expect", st5["sha"], "--root", str(link))
check(code == 0 and (link / "hyprland.lua").is_symlink() and st5["line"] in (real / "hyprland.lua").read_text(),
      "a link to hyprland.lua is written through, the link kept", r)
sys.exit(1 if fails else 0)
KEYREPORT_WRITER_PY
rc=$?
if python3 -I "$KIT/common/guard.py" verify "$NAME" >/dev/null; then
    echo "PASS no real file changed"
else
    echo "FAIL a real file changed"
    rc=1
fi
exit $rc
