#!/bin/bash
# sandbox.sh DIR CMD...: run CMD in a bubblewrap sandbox in which only DIR can be written and nothing of the user's
# session can be reached.
#
# What the sandbox gets:
#   the whole file system read-only (fonts, icons and programs load; nothing can be written), DIR read-write, a
#   private /tmp, an empty private XDG_RUNTIME_DIR (a tmpfs at the usual short path: a Unix socket path may not
#   exceed 108 bytes), and a minimal /dev with only the GPU's render node added (no card node, so no display can be
#   driven; no /dev/input and no tty, so no real input device or virtual terminal).
#   HOME is DIR/home (a fresh, empty home with its own XDG folders) unless SANDBOX_HOME=real, which keeps the real
#   home, read-only, with XDG_CONFIG_HOME, XDG_STATE_HOME and XDG_CACHE_HOME in DIR/config, DIR/state, DIR/cache.
# What it does not get:
#   the live compositor's Wayland and Hyprland sockets (a shell under test that sent a dispatch would act on the real
#   session; whole-window tests start their own compositor and a stand-in Hyprland, common/ui/), the system D-Bus
#   (logind, NetworkManager, UPower, power profiles: a nested compositor once tried to take control of the session
#   through logind), the session D-Bus, PipeWire, the network, the live shell's IPC, or a view of outside processes.
# Lifetime: everything inside dies when CMD ends or this script is killed (--die-with-parent, and the PID namespace
#   ends with its first process); the caller deletes DIR.
# CMD inherits only the variables listed here (--clearenv); QT_QPA_PLATFORM is offscreen until a test starts its own
# compositor.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/env.sh"
DIR=$(readlink -f "${1:?run folder}")
shift
case "$DIR/" in "$RUN"/*) ;; *) echo "sandbox: $DIR is not under $RUN"; exit 2 ;; esac
RT=$XDG_RUNTIME_DIR
# without a real runtime folder env.sh falls back to /tmp, and the session's own runtime folder would stay visible
case "$RT" in /run/user/*) ;; *) echo "sandbox: XDG_RUNTIME_DIR is not a /run/user folder ($RT)"; exit 2 ;; esac
# a fresh home holds its own XDG folders, as a real one does; with the real home they are run folders of their own
H=$DIR/home CFG=$DIR/home/.config ST=$DIR/home/.local/state CA=$DIR/home/.cache DA=$DIR/home/.local/share
[ "${SANDBOX_HOME:-fake}" = real ] && H=$HOME CFG=$DIR/config ST=$DIR/state CA=$DIR/cache DA=$XDG_DATA_HOME
mkdir -p "$H" "$CFG" "$ST" "$CA" "$DA" 2>/dev/null || true
render=()
for n in /dev/dri/renderD*; do
    [ -e "$n" ] && render+=(--dev-bind "$n" "$n")
done

exec bwrap \
    --ro-bind / / \
    --dev /dev \
    "${render[@]}" \
    --proc /proc \
    --tmpfs /tmp \
    --tmpfs /run/user \
    --tmpfs "$RT" \
    --tmpfs /run/dbus \
    --bind "$DIR" "$DIR" \
    --unshare-pid --unshare-ipc --unshare-net --unshare-uts \
    --die-with-parent --new-session \
    --clearenv \
    --setenv HOME "$H" \
    --setenv PATH "/usr/local/bin:/usr/bin:/bin" \
    --setenv LANG "${LANG:-C.UTF-8}" \
    --setenv XDG_RUNTIME_DIR "$RT" \
    --setenv XDG_CONFIG_HOME "$CFG" \
    --setenv XDG_STATE_HOME "$ST" \
    --setenv XDG_CACHE_HOME "$CA" \
    --setenv XDG_DATA_HOME "$DA" \
    --setenv QT_QPA_PLATFORM offscreen \
    --setenv SLEEPYSHELL_SANDBOX "$DIR" \
    --setenv KIT "$KIT" \
    --chdir "$DIR" \
    "$@"
