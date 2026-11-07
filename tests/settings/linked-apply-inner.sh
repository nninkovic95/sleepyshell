#!/bin/bash
# The sandboxed half of settings/linked-apply.test.sh: runs inside common/sandbox.sh, never on its own.
# linked-apply-inner.sh RUN_FOLDER BAR_HELPERS
# Case "dies" (copy c): the window's end links to a fake bar that closes on the first commit without answering.
# Case "saves" (copy d): the window's end links to the tree's real bar end, which writes the file and answers.
# Leaves the logs in the run folder; the outer script checks them and the two settings files.
set -uo pipefail
D=$1
B=$2
export QT_QPA_PLATFORM=offscreen
trap 'kill $(jobs -p) 2>/dev/null' EXIT

wait_sock() {
    for _ in $(seq 100); do grep -q 'SOCK ' "$1" 2>/dev/null && return 0; sleep 0.1; done
    return 1
}

# dies: the window first, so the fake bar listens where this tree's window looks
T3_ACTION=apply T3_WAIT=3000 qs -p "$D/c/link-harness.qml" >"$D/win-c.log" 2>&1 &
WC=$!
if wait_sock "$D/win-c.log"; then
    python3 -I "$B/fake_bar.py" "$(grep -o 'SOCK .*' "$D/win-c.log" | tail -1 | cut -c6-)" "$D/fake-bar.log" &
else
    echo "inner: window c named no socket"
fi
wait "$WC"

# twice: a fake bar that answers only after both Applies came
T3_ACTION=twice T3_WAIT=3000 qs -p "$D/e/link-harness.qml" >"$D/win-e.log" 2>&1 &
WE=$!
if wait_sock "$D/win-e.log"; then
    python3 -I "$B/fake_bar.py" "$(grep -o 'SOCK .*' "$D/win-e.log" | tail -1 | cut -c6-)" "$D/fake-bar-e.log" answer2 &
else
    echo "inner: window e named no socket"
fi
wait "$WE"

# saves: the real bar end first
qs -p "$D/d/bar-harness.qml" >"$D/bar-d.log" 2>&1 &
BD=$!
wait_sock "$D/bar-d.log" || echo "inner: bar d named no socket"
sleep 1
T3_ACTION=apply T3_WAIT=3000 qs -p "$D/d/link-harness.qml" >"$D/win-d.log" 2>&1
kill "$BD" 2>/dev/null
wait 2>/dev/null
