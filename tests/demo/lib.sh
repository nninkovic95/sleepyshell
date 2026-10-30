# demo/lib.sh: helpers the recording scripts share. Sourced, never run.
#
# The cursor moves through wlrctl's virtual pointer, in small relative steps along an eased, slightly
# bowed path, so the compositor delivers real motion events and the shell shows its hover effects as for
# a mouse (a warp through Hyprland's dispatcher moves the cursor but fires no hover; it is the fallback
# when wlrctl is missing). Clicks and scrolls come from the same virtual pointer, a drag from ydotool
# (the only one of the two that can hold a button); without the tool the caller falls back or skips.
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
SHELL_DIR=$XDG_CONFIG_HOME/quickshell/sleepyshell
QS="qs -c sleepyshell ipc call sleepybar"
HAVE_WLRCTL=$(command -v wlrctl || true)
HAVE_YDOTOOL=
if command -v ydotool >/dev/null; then
    [ -z "${YDOTOOL_SOCKET:-}" ] && [ -S /tmp/.ydotool_socket ] && export YDOTOOL_SOCKET=/tmp/.ydotool_socket
    ydotool mousemove -x 0 -y 0 >/dev/null 2>&1 && HAVE_YDOTOOL=yes
fi

hc() { hyprctl dispatch "$1" >/dev/null; }
ws() { hc "hl.dsp.focus({ workspace = $1 })"; }
jump() { hc "hl.dsp.cursor.move({ x = $1, y = $2 })"; }
shortcut() { hc "hl.dsp.send_shortcut({ mods = \"$1\", key = \"$2\", window = \"$3\" })"; }

# glide X Y [SECONDS]: move the cursor to X,Y along an eased, slightly bowed path
glide() {
    python3 -I - "$1" "$2" "${3:-}" "${HAVE_WLRCTL:-}" <<'PY_GLIDE'
import math, random, subprocess, sys, time
x1, y1 = int(sys.argv[1]), int(sys.argv[2])
wlrctl = sys.argv[4]
def pos():
    out = subprocess.run(["hyprctl", "cursorpos"], capture_output=True, text=True).stdout
    return [int(v) for v in out.replace(" ", "").split(",")]
def warp(x, y):
    subprocess.run(["hyprctl", "dispatch", f"hl.dsp.cursor.move({{ x = {x}, y = {y} }})"], capture_output=True)
x0, y0 = pos()
dist = math.hypot(x1 - x0, y1 - y0)
if dist < 2:
    sys.exit(0)
dur = float(sys.argv[3]) if sys.argv[3] else min(1.1, 0.32 + dist / 2200)
n = max(20, min(320, int(dur * 100)))   # about a hundred steps a second: smooth at any speed
bow = min(36.0, dist * 0.06) * random.choice((-1, 1))
px, py = -(y1 - y0) / dist, (x1 - x0) / dist
cx, cy = x0, y0
t0 = time.time()
for i in range(1, n + 1):
    t = i / n
    e = t * t * (3 - 2 * t)
    s = math.sin(math.pi * t)
    x = round(x0 + (x1 - x0) * e + px * bow * s)
    y = round(y0 + (y1 - y0) * e + py * bow * s)
    if wlrctl:
        dx, dy = x - cx, y - cy
        if dx or dy:
            subprocess.run([wlrctl, "pointer", "move", str(dx), str(dy)], capture_output=True)
        cx, cy = x, y
    else:
        warp(x, y)
    d = t0 + dur * t - time.time()
    if d > 0:
        time.sleep(d)
if wlrctl:
    # the virtual pointer's steps can land a pixel or two off (acceleration, clamping): settle exactly
    rx, ry = pos()
    if (rx, ry) != (x1, y1):
        subprocess.run([wlrctl, "pointer", "move", str(x1 - rx), str(y1 - ry)], capture_output=True)
PY_GLIDE
}

click() { [ -n "$HAVE_WLRCTL" ] && wlrctl pointer click "${1:-left}"; }
scroll() { [ -n "$HAVE_WLRCTL" ] && wlrctl pointer scroll "$1" 0; }
# go X Y: glide there, settle, click
go() { glide "$1" "$2"; sleep 0.25; click; }
# drag X0 Y0 X1 Y1: press at the first point, glide to the second, release (ydotool)
drag() {
    [ -n "$HAVE_YDOTOOL" ] || return 1
    glide "$1" "$2"; sleep 0.3
    ydotool click 0x40; sleep 0.25
    glide "$3" "$4" 1.0; sleep 0.35
    ydotool click 0x80; sleep 0.2
}

# win TITLE_REGEX: prints "x y w h" of the first client whose title matches, or nothing
win() {
    hyprctl clients -j | python3 -I -c '
import json, re, sys
for c in json.load(sys.stdin):
    if re.search(sys.argv[1], c.get("title", "")):
        print(*c["at"], *c["size"]); break' "$1"
}
# at DX DY: glide to a point relative to the settings window and click it
at() {
    read -r wx wy _ _ < <(win '^Sleepysettings$')
    [ -n "${wx:-}" ] || return 1
    go $((wx + $1)) $((wy + $2))
}
# hover DX DY: glide to a point relative to the settings window, no click
hover() {
    read -r wx wy _ _ < <(win '^Sleepysettings$')
    [ -n "${wx:-}" ] || return 1
    glide $((wx + $1)) $((wy + $2))
}
