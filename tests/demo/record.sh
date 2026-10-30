#!/bin/bash
# record.sh FRAMES_DIR: record the demo clips for docs/demo as folders of PNG frames, one folder per
# clip, each frame a JPEG named by its time in ms (assemble.sh turns them into animated WebP with the
# real timing; JPEG because grim writes one in 13 ms where a PNG takes 27). One feature per clip. The cursor is in every frame and does everything: it glides like a
# hand through a virtual pointer (demo/lib.sh), so hover effects fire; it clicks and scrolls the same
# way, and drags through ydotool when its daemon runs. The settings clip is an automated tour
# (demo/settings_tour.sh) through the window's IPC.
#
# What it does to the desktop while it runs, and undoes at the end (also on an error):
#   - switches to an empty workspace (REC_WS, checked to be empty before the first frame) and back to
#     the one that was active; a special workspace that is shown is hidden first and shown again; the
#     workspace clip only visits workspaces that are empty, so no window of the user's is recorded
#   - clears the notification list once before the clips, so only the demo notifications appear
#   - points wallpaperDir at an empty folder for the whole run, so the picker and Shuffle wallpaper
#     use Hyprland's own fallback wallpapers (/usr/share/hypr/wall*.png), and writes the line back
#   - sets the first fallback wallpaper through scripts/theme.py, then puts the previous wallpaper
#     back and re-renders the previous palette from the seed colour theme.py had recorded
#   - flips dropdownFit to "float" for a few seconds (the Float demo) and writes the line back
#   - clicks tiles on and off again (Do not disturb, Keep awake, Night light, Bluetooth; the power
#     profile is cycled back to where it was); moves every sink's volume (slider, scroll, mute) and
#     sets each back
# Needs grim, notify-send, wpctl, awww (or swww), matugen and wlrctl; ydotool for the drag clip.
set -u
OUT=${1:?frames folder}
mkdir -p "$OUT"
exec > >(tee -a "$OUT/record.log") 2>&1
. "$(dirname "$(readlink -f "$0")")/lib.sh"
TOUR=$(dirname "$(readlink -f "$0")")/settings_tour.sh

XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
TOML=$SHELL_DIR/sleepysettings.toml
THEME="python3 $SHELL_DIR/scripts/theme.py"
REC_WS=${REC_WS:-4}
WALL0=/usr/share/hypr/wall0.png
DAEMON=$(command -v awww || command -v swww)

# positions on a 2560 px wide screen with the default bar, measured on probe frames
Y=15
DOT=(18 44 72 100 128)                          # workspace dots 1..5
CLOCK=1275; SPEAKER=1378; BELL=2403
T_WIFI="1185 76"; T_BT="1375 76"; T_DND="1185 134"; T_AWAKE="1375 134"; T_PROFILE="1185 192"; T_NIGHT="1375 192"
TOOL_SHUFFLE="1200 259"; TOOL_WALLS="1360 259"; TOOL_PALETTE="1190 293"; TOOL_CAL="1353 293"
TOOL_MIXER="1175 327"; TOOL_SETTINGS="1375 327"; POWER="1280 361"
SLIDER_LOW="1580 86"; SLIDER_HIGH="1690 86"
CLEAR_ALL="2485 55"; FIRST_TOAST="2345 95"; LIST="2320 200"
CARD1_L="2190 140"; CARD1_R="2480 170"; CARD2_L="2190 240"; CARD2_R="2480 260"
THUMB1="1045 130"; THUMB2="1200 130"; THUMB3="1360 130"
CAL_DAY="1131 695"; CAL_NEXT="1297 462"; CAL_TODAY="1348 462"
S_LOCK="920 703"; S_SLEEP="1100 703"; S_LOGOUT="1279 703"; S_REBOOT="1459 703"; S_SHUTDOWN="1640 703"
BACKDROP="400 1200"
PARK="2200 900"

ORIG_WS=$(hyprctl activeworkspace -j | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["id"])')
ORIG_SPECIAL=$(hyprctl monitors -j | python3 -I -c 'import json,sys; m=[x for x in json.load(sys.stdin) if x["focused"]][0]; print(m["specialWorkspace"]["name"].replace("special:", ""))')
ORIG_WALL=$($DAEMON query | sed -n 's/.*image: //p' | head -1)
ORIG_SEED=$(cat "$XDG_CACHE_HOME/theme-last-source" 2>/dev/null)
ORIG_COLORS=$(sha256sum "$XDG_STATE_HOME/quickshell/colors.json" | cut -d' ' -f1)
ORIG_VOL=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
# every sink's level and mute state: the pill moves the hardware sink behind an Easy Effects chain, not
# the default sink, so all of them are put back
sink_ids() { wpctl status 2>/dev/null | sed -n '/Sinks:/,/Sources:/p' | grep -oE '[0-9]+\. ' | tr -d '. '; }
ORIG_SINKS=""
for id in $(sink_ids); do
    v=$(wpctl get-volume "$id" 2>/dev/null | awk '{print $2}')
    m=$(wpctl get-volume "$id" 2>/dev/null | grep -c MUTED)
    ORIG_SINKS="$ORIG_SINKS $id:$v:$m"
done
restore_sinks() { for s in $ORIG_SINKS; do IFS=: read -r id v m <<< "$s"; wpctl set-volume "$id" "$v"; wpctl set-mute "$id" "$m"; done; }
ORIG_WALLDIR=$(grep -E '^wallpaperDir = ' "$TOML")
ORIG_FIT=$(grep -E '^dropdownFit = ' "$TOML")
ORIG_CURSOR=$(hyprctl cursorpos)
EMPTY=$OUT/empty-wallpapers
mkdir -p "$EMPTY"
# the empty workspaces the workspace clip may visit (never one with a window on it)
EMPTY_WS=$(hyprctl workspaces -j | python3 -I -c '
import json, sys
busy = {w.get("id") for w in json.load(sys.stdin) if w.get("windows", 0) > 0}
print(" ".join(str(n) for n in (5, 3, 4) if n not in busy))')
echo "start: workspace $ORIG_WS, special '$ORIG_SPECIAL', wallpaper $ORIG_WALL, seed $ORIG_SEED, volume $ORIG_VOL, sinks$ORIG_SINKS, empty workspaces [$EMPTY_WS], clicks: ${HAVE_WLRCTL:-none}, drag: ${HAVE_YDOTOOL:-no}"

FPID=
CLIP=
start() {
    # start NAME REGION: frames of REGION ("X,Y WxH") every ~0.1 s until stop, cursor included
    CLIP=$OUT/$1
    rm -rf "$CLIP"
    mkdir -p "$CLIP"
    (
        while [ ! -e "$CLIP/.stop" ]; do
            grim -c -t jpeg -q 92 -g "$2" "$CLIP/$(date +%s%3N).jpg" 2>/dev/null
            sleep 0.012
        done
    ) &
    FPID=$!
}
stop() {
    touch "$CLIP/.stop"
    wait "$FPID" 2>/dev/null
    echo "clip $(basename "$CLIP"): $(find "$CLIP" -name '*.jpg' | wc -l) frames"
}

set_line() {
    # set_line KEY LINE: replace the line "KEY = ..." of the settings file (the shell reads hand edits)
    python3 -I - "$TOML" "$1" "$2" <<'PY_LINE'
import re, sys
p, key, line = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
s2 = re.sub(r'^' + re.escape(key) + r' = .*$', lambda m: line, s, count=1, flags=re.M)
if s2 != s:
    open(p, "w").write(s2)
PY_LINE
}

close_settings() {
    shortcut "" Escape 'title:^(Sleepysettings)$'
    sleep 0.8
    [ -z "$(win '^Sleepysettings$')" ] || qs -p "$SHELL_DIR/sleepysettings.qml" ipc call sleepysettings close >/dev/null 2>&1 || true
    sleep 0.6
}
open_cc() { glide $CLOCK $Y; sleep 1.4; }
# leave: the cursor to the desktop and a click there, which closes a pinned control centre or dropdown
leave() { go $PARK; }
toast() { notify-send -a "$1" "$2" "$3"; }
# tile NAME "X Y": a tile clicked on, held, clicked off again
tile() {
    start "$1" "560,0 1440x760"
    sleep 0.6; open_cc; go $2; sleep "${3:-1.6}"; go $2; sleep 1.0
    leave; sleep 0.8
    stop
}

restore() {
    trap - EXIT INT TERM
    [ -n "$FPID" ] && { touch "$CLIP/.stop" 2>/dev/null; kill "$FPID" 2>/dev/null; }
    echo "restore: settings lines, wallpaper, palette, volume, cursor, workspace"
    [ -n "$(win '^Sleepysettings$')" ] && qs -p "$SHELL_DIR/sleepysettings.qml" ipc call sleepysettings close >/dev/null 2>&1
    set_line wallpaperDir "$ORIG_WALLDIR"
    set_line dropdownFit "$ORIG_FIT"
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "$ORIG_VOL"
    restore_sinks
    $QS clearNotifications >/dev/null 2>&1
    [ -n "$ORIG_WALL" ] && "$DAEMON" img "$ORIG_WALL" -t fade --transition-duration 0.6 --transition-fps 60
    if [ -n "$ORIG_SEED" ]; then
        # the same matugen call theme.py makes, with the recorded seed instead of a random pick
        (cd "$SHELL_DIR/scripts" && python3 -c '
import subprocess, sys, theme
cfg = theme.settings()
src = sys.argv[1]
seed = theme.fold_cool(src) if cfg["cool"] else src.upper()
subprocess.run(["matugen", "--type", cfg["scheme"], "--mode", cfg["mode"], "--contrast=" + str(cfg["contrast"]), "color", "hex", seed], check=True)
theme.LAST.write_text(src + "\n")
print("palette: seed", seed)
' "$ORIG_SEED")
    fi
    sleep 2
    now=$(sha256sum "$XDG_STATE_HOME/quickshell/colors.json" | cut -d' ' -f1)
    [ "$now" = "$ORIG_COLORS" ] && echo "palette: identical to the start" || echo "palette: DIFFERS from the start ($ORIG_COLORS -> $now)"
    jump "${ORIG_CURSOR%%,*}" "${ORIG_CURSOR##*, }"
    ws "$ORIG_WS"
    [ -n "$ORIG_SPECIAL" ] && hc "hl.dsp.workspace.toggle_special(\"$ORIG_SPECIAL\")"
    echo "done"
}
trap restore EXIT
trap 'exit 130' INT TERM
UPDATES=2263

# ---- the empty workspace, checked ----
[ -n "$ORIG_SPECIAL" ] && hc "hl.dsp.workspace.toggle_special(\"$ORIG_SPECIAL\")"
ws "$REC_WS"
sleep 1.5
read -r now_ws now_n < <(hyprctl activeworkspace -j | python3 -I -c 'import json,sys; w=json.load(sys.stdin); print(w["id"], w["windows"])')
if [ "$now_ws" != "$REC_WS" ] || [ "$now_n" != 0 ]; then
    echo "abort: workspace $now_ws with $now_n windows is active, not an empty $REC_WS"
    exit 1
fi
jump $PARK
$QS clearNotifications >/dev/null
set_line wallpaperDir "wallpaperDir = \"$EMPTY\""
sleep 2
$THEME "$WALL0"
sleep 4

# ---- control centre: opens on hover, closes when the cursor leaves ----
start control-centre "560,0 1440x760"
sleep 0.8; open_cc; sleep 1.8; glide $PARK; sleep 1.4
stop

# ---- tile tilt: the Lift and tilt hover effect across the quick settings ----
start tile-tilt "560,0 1440x760"
sleep 0.6; open_cc
glide $T_WIFI 0.9; sleep 0.3; glide 1240 90 0.9; sleep 0.2; glide 1140 62 0.9; sleep 0.3
glide $T_AWAKE 0.9; sleep 0.3; glide 1430 148 0.9; sleep 0.2; glide 1330 120 0.9; sleep 0.3
glide $T_PROFILE 0.9; sleep 0.3; glide $T_NIGHT 1.0; sleep 0.4
glide $PARK; sleep 1.0
stop

# ---- each quick setting, on and off ----
tile tile-do-not-disturb "$T_DND"
tile tile-keep-awake "$T_AWAKE"
tile tile-night-light "$T_NIGHT" 2.2
tile tile-bluetooth "$T_BT" 2.0
start tile-power-profile "560,0 1440x760"
sleep 0.6; open_cc
go $T_PROFILE; sleep 1.2; go $T_PROFILE; sleep 1.2; go $T_PROFILE; sleep 1.2
leave; sleep 0.8
stop

# ---- audio: the pill opens the panels, the slider moves the volume ----
start audio "560,0 1440x760"
sleep 0.6; go $SPEAKER $Y; sleep 1.6
go $SLIDER_LOW; sleep 0.9; go $SLIDER_HIGH; sleep 0.9
leave; sleep 1.0
stop
restore_sinks

# ---- the pill: scroll changes the volume ----
start pill-scroll "760,0 1040x300"
sleep 0.6; glide $SPEAKER $Y; sleep 0.5
scroll 15; sleep 0.5; scroll 15; sleep 1.0; scroll -15; sleep 0.5; scroll -15; sleep 1.0
leave; sleep 0.6
stop
restore_sinks

# ---- the pill: right click mutes ----
start pill-mute "760,0 1040x300"
sleep 0.6; glide $SPEAKER $Y; sleep 0.6
click right; sleep 1.4; click right; sleep 1.0
leave; sleep 0.6
stop
restore_sinks

# ---- updates: the count on the bar, the dropdown with the packages ----
start updates "1500,0 1060x760"
sleep 0.5; go $UPDATES $Y; sleep 2.6
glide 2300 120 0.8; sleep 0.8; glide 2300 200 0.8; sleep 0.8
go $UPDATES $Y; sleep 0.6
glide $PARK; sleep 0.5
stop

# ---- notifications: ten toasts arrive, one is held under the cursor ----
start notifications "1500,0 1060x760"
sleep 0.5
toast "Compiler" "Build finished" "sleepyshell: 154 files compiled, 0 failed"; sleep 0.9
toast "Mail" "New message" "The demo recordings are ready for review"; sleep 0.9
toast "Calendar" "In 15 minutes" "Design review, room 2"; sleep 0.9
toast "Chat" "Mira" "Can you look at the island animation?"; sleep 0.9
toast "Download" "Finished" "quickshell-0.3.2.tar.gz, 4.1 MB"; sleep 0.9
toast "Updates" "3 packages can be updated" "hyprland, quickshell, matugen"; sleep 0.9
toast "Timer" "Tea is ready" "4 minutes are up"; sleep 0.9
toast "Backup" "Snapshot taken" "home, 12.4 GiB, 38 s"; sleep 0.9
toast "Mail" "New message" "Release notes for 0.4 attached"; sleep 0.9
toast "Camera" "Motion at the door" "Front camera, 22:41"; sleep 1.0
glide $FIRST_TOAST; sleep 2.2
glide $PARK; sleep 1.0
stop

# ---- the list: the bell opens it, it scrolls ----
start notification-list "1500,0 1060x760"
sleep 0.5; go $BELL $Y; sleep 1.4
glide $LIST; sleep 0.3; scroll 15; sleep 0.4; scroll 15; sleep 0.7; scroll -15; sleep 0.3; scroll -15; sleep 0.8
go $BELL $Y; sleep 0.8
glide $PARK; sleep 0.5
stop

# ---- card tilt: the Lift and tilt hover effect across the cards ----
start card-tilt "1500,0 1060x760"
sleep 0.5; go $BELL $Y; sleep 1.2
glide $CARD1_L 0.8; sleep 0.2; glide $CARD1_R 1.2; sleep 0.3; glide $CARD2_R 0.7; sleep 0.2; glide $CARD2_L 1.2; sleep 0.4
go $BELL $Y; sleep 0.8
glide $PARK; sleep 0.5
stop

# ---- clear all: the cards sweep out one by one ----
start clear-all "1500,0 1060x760"
sleep 0.5; go $BELL $Y; sleep 1.4
go $CLEAR_ALL; sleep 4.0
glide $PARK; sleep 0.6
stop

# ---- island extend: a side island widens so the dropdown hangs flush under it ----
toast "Compiler" "Build finished" "sleepyshell: 154 files compiled, 0 failed"; sleep 0.7
toast "Mail" "New message" "The demo recordings are ready for review"; sleep 2.5
start island-extend "1800,0 760x700"
sleep 0.5; go $BELL $Y; sleep 2.2; click; sleep 1.0
glide $PARK; sleep 0.5
stop

# ---- island float: the same dropdown as a floating card ----
set_line dropdownFit 'dropdownFit = "float"'; sleep 1.0
start island-float "1800,0 760x700"
sleep 0.5; go $BELL $Y; sleep 2.2; click; sleep 1.0
glide $PARK; sleep 0.5
stop
set_line dropdownFit "$ORIG_FIT"; sleep 0.5
$QS clearNotifications >/dev/null; sleep 2.5

# ---- workspaces: clicks on the dots of empty workspaces, the disc slides ----
start workspaces "0,0 400x100"
sleep 0.5
for n in $EMPTY_WS "$REC_WS"; do go "${DOT[$((n - 1))]}" $Y; sleep 1.0; done
glide $PARK; sleep 0.7
stop

# ---- calendar: from the tools, a day, next month, Today ----
start calendar "0,0 2560x1440"
sleep 0.5; open_cc; go $TOOL_CAL; sleep 1.8
go $CAL_DAY; sleep 1.0; go $CAL_NEXT; sleep 1.0; go $CAL_TODAY; sleep 1.0
go $BACKDROP; sleep 0.9
glide $PARK; sleep 0.4
stop

# ---- session menu: from the Power button; hover only ----
start session "0,0 2560x1440"
sleep 0.5; open_cc; go $POWER; sleep 1.2
glide $S_LOCK; sleep 0.5; glide $S_SLEEP; sleep 0.5; glide $S_LOGOUT; sleep 0.5; glide $S_REBOOT; sleep 0.5; glide $S_SHUTDOWN; sleep 0.7
go $BACKDROP; sleep 0.9
glide $PARK; sleep 0.4
stop

# ---- settings: opened from the tools, then the automated tour ----
start settings "0,0 2560x1440"
sleep 0.5; open_cc; go $TOOL_SETTINGS; sleep 2.4
bash "$TOUR"
sleep 0.6; close_settings
glide $PARK; sleep 0.5
stop
$QS clearNotifications >/dev/null; sleep 2

# ---- drag and drop: a tile moved to the top of the quick settings and back ----
if [ -n "$HAVE_YDOTOOL" ]; then
    start drag "0,0 2560x1440"
    sleep 0.5; open_cc; go $TOOL_SETTINGS; sleep 2.4
    at 106 189; sleep 0.8                            # Centre island tab
    read -r wx wy _ _ < <(win '^Sleepysettings$')
    drag $((wx + 233)) $((wy + 638)) $((wx + 233)) $((wy + 521)); sleep 1.4
    drag $((wx + 233)) $((wy + 521)) $((wx + 233)) $((wy + 638)); sleep 1.2
    close_settings
    glide $PARK; sleep 0.4
    stop
else
    echo "clip drag: skipped (no ydotool daemon)"
fi

# ---- wallpaper picker from the tools ----
start wallpaper "0,0 2560x900"
sleep 0.5; open_cc; go $TOOL_WALLS; sleep 1.8
glide $THUMB1; sleep 0.6; glide $THUMB3; sleep 0.6; go $THUMB2; sleep 3.5
go $BACKDROP; sleep 0.8
glide $PARK; sleep 0.4
stop

# ---- wallpaper picker from the Theme tab ----
start wallpaper-settings "0,0 2560x1440"
sleep 0.5; open_cc; go $TOOL_SETTINGS; sleep 2.4
at 106 349; sleep 0.9                                # Theme tab
at 775 655; sleep 1.8                                # Choose wallpaper
glide $THUMB1; sleep 0.5; go $THUMB3; sleep 3.0
go $BACKDROP; sleep 0.6
close_settings
glide $PARK; sleep 0.4
stop

# ---- shuffle wallpaper: another wallpaper, every colour follows ----
start shuffle-wallpaper "0,0 2560x900"
sleep 0.5; open_cc; go $TOOL_SHUFFLE; sleep 4.5
glide $PARK; sleep 0.8
stop

# ---- shuffle colours: a new palette for the same wallpaper ----
start shuffle-colours "0,0 2560x900"
sleep 0.5; open_cc; go $TOOL_PALETTE; sleep 3.5
glide $PARK; sleep 0.8
stop
