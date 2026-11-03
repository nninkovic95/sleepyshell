#!/bin/bash
# settings_tour.sh: a fast tour through Sleepysettings for the recording. The window must already be
# open (record.sh clicks the Sleepysettings tool first). Tabs and values go through the window's IPC
# (`tab`, `stage`, `discard`), so the tour does not depend on where a row sits; the cursor still glides
# to the sidebar entry and to the row for the look of it. Every staged value shows on the bar at once
# (the live preview) and is put back to the stored value before the next, so the Apply bar comes and
# goes and nothing is written; `discard` at the end drops anything left. Two actions are real and not
# staged: the test notifications (they time out) and the palette shuffle (record.sh restores the palette).
set -u
. "$(dirname "$(readlink -f "$0")")/lib.sh"
TOML=$SHELL_DIR/sleepysettings.toml
THEME="python3 $SHELL_DIR/scripts/theme.py"
P=${TOUR_PAUSE:-0.6}

sipc() {
    qs -p "$SHELL_DIR/sleepysettings.qml" ipc call sleepysettings "$@" >/dev/null 2>&1 \
        || qs -p "$(readlink -f "$SHELL_DIR")/sleepysettings.qml" ipc call sleepysettings "$@" >/dev/null 2>&1
}
# the stored value of a key, unquoted
orig() { grep -E "^$1 = " "$TOML" | head -1 | sed -E 's/^[^=]+= *//; s/^"(.*)"$/\1/'; }
# tab KEY INDEX: the sidebar entry under the cursor, then the tab over IPC
tab() { hover 106 $((109 + 40 * $2)); sipc tab "$1"; sleep 0.5; }
# set KEY VALUE [DX DY]: the row under the cursor (when given), then the value over IPC
set_() { [ $# -ge 4 ] && hover "$3" "$4"; sipc stage "$1" "$2"; sleep "$P"; }
back() { sipc stage "$1" "$(orig "$1")"; sleep 0.35; }

# ---- Sleepybar: look and motion ----
tab bar 0
set_ corners round 650 395; set_ corners sharp 505 395; back corners
set_ barHeight 36 588 100; back barHeight
set_ barOpacity 0.95 720 353; set_ barOpacity 0.25 600 353; back barOpacity
set_ islandEasing snappy 654 520; back islandEasing
set_ cardHover lift 502 821; back cardHover

# ---- Left island: the dots ----
tab left 1
set_ workspaceShape triangle 627 143; set_ workspaceShape number 706 143; set_ workspaceShape square 547 143; back workspaceShape
set_ workspaces 7 550 100; back workspaces

# ---- Centre island: clock, readouts, shape ----
tab centre 2
set_ clockSize 26 476 100; back clockSize
set_ showDate false 480 143; back showDate
set_ centreSysinfo false 410 226; back centreSysinfo
set_ centreLeft audio 613 269; back centreLeft
set_ centreStep false 392 353; back centreStep
set_ centreUneven false 800 353; back centreUneven
set_ clockFont "CPMono_v07" 718 968; set_ clockFont "0xProto Nerd Font"; back clockFont

# ---- Right island: hide a widget, bring it back ----
tab widgets 3
set_ rightHidden network 994 177; back rightHidden

# ---- Apps: a look ----
tab apps 4; sleep 0.8

# ---- Notifications: a test toast of each kind, Do not disturb on and off ----
tab notifications 5
hover 502 226; notify-send -a "Sleepysettings" "Test notification" "This is what a notification looks like"; sleep 0.9
hover 603 226; notify-send -u critical -a "Sleepysettings" "Critical test" "A critical one stays until it is dismissed"; sleep 1.1
set_ dnd true 478 100; back dnd

# ---- Theme: a new palette for the same wallpaper ----
tab theme 6
hover 946 292; $THEME --palette >/dev/null 2>&1; sleep 1.8

# ---- the rest, one look each ----
tab idle 7; sleep 0.7
tab display 8; sleep 0.7
tab keybinds 9; sleep 0.7
tab files 10; sleep 0.7
tab system 11; sleep 0.9
sipc discard
