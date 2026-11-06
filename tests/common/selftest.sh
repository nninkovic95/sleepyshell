#!/bin/bash
# selftest.sh: prove the kit's isolation on this machine before any suite trusts it.
#
# Inside a sandbox (sandbox.sh) it checks that: the real home cannot be written and is not the sandbox's home, the
# run folder is writable, the runtime folder starts empty (no live Wayland or Hyprland socket), neither the system nor
# the session D-Bus can be reached, /dev holds no display card, input device or tty, no outside process is visible,
# and the input and Hyprland stand-ins refuse to run outside a sandbox. Then that a private headless compositor starts
# inside, answers, and is gone afterwards. Outside it checks that the guard snapshot of the real files is unchanged
# and that cleanup leaves nothing. Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/env.sh"
D=$RUN/selftest-$$
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT

python3 -I "$KIT/common/guard.py" snapshot selftest-$$ >/dev/null

# with no Wayland display and a runtime folder of its own, so even a broken refusal could reach nothing live
mkdir -p "$D/rt"
refused=1
for tool in "wlinput.py serve $D/x.sock" "fakehypr.py serve $D" "fake.py" "fakehyprctl.py version"; do
    set -- $tool
    msg=$(env -u SLEEPYSHELL_SANDBOX -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$D/rt" timeout 3 python3 -I "$KIT/common/ui/$1" "${@:2}" 2>&1)
    case "$msg" in *"only inside a test sandbox"*) ;; *) refused=0; echo "FAIL $1 did not refuse outside a sandbox: ${msg:0:120}" ;; esac
done
[ "$refused" = 1 ] && echo "PASS the input, Hyprland and program stand-ins refuse to run outside a sandbox"

out=$(REAL_HOME=$HOME bash "$KIT/common/sandbox.sh" "$D" env REAL_HOME="$HOME" sh -c '
probe=$REAL_HOME/.sleepyshell-sandbox-probe
if touch "$probe" 2>/dev/null; then rm -f "$probe"; echo "FAIL the real home is writable"; else echo "PASS the real home is read-only"; fi
[ "$HOME" != "$REAL_HOME" ] && echo "PASS the sandbox has its own home" || echo "FAIL the sandbox uses the real home"
touch "$SLEEPYSHELL_SANDBOX/probe" 2>/dev/null && echo "PASS run folder is writable" || echo "FAIL run folder is not writable"
extra=$(ls -A "$XDG_RUNTIME_DIR" | grep -vx sleepyshell-tests)
[ -z "$extra" ] && echo "PASS runtime folder holds only the run folders: no live Wayland or Hyprland socket" || echo "FAIL runtime folder holds: $extra"
hyprctl version >/dev/null 2>&1 && echo "FAIL hyprctl reaches a compositor" || echo "PASS hyprctl reaches no compositor"
if [ -e /run/dbus/system_bus_socket ] || gdbus call --system --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    echo "FAIL the system D-Bus is reachable"
else
    echo "PASS no system D-Bus"
fi
if gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    echo "FAIL the session D-Bus is reachable"
else
    echo "PASS no session D-Bus"
fi
devs=$(ls /dev/dri/card* /dev/input /dev/tty[0-9]* 2>/dev/null)
[ -z "$devs" ] && echo "PASS no display card, input device or tty in /dev" || echo "FAIL /dev holds: $devs"
n=$(ls /proc | grep -c "^[0-9]")
[ "$n" -le 6 ] && echo "PASS own process namespace ($n processes visible)" || echo "FAIL $n processes visible"
. "$KIT/common/ui/session.sh"
if ui_start "$SLEEPYSHELL_SANDBOX" >/dev/null 2>&1 && swaymsg -t get_outputs >/dev/null 2>&1 && [ -S "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]; then
    echo "PASS a private headless compositor, virtual input and a stand-in Hyprland start"
else
    echo "FAIL the private test compositor did not start"
fi
ui_stop
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
