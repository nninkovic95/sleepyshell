#!/bin/bash
# settings/linked-apply.sh [TREE]: an Apply through the bar counts as applied only once the bar saved it.
#
# Tier 2 (data loss): a bar that died while it handled an Apply from the settings window left the change shown as
# applied though it was never written; it was lost on the next start. Two copies of the tree (default: the live
# shell), offscreen in one sandbox. In both the window's end (the real BarLink and Settings) links to a bar, then in
# one go saves barFontSize = 15 at once (Settings.setNow) and Applies barHeight = 33.
#   dies:  a fake bar closes on the first commit without answering. barHeight must stay staged (unapplied), not
#          stored, reported as unsaved, and not be in the file; barFontSize (no draft to keep) must be written by the
#          window itself.
#   saves: the real bar end answers. barHeight must be stored, no longer staged, and both keys in the file.
#   twice: barHeight Applied as 33, then as 34, then staged as 35 without Apply; a fake bar answers only after both
#          Applies came. 34 must be stored and the unapplied 35 must stay staged.
# Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
NAME=linked-apply-$$
D=$RUN/$NAME
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT

python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
for c in c d e; do
    copy_tree "$TREE" "$D/$c"
    rm -f "$D/$c"/sleepysettings.toml* "$D/$c"/settings.json*
    cp "$KIT/settings/bar-harness.qml" "$KIT/settings/link-harness.qml" "$D/$c/"
done

timeout 120 bash "$KIT/common/sandbox.sh" "$D" bash "$KIT/settings/linked-apply-inner.sh" "$D" "$KIT/settings"

python3 -I - "$D" <<'CHECK_LINKED_APPLY_PY'
import json, re, sys
from pathlib import Path
D = Path(sys.argv[1])
fails = 0
def check(ok, what, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or not detail else f": {detail}"))
    fails += 0 if ok else 1
def result(name):
    t = (D / name).read_text(errors="replace") if (D / name).exists() else ""
    line = next((l for l in t.splitlines() if "RESULT {" in l), None)
    return json.loads(line[line.index("RESULT {") + 7:]) if line else None
def value(copy, key):
    f = D / copy / "sleepysettings.toml"
    if not f.exists():
        return None
    m = re.search(rf"^\s*{key}\s*=\s*(\S+)", f.read_text(), re.M)
    return m.group(1) if m else None

c = result("win-c.log")
fake = (D / "fake-bar.log").read_text() if (D / "fake-bar.log").exists() else ""
check(c is not None and c["applied"] and "died" in fake, "dies: the window linked, applied, and the fake bar died on the commit",
      f"result {c}, fake bar log: {fake[-300:]!r}")
if c:
    check(c["pending"].get("barHeight") == 33, "dies: the Apply stays unapplied (still staged)", f"staged {c['pending']}")
    check(c["storedBarHeight"] == 30, "dies: the Apply is not shown as saved", f"stored barHeight {c['storedBarHeight']}")
    check("barHeight" in c["unsaved"] and "barHeight" not in c["committed"], "dies: the tabs are told it was not saved",
          f"unsaved {c['unsaved']}, committed {c['committed']}")
check(value("c", "barHeight") in (None, "30"), "dies: barHeight = 33 is not in the file", f"file has {value('c', 'barHeight')}")
check(value("c", "barFontSize") == "15", "dies: the at-once save (no draft) was written by the window itself",
      f"file has barFontSize {value('c', 'barFontSize')}")

d = result("win-d.log")
check(d is not None and d["applied"] and d["linked"], "saves: the window linked to the real bar end and applied", f"result {d}")
if d:
    check("barHeight" not in d["pending"] and d["storedBarHeight"] == 33, "saves: the Apply counts as applied once the bar answered",
          f"staged {d['pending']}, stored {d['storedBarHeight']}")
    check("barHeight" in d["committed"] and not d["unsaved"], "saves: the tabs are told it was saved",
          f"committed {d['committed']}, unsaved {d['unsaved']}")
check(value("d", "barHeight") == "33" and value("d", "barFontSize") == "15", "saves: the bar wrote both keys",
      f"barHeight {value('d', 'barHeight')}, barFontSize {value('d', 'barFontSize')}")
e = result("win-e.log")
fe = (D / "fake-bar-e.log").read_text() if (D / "fake-bar-e.log").exists() else ""
check(e is not None and e["applied"] and "answered" in fe, "twice: two Applies of one key went out before the bar answered both",
      f"result {e}, fake bar log: {fe[-300:]!r}")
if e:
    check(e["storedBarHeight"] == 34 and e["pending"].get("barHeight") == 35, "twice: the last Apply is stored and the newer draft stays staged",
          f"stored {e['storedBarHeight']}, staged {e['pending']}")
sys.exit(1 if fails else 0)
CHECK_LINKED_APPLY_PY
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
