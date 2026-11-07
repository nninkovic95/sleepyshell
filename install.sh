#!/usr/bin/env bash
# install.sh: install Sleepy Shell from this clone, with every dependency.
#
#   ./install.sh [--plain] [--dry-run]
#
#   --plain     plain questions instead of the full-screen interface (also used by itself when the terminal cannot
#               show it: not a terminal, TERM=dumb, or smaller than 60x18)
#   --dry-run   ask everything and show the summary, then stop; nothing is installed or changed
#
# For Hyprland 0.55 or newer with the Lua config (hyprland.lua), on Arch Linux or an Arch-based distribution; anything
# else is refused before a question is asked. Run it as your user from a terminal inside Hyprland; it asks for sudo only
# for pacman, for the system services you say yes to and for the i2c-dev module file.
#
# What it does, in order: checks the system, lets you pick the optional parts (all picked to start with), asks about
# AUR packages when there is no AUR helper, about each system service and about every file of yours it would change,
# shows a summary of everything it will do, and only after a yes installs the packages and sets the shell up: the link
# ~/.config/quickshell/sleepyshell to this clone, the default settings, a Hyprland module of its own
# (modules/sleepyshell.lua) and one require line for it in hyprland.lua, the Keybinds tab's file, hypridle.conf, the
# matugen template of the bar's colours, a first theme run, and the shell itself. A file of yours is changed only after a
# yes to a question that shows the change, and is copied first. A final report says what was done and what is left.
#
# Everything it installs, creates or changes is recorded in $XDG_STATE_HOME/sleepyshell/install/ (manifest.tsv, one
# line per change, with the copies under backups/<run>/ and a report per run), so it can all be undone later.
#
# Bash with ncurses' tput only (both come with every Arch install): the interface needs nothing installed first.
# Tests: SLEEPYSHELL_OS_RELEASE names another os-release file, SLEEPYSHELL_DEV and SLEEPYSHELL_MODULES_LOAD stand in for
# /dev and /etc/modules-load.d (where the i2c-dev question looks).
set -uo pipefail

SRC=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
PLAIN=0 DRY=0
for a in "$@"; do
    case $a in
    --plain) PLAIN=1 ;;
    --dry-run) DRY=1 ;;
    -h | --help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option $a (see --help)" >&2; exit 2 ;;
    esac
done

CFG=${XDG_CONFIG_HOME:-$HOME/.config}
STATE_BASE=${XDG_STATE_HOME:-$HOME/.local/state}/sleepyshell/install
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$STATE_BASE/backups/$STAMP
MANIFEST=$STATE_BASE/manifest.tsv
HYPR=$CFG/hypr
LINK=$CFG/quickshell/sleepyshell
MIN_HYPR=0.55
WORK=$(mktemp -d)
PLAN=$WORK/plan.json
LOG=$WORK/steps.log

# ---------------------------------------------------------------------------------------------------------------------
# Checks that need no question: who, where, which system, which compositor. Each one stops with a plain sentence.
die() {
    printf '\n%s\n\n' "$*" >&2
    exit 1
}

[ "$(id -u)" -ne 0 ] || die "Run install.sh as your own user, not as root or with sudo. It asks for sudo itself when it needs it."
[ -f "$SRC/shell.qml" ] && [ -f "$SRC/tools/install.py" ] ||
    die "install.sh must be run from inside its Sleepy Shell clone (shell.qml was not found beside it)."

OSR=${SLEEPYSHELL_OS_RELEASE:-/etc/os-release}
os_field() { sed -n "s/^$1=//p" "$OSR" 2>/dev/null | head -1 | tr -d '"'"'"; }
OS_ID=$(os_field ID) OS_LIKE=$(os_field ID_LIKE) OS_NAME=$(os_field PRETTY_NAME)
case " $OS_ID $OS_LIKE " in
*" arch "*) command -v pacman >/dev/null ||
    die "Sleepy Shell installs only on Arch Linux and Arch-based distributions, and this one has no pacman." ;;
*) die "Sleepy Shell installs only on Arch Linux and Arch-based distributions (it uses pacman and the AUR).
This system is ${OS_NAME:-${OS_ID:-unknown}}." ;;
esac

HYPR_MSG="Sleepy Shell is a desktop shell for Hyprland only: it needs Hyprland $MIN_HYPR or newer with the Lua config (hyprland.lua)."
[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null ||
    die "$HYPR_MSG
No Hyprland session was found. Log in to Hyprland and run install.sh again from a terminal there."
HYPR_VER=$(hyprctl version -j 2>/dev/null | sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' | head -1)
[ -n "$HYPR_VER" ] || HYPR_VER=$(hyprctl version -j 2>/dev/null | sed -n 's/^[[:space:]]*"tag":[[:space:]]*"v\([0-9][0-9.]*\)".*/\1/p' | head -1)
[ -n "$HYPR_VER" ] || die "$HYPR_MSG
Hyprland's version could not be read (hyprctl version)."
[ "$(printf '%s\n%s\n' "$MIN_HYPR" "$HYPR_VER" | sort -V | head -1)" = "$MIN_HYPR" ] ||
    die "$HYPR_MSG
This is Hyprland $HYPR_VER. Update Hyprland, then run install.sh again."
if [ ! -f "$HYPR/hyprland.lua" ]; then
    [ -f "$HYPR/hyprland.conf" ] && die "$HYPR_MSG
Your config is still $HYPR/hyprland.conf. Move it to the Lua format (hyprland.lua), then run install.sh again."
    die "$HYPR_MSG
$HYPR/hyprland.lua was not found."
fi

# ---------------------------------------------------------------------------------------------------------------------
# The interface: a full-screen one drawn with escape codes, or plain questions. Every screen is built in BODY as
# "style<TAB>text" lines, wrapped to the width, then drawn by one of the screen functions.
TUI=0
if [ "$PLAIN" = 0 ] && [ -t 0 ] && [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && command -v tput >/dev/null; then
    read -r ROWS COLS < <(stty size 2>/dev/null) || true
    [ "${ROWS:-0}" -ge 18 ] && [ "${COLS:-0}" -ge 60 ] && TUI=1
fi
ESC=$'\e'
S_N="$ESC[0m" S_B="$ESC[1m" S_D="$ESC[2m" S_R="$ESC[7m" S_A="$ESC[1;36m" S_G="$ESC[32m" S_Y="$ESC[33m" S_E="$ESC[1;31m"
# plain text where the output is not a terminal that understands them
if [ "$TUI" = 0 ] && { [ ! -t 1 ] || [ "${TERM:-dumb}" = dumb ]; }; then S_N="" S_B="" S_D="" S_R="" S_A="" S_G="" S_Y="" S_E=""; fi
IN_TUI=0
tui_enter() {
    [ "$TUI" = 1 ] || return 0
    tput smcup 2>/dev/null; tput civis 2>/dev/null
    IN_TUI=1
}
tui_leave() {
    [ "$IN_TUI" = 1 ] || return 0
    printf '%s' "$S_N"; tput cnorm 2>/dev/null; tput rmcup 2>/dev/null
    IN_TUI=0
}
cleanup() {
    tui_leave
    rm -rf -- "$WORK"
}
trap cleanup EXIT
# stopped part way: the packages installed so far still go into the record
on_stop() {
    tui_leave
    [ -f "$WORK/before" ] && record_packages >/dev/null 2>&1
    printf '\nStopped. Nothing more was changed; what was done so far is in %s.\n' "$MANIFEST" >&2
    exit 130
}
trap on_stop INT TERM HUP

style() {
    case $1 in
    b) printf '%s' "$S_B" ;; d) printf '%s' "$S_D" ;; a) printf '%s' "$S_A" ;; g) printf '%s' "$S_G" ;;
    y) printf '%s' "$S_Y" ;; e) printf '%s' "$S_E" ;; *) ;;
    esac
}
BODY=()
body_clear() { BODY=(); }
# say STYLE TEXT...: one paragraph (styles: n plain, b bold, d dim, a accent, g green, y yellow, e red)
say() {
    local s=$1
    shift
    BODY+=("$s"$'\t'"$*")
}
blank() { BODY+=("n"$'\t'""); }
# the body wrapped to width W into WRAPPED (continuation lines keep the paragraph's indent)
wrap_body() {
    local w=$1 e s t ind line
    WRAPPED=()
    for e in "${BODY[@]}"; do
        s=${e%%$'\t'*} t=${e#*$'\t'}
        if [ -z "$t" ]; then WRAPPED+=("n"$'\t'""); continue; fi
        ind=${t%%[! ]*}
        while IFS= read -r line; do
            WRAPPED+=("$s"$'\t'"$line")
        done < <(printf '%s\n' "${t#"$ind"}" | fold -s -w $((w - ${#ind})) | sed "s/^/$ind/;s/ *$//")
    done
}
size() {
    read -r ROWS COLS < <(stty size 2>/dev/null) || true
    ROWS=${ROWS:-24} COLS=${COLS:-80}
}
# the frame: title bar, body lines from WRAPPED starting at $1, footer hints $2, button row $3 (already styled)
draw() {
    local top=$1 hint=$2 buttons=${3:-} area i e s t out title
    area=$((ROWS - 4))
    [ -n "$buttons" ] && area=$((area - 2))
    title=" Sleepy Shell installer: $SCREEN "
    out="$ESC[H$ESC[2J$S_R$(printf '%-*.*s' "$COLS" "$COLS" "$title")$S_N"$'\n\n'
    for ((i = 0; i < area; i++)); do
        e=${WRAPPED[top + i]:-}
        if [ -n "$e" ]; then
            s=${e%%$'\t'*} t=${e#*$'\t'}
            out+="  $(style "$s")${t:0:$((COLS - 3))}$S_N"
        fi
        out+=$'\n'
    done
    if [ -n "$buttons" ]; then out+=$'\n'"  $buttons"$'\n'; fi
    local more=""
    [ $((top + area)) -lt ${#WRAPPED[@]} ] && more="  (more below)"
    out+=$'\n'"$S_D  ${hint}${more}$S_N"
    printf '%s' "$out"
}
KEY=""
read_key() {
    local k r
    IFS= read -rsn1 k || { KEY=eof; return; }
    case $k in
    "$ESC")
        IFS= read -rsn1 -t 0.05 r || { KEY=esc; return; }
        if [ "$r" = "[" ] || [ "$r" = "O" ]; then
            IFS= read -rsn1 -t 0.05 r || r=""
            case $r in
            A) KEY=up ;; B) KEY=down ;; C) KEY=right ;; D) KEY=left ;; H) KEY=home ;; F) KEY=end ;;
            5) IFS= read -rsn1 -t 0.05 _; KEY=pgup ;; 6) IFS= read -rsn1 -t 0.05 _; KEY=pgdn ;;
            *) KEY=other ;;
            esac
        else
            KEY=esc
        fi
        ;;
    "") KEY=enter ;;
    " ") KEY=space ;;
    $'\t') KEY=tab ;;
    *) KEY=$k ;;
    esac
}
scroll() {
    local area=$1 max
    max=$((${#WRAPPED[@]} - area))
    [ "$max" -lt 0 ] && max=0
    case $KEY in
    up | k) TOP=$((TOP - 1)) ;; down | j) TOP=$((TOP + 1)) ;; pgup) TOP=$((TOP - area)) ;; pgdn) TOP=$((TOP + area)) ;;
    home) TOP=0 ;; end) TOP=$max ;;
    esac
    [ "$TOP" -gt "$max" ] && TOP=$max
    [ "$TOP" -lt 0 ] && TOP=0
}
plain_body() {
    local e s t
    wrap_body "$(( ${COLS:-80} > 100 ? 100 : ${COLS:-80} ))"
    for e in "${WRAPPED[@]}"; do
        s=${e%%$'\t'*} t=${e#*$'\t'}
        printf '%s\n' "$t"
    done
}

# ask TITLE DEFAULT(y|n) YES-LABEL NO-LABEL: the body and a choice; 0 for yes
ask() {
    SCREEN=$1
    local def=$2 yes=$3 no=$4 sel ans b area
    if [ "$TUI" = 0 ]; then
        printf '\n== %s ==\n' "$1"
        plain_body
        local hint="[y/N]"
        [ "$def" = y ] && hint="[Y/n]"
        while :; do
            printf '%s / %s %s ' "$yes" "$no" "$hint"
            IFS= read -r ans || ans=""
            case ${ans,,} in
            y | yes) return 0 ;; n | no) return 1 ;;
            "") [ "$def" = y ] && return 0; return 1 ;;
            esac
        done
    fi
    sel=$def TOP=0
    while :; do
        size
        wrap_body $((COLS - 4))
        area=$((ROWS - 6))
        if [ "$sel" = y ]; then b="$S_R[ $yes ]$S_N   [ $no ]"; else b="[ $yes ]   $S_R[ $no ]$S_N"; fi
        draw "$TOP" "Left/Right choose, Enter confirms, y/n answer, Up/Down scroll" "$b"
        read_key
        case $KEY in
        left | right | tab | h | l) [ "$sel" = y ] && sel=n || sel=y ;;
        y | Y) return 0 ;; n | N | esc | q) return 1 ;;
        enter) [ "$sel" = y ] && return 0; return 1 ;;
        eof) return 1 ;;
        *) scroll "$area" ;;
        esac
    done
}

# page TITLE: the body to read; Enter or q closes it
page() {
    SCREEN=$1
    local area
    if [ "$TUI" = 0 ]; then
        printf '\n== %s ==\n' "$1"
        plain_body
        return 0
    fi
    TOP=0
    while :; do
        size
        wrap_body $((COLS - 4))
        area=$((ROWS - 4))
        draw "$TOP" "Up/Down/PgUp/PgDn scroll, Enter or q closes"
        read_key
        case $KEY in
        enter | q | esc | eof) return 0 ;;
        *) scroll "$area" ;;
        esac
    done
}

# ---------------------------------------------------------------------------------------------------------------------
# The parts. Each: id|label|what it enables|packages. "core" is always installed.
COMPONENTS=(
    "core|Sleepy Shell|Always installed: Quickshell, the Nerd Font for text and icons, Python 3.|quickshell ttf-jetbrains-mono-nerd python"
    "theme|Wallpaper theming|Colours from your wallpaper, the wallpaper picker and Shuffle colours.|matugen imagemagick awww"
    "idle|Idle timers|Dim, lock and sleep after a while.|hypridle"
    "audio|Audio|The audio pill and panels, and the microphone, camera and screen-share indicators.|pipewire wireplumber"
    "network|Network|The network widget and the Wi-Fi tile.|networkmanager"
    "bluetooth|Bluetooth|The Bluetooth tile and widget.|bluez"
    "updates|Package updates|The updates widget and Update now.|paru fakeroot"
    "wlclip|Screenshot copy|Copying a screenshot from its notification.|wl-clipboard"
    "power|Power profiles|The power profile tile and a profile per power source.|power-profiles-daemon"
    "system|System tools|Backlight slider, lid and session actions, default apps, icon theme and font, test notifications.|systemd util-linux glib2 xdg-utils fontconfig libnotify"
    "logout|Log out|Log out from the session menu.|uwsm"
    "walker|Clipboard button|The clipboard button (walker's clipboard mode).|walker elephant elephant-clipboard"
    "calendar|Calendar|The calendar popup and the Calendar tool.|khal"
    "gpu|GPU names|GPU names in the System tab instead of PCI ids.|pciutils"
    "apps|Mixer and colour picker|The Audio mixer tool and the Colour picker tool.|pwvucontrol hyprpicker"
)
NC=${#COMPONENTS[@]}
C_ID=() C_LABEL=() C_DESC=() C_PKGS=() C_ON=()
for ((i = 0; i < NC; i++)); do
    IFS='|' read -r id label desc pkgs <<<"${COMPONENTS[i]}"
    C_ID+=("$id") C_LABEL+=("$label") C_DESC+=("$desc") C_PKGS+=("$pkgs") C_ON+=(1)
done
picked() {
    local i
    for ((i = 0; i < NC; i++)); do [ "${C_ID[i]}" = "$1" ] && [ "${C_ON[i]}" = 1 ] && return 0; done
    return 1
}

# which packages are missing (pacman -T knows what other packages provide), and where each one comes from
declare -A MISSING=() FROM=()
refresh_packages() {
    local all=() p
    MISSING=()
    for ((i = 0; i < NC; i++)); do for p in ${C_PKGS[i]}; do all+=("$p"); done; done
    while IFS= read -r p; do [ -n "$p" ] && MISSING[$p]=1; done < <(pacman -T "${all[@]}" 2>/dev/null)
    for p in "${!MISSING[@]}"; do
        [ -n "${FROM[$p]:-}" ] && continue
        if pacman -Si "$p" >/dev/null 2>&1; then FROM[$p]=repo; else FROM[$p]=aur; fi
    done
}
# the wallpaper daemon: awww, or swww where only the old name is packaged
pkg_name() {
    if [ "$1" = awww ] && [ "${FROM[awww]:-repo}" = aur ] && pacman -Si swww >/dev/null 2>&1; then
        echo swww
    else
        echo "$1"
    fi
}
pkg_line() {
    local p out=() n
    for p in $1; do
        n=$(pkg_name "$p")
        if [ -z "${MISSING[$p]:-}" ]; then out+=("$n (installed)")
        elif [ "${FROM[$p]}" = aur ] && [ "$n" = "$p" ]; then out+=("$n (AUR)")
        else out+=("$n"); fi
    done
    local IFS=,
    printf '%s' "${out[*]}" | sed 's/,/, /g'
}

# the component picker: 0 to go on, 1 to quit
picker() {
    SCREEN="Pick the parts"
    if [ "$TUI" = 0 ]; then
        local ans n
        while :; do
            printf '\n== %s ==\n' "$SCREEN"
            printf 'Everything is picked to start with. Each part enables one feature; without it, that feature is greyed out or hidden.\n\n'
            for ((i = 0; i < NC; i++)); do
                local mark="[x]"
                [ "${C_ON[i]}" = 0 ] && mark="[ ]"
                [ "$i" = 0 ] && mark="[*]"
                printf '%2d %s %s: %s\n      %s\n' "$((i + 1))" "$mark" "${C_LABEL[i]}" "${C_DESC[i]}" "$(pkg_line "${C_PKGS[i]}")"
            done
            printf '\n[*] is always installed. Numbers switch parts on or off (e.g. 3 7), a picks all, n none, Enter goes on, q quits: '
            IFS= read -r ans || ans=""
            case $ans in
            "") return 0 ;; q | Q) return 1 ;;
            a | A) for ((i = 1; i < NC; i++)); do C_ON[i]=1; done ;;
            n | N) for ((i = 1; i < NC; i++)); do C_ON[i]=0; done ;;
            *) for n in $ans; do
                [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 2 ] && [ "$n" -le "$NC" ] && C_ON[n - 1]=$((1 - C_ON[n - 1]))
            done ;;
            esac
        done
    fi
    local cur=0 top=0 per area out mark i line
    while :; do
        size
        area=$(((ROWS - 6) / 3))
        [ "$cur" -lt "$top" ] && top=$cur
        [ "$cur" -ge $((top + area)) ] && top=$((cur - area + 1))
        out="$ESC[H$ESC[2J$S_R$(printf '%-*.*s' "$COLS" "$COLS" " Sleepy Shell installer: $SCREEN ")$S_N"$'\n'
        out+="$S_D  All parts start picked. Without a part its feature is greyed out or hidden; the rest works.$S_N"$'\n'
        for ((i = top; i < NC && i < top + area; i++)); do
            mark="[x]"
            [ "${C_ON[i]}" = 0 ] && mark="[ ]"
            [ "$i" = 0 ] && mark="[*]"
            line=$(printf '%s %s' "$mark" "${C_LABEL[i]}")
            if [ "$i" = "$cur" ]; then out+=$'\n'"$S_R> ${line:0:$((COLS - 3))}$S_N"$'\n'
            else out+=$'\n'"  $S_B${line:0:$((COLS - 3))}$S_N"$'\n'; fi
            out+="      ${C_DESC[i]:0:$((COLS - 7))}"$'\n'
            line=$(pkg_line "${C_PKGS[i]}")
            out+="$S_D      ${line:0:$((COLS - 7))}$S_N"
        done
        out+=$'\n\n'"$S_D  Up/Down move, Space switches, a all, n none, Enter goes on, q quits. [*] is always installed.$S_N"
        printf '%s' "$out"
        read_key
        case $KEY in
        up | k) [ "$cur" -gt 0 ] && cur=$((cur - 1)) ;;
        down | j) [ "$cur" -lt $((NC - 1)) ] && cur=$((cur + 1)) ;;
        home) cur=0 ;; end) cur=$((NC - 1)) ;;
        space | x) [ "$cur" -gt 0 ] && C_ON[cur]=$((1 - C_ON[cur])) ;;
        a) for ((i = 1; i < NC; i++)); do C_ON[i]=1; done ;;
        n) for ((i = 1; i < NC; i++)); do C_ON[i]=0; done ;;
        enter) return 0 ;;
        q | esc | eof) return 1 ;;
        esac
    done
}

# ---------------------------------------------------------------------------------------------------------------------
# What will be done: filled by the questions, shown in the summary, done in order.
REPO_PKGS=() AUR_PKGS=() AUR_LEFT=() SERVICES=() TODO=() DECLINED=()
BOOTSTRAP=0 HELPER="" I2C=0 START=0
DO_LINK="" DO_SETTINGS=0 DO_MODULE="" DO_REQUIRE=0 DO_BINDS=0 DO_IDLE=0 DO_MATUGEN="" DO_THEME=0
jget() { python3 -I -c '
import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    v = v[int(k)] if isinstance(v, list) else v.get(k) if isinstance(v, dict) else None
print("" if v is None else json.dumps(v) if isinstance(v, (bool, list, dict)) else v, end="")' "$PLAN" "$1"; }
# running NAME: is a program of that name running (pgrep -x sees only the first 15 characters of a name)
running() {
    if [ ${#1} -le 15 ]; then pgrep -x -- "$1" >/dev/null; else pgrep -f -- "(^|/)$1( |\$)" >/dev/null; fi
}
# active [--user] UNIT: is the unit running
active() {
    if [ "$1" = --user ]; then systemctl --user is-active --quiet "$2" 2>/dev/null; else systemctl is-active --quiet "$1" 2>/dev/null; fi
}

record() {
    mkdir -p "$STATE_BASE"
    if [ ! -f "$MANIFEST" ]; then
        printf '# Sleepy Shell installer record: run<TAB>kind<TAB>details. Kinds: package NAME explicit|dependency repo|aur;\n# service system|user UNIT; link PATH TARGET; moved PATH BACKUP; created PATH; changed PATH BACKUP; backup PATH BACKUP;\n# root-created PATH; dir-created PATH; pending PATH (a write began: a later line for PATH says what it did, none means\n# it may or may not have happened).\n' >"$MANIFEST"
    fi
    local IFS=$'\t'
    printf '%s\t%s\n' "$STAMP" "$*" >>"$MANIFEST"
}

# ensure_dir DIR: make DIR, recording every folder of it that did not exist (the uninstall removes them if empty)
ensure_dir() {
    local d=$1 missing=()
    while [ -n "$d" ] && [ "$d" != / ] && [ ! -e "$d" ]; do missing=("$d" "${missing[@]}"); d=$(dirname "$d"); done
    mkdir -p -- "$1" || return 1
    for d in "${missing[@]}"; do record dir-created "$d"; done
}

main() {
    tui_enter
    body_clear
    say b "Sleepy Shell $(git -C "$SRC" describe --tags --always 2>/dev/null || true)"
    blank
    say n "This installs Sleepy Shell for Hyprland from $SRC, with everything it needs."
    blank
    say n "Found: ${OS_NAME:-Arch-based system}, Hyprland $HYPR_VER with hyprland.lua."
    blank
    say n "First you pick the parts you want, then it asks before anything that touches your files or your system, then shows a summary. Nothing is installed or changed before you say yes to that summary."
    [ "$DRY" = 1 ] && { blank; say y "Dry run: it stops after the summary."; }
    ask "Welcome" y "Go on" "Quit" || return 1

    # the installer's own helpers are Python
    if ! command -v python3 >/dev/null; then
        body_clear
        say n "The installer itself needs Python 3 (it reads your config files and writes them safely), and the settings app uses it too."
        blank
        say a "sudo pacman -S --needed python"
        [ "$DRY" = 1 ] && { blank; say y "This is a dry run, so it stops here: Python is needed to work out the rest."; }
        ask "Python 3" n "Install it" "Quit" || return 1
        [ "$DRY" = 1 ] && return 1
        tui_leave
        sudo pacman -S --needed python || { tui_enter; body_clear; say e "Python 3 was not installed, so the installer stops here. Nothing else was changed."; page "Stopped"; return 1; }
        record package python explicit repo
        tui_enter
    fi

    refresh_packages
    picker || return 1

    # packages, by source
    local p n i
    for ((i = 0; i < NC; i++)); do
        [ "${C_ON[i]}" = 1 ] || continue
        for p in ${C_PKGS[i]}; do
            [ -n "${MISSING[$p]:-}" ] || continue
            n=$(pkg_name "$p")
            if [ "${FROM[$p]}" = aur ] && [ "$n" = "$p" ]; then AUR_PKGS+=("$n"); else REPO_PKGS+=("$n"); fi
        done
    done
    if [ ${#AUR_PKGS[@]} -gt 0 ]; then
        HELPER=$(command -v paru >/dev/null && echo paru || { command -v yay >/dev/null && echo yay; } || true)
        if [ -z "$HELPER" ]; then
            body_clear
            say n "These picked packages come from the AUR, and no AUR helper (paru or yay) is installed:"
            say a "  ${AUR_PKGS[*]}"
            blank
            say n "Build paru now? The installer would install git and base-devel from the repositories, download paru-bin's build files from aur.archlinux.org into a temporary folder, build it with makepkg and install it (makepkg asks for sudo). AUR packages are made by users, not by your distribution; paru-bin is published by paru's author."
            blank
            say n "No: the AUR packages are left out, and the features that need them stay greyed out. You can install them later."
            if ask "AUR helper" n "Build paru" "Leave them out"; then
                BOOTSTRAP=1 HELPER=paru
                for p in git base-devel; do pacman -T "$p" >/dev/null 2>&1 || REPO_PKGS+=("$p"); done
                local rest=()
                for p in "${AUR_PKGS[@]}"; do [ "$p" = paru ] || rest+=("$p"); done
                AUR_PKGS=("${rest[@]}")
            else
                AUR_LEFT=("${AUR_PKGS[@]}") AUR_PKGS=()
                DECLINED+=("The AUR packages (${AUR_LEFT[*]}): no AUR helper. Install one (paru or yay), then: paru -S ${AUR_LEFT[*]}")
            fi
        fi
    fi

    # what the user's files look like (read only)
    python3 -I "$SRC/tools/install.py" plan $(picked theme && echo --theming) >"$PLAN" 2>"$WORK/plan.err" || {
        body_clear; say e "The installer could not read your configuration:"; say n "$(tail -3 "$WORK/plan.err")"; page "Stopped"; return 1
    }

    # the link Quickshell finds the shell by
    local target
    target=$(readlink -f "$LINK" 2>/dev/null || true)
    LINK_SEEN=$(stat -c '%F %i %Y' -- "$LINK" 2>/dev/null || echo none)
    if [ "$target" = "$SRC" ]; then
        DO_LINK=""
    elif [ -e "$LINK" ] || [ -L "$LINK" ]; then
        body_clear
        say n "Quickshell finds the shell at:"
        say a "  $LINK"
        say n "Something else is there now$( [ -L "$LINK" ] && echo " (a link to $(readlink "$LINK"))")."
        blank
        say n "Move it aside to $LINK.bak-$STAMP and put a link to this clone in its place? Nothing in it is deleted."
        blank
        say n "No: the installer stops here, because the shell cannot start without it. Nothing was changed."
        ask "Shell folder" n "Move it aside" "Quit" || return 1
        DO_LINK=move
    else
        DO_LINK=new
    fi

    # default settings: only where there is no settings file of any kind (an old settings.json is migrated by the shell)
    if [ "$(jget settings.exists)" = false ] && [ "$(jget settings.legacy)" = false ]; then DO_SETTINGS=1; fi

    # the installer's Hyprland module
    if [ "$(jget module.exists)" = false ]; then
        DO_MODULE=new
    elif [ "$(jget module.same)" = true ]; then
        DO_MODULE=""
    elif [ "$(jget module.intact)" = true ]; then
        DO_MODULE=update
    else
        body_clear
        if [ "$(jget module.ours)" = true ]; then
            say n "$(jget module.path) was written by this installer and changed since. Replace it with the shell's current module? A copy is kept first."
        else
            say n "$(jget module.path) exists and was not written by this installer. Replace it with the shell's module? A copy is kept first."
        fi
        blank
        say d "The new content:"
        while IFS= read -r l; do say a "  $l"; done < <(jget module.text)
        if ask "Your file: sleepyshell.lua" n "Replace it" "Keep mine"; then DO_MODULE=replace; else
            DECLINED+=("Hyprland module: $(jget module.path) is yours and was kept, so the shell is not started with Hyprland and its keys are not bound.")
        fi
    fi
    # the require line only for the installer's own module (never for a sleepyshell.lua the user kept)
    if [ "$(jget hypr.required)" = false ] && { [ -n "$DO_MODULE" ] || [ "$(jget module.ours)" = true ]; }; then
        body_clear
        say n "Hyprland loads the shell's module through one line in your config. Add it?"
        blank
        say d "File:"
        say a "  $(jget hypr.main)"
        say d "Line to add (after your last require line):"
        say a "  $(jget hypr.requireLine)"
        blank
        say n "A copy of hyprland.lua is kept beside it, and the line is taken out again if your config would not load the module with it. Hyprland reloads its config when the file changes."
        blank
        say d "What the module ($(jget module.path)) does:"
        while IFS= read -r l; do say a "  $l"; done < <(jget module.text)
        blank
        say n "No: the module is still written, but Hyprland does not load it until you add the line yourself."
        if ask "Your file: hyprland.lua" n "Add the line" "Leave it"; then DO_REQUIRE=1; else
            DECLINED+=("hyprland.lua: add this line yourself so Hyprland starts the shell and binds its keys: $(jget hypr.requireLine)")
        fi
    fi
    if [ "$(jget binds.exists)" = false ] && [ -n "$(jget binds.require)" ]; then DO_BINDS=1; fi

    # hypridle.conf: made only when there is none
    local idlefind=""
    if picked idle; then
        idlefind=$(python3 -I "$SRC/scripts/idle.py" --find 2>/dev/null || true)
        local idle=()
        mapfile -t idle < <(printf '%s' "$idlefind" | python3 -I -c 'import json,sys
try: d=json.load(sys.stdin); print(d.get("path","")); print("true" if d.get("exists") else "false"); print("true" if d.get("owned") else "false")
except ValueError: pass')
        IDLE_FILE=${idle[0]:-} IDLE_EXISTS=${idle[1]:-false}
        [ -n "$IDLE_FILE" ] && [ "$IDLE_EXISTS" = false ] && DO_IDLE=1
        [ -z "$IDLE_FILE" ] && TODO+=("Idle timers: where hypridle reads its file could not be found, so no hypridle.conf was made. Sleepysettings' Idle tab offers Create.")
        [ "$IDLE_EXISTS" = true ] && [ "${idle[2]:-false}" = false ] &&
            TODO+=("Idle timers: $IDLE_FILE is your own hypridle.conf and was left alone. Sleepysettings' Idle tab offers to replace it (it asks first and keeps a copy).")
    fi

    # matugen: the bar's colours template
    if picked theme; then
        if [ "$(jget matugen.exists)" = false ]; then
            DO_MATUGEN=new
        elif [ "$(jget matugen.parses)" = false ]; then
            TODO+=("Theme colours: your matugen config $(jget matugen.path) has a mistake ($(jget matugen.error)), so it was not changed and the bar keeps its built-in colours. Fix it, then run install.sh again.")
        elif [ "$(jget matugen.hasColors)" = false ]; then
            body_clear
            say n "The bar takes its colours from matugen, like your other themed apps. Add the shell's template to your matugen config?"
            blank
            say d "File:"
            say a "  $(jget matugen.path)"
            say d "Lines to add at the end:"
            while IFS= read -r l; do [ -n "$l" ] && say a "  $l"; done < <(jget matugen.snippet)
            blank
            say n "A copy is kept first. No: the bar keeps its built-in colours."
            if ask "Your file: matugen config" n "Add the lines" "Leave it"; then DO_MATUGEN=append; else
                DECLINED+=("matugen config: the bar's colours template was not added; the bar keeps its built-in colours.")
            fi
        fi
        # the first theme run: a wallpaper and its palette, through every matugen template
        local outs=() o
        while IFS= read -r o; do [ -n "$o" ] && outs+=("$o"); done < <(python3 -I -c '
import json, sys
m = json.load(open(sys.argv[1]))["matugen"]
skip = sys.argv[2] == "no" and not m["preset"]
for o in m["outputs"]:
    if skip and not o["exists"] and o["path"] == json.load(open(sys.argv[1]))["colors"]:
        continue
    print(("rewrite " if o["exists"] else "create  ") + o["path"])' "$PLAN" "$([ -n "$DO_MATUGEN" ] || [ "$(jget matugen.hasColors)" = true ] && echo yes || echo no)")
        printf '%s\n' "${outs[@]#* }" | sed 's/^ *//' >"$WORK/theme-shown"
        if [ "$(jget themeSafe)" = false ]; then
            TODO+=("Theme: not run, because XDG_CONFIG_HOME is not ~/.config and matugen would read another config than the one the shell uses. Run scripts/theme.py yourself once the two agree.")
        elif [ "$(jget matugen.parses)" != false ]; then
            body_clear
            say n "Run the theme once now? It sets a random wallpaper from ~/Pictures/Wallpapers (Hyprland's own wallpapers while that folder is empty) and makes the palette from it, which matugen writes into every file its config lists:"
            for o in "${outs[@]}"; do say a "  $o"; done
            [ "$(jget matugen.hooks)" != "[]" ] && { blank; say y "Your matugen config also runs commands of its own around these templates: $(jget matugen.hooks | tr -d '[]"')"; }
            blank
            say n "Every file that already exists is copied first (into $BK)."
            blank
            say n "No: nothing is rewritten; Shuffle colours in the control centre does the same later."
            if ask "First theme run" n "Run the theme" "Not now"; then DO_THEME=1; else
                TODO+=("Theme: not run yet. Shuffle colours in the control centre (or scripts/theme.py) sets a wallpaper and its colours.")
            fi
        fi
    fi

    # system services and the i2c-dev module: asked one by one, No unless you say yes
    service_q() { # UNIT SCOPE(system|user) LABEL WHY
        local unit=$1 scope=$2 label=$3 why=$4 flag=()
        [ "$scope" = user ] && flag=(--user)
        active "${flag[@]}" "$unit" && return 0
        local cmd="sudo systemctl enable --now $unit"
        [ "$scope" = user ] && cmd="systemctl --user enable --now $unit"
        body_clear
        say n "For $label, $unit has to run, and it is not running now. $why"
        blank
        say d "Enable it now and start it with every boot$([ "$scope" = user ] && echo " (your user's service)"):"
        say a "  $cmd"
        if ask "Service: $unit" n "Enable it" "Not now"; then SERVICES+=("$scope $unit"); else
            DECLINED+=("$unit is not enabled. To start it now and at every boot: $cmd")
        fi
    }
    if picked network; then
        local other=""
        for p in iwd systemd-networkd connman; do active "$p" && other+="${other:+, }$p"; done
        if [ -n "$other" ]; then
            active NetworkManager || TODO+=("Network: $other manages your network, so NetworkManager was installed but not enabled (two network managers fight over the same devices). The network widget and the Wi-Fi tile need NetworkManager; to switch: stop and disable $other, then sudo systemctl enable --now NetworkManager")
        else
            service_q NetworkManager.service system "the network widget and the Wi-Fi tile" ""
        fi
    fi
    picked bluetooth && service_q bluetooth.service system "the Bluetooth tile and widget" ""
    if picked power; then
        local other=""
        for p in tlp tuned auto-cpufreq; do active "$p" && other+="${other:+, }$p"; done
        if [ -n "$other" ]; then
            active power-profiles-daemon || TODO+=("Power profiles: $other manages power here, so power-profiles-daemon was not enabled (they conflict). To switch: disable $other, then sudo systemctl enable --now power-profiles-daemon")
        else
            service_q power-profiles-daemon.service system "the power profile tile" ""
        fi
    fi
    if picked idle && ! running hypridle && [ "$(jget hypr.startsHypridle)" != true ]; then
        service_q hypridle.service user "the idle timers (dim, lock, sleep)" "Hyprland's config does not start it either."
    fi
    local devdir=${SLEEPYSHELL_DEV:-/dev} mload=${SLEEPYSHELL_MODULES_LOAD:-/etc/modules-load.d}
    if ! ls "$devdir"/i2c-* >/dev/null 2>&1 && ! grep -qsx 'i2c[-_]dev' "$mload"/*.conf; then
        body_clear
        say n "Brightness and contrast of external monitors (the Display tab) talk to them over DDC/CI, which needs the i2c-dev kernel module. It is not loaded now."
        blank
        say d "Load it at every boot, with one new file (sudo):"
        say a "  /etc/modules-load.d/i2c-dev.conf   containing: i2c-dev"
        blank
        say n "It takes effect after a reboot, or at once with: sudo modprobe i2c-dev. Access to the monitors' buses is a second step the Display tab shows."
        if ask "Monitor brightness: i2c-dev" n "Add the file" "Not now"; then I2C=1; else
            DECLINED+=("i2c-dev is not loaded at boot. For external monitor brightness: echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf, then reboot or sudo modprobe i2c-dev")
        fi
    fi
    picked walker && TODO+=("Clipboard button: walker reads the clipboard through its elephant service, which has to run in your session; see walker's documentation for how to start it.")

    # programs that would do the shell's jobs too, and keys that were taken (only reported)
    local c
    while IFS= read -r c; do [ -n "$c" ] && TODO+=("$c"); done < <(python3 -I "$SRC/tools/install.py" notes "$PLAN")
    for p in waybar hyprpanel nwg-panel ags eww swaync mako dunst fnott hyprpolkitagent polkit-gnome-authentication-agent-1 lxpolkit hyprpaper swaybg; do
        running "$p" && TODO+=("$p is running now and does a job Sleepy Shell does (a bar, notifications, the polkit prompt or the wallpaper). Stop it before using the shell, and stop starting it with your session.")
    done

    # start it now
    if pgrep -f '^(qs|quickshell) -c sleepyshell( -d)?$' >/dev/null; then
        START=0
    else
        body_clear
        say n "Start Sleepy Shell now, at the end? It is also started with every Hyprland login once Hyprland loads its module."
        if ask "Start the shell" n "Start it" "Not now"; then START=1; else TODO+=("Start the shell: qs -c sleepyshell -d (or log in again)"); fi
    fi

    summary
    if ! ask "Summary" n "Install" "Cancel"; then
        body_clear; say n "Cancelled. Nothing was installed or changed."; page "Cancelled"; return 1
    fi
    if [ "$DRY" = 1 ]; then
        body_clear; say y "Dry run: nothing was installed or changed."; page "Dry run"; return 0
    fi
    run_steps
    report
}

summary() {
    body_clear
    say b "Packages"
    if [ ${#REPO_PKGS[@]} -gt 0 ]; then say n "From your distribution's repositories (sudo pacman -S --needed):"; say a "  ${REPO_PKGS[*]}"; fi
    [ "$BOOTSTRAP" = 1 ] && { say n "Build the AUR helper paru from the AUR (makepkg)."; }
    if [ ${#AUR_PKGS[@]} -gt 0 ]; then say n "From the AUR ($HELPER -S --needed):"; say a "  ${AUR_PKGS[*]}"; fi
    [ ${#AUR_LEFT[@]} -gt 0 ] && say y "Left out (AUR, no helper): ${AUR_LEFT[*]}"
    [ ${#REPO_PKGS[@]} -eq 0 ] && [ ${#AUR_PKGS[@]} -eq 0 ] && [ "$BOOTSTRAP" = 0 ] && say d "  Nothing to install: everything picked is already there."
    blank
    say b "Services"
    local s
    for s in "${SERVICES[@]}"; do say n "  Enable and start ${s#* } (${s%% *})"; done
    [ "$I2C" = 1 ] && say n "  Create /etc/modules-load.d/i2c-dev.conf (sudo; takes effect after a reboot or sudo modprobe i2c-dev)"
    [ ${#SERVICES[@]} -eq 0 ] && [ "$I2C" = 0 ] && say d "  None."
    blank
    say b "New files (the installer's own)"
    local any=0
    case $DO_LINK in new | move) say n "  $LINK -> $SRC"; any=1 ;; esac
    [ "$DO_SETTINGS" = 1 ] && { say n "  $SRC/sleepysettings.toml (the default settings)"; any=1; }
    [ "$DO_MODULE" = new ] && { say n "  $(jget module.path) (starts the shell, its window rules and keys)"; any=1; }
    [ "$DO_MODULE" = update ] && { say n "  $(jget module.path): the installer's module, rewritten (a copy is kept)"; any=1; }
    [ "$DO_BINDS" = 1 ] && { say n "  $(jget binds.path) (the Keybinds tab's file)"; any=1; }
    [ "$DO_IDLE" = 1 ] && { say n "  $IDLE_FILE (the idle timers)"; any=1; }
    [ "$DO_MATUGEN" = new ] && { say n "  $(jget matugen.path) (matugen's config, with the bar's colours template)"; any=1; }
    [ "$any" = 0 ] && say d "  None: everything is already in place."
    blank
    say b "Your files (changed only because you said yes; a copy of each is kept)"
    any=0
    [ "$DO_LINK" = move ] && { say n "  $LINK: moved aside to $LINK.bak-$STAMP"; any=1; }
    [ "$DO_MODULE" = replace ] && { say n "  $(jget module.path): replaced with the shell's module"; any=1; }
    [ "$DO_REQUIRE" = 1 ] && { say n "  $(jget hypr.main): one line, $(jget hypr.requireLine)"; any=1; }
    [ "$DO_MATUGEN" = append ] && { say n "  $(jget matugen.path): the bar's colours template added at the end"; any=1; }
    [ "$DO_THEME" = 1 ] && { say n "  The first theme run: a wallpaper, and every file matugen's config lists rewritten with its palette"; any=1; }
    [ "$any" = 0 ] && say d "  None."
    blank
    [ "$START" = 1 ] && { say n "Then start the shell."; blank; }
    if [ ${#DECLINED[@]} -gt 0 ] || [ ${#TODO[@]} -gt 0 ]; then
        say b "Not done (listed again in the final report)"
        for s in "${DECLINED[@]}" "${TODO[@]}"; do say y "  - $s"; done
        blank
    fi
    say d "Everything done is recorded in $MANIFEST, with copies of changed files in $BK."
}

# ---------------------------------------------------------------------------------------------------------------------
# The work, step by step, with a progress screen. A step that needs the terminal (sudo, pacman, makepkg) leaves the
# screen while it runs.
STEPS=() STEP_ST=() DONE=() CHANGED=() FAILED=()
progress() {
    local i n=${#STEPS[@]} doneN=0 bar w
    if [ "$TUI" = 0 ]; then return 0; fi
    size
    for ((i = 0; i < n; i++)); do [ "${STEP_ST[i]}" != wait ] && [ "${STEP_ST[i]}" != run ] && doneN=$((doneN + 1)); done
    w=$((COLS - 14))
    bar=$(printf '%*s' $((w * doneN / (n > 0 ? n : 1))) '' | tr ' ' '#')$(printf '%*s' $((w - w * doneN / (n > 0 ? n : 1))) '' | tr ' ' '.')
    body_clear
    say a "[$bar] $doneN/$n"
    blank
    for ((i = 0; i < n; i++)); do
        case ${STEP_ST[i]} in
        ok) say g "  ok    ${STEPS[i]}" ;; fail) say e "  fail  ${STEPS[i]}" ;; skip) say d "  --    ${STEPS[i]}" ;;
        run) say b "  >>    ${STEPS[i]}" ;; *) say d "        ${STEPS[i]}" ;;
        esac
    done
    SCREEN="Installing"
    wrap_body $((COLS - 4))
    draw 0 "Working; the log of this run is kept with the report."
}
# step N STATE: set a step's state and redraw
step() {
    STEP_ST[$1]=$2
    if [ "$TUI" = 0 ]; then
        case $2 in run) printf '\n[%d/%d] %s\n' "$(($1 + 1))" "${#STEPS[@]}" "${STEPS[$1]}" ;; ok) echo "  done" ;; fail) echo "  FAILED" ;; skip) echo "  skipped" ;; esac
    fi
    progress
}
# in_terminal TITLE CMD...: run a command that talks to the user (sudo, pacman), outside the screen
in_terminal() {
    local title=$1 rc
    shift
    tui_leave
    printf '\n%s== %s ==%s\n' "$S_B" "$title" "$S_N"
    printf '%s$ %s%s\n' "$S_D" "$*" "$S_N"
    "$@"
    rc=$?
    tui_enter
    return $rc
}
quiet() { "$@" >>"$LOG" 2>&1; }

run_steps() {
    local plan_steps=() i
    [ ${#REPO_PKGS[@]} -gt 0 ] && plan_steps+=("repo|Install packages from the repositories")
    [ "$BOOTSTRAP" = 1 ] && plan_steps+=("paru|Build paru from the AUR")
    [ ${#AUR_PKGS[@]} -gt 0 ] && plan_steps+=("aur|Install packages from the AUR")
    { [ ${#SERVICES[@]} -gt 0 ] || [ "$I2C" = 1 ]; } && plan_steps+=("services|Enable services")
    [ -n "$DO_LINK" ] && plan_steps+=("link|Link the shell where Quickshell finds it")
    [ "$DO_SETTINGS" = 1 ] && plan_steps+=("settings|Default settings")
    [ -n "$DO_MODULE" ] || [ "$DO_REQUIRE" = 1 ] || [ "$DO_BINDS" = 1 ] && plan_steps+=("hypr|Hyprland: module, keys and require line")
    [ "$DO_IDLE" = 1 ] && plan_steps+=("idle|Idle timers file")
    [ -n "$DO_MATUGEN" ] && plan_steps+=("matugen|Theme colours template")
    [ "$DO_THEME" = 1 ] && plan_steps+=("theme|First theme run")
    [ "$START" = 1 ] && plan_steps+=("start|Start the shell")
    for i in "${plan_steps[@]}"; do STEPS+=("${i#*|}") STEP_ST+=(wait); done
    mkdir -p "$STATE_BASE"
    pacman -Qq >"$WORK/before" 2>/dev/null
    local core_ok=1 n=0 id st
    for i in "${plan_steps[@]}"; do
        id=${i%%|*}
        if [ "$core_ok" = 0 ] && [ "$id" != repo ]; then step $n skip; n=$((n + 1)); continue; fi
        step $n run
        if "do_$id"; then st=ok; else st=fail; fi
        case $id in repo | paru | aur) record_packages ;; esac
        if [ "$st" = ok ]; then step $n ok; else
            step $n fail
            FAILED+=("${STEPS[n]}${FAIL_WHY:+: $FAIL_WHY}")
            # without the shell's own packages nothing else makes sense
            [ "$id" = repo ] && ! pacman -T quickshell ttf-jetbrains-mono-nerd python >/dev/null 2>&1 && core_ok=0
        fi
        FAIL_WHY=""
        n=$((n + 1))
    done
    record_packages
}
FAIL_WHY=""
record_packages() {
    local p kind src
    pacman -Qq >"$WORK/after" 2>/dev/null
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        kind=dependency src=repo
        pacman -Qqe "$p" >/dev/null 2>&1 && kind=explicit
        pacman -Qqm "$p" >/dev/null 2>&1 && src=aur
        record package "$p" "$kind" "$src"
        DONE+=("Installed $p ($kind, $src)")
    done < <(comm -13 <(sort "$WORK/before") <(sort "$WORK/after"))
    cp -- "$WORK/after" "$WORK/before"
}
do_repo() {
    in_terminal "Packages from the repositories" sudo pacman -S --needed "${REPO_PKGS[@]}" || { FAIL_WHY="pacman stopped; nothing more was installed from the repositories"; return 1; }
}
do_paru() {
    local d=$WORK/paru
    mkdir -p "$d"
    in_terminal "Building paru from the AUR" sh -c 'git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$1/paru-bin" && cd "$1/paru-bin" && makepkg -si --needed' sh "$d" ||
        { FAIL_WHY="paru could not be built"; return 1; }
    command -v paru >/dev/null || { FAIL_WHY="paru is not installed after the build"; return 1; }
}
do_aur() {
    command -v "$HELPER" >/dev/null || { FAIL_WHY="no AUR helper"; AUR_LEFT+=("${AUR_PKGS[@]}"); return 1; }
    in_terminal "Packages from the AUR" "$HELPER" -S --needed "${AUR_PKGS[@]}" || { FAIL_WHY="$HELPER stopped"; return 1; }
}
do_services() {
    local s scope unit ok=0
    for s in "${SERVICES[@]}"; do
        scope=${s%% *} unit=${s#* }
        if [ "$scope" = user ]; then
            if quiet systemctl --user enable --now "$unit"; then record service user "$unit"; DONE+=("Enabled and started $unit (your user)")
            else ok=1; FAILED+=("$unit could not be enabled: systemctl --user enable --now $unit"); fi
        else
            if in_terminal "Enable $unit" sudo systemctl enable --now "$unit"; then record service system "$unit"; DONE+=("Enabled and started $unit")
            else ok=1; FAILED+=("$unit could not be enabled: sudo systemctl enable --now $unit"); fi
        fi
    done
    if [ "$I2C" = 1 ]; then
        local conf=${SLEEPYSHELL_MODULES_LOAD:-/etc/modules-load.d}/i2c-dev.conf
        if [ -e "$conf" ]; then
            TODO+=("$conf already exists and was left alone.")
        elif in_terminal "Load i2c-dev at boot" sudo sh -c 'set -C; printf "i2c-dev\n" > "$1"' sh "$conf"; then
            record root-created "$conf"
            DONE+=("Created $conf (i2c-dev loads from the next boot; now: sudo modprobe i2c-dev)")
        else
            ok=1; FAILED+=("$conf could not be written")
        fi
    fi
    return $ok
}
do_link() {
    ensure_dir "$(dirname "$LINK")"
    # what is there must still be what the user was asked about
    [ "$(stat -c '%F %i %Y' -- "$LINK" 2>/dev/null || echo none)" = "$LINK_SEEN" ] ||
        { FAIL_WHY="$LINK changed after you were asked; nothing was done there. Run install.sh again."; return 1; }
    if [ "$DO_LINK" = move ]; then
        record pending "$LINK"
        mv -n -T -- "$LINK" "$LINK.bak-$STAMP" && [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || { FAIL_WHY="could not move $LINK aside"; return 1; }
        record moved "$LINK" "$LINK.bak-$STAMP"
        CHANGED+=("$LINK moved aside to $LINK.bak-$STAMP")
    fi
    ln -s -T -- "$SRC" "$LINK" || { FAIL_WHY="could not create $LINK"; return 1; }
    record link "$LINK" "$SRC"
    DONE+=("Linked $LINK to $SRC")
}
do_settings() {
    [ -e "$SRC/sleepysettings.toml" ] && { DONE+=("Settings: a settings file appeared meanwhile and was kept"); return 0; }
    record pending "$SRC/sleepysettings.toml"
    cp -n -- "$SRC/data/default-settings.toml" "$SRC/sleepysettings.toml" || { FAIL_WHY="could not copy the default settings"; return 1; }
    record created "$SRC/sleepysettings.toml"
    DONE+=("Default settings: $SRC/sleepysettings.toml")
}
# write_file PATH SHA-SHOWN TEXT-SOURCE...: the helper's safe write; sets WROTE_BACKUP
write_file() {
    local path=$1 was=$2 out
    shift 2
    # the whole text first: a source that fails half way must not become a half-written file
    "$@" >"$WORK/content" || { FAIL_WHY="the text for $path could not be made"; return 1; }
    ensure_dir "$(dirname "$path")"
    record pending "$path"
    out=$(python3 -I "$SRC/tools/install.py" write "$path" --was "$was" --backup-dir "$BK" <"$WORK/content") || {
        FAIL_WHY=$(printf '%s' "$out" | python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("message",""))
except ValueError: print("the write failed")'); return 1; }
    WROTE_BACKUP=$(printf '%s' "$out" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("backup") or "")')
}
do_hypr() {
    local path out ok=0 text=module.text
    # the Keybinds tab's file first: the module requires it, and a require of a missing file is an error in Hyprland
    if [ "$DO_BINDS" = 1 ]; then
        path=$(jget binds.path)
        if [ -e "$path" ] || [ -L "$path" ]; then
            DONE+=("$path appeared meanwhile and was kept")
        else
            ensure_dir "$(dirname "$path")"
            record pending "$path"
            if jget binds.text | quiet python3 -I "$SRC/scripts/hyprconf.py" write-binds "$path" && [ -f "$path" ]; then
                record created "$path"
                DONE+=("Created $path (the Keybinds tab's file$( [ "$(jget binds.keysWindow)" != "" ] && echo ", with SUPER + slash for the Keybinds window"))")
            else
                ok=1; FAILED+=("$path could not be created, so the module does not load it")
            fi
        fi
        [ -f "$path" ] || text=module.textNoBinds
    fi
    path=$(jget module.path)
    if [ -n "$DO_MODULE" ]; then
        if write_file "$path" "$(jget module.sha)" jget "$text"; then
            if [ -n "$WROTE_BACKUP" ]; then record changed "$path" "$WROTE_BACKUP"; CHANGED+=("$path rewritten (copy: $WROTE_BACKUP)")
            else record created "$path"; DONE+=("Created $path"); fi
        else
            return 1
        fi
    fi
    if [ "$DO_REQUIRE" = 1 ]; then
        local main sha_now
        main=$(jget hypr.main)
        sha_now=$(python3 -I "$SRC/tools/install.py" sha "$main")
        if [ "$sha_now" != "$(jget hypr.mainSha)" ]; then
            ok=1; FAILED+=("$main changed after you were asked, so the require line was not added. Run install.sh again.")
        else
            mkdir -p "$BK"
            local beside copy changed
            python3 -I "$SRC/tools/install.py" backup "$BK" "$main" >"$WORK/bk.json"
            copy=$(python3 -I -c 'import json,sys; b=json.load(open(sys.argv[1]))["backups"]; print(b[0]["backup"] if b else "")' "$WORK/bk.json")
            [ -n "$copy" ] && record backup "$main" "$copy"
            record pending "$main"
            out=$(python3 -I "$SRC/scripts/hyprconf.py" add-require "$(jget module.path)" --root "$HYPR" 2>>"$LOG")
            printf '%s\n' "$out" >>"$LOG"
            beside=$(printf '%s' "$out" | python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("backup") or "")
except ValueError: pass')
            changed=$(printf '%s' "$out" | python3 -I -c 'import json,sys
try: print("yes" if json.load(sys.stdin).get("changed") else "no")
except ValueError: print("no")')
            # a copy it left beside the file belongs to the record whatever happened
            [ -n "$beside" ] && [ -e "$beside" ] && record backup "$main" "$beside"
            if printf '%s' "$out" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("ok") else 1)' 2>/dev/null; then
                if [ "$changed" = yes ]; then
                    record changed "$main" "${beside:-$copy}"
                    CHANGED+=("$main: added $(jget hypr.requireLine) (copy: ${beside:-$copy})")
                else
                    record unchanged "$main"
                    DONE+=("$main already loads the module; nothing was added")
                fi
            else
                ok=1; FAILED+=("The require line could not be added to $main: $(printf '%s' "$out" | python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("message",""))
except ValueError: print("see the log")')")
            fi
        fi
    fi
    return $ok
}
do_idle() {
    ensure_dir "$(dirname "$IDLE_FILE")"
    record pending "$IDLE_FILE"
    if quiet python3 -I "$SRC/scripts/idle.py" --create --expect "$IDLE_FILE"; then
        record created "$IDLE_FILE"
        DONE+=("Created $IDLE_FILE (idle timers; change them in Sleepysettings, Idle tab)")
    else
        FAIL_WHY="idle.py could not create $IDLE_FILE"; return 1
    fi
}
do_matugen() {
    local path
    path=$(jget matugen.path)
    if [ "$DO_MATUGEN" = new ]; then
        write_file "$path" none sh -c 'printf "[config]\n"; python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))[\"matugen\"][\"snippet\"], end=\"\")" "$1"' sh "$PLAN" || return 1
        record created "$path"
        DONE+=("Created $path with the bar's colours template")
    else
        write_file "$path" "$(jget matugen.sha)" sh -c 'cat "$1"; [ -z "$(tail -c1 "$1")" ] || echo; python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))[\"matugen\"][\"snippet\"], end=\"\")" "$2"' sh "$path" "$PLAN" || return 1
        record changed "$path" "$WROTE_BACKUP"
        CHANGED+=("$path: the bar's colours template added (copy: $WROTE_BACKUP)")
    fi
    # read back: the result must parse and write the colours
    python3 -I -c 'import sys,tomllib; tomllib.loads(open(sys.argv[1]).read())' "$path" 2>>"$LOG" || {
        [ -n "$WROTE_BACKUP" ] && cp -- "$WROTE_BACKUP" "$path"
        FAIL_WHY="the new matugen config did not parse, so the old one was put back"; return 1; }
}
do_theme() {
    local outs=() o list
    command -v matugen >/dev/null && command -v magick >/dev/null || { FAIL_WHY="matugen or ImageMagick is missing"; return 1; }
    # every file a run writes, as the config lists them now (the template may just have been added)
    python3 -I "$SRC/tools/install.py" plan --theming >"$WORK/plan2.json" 2>>"$LOG" || { FAIL_WHY="matugen's config could not be read"; return 1; }
    # what the config writes now (the colours file only when the template is really there)
    while IFS= read -r o; do [ -n "$o" ] && outs+=("$o"); done < <(python3 -I -c 'import json,sys
d = json.load(open(sys.argv[1])); m = d["matugen"]
for o in m["outputs"]:
    if m["hasColors"] or m["preset"] or o["path"] != d["colors"]: print(o["path"])' "$WORK/plan2.json")
    # only the files the question named: a template added since then stops the run
    for o in "${outs[@]}"; do
        grep -qxF -- "$o" "$WORK/theme-shown" || { FAIL_WHY="matugen's config changed after you were asked ($o is new), so the theme did not run"; return 1; }
    done
    local cache
    cache=$(jget themeCache)
    mkdir -p "$BK"
    python3 -I "$SRC/tools/install.py" backup "$BK" "${outs[@]}" "$cache" >"$WORK/theme-bk.json" || { FAIL_WHY="the files could not be copied first, so the theme did not run"; return 1; }
    declare -A copy_of=()
    while IFS=$'\t' read -r o list; do
        [ -n "$o" ] && copy_of[$o]=$list
    done < <(python3 -I -c 'import json,sys
for b in json.load(open(sys.argv[1]))["backups"]: print(b["path"] + "\t" + b["backup"])' "$WORK/theme-bk.json")
    for o in "${outs[@]}" "$cache"; do ensure_dir "$(dirname "$o")"; record pending "$o"; done
    local daemon=awww
    command -v awww >/dev/null || daemon=swww
    if command -v "$daemon" >/dev/null && ! pgrep -x "$daemon-daemon" >/dev/null; then
        setsid -f "$daemon-daemon" >/dev/null 2>&1 </dev/null
        sleep 1
    fi
    local rc=0
    quiet python3 -I "$SRC/scripts/theme.py" || rc=$?
    # recorded whatever the run did: a failed run may have written some of them
    for o in "${outs[@]}" "$cache"; do
        if [ -n "${copy_of[$o]:-}" ]; then
            record changed "$o" "${copy_of[$o]}"
            [ "$o" = "$cache" ] || CHANGED+=("$o rewritten by the theme run (copy: ${copy_of[$o]})")
        elif [ -e "$o" ]; then
            record created "$o"
            [ "$o" = "$cache" ] || DONE+=("Created $o (theme run)")
        fi
    done
    [ "$rc" = 0 ] || { FAIL_WHY="scripts/theme.py failed (the copies are in $BK)"; return 1; }
    DONE+=("First theme run: wallpaper and colours set")
}
do_start() {
    setsid -f qs -c sleepyshell -d >/dev/null 2>&1 </dev/null
    local i
    for i in 1 2 3 4 5 6; do
        sleep 0.5
        pgrep -f '^qs -c sleepyshell( -d)?$' >/dev/null && { DONE+=("Started the shell (qs -c sleepyshell)"); return 0; }
    done
    FAIL_WHY="it did not start; see qs log -c sleepyshell"
    return 1
}

report() {
    local s file=$STATE_BASE/report-$STAMP.txt
    body_clear
    if [ ${#FAILED[@]} -eq 0 ]; then say g "Sleepy Shell is installed."; else say e "Sleepy Shell is installed, but some steps failed (below)."; fi
    blank
    if [ ${#DONE[@]} -gt 0 ]; then say b "Done"; for s in "${DONE[@]}"; do say n "  - $s"; done; blank; fi
    if [ ${#CHANGED[@]} -gt 0 ]; then say b "Your files that changed (each with a copy)"; for s in "${CHANGED[@]}"; do say n "  - $s"; done; blank; fi
    if [ ${#FAILED[@]} -gt 0 ]; then say b "Failed"; for s in "${FAILED[@]}"; do say e "  - $s"; done; blank; fi
    if [ ${#DECLINED[@]} -gt 0 ] || [ ${#TODO[@]} -gt 0 ]; then
        say b "Left for you"
        for s in "${DECLINED[@]}" "${TODO[@]}"; do say y "  - $s"; done
        blank
    fi
    say b "Next"
    say n "  Open Sleepysettings from the gear in the control centre. Its Config tab checks every file the shell uses."
    blank
    say d "Record: $MANIFEST"
    [ -d "$BK" ] && say d "Copies: $BK"
    say d "This report: $file"
    mkdir -p "$STATE_BASE"
    { local e; for e in "${BODY[@]}"; do printf '%s\n' "${e#*$'\t'}"; done
      printf '\n-- log --\n'; cat "$LOG" 2>/dev/null; } >"$file"
    page "Finished"
    [ ${#FAILED[@]} -eq 0 ]
}

main
rc=$?
tui_leave
[ "$TUI" = 1 ] && [ -f "$STATE_BASE/report-$STAMP.txt" ] && printf 'Sleepy Shell installer: the report is in %s\n' "$STATE_BASE/report-$STAMP.txt"
exit $rc
