#!/bin/bash
# settings/socket-per-copy.test.sh [TREE]: each copy of the shell has its own settings socket.
#
# Tier 1 (security): with one fixed socket path, a second copy of the shell (a test copy, a candidate) reached the
# live bar and could change its settings file. Two copies of the tree (default: the live shell) run in one sandbox,
# offscreen: the bar's end (the real SettingsServer) of copy A started through a config-folder link, the window's
# end (the real BarLink) of copy A through the folder itself, and the window's end of copy B. A's window must link
# to A's bar, B's must not, B's bar must use another socket, and nothing may use the old fixed path.
# Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
NAME=socket-per-copy-$$
D=$RUN/$NAME
mkdir -p "$D/home/.config/quickshell"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT

python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
for c in a b; do
    copy_tree "$TREE" "$D/$c"
    rm -f "$D/$c"/sleepysettings.toml* "$D/$c"/settings.json*
    cp "$KIT/settings/bar-harness.qml" "$KIT/settings/link-harness.qml" "$D/$c/"
done
ln -s "$D/a" "$D/home/.config/quickshell/sleepyshell"

timeout 90 bash "$KIT/common/sandbox.sh" "$D" bash "$KIT/settings/socket-per-copy-inner.sh" "$D"

python3 -I - "$D" <<'CHECK_SOCKETS_PY'
import json, re, sys
from pathlib import Path
D = Path(sys.argv[1])
fails = 0
def check(ok, what, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or not detail else f": {detail}"))
    fails += 0 if ok else 1
def sock(name):
    m = re.findall(r"SOCK (\S+)", (D / name).read_text(errors="replace")) if (D / name).exists() else []
    return m[-1] if m else ""
def result(name):
    t = (D / name).read_text(errors="replace") if (D / name).exists() else ""
    line = next((l for l in t.splitlines() if "RESULT {" in l), None)
    return json.loads(line[line.index("RESULT {") + 7:]) if line else None
bar_a, bar_b = sock("bar-a.log"), sock("bar-b.log")
win_a, win_b = result("win-a.log"), result("win-b.log")
check(bar_a != "" and win_a is not None and win_b is not None, "both bars and both windows started",
      f"bar A {bar_a!r}, window A {win_a}, window B {win_b}")
if win_a and win_b and bar_a:
    check(win_a["sock"] == bar_a and win_a["linked"], "copy A's window (opened through the folder) links to copy A's bar (started through the config link)",
          f"window {win_a['sock']} linked={win_a['linked']}, bar {bar_a}")
    check(win_b["sock"] != bar_a and not win_b["linked"], "copy B's window does not reach copy A's bar",
          f"window B {win_b['sock']} linked={win_b['linked']}")
    check(bar_b != "" and bar_b != bar_a and bar_b == win_b["sock"], "copy B's bar uses its own socket, the one B's window looks for",
          f"bar B {bar_b!r}, bar A {bar_a!r}, window B {win_b['sock']!r}")
runtime = (D / "runtime.txt").read_text().split() if (D / "runtime.txt").exists() else []
check("sleepyshell-settings.sock" not in runtime, "nothing uses the old fixed socket path", f"runtime folder: {runtime}")
sys.exit(1 if fails else 0)
CHECK_SOCKETS_PY
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
