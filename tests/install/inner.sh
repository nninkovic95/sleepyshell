#!/bin/bash
# Inside the sandbox of installer.test.sh: one fresh world per scenario, then install.sh with the scenario's answers.
#
#   inner.sh D SCENARIO...
#
# A world is D/<scenario>: home/ (the user's home, with the kit's fixture Hyprland config), clone/ (a copy of D/clone-src,
# the clone install.sh runs from), bin/ (the only PATH: links to the system's own programs, minus everything install.sh
# could install, enable or start with, which are the stand-ins of stub.py instead), stub/ (the stand-ins' package
# database and call log), os-release, dev/ and modules-load.d/. The answers of a scenario are its stdin (plain mode).
# Writes D/<scenario>/out.txt (everything install.sh printed) and rc (its exit code). The checks are in installer.test.sh.
set -u
D=$1
shift
KIT=${KIT:?}
# paru and yay only where a scenario has an AUR helper (helper NAME WORLD)
STUBS=(pacman sudo systemctl hyprctl qs git makepkg awww awww-daemon notify-send)
DENY=" pacman sudo doas systemctl hyprctl qs quickshell paru yay git makepkg awww awww-daemon swww swww-daemon notify-send hypridle Hyprland hyprland pkexec su "

if [ ! -d "$D/bin-base" ]; then
    mkdir -p "$D/bin-base"
    for f in /usr/bin/*; do
        n=${f##*/}
        case "$DENY" in *" $n "*) continue ;; esac
        ln -s "$f" "$D/bin-base/$n"
    done
fi

# world NAME: a fresh world (Arch, Hyprland 0.57.1, nothing of the shell's installed but a few base packages)
world() {
    local S=$D/$1
    mkdir -p "$S/home/.config" "$S/stub" "$S/dev" "$S/modules-load.d" "$S/proc"
    cp -a "$D/bin-base" "$S/bin"
    for n in "${STUBS[@]}"; do ln -sf "$KIT/install/stub.py" "$S/bin/$n"; done
    cp -a "$D/clone-src" "$S/clone"
    cp -r "$KIT/fixtures/hypr" "$S/home/.config/hypr"
    printf 'NAME="Arch Linux"\nPRETTY_NAME="Arch Linux"\nID=arch\n' >"$S/os-release"
    printf '%s\n' quickshell ttf-jetbrains-mono-nerd python matugen imagemagick awww hypridle pipewire wireplumber \
        networkmanager bluez fakeroot wl-clipboard power-profiles-daemon systemd util-linux glib2 xdg-utils fontconfig \
        libnotify uwsm khal pciutils hyprpicker git base-devel bash >"$S/stub/repo"
    printf '%s\n' "bash explicit repo" "systemd explicit repo" "util-linux explicit repo" "glib2 explicit repo" \
        "fontconfig explicit repo" "pciutils explicit repo" "xdg-utils explicit repo" "python explicit repo" >"$S/stub/installed"
    : >"$S/stub/calls.log"
}

# helper NAME WORLD: the world has that AUR helper installed
helper() {
    ln -sf "$KIT/install/stub.py" "$D/$2/bin/$1"
    printf '%s explicit aur\n' "$1" >>"$D/$2/stub/installed"
}

# run NAME [install.sh options]: install.sh in that world, answers on stdin; extra environment from $S/env (KEY=VALUE lines)
run() {
    local S=$D/$1 extra=()
    shift
    [ -f "$S/env" ] && mapfile -t extra <"$S/env"
    env -i HOME="$S/home" PATH="$S/bin" LANG=C.UTF-8 TERM=dumb \
        XDG_CONFIG_HOME="$S/home/.config" XDG_STATE_HOME="$S/home/.local/state" XDG_CACHE_HOME="$S/home/.cache" \
        XDG_DATA_HOME="$S/home/.local/share" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}" \
        HYPRLAND_INSTANCE_SIGNATURE=test SLEEPYSHELL_OS_RELEASE="$S/os-release" SLEEPYSHELL_DEV="$S/dev" \
        SLEEPYSHELL_MODULES_LOAD="$S/modules-load.d" SLEEPYSHELL_HYPRIDLE_SERVICE=none SLEEPYSHELL_HYPRIDLE_PROC="$S/proc" \
        STUB_DIR="$S/stub" STUB_BIN="$S/bin" QT_QPA_PLATFORM=offscreen "${extra[@]}" \
        timeout 120 /usr/bin/bash "$S/clone/install.sh" "$@" >"$S/out.txt" 2>&1
    echo $? >"$S/rc"
}

. "$KIT/install/scenarios.sh"
for sc in "$@"; do
    if declare -F "sc_$sc" >/dev/null; then
        "sc_$sc"
        # the scenario's stand-in shell, if it started one (by its pid, inside this sandbox's own process namespace)
        for f in "$D"/*/stub/qs.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; rm -f "$f"; done
    else
        echo "inner: no scenario $sc" >&2
    fi
done
