#!/bin/bash
# The sandboxed half of settings/socket-per-copy.test.sh: runs inside common/sandbox.sh, never on its own.
# socket-per-copy-inner.sh RUN_FOLDER
# Copy A is reached two ways, as on a real install: the bar through the config link ($XDG_CONFIG_HOME/quickshell/
# sleepyshell -> a), the window through the folder itself. Copy B is a second copy (a test copy). Leaves the logs and
# runtime.txt (what the runtime folder held) in the run folder; the outer script checks them.
set -uo pipefail
D=$1
export QT_QPA_PLATFORM=offscreen
trap 'kill $(jobs -p) 2>/dev/null' EXIT

# wait_sock LOG: until the log names the socket (10 s)
wait_sock() {
    for _ in $(seq 100); do grep -q 'SOCK ' "$1" 2>/dev/null && return 0; sleep 0.1; done
    return 1
}

qs -p "$XDG_CONFIG_HOME/quickshell/sleepyshell/bar-harness.qml" >"$D/bar-a.log" 2>&1 &
BAR_A=$!
wait_sock "$D/bar-a.log" || echo "inner: bar A named no socket"
# the server opens 600 ms after start (SettingsServer.openLater)
sleep 1

T3_ACTION=probe T3_WAIT=5000 qs -p "$D/a/link-harness.qml" >"$D/win-a.log" 2>&1 &
WA=$!
T3_ACTION=probe T3_WAIT=5000 qs -p "$D/b/link-harness.qml" >"$D/win-b.log" 2>&1 &
WB=$!
wait "$WA" "$WB"

qs -p "$D/b/bar-harness.qml" >"$D/bar-b.log" 2>&1 &
BAR_B=$!
wait_sock "$D/bar-b.log" || echo "inner: bar B named no socket"
sleep 1
ls -A "$XDG_RUNTIME_DIR" >"$D/runtime.txt"
kill "$BAR_A" "$BAR_B" 2>/dev/null
wait 2>/dev/null
