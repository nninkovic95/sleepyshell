#!/bin/bash
# preview.sh start [CANDIDATE]   run a candidate tree as the real bar, in place of the live shell
# preview.sh stop                stop the preview and start the live shell again
# preview.sh status              what runs now: the live shell, a preview, or nothing
#
# A preview is the only way to see a change on the real screen before it is deployed. It changes no
# live file: the candidate keeps its own sleepysettings.toml (a copy), so what is applied in its settings
# window stays in the candidate. Keybinds still reach it (they send Hyprland events) and SUPER+L still
# starts the live lock; `qs -c sleepyshell ipc ...` does not reach it (it is not that config).
# start compiles the candidate first and, when it does not load, stops it and brings the live shell back.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/common/env.sh"

status() {
    local p l
    p=$(preview_pid)
    l=$(live_shell_pid)
    [ -n "$l" ] && echo "live shell running (pid $l)"
    [ -n "$p" ] && echo "preview running (pid $p): $(preview_dir)"
    [ -z "$l$p" ] && echo "no shell running: run '$0 stop' or 'qs -c sleepyshell -d'"
    return 0
}

case "${1:-status}" in
start)
    CAND=$(readlink -f "${2:-$KIT/candidate}")
    [ -f "$CAND/shell.qml" ] || { echo "preview: $CAND is not a sleepyshell tree"; exit 2; }
    [ -n "$(preview_pid)" ] && { echo "preview: one already runs ($(preview_dir)); stop it first"; exit 1; }
    bash "$KIT/common/compile.sh" "$CAND" | tail -1
    l=$(live_shell_pid)
    [ -n "$l" ] && { stop_pid "$l"; echo "preview: live shell stopped"; }
    p=$(start_shell "$CAND")
    if [ -n "$p" ] && r=$(wait_loaded 0 "$p"); then
        echo "preview: $CAND runs as the bar (pid $p, $r)"
    else
        echo "preview: the candidate did not load (${r:-no process}); its log:"
        [ -n "$p" ] && qs log --pid "$p" 2>/dev/null | grep -aE 'ERROR|caused by' | head -8
        [ -n "$p" ] && stop_pid "$p"
        l=$(start_shell)
        echo "preview: live shell back (pid $l, $(wait_loaded 0 "$l" || true))"
        exit 1
    fi
    ;;
stop)
    p=$(preview_pid)
    [ -n "$p" ] && { stop_pid "$p"; echo "preview: stopped"; }
    if [ -z "$(live_shell_pid)" ]; then
        l=$(start_shell)
        echo "preview: live shell started (pid $l, $(wait_loaded 0 "$l" || true))"
    fi
    ;;
status)
    status
    ;;
*)
    sed -n '2,4p' "$0"
    exit 2
    ;;
esac
