#!/bin/bash
# record_updates.sh FRAMES_DIR [updater]: the two updates clips on their own, with the same setup and
# restore as record.sh (empty workspace, fallback wallpaper, the palette put back from the recorded seed).
#   updates   the count on the bar and the dropdown with the packages
#   updater   with a second argument "updater": the dropdown's "Update now" opens the terminal updater,
#             which is closed again at its first prompt (the terminal process is ended; nothing is
#             installed). UPDATE_NOW holds the button's place inside the open dropdown.
# The updates item sits at the left end of the right island; its place depends on which widgets show,
# so the list is cleared first (no bell) and UPDATES names the glyph's x for that state.
set -u
OUT=${1:?frames folder}
WHAT=${2:-updates}
mkdir -p "$OUT"
exec > >(tee -a "$OUT/record.log") 2>&1
. "$(dirname "$(readlink -f "$0")")/lib.sh"
XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
THEME="python3 $SHELL_DIR/scripts/theme.py"
REC_WS=${REC_WS:-4}
DAEMON=$(command -v awww || command -v swww)
Y=15
UPDATES=${UPDATES:-2317}
UPDATE_NOW=${UPDATE_NOW:-"2440 230"}
PARK="2200 900"

ORIG_WS=$(hyprctl activeworkspace -j | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["id"])')
ORIG_WALL=$($DAEMON query | sed -n 's/.*image: //p' | head -1)
ORIG_SEED=$(cat "$XDG_CACHE_HOME/theme-last-source" 2>/dev/null)
ORIG_COLORS=$(sha256sum "$XDG_STATE_HOME/quickshell/colors.json" | cut -d' ' -f1)
ORIG_CURSOR=$(hyprctl cursorpos)
echo "start: workspace $ORIG_WS, wallpaper $ORIG_WALL, seed $ORIG_SEED, clip $WHAT"

FPID=
CLIP=
start() {
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
restore() {
    trap - EXIT INT TERM
    [ -n "$FPID" ] && { touch "$CLIP/.stop" 2>/dev/null; kill "$FPID" 2>/dev/null; }
    pkill -f 'kitty --class bar-update' 2>/dev/null
    echo "restore: wallpaper, palette, cursor, workspace"
    [ -n "$ORIG_WALL" ] && "$DAEMON" img "$ORIG_WALL" -t fade --transition-duration 0.6 --transition-fps 60
    if [ -n "$ORIG_SEED" ]; then
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
    [ "$now" = "$ORIG_COLORS" ] && echo "palette: identical to the start" || echo "palette: DIFFERS from the start"
    jump "${ORIG_CURSOR%%,*}" "${ORIG_CURSOR##*, }"
    ws "$ORIG_WS"
    echo "done"
}
trap restore EXIT
trap 'exit 130' INT TERM

ws "$REC_WS"
sleep 1.5
read -r now_ws now_n < <(hyprctl activeworkspace -j | python3 -I -c 'import json,sys; w=json.load(sys.stdin); print(w["id"], w["windows"])')
if [ "$now_ws" != "$REC_WS" ] || [ "$now_n" != 0 ]; then
    echo "abort: workspace $now_ws with $now_n windows is active, not an empty $REC_WS"
    exit 1
fi
jump $PARK
$QS clearNotifications >/dev/null
sleep 2
$THEME /usr/share/hypr/wall0.png
sleep 4

if [ "$WHAT" = updates ]; then
    start updates "1500,0 1060x760"
    sleep 0.5; go $UPDATES $Y; sleep 2.6
    glide 2320 120 0.8; sleep 0.8; glide 2320 200 0.8; sleep 0.8
    go $UPDATES $Y; sleep 0.6
    glide $PARK; sleep 0.5
    stop
else
    start updater "0,0 2560x1440"
    sleep 0.5; go $UPDATES $Y; sleep 1.8
    go $UPDATE_NOW; sleep 4.5
    pkill -f 'kitty --class bar-update'; sleep 1.2
    glide $PARK; sleep 0.5
    stop
fi
