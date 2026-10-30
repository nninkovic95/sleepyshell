#!/bin/bash
# record.sh FRAMES_DIR: record the demo clips for docs/demo as folders of PNG frames, one folder per
# clip, each frame named by its time in ms (assemble.sh turns them into animated WebP with the real
# timing). The cursor is in every frame.
#
# What it does to the desktop while it runs, and undoes at the end (also on an error):
#   - switches to an empty workspace (REC_WS, checked to be empty before the first frame) and back to
#     the one that was active; a special workspace that is shown is hidden first and shown again
#   - clears the notification list once before the clips, so only the demo notifications appear
#   - sets Hyprland's own fallback wallpapers (/usr/share/hypr/wall*.png) through scripts/theme.py,
#     then puts the previous wallpaper back and re-renders the previous palette from the seed colour
#     theme.py had recorded, so the colours end exactly as they were
#   - edits two lines of sleepysettings.toml for a few seconds each and writes them back: wallpaperDir
#     (an empty folder, so the picker lists the fallback wallpapers) and dropdownFit (the Float demo)
#   - moves the cursor, and moves the default sink's volume for the on-screen display clip and sets it back
# Clicks and scrolls are real when wlrctl (a virtual pointer) is installed; without it the popups open
# through the bar's IPC with the cursor parked on the element. Workspaces, cursor and the keyboard
# shortcut that walks the settings tabs go through hyprctl in the Lua config's dispatcher form.
# Needs grim, notify-send, wpctl, awww (or swww) and matugen.
set -u
OUT=${1:?frames folder}
mkdir -p "$OUT"
exec > >(tee -a "$OUT/record.log") 2>&1

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
SHELL_DIR=$XDG_CONFIG_HOME/quickshell/sleepyshell
TOML=$SHELL_DIR/sleepysettings.toml
QS="qs -c sleepyshell ipc call sleepybar"
THEME="python3 $SHELL_DIR/scripts/theme.py"
REC_WS=${REC_WS:-4}
WALL0=/usr/share/hypr/wall0.png
WALL1=/usr/share/hypr/wall1.png
WALL2=/usr/share/hypr/wall2.png
DAEMON=$(command -v awww || command -v swww)
HAVE_WLRCTL=$(command -v wlrctl || true)

# positions on a 2560 px wide screen with the default bar (measured on a probe frame; the right
# island is right-aligned, so its items keep their place only while the same widgets are shown)
Y=15
DOT=(18 44 72 100 128)          # workspace dots 1..5
CLOCK=1275; SPEAKER=1378; MIC=1470
WIFI=2345; BELL=2403
# inside the open control centre (frame region starts at x=560)
T_WIFI="1185 73"; T_BT="1375 73"; T_DND="1185 131"; T_AWAKE="1375 131"; T_PROFILE="1185 190"; T_NIGHT="1375 190"
TOOL_CAL="1350 290"; TOOL_SETTINGS="1375 324"; SLIDER_OUT="1625 83"
PARK="2200 900"

hc() { hyprctl dispatch "$1" >/dev/null; }
ws() { hc "hl.dsp.focus({ workspace = $1 })"; }
mv() { hc "hl.dsp.cursor.move({ x = $1, y = $2 })"; }
click() { [ -n "$HAVE_WLRCTL" ] && wlrctl pointer click "${1:-left}"; }
scroll() { [ -n "$HAVE_WLRCTL" ] && wlrctl pointer scroll "$1" 0; }
# open NAME X Y: hover the element, click it when clicks are real, else open its popup over IPC
open() { mv "$2" "$3"; sleep 0.5; click || $QS toggle "$1" >/dev/null; }
shortcut() { hc "hl.dsp.send_shortcut({ mods = \"$1\", key = \"$2\", window = \"$3\" })"; }

ORIG_WS=$(hyprctl activeworkspace -j | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["id"])')
ORIG_SPECIAL=$(hyprctl monitors -j | python3 -I -c 'import json,sys; m=[x for x in json.load(sys.stdin) if x["focused"]][0]; print(m["specialWorkspace"]["name"].replace("special:", ""))')
ORIG_WALL=$($DAEMON query | sed -n 's/.*image: //p' | head -1)
ORIG_SEED=$(cat "$XDG_CACHE_HOME/theme-last-source" 2>/dev/null)
ORIG_COLORS=$(sha256sum "$XDG_STATE_HOME/quickshell/colors.json" | cut -d' ' -f1)
ORIG_VOL=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
ORIG_WALLDIR=$(grep -E '^wallpaperDir = ' "$TOML")
ORIG_FIT=$(grep -E '^dropdownFit = ' "$TOML")
ORIG_CURSOR=$(hyprctl cursorpos)
EMPTY=$OUT/empty-wallpapers
mkdir -p "$EMPTY"
echo "start: workspace $ORIG_WS, special '$ORIG_SPECIAL', wallpaper $ORIG_WALL, seed $ORIG_SEED, volume $ORIG_VOL, clicks: ${HAVE_WLRCTL:-ipc}"

FPID=
CLIP=
start() {
    # start NAME REGION: frames of REGION ("X,Y WxH") every ~0.1 s until stop, cursor included
    CLIP=$OUT/$1
    rm -rf "$CLIP"
    mkdir -p "$CLIP"
    (
        while [ ! -e "$CLIP/.stop" ]; do
            grim -c -l 1 -g "$2" "$CLIP/$(date +%s%3N).png" 2>/dev/null
            sleep 0.04
        done
    ) &
    FPID=$!
}
stop() {
    touch "$CLIP/.stop"
    wait "$FPID" 2>/dev/null
    echo "clip $(basename "$CLIP"): $(find "$CLIP" -name '*.png' | wc -l) frames"
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

restore() {
    trap - EXIT
    echo "restore: settings lines, wallpaper, palette, volume, cursor, workspace"
    set_line wallpaperDir "$ORIG_WALLDIR"
    set_line dropdownFit "$ORIG_FIT"
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "$ORIG_VOL"
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
    mv "${ORIG_CURSOR%%,*}" "${ORIG_CURSOR##*, }"
    ws "$ORIG_WS"
    [ -n "$ORIG_SPECIAL" ] && hc "hl.dsp.workspace.toggle_special(\"$ORIG_SPECIAL\")"
    echo "done"
}
trap restore EXIT

# ---- the empty workspace, checked ----
[ -n "$ORIG_SPECIAL" ] && hc "hl.dsp.workspace.toggle_special(\"$ORIG_SPECIAL\")"
ws "$REC_WS"
sleep 1.5
read -r now_ws now_n < <(hyprctl activeworkspace -j | python3 -I -c 'import json,sys; w=json.load(sys.stdin); print(w["id"], w["windows"])')
if [ "$now_ws" != "$REC_WS" ] || [ "$now_n" != 0 ]; then
    echo "abort: workspace $now_ws with $now_n windows is active, not an empty $REC_WS"
    exit 1
fi
mv $PARK
$QS clearNotifications >/dev/null
sleep 3
$THEME "$WALL0"
sleep 4

# ---- control centre: opens on hover, tiles highlight on hover, closes when the cursor leaves ----
start control-centre "560,0 1440x760"
sleep 0.8; mv $CLOCK $Y; sleep 1.8
mv $T_WIFI; sleep 0.7; mv $T_BT; sleep 0.7; mv $T_AWAKE; sleep 0.7; mv $T_NIGHT; sleep 0.7
mv $TOOL_CAL; sleep 0.7; mv $SLIDER_OUT; sleep 0.9
mv $PARK; sleep 1.5
stop

# ---- audio: the pill, scroll and mute when clicks are real ----
start audio "560,0 1440x760"
sleep 0.6; mv $SPEAKER $Y; sleep 0.8
if [ -n "$HAVE_WLRCTL" ]; then
    scroll -1; sleep 0.6; scroll -1; sleep 0.9; scroll 1; sleep 0.6; scroll 1; sleep 0.9
    click right; sleep 1.2; click right; sleep 0.9
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "$ORIG_VOL"
else
    $QS toggle audio >/dev/null; sleep 3; $QS toggle audio >/dev/null
fi
sleep 0.8; mv $PARK; sleep 1
stop

# ---- notifications: toasts arrive, the bell shows, its dropdown, Clear all sweeps the cards out ----
start notifications "1500,0 1060x760"
sleep 0.5
notify-send -a "Compiler" "Build finished" "sleepyshell: 154 files compiled, 0 failed"; sleep 1.3
notify-send -a "Mail" "New message" "The demo recordings are ready for review"; sleep 1.3
notify-send -a "Updates" "3 packages can be updated" "hyprland, quickshell, matugen"; sleep 2.2
open notifications $BELL $Y; sleep 2.5
$QS clearNotifications >/dev/null; sleep 3.5
mv $PARK; sleep 0.6
stop

# ---- islands: a side island widens so the dropdown hangs flush (Extend), then the Float card ----
notify-send -a "Compiler" "Build finished" "sleepyshell: 154 files compiled, 0 failed"; sleep 0.8
notify-send -a "Mail" "New message" "The demo recordings are ready for review"; sleep 2.5
start islands "1800,0 760x700"
sleep 0.6; open notifications $BELL $Y; sleep 2.5; $QS toggle notifications >/dev/null; sleep 1.2
set_line dropdownFit 'dropdownFit = "float"'; sleep 1
open notifications $BELL $Y; sleep 2.5; $QS toggle notifications >/dev/null; sleep 1
set_line dropdownFit "$ORIG_FIT"; sleep 0.4
mv $PARK; sleep 0.5
stop
$QS clearNotifications >/dev/null; sleep 3

# ---- workspaces: the disc slides between the dots (clicks when real, else the dispatcher) ----
start workspaces "0,0 400x100"
sleep 0.6
for n in 5 3 1 "$REC_WS"; do
    mv "${DOT[$((n - 1))]}" $Y; sleep 0.4
    click || ws "$n"
    sleep 1.1
done
mv $PARK; sleep 0.8
stop

# ---- calendar ----
start calendar "0,0 2560x1440"
sleep 0.6; mv $CLOCK $Y; sleep 1.5; mv $TOOL_CAL; sleep 0.6
click || $QS toggle calendar >/dev/null
sleep 3.2; $QS toggle calendar >/dev/null; sleep 0.8
mv $PARK; sleep 0.6
stop

# ---- settings: the window, then every tab with Ctrl+Tab ----
start settings "0,0 2560x1440"
sleep 0.6; mv $CLOCK $Y; sleep 1.5; mv $TOOL_SETTINGS; sleep 0.6
click || $QS toggle settings >/dev/null
sleep 3.5
for _ in $(seq 12); do
    shortcut CTRL Tab 'title:^(Sleepysettings)$'
    sleep 1.5
done
sleep 0.8
qs -p "$SHELL_DIR/sleepysettings.qml" ipc call sleepysettings close >/dev/null 2>&1 \
    || qs -p "$(readlink -f "$SHELL_DIR")/sleepysettings.qml" ipc call sleepysettings close >/dev/null 2>&1 \
    || hc 'hl.dsp.window.close()'
sleep 1.2
mv $PARK
stop

# ---- wallpaper picker, listing the fallback wallpapers ----
set_line wallpaperDir "wallpaperDir = \"$EMPTY\""
sleep 1
start wallpaper "0,0 2560x900"
sleep 0.8; $QS toggle wallpaper >/dev/null; sleep 4.5; $QS toggle wallpaper >/dev/null; sleep 1
stop
set_line wallpaperDir "$ORIG_WALLDIR"

# ---- on-screen display: volume ----
start osd "760,0 1040x300"
sleep 0.6
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.9; sleep 0.4
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.8; sleep 0.4
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.9; sleep 0.4
wpctl set-volume @DEFAULT_AUDIO_SINK@ "$ORIG_VOL"; sleep 2.5
stop

# ---- session menu ----
start session "0,0 2560x1440"
sleep 0.6; $QS toggle session >/dev/null; sleep 2; $QS toggle session >/dev/null; sleep 0.8
stop

# ---- theme: the wallpaper changes and every colour follows ----
start theme "0,0 2560x900"
sleep 1; $THEME "$WALL1"; sleep 4.5; $THEME "$WALL2"; sleep 4.5
stop
