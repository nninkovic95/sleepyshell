#!/bin/bash
# run-ui.sh NAME TEST.py [TREE]: run one whole-window test (a Python file using common/ui/ui.py).
#
# Makes the run folder RUN/NAME-PID (deleted by cleanup.sh on exit), takes the checksum guard, copies TREE (default:
# the live shell) to RUN/.../s without the user's settings, gives the sandbox a fresh home holding the fixture Hyprland
# config (tests/fixtures/hypr -> home/.config/hypr), starts the private desktop of session.sh inside the sandbox and runs
# `python3 -I TEST.py RUN/.../s` there. Its PASS/FAIL lines are printed; then the guard must still match and cleanup
# must leave nothing. Exit 1 on any FAIL. SLEEPYSHELL_WATCH=1 (tests/run.sh --watch) shares the screen view-only.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../env.sh"
NAME=$1
TEST=$(readlink -f "$2")
TREE=$(readlink -f "${3:-$LIVE}")
D=$RUN/$NAME-$$
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT

python3 -I "$KIT/common/guard.py" snapshot "$NAME-$$" >/dev/null
copy_tree "$TREE" "$D/s"
rm -f "$D"/s/sleepysettings.toml* "$D"/s/settings.json*
mkdir -p "$D/home/.config"
cp -r "$KIT/fixtures/hypr" "$D/home/.config/hypr"
echo "$D" >"$KIT/jobs/.last-ui-run" 2>/dev/null || true

# watch mode: the viewer runs on the user's desktop, outside the sandbox, view-only, on the socket wayvnc makes in the
# run folder (the sandbox has no network); its command line names the run folder, so cleanup.sh closes it
if [ "${SLEEPYSHELL_WATCH:-}" = 1 ]; then
    (
        for _ in $(seq 200); do [ -S "$D/watch.sock" ] && break; sleep 0.05; done
        [ -S "$D/watch.sock" ] && exec vncviewer -ViewOnly -Shared -RemoteResize=0 "$D/watch.sock" >"$D/viewer.log" 2>&1
    ) &
fi

timeout "${UI_TIMEOUT:-240}" bash "$KIT/common/sandbox.sh" "$D" env SLEEPYSHELL_WATCH="${SLEEPYSHELL_WATCH:-}" \
    SLEEPYSHELL_UPDATE_REFS="${SLEEPYSHELL_UPDATE_REFS:-}" SLEEPYTEST_DUMP="${SLEEPYTEST_DUMP:-}" bash -c '
    . "$KIT/common/ui/session.sh"
    ui_start "$SLEEPYSHELL_SANDBOX" || { echo "FAIL the private test desktop did not start"; exit 1; }
    [ "${SLEEPYSHELL_WATCH:-}" = 1 ] && sleep "${UI_WATCH_DELAY:-3}"
    cd "$(dirname "$1")"
    PYTHONPATH="$KIT/common/ui" python3 -I -c "import sys; sys.path.insert(0, \"$KIT/common/ui\"); sys.argv = sys.argv[1:]; exec(compile(open(sys.argv[0]).read(), sys.argv[0], \"exec\"))" "$1" "$SLEEPYSHELL_SANDBOX/s"
    rc=$?
    ui_stop
    exit $rc' sh "$TEST" | tee "$D/result.txt"
rc=${PIPESTATUS[0]}
if [ -d "$D/failed" ]; then
    mkdir -p "$KIT/jobs/failed/$NAME-$$"
    cp -r "$D/failed/." "$KIT/jobs/failed/$NAME-$$/"
    echo "      images kept in tests/jobs/failed/$NAME-$$"
fi
[ "$rc" = 124 ] && echo "FAIL $NAME timed out"

if ! python3 -I "$KIT/common/guard.py" verify "$NAME-$$" >/dev/null; then
    echo "FAIL a real file changed:"
    python3 -I "$KIT/common/guard.py" verify "$NAME-$$" | sed 's/^/    /'
    rc=1
fi
grep -q "^FAIL" "$D/result.txt" && rc=1
[ "$rc" = 0 ] || [ "$rc" = 1 ] || rc=1
exit "$rc"
