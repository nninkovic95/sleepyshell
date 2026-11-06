#!/bin/bash
# lock/hypridle-restart.test.sh [TREE]: a lock screen started by hypridle survives a restart of hypridle.
#
# Tier 2 (lock failing): on a laptop the bar rewrites hypridle.conf when the charger is plugged in or out
# (PowerPolicy -> idle.py --background --battery|--ac), and idle.py then restarts hypridle.service. systemd stops
# everything in the unit's cgroup, so a lock screen that hypridle's lock_cmd had started died with it and the session
# stayed locked with nothing to unlock it. This reproduces that on any machine, battery or not:
#   - a transient user service, sleepyshell-test-hypridle-<pid>.service, stands in for hypridle.service (the same
#     KillMode=control-group); its program starts the lock_cmd of the hypridle.conf the tree's idle.py wrote, once,
#     as hypridle does on a Lock signal;
#   - a stand-in `qs` on its PATH plays the lock screen (it only sleeps), so nothing is locked;
#   - the lock's flock file is a private one: a stand-in `flock` passes the same options to the real flock with a file
#     in the run folder, so the real lock is never held back (the unit keeps the real runtime folder, where
#     `systemd-run --user` finds the user's systemd, as hypridle.service does);
#   - the change of power source runs as the bar runs it: the tree's idle.py --background --battery, pointed at the
#     stand-in unit (SLEEPYSHELL_HYPRIDLE_UNIT). A tree whose idle.py has no such setting gets the restart idle.py
#     would run, `systemctl --user restart <unit>`, so the real hypridle is never restarted.
# Outside the bubblewrap sandbox (it needs the user's systemd); every file is in the run folder, the checksum guard
# runs before and after, and the units are removed and shown gone at the end.
# Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
NAME=hypridle-restart-$$
D=$RUN/$NAME
UNIT=sleepyshell-test-hypridle-$$.service
mkdir -p "$D/bin" "$D/config/hypr" "$D/proc"
mkdir -m 700 "$D/rt"
FLOCK=$(command -v flock) || { echo "FAIL flock is not installed"; exit 1; }
SCOPE=""
fails=0
check() {
    if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2${3:+: $3}"; fails=$((fails + 1)); fi
}
finish() {
    systemctl --user stop "$UNIT" >/dev/null 2>&1
    [ -s "$D/lock.pid" ] && kill "$(cat "$D/lock.pid")" 2>/dev/null
    [ -n "$SCOPE" ] && systemctl --user stop "$SCOPE" >/dev/null 2>&1
    sleep 0.5
}
trap 'finish; bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT
echo "unit: $UNIT"

python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
copy_tree "$TREE" "$D/s"
rm -f "$D"/s/sleepysettings.toml* "$D"/s/settings.json*
printf '[idle]\nidleDimMin = 5\n' >"$D/settings.toml"

# the stand-in lock screen: notes its pid, then waits as a lock would
printf '#!/bin/sh\necho $$ > "%s/lock.pid"\nexec sleep 300\n' "$D" >"$D/bin/qs"
# the stand-in hypridle: runs lock_cmd through sh (as hypridle does) on its first start only, then idles
printf '#!/bin/sh\nif [ ! -e "%s/started" ]; then\n    touch "%s/started"\n    cmd=$(sed -n "s/^    lock_cmd = //p" "%s/config/hypr/hypridle.conf")\n    sh -c "$cmd" &\nfi\nexec sleep 300\n' \
    "$D" "$D" "$D" >"$D/bin/fake-hypridle"
# the stand-in flock: `flock -n -E 75 FILE CMD...` from lock_cmd, run by the real flock on a file of this run
printf '#!/bin/sh\necho "$*" >> "%s/flock.log"\n[ "$#" -ge 4 ] || exit 64\na=$1 b=$2 c=$3\nshift 4\nexec "%s" "$a" "$b" "$c" "%s/rt/sleepylock.lock" "$@"\n' \
    "$D" "$FLOCK" "$D" >"$D/bin/flock"
chmod +x "$D/bin/qs" "$D/bin/fake-hypridle" "$D/bin/flock"

export SLEEPYSHELL_SETTINGS=$D/settings.toml SLEEPYSHELL_HYPRIDLE_SERVICE=none SLEEPYSHELL_HYPRIDLE_PROC=$D/proc
export SLEEPYSHELL_HYPRIDLE_UNIT=$UNIT
XDG_CONFIG_HOME=$D/config python3 -I "$D/s/scripts/idle.py" --print --ac >"$D/config/hypr/hypridle.conf"
echo "lock_cmd: $(sed -n 's/^    lock_cmd = //p' "$D/config/hypr/hypridle.conf")"

systemd-run --user --quiet --collect --unit="$UNIT" -p KillMode=control-group \
    --setenv=PATH="$D/bin:/usr/local/bin:/usr/bin:/bin" --setenv=HOME="$HOME" \
    "$D/bin/fake-hypridle"
for _ in $(seq 100); do [ -s "$D/lock.pid" ] && break; sleep 0.1; done
LOCK=$(cat "$D/lock.pid" 2>/dev/null)
check "$([ -n "$LOCK" ] && kill -0 "$LOCK" 2>/dev/null && [ -s "$D/flock.log" ] && echo 0 || echo 1)" \
    "the stand-in hypridle started the lock through lock_cmd (with the run's own lock file)" "flock log: $(cat "$D/flock.log" 2>/dev/null)"
CG=$(cat "/proc/$LOCK/cgroup" 2>/dev/null | sed 's/^0:://')
echo "lock cgroup: ${CG##*/}"
case "$CG" in */run-*.scope) SCOPE=${CG##*/} ;; esac

if grep -q SLEEPYSHELL_HYPRIDLE_UNIT "$D/s/scripts/idle.py"; then
    XDG_CONFIG_HOME=$D/config python3 -I "$D/s/scripts/idle.py" --background --battery >"$D/idle.out" 2>&1
    echo "idle.py: $(cat "$D/idle.out")"
else
    echo "(this tree's idle.py cannot be pointed at the stand-in unit: restarting it with the command idle.py runs)"
    systemctl --user restart "$UNIT"
fi
sleep 2
active=$(systemctl --user is-active "$UNIT" 2>/dev/null)
check "$([ "$active" = active ] && grep -q '^# Written by sleepyshell' "$D/config/hypr/hypridle.conf" && echo 0 || echo 1)" \
    "the change of power source rewrote hypridle.conf and restarted the stand-in unit" "unit $active"
check "$([ -n "$LOCK" ] && kill -0 "$LOCK" 2>/dev/null && echo 0 || echo 1)" "the lock screen survived the restart" \
    "the lock (pid $LOCK, cgroup ${CG##*/}) was stopped with the unit"

finish
units=$(systemctl --user list-units --all --no-legend 2>/dev/null)
left=$(printf '%s\n' "$units" | grep -F -e "sleepyshell-test-hypridle-$$" -e "${SCOPE:-sleepyshell-test-hypridle-$$}")
what="the stand-in unit is gone"
[ -n "$SCOPE" ] && what="the stand-in unit and the lock's scope are gone"  # the scope's name changes every run
check "$([ -z "$left" ] && echo 0 || echo 1)" "$what" "$left"

if python3 -I "$KIT/common/guard.py" verify "$NAME" >/dev/null; then
    echo "PASS no real file changed"
else
    echo "FAIL a real file changed:"
    python3 -I "$KIT/common/guard.py" verify "$NAME" | sed 's/^/    /'
    fails=$((fails + 1))
fi
trap - EXIT
bash "$KIT/common/cleanup.sh" "$D" >/dev/null && echo "PASS nothing left running, run folder deleted" || { echo "FAIL processes, windows or files left"; fails=$((fails + 1)); }
[ "$fails" = 0 ]
