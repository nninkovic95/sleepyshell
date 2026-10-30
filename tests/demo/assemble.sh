#!/bin/bash
# assemble.sh FRAMES OUT: turn the frame folders record.sh wrote into animated WebP files in OUT
# (docs/demo). A frame's file name is its time in ms, so the animation keeps the real timing; the last
# frame is held for a second. Per clip, CROP keeps a region of the frame (W:H:X:Y in frame pixels),
# WIDTH scales the result, and COVER paints a filled rectangle (x:y:w:h:colour, in frame pixels before
# the crop) over a spot that must not be published, such as a network name on a tile. A clip without
# an entry is scaled whole. Needs ffmpeg with libwebp.
set -euo pipefail
FR=${1:?frames folder}
OUT=${2:?output folder}
mkdir -p "$OUT"

declare -A CROP WIDTH COVER
# filled in after the frames are reviewed; keys are the clip folder names
WIDTH_DEFAULT=1000
FPS=12

for dir in "$FR"/*/; do
    name=$(basename "$dir")
    frames=$(find "$dir" -maxdepth 1 -name '*.png' | sort)
    [ -n "$frames" ] || continue
    list=$dir/frames.txt
    python3 -I - "$dir" > "$list" <<'PY_LIST'
import pathlib, sys
d = pathlib.Path(sys.argv[1])
fs = sorted(p for p in d.glob("*.png"))
for a, b in zip(fs, fs[1:]):
    print(f"file '{a}'\nduration {(int(b.stem) - int(a.stem)) / 1000:.3f}")
print(f"file '{fs[-1]}'\nduration 1.000\nfile '{fs[-1]}'")
PY_LIST
    vf=""
    [ -n "${COVER[$name]:-}" ] && {
        IFS=: read -r cx cy cw ch cc <<< "${COVER[$name]}"
        vf="drawbox=x=$cx:y=$cy:w=$cw:h=$ch:color=$cc:t=fill,"
    }
    [ -n "${CROP[$name]:-}" ] && vf="${vf}crop=${CROP[$name]},"
    vf="${vf}scale=${WIDTH[$name]:-$WIDTH_DEFAULT}:-2:flags=lanczos,fps=$FPS"
    ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list" -vf "$vf" \
        -c:v libwebp_anim -lossless 0 -quality 82 -compression_level 6 -loop 0 -an "$OUT/$name.webp"
    printf '%-16s %5d frames -> %s (%s)\n' "$name" "$(echo "$frames" | wc -l)" "$OUT/$name.webp" "$(du -h "$OUT/$name.webp" | cut -f1)"
done
