#!/bin/bash
# install/defaults.test.sh [TREE]: the settings file install.sh ships is the one the schema gives.
#
# Tier 2 (a broken desktop): data/default-settings.toml is copied into place by install.sh as a new user's settings. If
# a setting is added, renamed or given a new default in services/Settings.qml and the file is not rendered again, new
# users start with stale values or keys the schema no longer knows. Renders the file again with
# tools/default-settings.sh --check inside the sandbox (offscreen Quickshell on a scratch copy) and compares; also checks
# that the file parses as TOML and holds nothing of this machine (no home folder).
# Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
REPO=$(cd "$KIT/.." && pwd)
NAME=defaults-$$
D=$RUN/$NAME
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT
python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
fails=0
F=$TREE/data/default-settings.toml
if timeout 120 bash "$KIT/common/sandbox.sh" "$D" bash "$REPO/tools/default-settings.sh" --check --tree "$TREE" >"$D/check.log" 2>&1; then
    echo "PASS the shipped settings file matches the schema"
else
    echo "FAIL the shipped settings file matches the schema: $(head -c 1500 "$D/check.log")"
    fails=1
fi
if python3 -I -c 'import sys, tomllib; tomllib.loads(open(sys.argv[1]).read())' "$F" 2>"$D/toml.err"; then
    echo "PASS it parses as TOML"
else
    echo "FAIL it parses as TOML: $(cat "$D/toml.err")"
    fails=1
fi
if [ ! -f "$F" ] || grep -qE "$HOME|/home/|Has no effect without|Only used on a laptop" "$F"; then
    echo "FAIL it holds nothing of this machine: $(grep -nE "$HOME|/home/|Has no effect without|Only used on a laptop" "$F" | head -3)"
    fails=1
else
    echo "PASS it holds nothing of this machine"
fi
python3 -I "$KIT/common/guard.py" verify "$NAME" >/dev/null && echo "PASS guard: no real file changed" || { echo "FAIL guard: a real file changed"; fails=1; }
exit $fails
