#!/bin/bash
# bar/keyreport.test.sh [TREE]: the keybind overlay's reporter (data/keyreport.lua) names only keybinds that fire.
#
# Tier 1 (input seen that must not be: typing, or keybinds while the overlay is off) and tier 3 (keybinds that stop
# working, or are named twice): loaded by Lua against a stand-in `hl` table, in the sandbox, without Hyprland. While
# off nothing is reported; while on a fired bind is reported with its mask, kind and key and still does what it did;
# a drag bind is left alone and reported by a pass-through bind; a config reload does not wrap twice; the reporter
# makes no bind of its own. Prints PASS or FAIL per check; exits 1 on any FAIL. Needs `lua`.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
NAME=keyreport-$$
D=$RUN/$NAME
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT
command -v lua >/dev/null || { echo "FAIL lua is not installed (the kit needs it for this test)"; exit 1; }
python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
cp "$TREE/data/keyreport.lua" "$D/keyreport.lua"

timeout 30 bash "$KIT/common/sandbox.sh" "$D" lua "$KIT/bar/keyreport-stub.lua" "$D/keyreport.lua"
rc=$?

if python3 -I "$KIT/common/guard.py" verify "$NAME" >/dev/null; then
    echo "PASS no real file changed"
else
    echo "FAIL a real file changed"
    rc=1
fi
exit $rc
