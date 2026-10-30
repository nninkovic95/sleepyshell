#!/bin/bash
# assemble.sh FRAMES OUT: turn the frame folders record.sh wrote into animated WebP files in OUT
# (docs/demo). A frame's file name is its time in ms, so the animation keeps the real timing; the last
# frame is held for a second. Per clip (keyed by the folder name): CROP keeps a region of the frame
# (W:H:X:Y in frame pixels), WIDTH scales the result, and BLUR blurs a rectangle (x:y:w:h in frame
# pixels, before the crop) in every frame of the clip, for a spot that must not be published such as the
# network name on the Wi-Fi tile; the smudge over wallpaper while the tile is closed is accepted. A clip
# without an entry is scaled whole. Needs ffmpeg with libwebp.
set -euo pipefail
FR=${1:?frames folder}
OUT=${2:?output folder}
mkdir -p "$OUT"

declare -A CROP WIDTH BLUR
WIDTH_DEFAULT=1000
FPS=12
# the Wi-Fi tile's subtitle, in frames whose region starts at x=560, at x=760, and in full-width frames
WIFI_560="572:74:124:22"
WIFI_760="372:74:124:22"
WIFI_FULL="1132:74:124:22"
for c in control-centre tile-tilt tile-do-not-disturb tile-keep-awake tile-night-light tile-bluetooth tile-power-profile audio; do BLUR[$c]=$WIFI_560; done
for c in pill-scroll pill-mute; do BLUR[$c]=$WIFI_760; done
for c in calendar session settings drag wallpaper wallpaper-settings shuffle-wallpaper shuffle-colours; do BLUR[$c]=$WIFI_FULL; done
# crops (W:H:X:Y in frame pixels) measured on the reviewed frames
CROP[notifications]="760:520:300:0"
CROP[updates]="760:600:300:0"
WIDTH[updates]=760
CROP[notification-list]="760:600:300:0"
CROP[card-tilt]="760:600:300:0"
CROP[clear-all]="760:600:300:0"
CROP[calendar]="800:680:880:400"
CROP[session]="1000:400:780:500"
CROP[settings]="1060:1170:745:105"
CROP[drag]="1060:1170:745:105"
CROP[wallpaper]="720:480:900:0"
CROP[wallpaper-settings]="1060:1270:745:0"
WIDTH[workspaces]=400
WIDTH[island-extend]=760
WIDTH[island-float]=760
WIDTH[notifications]=760
WIDTH[notification-list]=760
WIDTH[card-tilt]=760
WIDTH[clear-all]=760
WIDTH[shuffle-wallpaper]=1280
WIDTH[shuffle-colours]=1280
WIDTH[pill-scroll]=1040
WIDTH[pill-mute]=1040

for dir in "$FR"/*/; do
    name=$(basename "$dir")
    frames=$(find "$dir" -maxdepth 1 \( -name '*.jpg' -o -name '*.png' \) | sort)
    [ -n "$frames" ] || continue
    list=$dir/frames.txt
    python3 -I - "$dir" > "$list" <<'PY_LIST'
import pathlib, sys
d = pathlib.Path(sys.argv[1]).resolve()   # absolute: the concat demuxer resolves entries against the list file
fs = sorted((*d.glob("*.jpg"), *d.glob("*.png")), key=lambda p: int(p.stem))
for a, b in zip(fs, fs[1:]):
    print(f"file '{a}'\nduration {(int(b.stem) - int(a.stem)) / 1000:.3f}")
print(f"file '{fs[-1]}'\nduration 1.000\nfile '{fs[-1]}'")
PY_LIST
    vf=""
    if [ -n "${BLUR[$name]:-}" ]; then
        IFS=: read -r bx by bw bh <<< "${BLUR[$name]}"
        vf="split[main][b];[b]crop=$bw:$bh:$bx:$by,boxblur=8:2[blur];[main][blur]overlay=$bx:$by,"
    fi
    [ -n "${CROP[$name]:-}" ] && vf="${vf}crop=${CROP[$name]},"
    vf="${vf}scale=${WIDTH[$name]:-$WIDTH_DEFAULT}:-2:flags=lanczos,fps=$FPS"
    ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list" -vf "$vf" \
        -c:v libwebp_anim -lossless 0 -quality 82 -compression_level 6 -loop 0 -an "$OUT/$name.webp"
    printf '%-20s %5d frames -> %s (%s)\n' "$name" "$(echo "$frames" | wc -l)" "$OUT/$name.webp" "$(du -h "$OUT/$name.webp" | cut -f1)"
done
