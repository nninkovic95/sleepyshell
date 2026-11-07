# session.sh: sourced inside a sandbox (common/sandbox.sh); starts and stops a private desktop for whole-window tests.
#
#   ui_start RUNDIR [WIDTH HEIGHT]   a headless sway (no GPU needed, pixman), a virtual pointer and keyboard
#                                    (wlinput.py), a stand-in Hyprland (fakehypr.py), a private session bus with no
#                                    service activation, and fakes for the programs the shell launches; exports the
#                                    variables an instance under test needs
#   ui_stop                          stop all of it
#
# The compositor is a separate sway on its own socket in the sandbox's private runtime folder: nothing is drawn on the
# user's screen and no input reaches the session. The fakes log every launch to RUNDIR/commands.log as
# "RUN <name> <args as JSON>" and print RUNDIR/fake/<name>.out when it exists (exit code RUNDIR/fake/<name>.code).
# With SLEEPYSHELL_WATCH=1, wayvnc also shares the compositor's screen view-only on RUNDIR/watch.sock (tests/run.sh
# --watch starts the viewer outside); without it nothing listens.

UI_FAKES="matugen magick awww swww nmcli paru yay pacman fakeroot lspci hypridle notify-send loginctl systemctl wpctl busctl
systemd-inhibit wl-copy khal ikhal xdg-mime xdg-open walker pwvucontrol hyprpicker kitty ddcutil brightnessctl
powerprofilesctl playerctl pactl grimblast uwsm"

ui_start() {
    local d=$1 w=${2:-2560} h=${3:-1440} n
    export SLEEPYSHELL_TEST_W=$w SLEEPYSHELL_TEST_H=$h SLEEPYSHELL_TEST_OUTPUT=HEADLESS-1
    mkdir -p "$d/fakebin" "$d/fake" "$d/sway"
    : >>"$d/commands.log"
    for n in $UI_FAKES; do ln -sf "$KIT/common/ui/fake.py" "$d/fakebin/$n"; done
    ln -sf "$KIT/common/ui/fakehyprctl.py" "$d/fakebin/hyprctl"
    export PATH="$d/fakebin:$PATH"

    cat >"$d/sway/config" <<UI_SWAY_CONFIG
output HEADLESS-1 resolution ${w}x${h} position 0 0
default_border none
default_floating_border none
focus_follows_mouse no
seat seat0 xcursor_theme default 24
for_window [app_id=".*"] floating enable, move position 0 0
for_window [title=".*"] floating enable, move position 0 0
UI_SWAY_CONFIG
    WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1 \
        sway -c "$d/sway/config" >"$d/sway.log" 2>&1 &
    UI_SWAY_PID=$!
    for _ in $(seq 100); do
        WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)
        SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1)
        [ -n "$WAYLAND_DISPLAY" ] && [ -n "$SWAYSOCK" ] && break
        kill -0 "$UI_SWAY_PID" 2>/dev/null || break
        sleep 0.1
    done
    [ -n "$SWAYSOCK" ] || { echo "ui_start: sway did not start" >&2; return 1; }
    export WAYLAND_DISPLAY SWAYSOCK QT_QPA_PLATFORM=wayland
    unset QT_QPA_PLATFORMTHEME

    python3 -I "$KIT/common/ui/wlinput.py" serve "$d/input.sock" >"$d/wlinput.log" 2>&1 &
    UI_INPUT_PID=$!
    python3 -I "$KIT/common/ui/fakehypr.py" serve "$d" ${UI_HYPR_STATE:+"$UI_HYPR_STATE"} >"$d/fakehypr.log" 2>&1 &
    UI_HYPR_PID=$!

    cat >"$d/bus.conf" <<UI_BUS_CONFIG
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path=$d/bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
UI_BUS_CONFIG
    dbus-daemon --config-file="$d/bus.conf" --nofork --nopidfile >"$d/bus.log" 2>&1 &
    UI_BUS_PID=$!
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$d/bus"

    for _ in $(seq 100); do
        [ -S "$d/input.sock" ] && [ -S "$d/bus" ] && [ -n "$(head -1 "$d/fakehypr.log" 2>/dev/null)" ] && break
        sleep 0.05
    done
    export HYPRLAND_INSTANCE_SIGNATURE=$(head -1 "$d/fakehypr.log")
    export UI_INPUT=$d/input.sock UI_RUN=$d

    # view-only: the viewer's mouse and keys never reach the test screen (kit/watch-view-only.test.py proves it)
    export UI_VNC_FLAGS="--disable-input --render-cursor --output=HEADLESS-1 --unix-socket"
    if [ "${SLEEPYSHELL_WATCH:-}" = 1 ]; then
        wayvnc $UI_VNC_FLAGS "$d/watch.sock" >"$d/wayvnc.log" 2>&1 &
        UI_VNC_PID=$!
    fi
    [ -S "$d/input.sock" ] && [ -S "$d/bus" ] && [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]
}

ui_stop() {
    local p
    for p in ${UI_VNC_PID:-} ${UI_BUS_PID:-} ${UI_HYPR_PID:-} ${UI_INPUT_PID:-} ${UI_SWAY_PID:-}; do
        kill "$p" 2>/dev/null
    done
    wait 2>/dev/null
    return 0
}
