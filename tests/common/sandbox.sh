#!/bin/bash
# sandbox.sh DIR CMD...: run CMD in a bubblewrap sandbox in which only DIR can be written.
#
# What the sandbox gets:
#   the whole file system read-only (the user's files can be read, fonts and icons load, nothing can
#   be written), DIR read-write, a private /tmp, and a private XDG_RUNTIME_DIR: an empty tmpfs at the
#   usual path that holds only the compositor's Wayland socket and Hyprland's sockets, so instances draw
#   on the real screen and hear Hyprland's events. It stays at the usual short path because a Unix
#   socket path may not exceed 108 bytes, and Hyprland's sockets sit two long folder names deep. XDG_CONFIG_HOME, XDG_STATE_HOME and XDG_CACHE_HOME point into DIR.
# What it does not get:
#   the session D-Bus (no notifications, no systemctl --user, no gsettings, no portals), PipeWire, the
#   network, the live shell's IPC sockets, or a view of any outside process (own PID namespace).
# Lifetime: everything inside dies when CMD ends or this script is killed (--die-with-parent, and the
#   PID namespace ends with its first process); the caller deletes DIR.
# Every suite runs its whole run inside one sandbox, so its instances, IPC calls and screenshots share
# one namespace. CMD inherits only the variables listed here (--clearenv).
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/env.sh"
DIR=$(readlink -f "${1:?run folder}")
shift
case "$DIR/" in "$RUN"/*) ;; *) echo "sandbox: $DIR is not under $RUN"; exit 2 ;; esac
: "${WAYLAND_DISPLAY:?no Wayland session}"
: "${HYPRLAND_INSTANCE_SIGNATURE:?not running under Hyprland}"
RT=$XDG_RUNTIME_DIR
mkdir -p "$DIR/config" "$DIR/state" "$DIR/cache"

exec bwrap \
    --ro-bind / / \
    --dev-bind /dev /dev \
    --proc /proc \
    --tmpfs /tmp \
    --tmpfs "$RT" \
    --bind "$DIR" "$DIR" \
    --ro-bind "$RT/$WAYLAND_DISPLAY" "$RT/$WAYLAND_DISPLAY" \
    --ro-bind "$RT/hypr/$HYPRLAND_INSTANCE_SIGNATURE" "$RT/hypr/$HYPRLAND_INSTANCE_SIGNATURE" \
    --unshare-pid --unshare-ipc --unshare-net --unshare-uts \
    --die-with-parent --new-session \
    --clearenv \
    --setenv HOME "$HOME" \
    --setenv PATH "/usr/local/bin:/usr/bin:/bin" \
    --setenv LANG "${LANG:-C.UTF-8}" \
    --setenv WAYLAND_DISPLAY "$WAYLAND_DISPLAY" \
    --setenv HYPRLAND_INSTANCE_SIGNATURE "$HYPRLAND_INSTANCE_SIGNATURE" \
    --setenv XDG_RUNTIME_DIR "$RT" \
    --setenv XDG_CONFIG_HOME "$DIR/config" \
    --setenv XDG_STATE_HOME "$DIR/state" \
    --setenv XDG_CACHE_HOME "$DIR/cache" \
    --setenv XDG_DATA_HOME "$XDG_DATA_HOME" \
    --setenv QT_QPA_PLATFORM wayland \
    --setenv XCURSOR_THEME "${XCURSOR_THEME:-}" \
    --setenv XCURSOR_SIZE "${XCURSOR_SIZE:-24}" \
    --setenv SLEEPYSHELL_SANDBOX "$DIR" \
    --setenv KIT "$KIT" \
    --chdir "$DIR" \
    "$@"
