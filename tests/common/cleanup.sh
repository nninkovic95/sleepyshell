#!/bin/bash
# cleanup.sh [RUNDIR]: stop everything a test run started, delete the run's files, prove nothing is left.
#
# With RUNDIR (a folder under RUN): only that run, so suites running side by side never touch each
# other. Without it: every run under RUN (stale folders after a killed run included).
# Only processes whose command line names a path under that folder are touched: an instance started as
# `qs -p <folder>/...`, the sandbox (bwrap) around it, a helper or stub. Never the live shell, the live
# settings window or lock, the preview, and never a broad pkill. SIGTERM, then SIGKILL after 4 s.
# Then the folder is deleted. Afterwards no process may point into it and no window may belong to one;
# else it exits 1. Every runner calls it from an EXIT trap; it is also fine by hand.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/env.sh"
T=${1:-$RUN}
T=$(readlink -m "$T")
case "$T/" in "$RUN"/*) ;; *) echo "cleanup: $T is not under $RUN"; exit 2 ;; esac

ours() {
    pgrep -f -- "$T/" | grep -vx -e "$$" -e "$BASHPID" || true
}

pids=$(ours)
n=$(echo "$pids" | grep -c . || true)
[ -n "$pids" ] && kill $pids 2>/dev/null
for _ in $(seq 20); do
    [ -z "$(ours)" ] && break
    sleep 0.2
done
left=$(ours)
if [ -n "$left" ]; then
    kill -9 $left 2>/dev/null
    sleep 0.3
    left=$(ours)
fi

# a window whose process points into the folder (only possible while one is left)
wins=$(python3 -I "$KIT/common/hypr.py" j/clients 2>/dev/null | python3 -I -c '
import json, sys
t = sys.argv[1] + "/"
for c in json.load(sys.stdin):
    try:
        cmd = open("/proc/%d/cmdline" % c["pid"], "rb").read().decode(errors="replace")
    except OSError:
        continue
    if t in cmd:
        print(c["title"])
' "$T" 2>/dev/null || true)

if [ -z "$left" ] && [ -d "$T" ]; then
    rm -rf -- "$T"
fi
gone=yes
[ -e "$T" ] && [ "$T" != "$RUN" ] && gone=no
[ "$T" = "$RUN" ] && [ -e "$T" ] && gone=no

echo "cleanup: $n stopped, $(echo "$left" | grep -c . || true) left, $(echo "$wins" | grep -c . || true) test windows, files removed: $gone"
[ -z "$left" ] && [ -z "$wins" ] && [ "$gone" = yes ]
