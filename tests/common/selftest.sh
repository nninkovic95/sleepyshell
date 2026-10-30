#!/bin/bash
# selftest.sh: prove the kit's isolation on this machine before any suite trusts it.
#
# Inside a sandbox (sandbox.sh) it checks that: a write to the home folder fails, the run folder is
# writable, Hyprland answers, the Wayland and Hyprland sockets are the only things in the runtime
# folder, the session D-Bus cannot be reached, and no outside process is visible. Outside it checks
# that the guard snapshot of the real files is unchanged afterwards and that cleanup leaves nothing.
# Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/env.sh"
D=$RUN/selftest-$$
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT

python3 -I "$KIT/common/guard.py" snapshot selftest-$$ >/dev/null

out=$(bash "$KIT/common/sandbox.sh" "$D" sh -c '
probe=$HOME/.sleepyshell-sandbox-probe
if touch "$probe" 2>/dev/null; then rm -f "$probe"; echo "FAIL home is writable"; else echo "PASS home is read-only"; fi
touch "$SLEEPYSHELL_SANDBOX/probe" 2>/dev/null && echo "PASS run folder is writable" || echo "FAIL run folder is not writable"
python3 -I "$KIT/common/hypr.py" j/version 2>/dev/null | grep -q "\"tag\"" && echo "PASS Hyprland answers on its socket" || echo "FAIL Hyprland does not answer"
hyprctl version >/dev/null 2>&1 && echo "FAIL hyprctl reaches the real compositor" || echo "PASS hyprctl cannot reach the real compositor"
extra=$(ls -A "$XDG_RUNTIME_DIR" | grep -vx -e "$WAYLAND_DISPLAY" -e hypr -e sleepyshell-tests)
[ -z "$extra" ] && echo "PASS runtime folder holds only the Wayland and Hyprland sockets" || echo "FAIL runtime folder also holds: $extra"
if gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    echo "FAIL the session D-Bus is reachable"
else
    echo "PASS no session D-Bus"
fi
n=$(ls /proc | grep -c "^[0-9]")
[ "$n" -le 6 ] && echo "PASS own process namespace ($n processes visible)" || echo "FAIL $n processes visible"
')
echo "$out"

if python3 -I "$KIT/common/guard.py" verify selftest-$$ >/dev/null; then
    echo "PASS no real file changed"
else
    echo "FAIL a real file changed:"
    python3 -I "$KIT/common/guard.py" verify selftest-$$ | sed 's/^/    /'
fi
bash "$KIT/common/cleanup.sh" "$D" >/dev/null && echo "PASS nothing left running, run folder deleted" || echo "FAIL processes, windows or files left"

! echo "$out" | grep -q "^FAIL"
