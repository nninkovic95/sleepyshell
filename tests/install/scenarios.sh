# Scenarios of installer.test.sh, sourced by inner.sh (world, helper, run and $D are inner.sh's). Each one builds its
# world, takes a snapshot (snap), runs install.sh with the answers a user would type (plain mode, one per line) and takes
# another; the checks read the worlds afterwards.

# snap WORLD TAG: the sha256 of every file and link target under the world's home and clone (the cache aside)
snap() {
    local S=$D/$1
    (cd "$S" && find home clone -path home/.cache -prune -o \( -type f -o -type l \) -print0 | sort -z |
        while IFS= read -r -d '' f; do
            if [ -L "$f" ]; then printf 'link %s %s\n' "$(readlink "$f")" "$f"; else sha256sum -- "$f"; fi
        done) >"$S/snap-$2"
}
answers() { printf '%s\n' "$@"; }

# refused before any question
sc_refuse_os() {
    world refuse_os
    printf 'NAME="Ubuntu"\nPRETTY_NAME="Ubuntu 24.04 LTS"\nID=ubuntu\nID_LIKE=debian\n' >"$D/refuse_os/os-release"
    snap refuse_os before; run refuse_os </dev/null; snap refuse_os after
}
sc_refuse_nohypr() {
    world refuse_nohypr
    echo "HYPRLAND_INSTANCE_SIGNATURE=" >>"$D/refuse_nohypr/env"
    snap refuse_nohypr before; run refuse_nohypr </dev/null; snap refuse_nohypr after
}
sc_refuse_old() {
    world refuse_old
    echo "STUB_HYPR_VER=0.54.2" >>"$D/refuse_old/env"
    snap refuse_old before; run refuse_old </dev/null; snap refuse_old after
}
sc_refuse_conf() {
    world refuse_conf
    mv "$D/refuse_conf/home/.config/hypr/hyprland.lua" "$D/refuse_conf/home/.config/hypr/hyprland.conf"
    snap refuse_conf before; run refuse_conf </dev/null; snap refuse_conf after
}
# an Arch-based distribution passes; quitting at the first screen changes nothing
sc_derivative() {
    world derivative
    printf 'NAME="CachyOS Linux"\nPRETTY_NAME="CachyOS"\nID=cachyos\nID_LIKE=arch\n' >"$D/derivative/os-release"
    snap derivative before; answers n | run derivative --plain; snap derivative after
}
# no Python: the installer asks to install it, and quitting there changes nothing
sc_nopython() {
    world nopython
    rm -f "$D/nopython/bin/python3"
    snap nopython before; answers y n | run nopython --plain; snap nopython after
}

# a fresh machine, no AUR helper: build paru, yes to every file, NetworkManager, hypridle and i2c-dev, no to Bluetooth
# and power profiles; then the same installer again over the result
sc_fresh() {
    world fresh
    snap fresh before
    # welcome, picker, AUR helper, require line, theme run, NetworkManager, Bluetooth, power profiles, hypridle, i2c-dev,
    # start, summary
    answers y "" y y y y n n y y y y | run fresh --plain
    snap fresh after
    cp "$D/fresh/out.txt" "$D/fresh/out-1.txt"
    cp "$D/fresh/stub/calls.log" "$D/fresh/calls-1.log"
    : >"$D/fresh/stub/calls.log"
    sleep 1
    # again: welcome, picker, theme run (no), Bluetooth, power profiles, i2c-dev (all no), summary
    answers y "" n n n n y | run fresh --plain
    snap fresh again
    cp "$D/fresh/out.txt" "$D/fresh/out-2.txt"
    # the user edits the installer's module: a third run asks before replacing it (no: kept), then the rest as above
    printf -- '-- my own line\n' >>"$D/fresh/home/.config/hypr/modules/sleepyshell.lua"
    cp "$D/fresh/home/.config/hypr/modules/sleepyshell.lua" "$D/fresh/module-edited"
    answers y "" n n n n n y | run fresh --plain
}

# a machine with files of its own in the way: an existing shell folder, a matugen config with a kitty template; first
# quit at the folder question, then say no to every change of a file of the user's
sc_declines() {
    world declines
    local H=$D/declines/home
    helper paru declines
    mkdir -p "$H/.config/quickshell/sleepyshell" "$H/.config/matugen/templates" "$H/.config/kitty"
    echo "// someone else's shell" >"$H/.config/quickshell/sleepyshell/shell.qml"
    printf '[config]\n\n[templates.kitty]\ninput_path = "~/.config/matugen/templates/kitty.conf"\noutput_path = "~/.config/kitty/kitty.conf"\n' >"$H/.config/matugen/config.toml"
    printf 'background {{colors.surface.default.hex}}\n' >"$H/.config/matugen/templates/kitty.conf"
    printf 'background #123456\n' >"$H/.config/kitty/kitty.conf"
    snap declines before
    answers y "" n | run declines --plain
    snap declines quit
    cp "$D/declines/out.txt" "$D/declines/out-quit.txt"
    # welcome, picker, shell folder (yes), require line (no), matugen lines (no), theme run (no), NetworkManager,
    # Bluetooth, power profiles, hypridle, i2c-dev, start (all no), summary
    answers y "" y n n n n n n n n n y | run declines --plain
    snap declines after
}

# --dry-run: every question, the summary, and nothing changed
sc_dryrun() {
    world dryrun
    snap dryrun before
    answers y "" y y y y y y y y y y | run dryrun --plain --dry-run
    snap dryrun after
}

# no AUR helper and no to building one: the AUR packages are left out and nothing from the AUR runs
sc_aur_declined() {
    world aur_declined
    answers y "" n n n n n n n n n y | run aur_declined --plain
}

# hyprland.lua is edited while pacman runs: the require line is not added over the edit
sc_changed() {
    world changed
    helper paru changed
    echo "$D/changed/home/.config/hypr/hyprland.lua" >"$D/changed/stub/touch-during-pacman"
    cp "$D/changed/home/.config/hypr/hyprland.lua" "$D/changed/hyprland.orig"
    # welcome, picker, require line, theme run (no), NetworkManager, Bluetooth, power profiles, hypridle, i2c-dev, start,
    # summary
    answers y "" y n n n n n n n y | run changed --plain
}

# a key already bound, a bar the config starts: the key is left out of the module, both are reported
sc_taken() {
    world taken
    helper paru taken
    printf 'hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"))\nhl.on("hyprland.start", function()\n    hl.exec_cmd("waybar")\nend)\n' \
        >>"$D/taken/home/.config/hypr/modules/binds.lua"
    answers y "" y n n n n n n n y | run taken --plain
}

# Ctrl+C right after pacman: the installed packages are still in the record
sc_interrupted() {
    world interrupted
    helper paru interrupted
    : >"$D/interrupted/stub/interrupt-after-pacman"
    answers y "" n n n n n n n n y | run interrupted --plain
}

# hyprland.lua already requires the module but the module file is missing (a config copied from another machine): no
# question about the line, the module is made, and hyprland.lua is neither changed nor recorded as changed
sc_dotfiles() {
    world dotfiles
    helper paru dotfiles
    printf 'require("modules.sleepyshell")\n' >>"$D/dotfiles/home/.config/hypr/hyprland.lua"
    cp "$D/dotfiles/home/.config/hypr/hyprland.lua" "$D/dotfiles/hyprland.orig"
    answers y "" n n n n n n n y | run dotfiles --plain
}

# files of the user's already there, and yes to each: a foreign sleepyshell.lua (replaced), a matugen config with a kitty
# template that runs a hook (the template appended, the hook named), an existing kitty.conf (rewritten by the theme run,
# copied first); iwd and TLP run, so NetworkManager and power-profiles-daemon are not offered
sc_existing() {
    world existing
    local H=$D/existing/home
    helper paru existing
    mkdir -p "$H/.config/hypr/modules" "$H/.config/matugen/templates" "$H/.config/kitty"
    printf -- '-- my own module\nhl.bind("SUPER + F1", hl.dsp.exec_cmd("true"))\n' >"$H/.config/hypr/modules/sleepyshell.lua"
    printf '[config]\n\n[templates.kitty]\ninput_path = "~/.config/matugen/templates/kitty.conf"\noutput_path = "~/.config/kitty/kitty.conf"\npost_hook = "true"\n' >"$H/.config/matugen/config.toml"
    printf 'background {{colors.surface.default.hex}}\n' >"$H/.config/matugen/templates/kitty.conf"
    printf 'background #123456\n' >"$H/.config/kitty/kitty.conf"
    printf '%s\n' iwd tlp >"$D/existing/stub/active"
    for f in .config/hypr/modules/sleepyshell.lua .config/matugen/config.toml .config/kitty/kitty.conf; do
        cp "$H/$f" "$D/existing/orig-${f##*/}"
    done
    # welcome, picker, replace the module, require line, matugen lines, theme run (all yes), Bluetooth, hypridle,
    # i2c-dev, start (no), summary
    answers y "" y y y y n n n n y | run existing --plain
}

# XDG_CONFIG_HOME is not ~/.config: matugen would read another config than the shell, so no theme run is offered
sc_xdg() {
    world xdg
    local H=$D/xdg/home
    mv "$H/.config/hypr" "$H/.xdgconf-hypr"
    mkdir -p "$H/xdgconf"
    mv "$H/.xdgconf-hypr" "$H/xdgconf/hypr"
    echo "XDG_CONFIG_HOME=$H/xdgconf" >>"$D/xdg/env"
    helper paru xdg
    # welcome, picker, require line, NetworkManager, Bluetooth, power profiles, hypridle, i2c-dev, start, summary
    answers y "" n n n n n n n y | run xdg --plain
}

# another polkit agent runs as a user service: keep it (the shell's prompt goes off in the new settings), or use the
# shell's (the service is disabled); the second world has no kitty and TERMINAL set, so the new settings name that one
sc_polkit_keep() {
    world polkit_keep
    helper paru polkit_keep
    echo "user:hyprpolkitagent.service" >"$D/polkit_keep/stub/active"
    # welcome, picker, require line, theme run, NetworkManager, Bluetooth, power profiles, hypridle, i2c-dev, password
    # prompt (keep mine), start, summary
    answers y "" n n n n n n n n n y | run polkit_keep --plain
}
sc_polkit_use() {
    world polkit_use
    helper paru polkit_use
    echo "user:hyprpolkitagent.service" >"$D/polkit_use/stub/active"
    rm -f "$D/polkit_use/bin/kitty"
    ln -s "$KIT/install/stub.py" "$D/polkit_use/bin/myterm"
    echo "TERMINAL=/usr/local/bin/myterm" >>"$D/polkit_use/env"
    answers y "" n n n n n n n y n y | run polkit_use --plain
}

# the clocks' font from the world's stand-in archive (see world in inner.sh); with another checksum nothing is installed
sc_font_ok() {
    world font_ok
    helper paru font_ok
    # welcome, picker, require line, theme run, NetworkManager, Bluetooth, power profiles, hypridle, i2c-dev, start, summary
    answers y "" n n n n n n n n y | run font_ok --plain
}
sc_font_bad() {
    world font_bad
    helper paru font_bad
    echo "SLEEPYSHELL_FONT_SHA256=0000000000000000000000000000000000000000000000000000000000000000" >>"$D/font_bad/env"
    answers y "" n n n n n n n n y | run font_bad --plain
}

# pacman fails: nothing after it is set up, and the run says so
sc_pacman_fails() {
    world pacman_fails
    helper paru pacman_fails
    : >"$D/pacman_fails/stub/pacman-fail"
    snap pacman_fails before
    answers y "" y y n n n n n n y | run pacman_fails --plain
    snap pacman_fails after
}

# the full-screen interface, driven by key presses through a terminal: pick, untick theming, answer, cancel at the summary
sc_tui() {
    world tui
    snap tui before
    python3 -I "$KIT/install/tui_drive.py" "$D/tui" >"$D/tui/drive.txt" 2>&1
    echo $? >"$D/tui/rc"
    snap tui after
}
