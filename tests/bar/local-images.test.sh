#!/bin/bash
# bar/local-images.test.sh [TREE]: notification and tray images load only from local sources, never from the network.
#
# Tier 1 (security): an app could otherwise make the shell fetch an address of its choosing (a read receipt, the
# user's IP address). The tree (default: the live shell) is copied into a run folder without the user's settings;
# inside one sandbox (no network but its own loopback) a private session bus carries ten real notifications and
# three stand-in tray items to the tree's real cards, toasts and tray, drawn offscreen. Every URL they name points
# at a local request counter; a control image proves the counter sees a fetch. Also checks that the usual forms
# (an icon name, a file path, a file: URL) still show, that an image that fails to load falls back to the app's
# icon, and that an unknown icon shows the bell instead of Quickshell's checkerboard.
# Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
NAME=local-images-$$
D=$RUN/$NAME
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT

python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
copy_tree "$TREE" "$D/shell"
rm -f "$D"/shell/sleepysettings.toml* "$D"/shell/settings.json*
cp "$KIT/bar/images-harness.qml" "$D/shell/"
# an icon every hicolor theme install has some of: the first application icon found
ICON=$(find /usr/share/icons/hicolor/48x48/apps -maxdepth 1 -name '*.png' -printf '%f\n' 2>/dev/null | sort | head -1)
ICON=${ICON%.png}
[ -n "$ICON" ] || { echo "FAIL no hicolor application icon to test with"; exit 1; }

timeout 120 bash "$KIT/common/sandbox.sh" "$D" bash "$KIT/bar/local-images-inner.sh" "$D" "$KIT/bar" "$ICON"
python3 -I "$KIT/bar/check_images.py" "$D" "$ICON"
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
