#!/bin/bash
# The sandboxed half of bar/local-images.test.sh: runs inside common/sandbox.sh, never on its own.
# local-images-inner.sh RUN_FOLDER BAR_FOLDER ICON_NAME
# The private test desktop and its session bus, the request counter, the harness (offscreen), three stand-in tray
# items and ten notifications sent the way an app sends them. Leaves qs.log, hits and the helpers' logs in the
# run folder; the outer script checks them.
set -uo pipefail
D=$1
B=$2
ICON=$3
# the private test desktop (common/ui/session.sh: a headless compositor and a private session bus at $D/bus): the gtk3
# platform theme gives Qt its icon search paths and needs a display (the offscreen platform has no icon paths, so no
# theme icon would be found); nothing is drawn on the user's screen
. "$KIT/common/ui/session.sh"
ui_start "$D" || { echo "inner: the private test desktop did not start"; exit 1; }
export QT_QPA_PLATFORMTHEME=gtk3
trap 'kill $(jobs -p) 2>/dev/null; ui_stop' EXIT

python3 -I "$B/hits_server.py" "$D/hits" "$D/port" &
for _ in $(seq 50); do [ -s "$D/port" ] && [ -S "$D/bus" ] && break; sleep 0.1; done
[ -s "$D/port" ] && [ -S "$D/bus" ] || { echo "inner: the bus or the counter did not start"; exit 1; }
PORT=$(cat "$D/port")
U="http://127.0.0.1:$PORT"
S="https://127.0.0.1:$PORT"
: > "$D/hits"

# a real 2x2 PNG, so the local-path cases load
python3 -I -c 'import struct,sys,zlib
def c(t,d): return struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d))
raw=b"".join(b"\0"+b"\xff\0\0\xff"*2 for _ in range(2))
open(sys.argv[1],"wb").write(b"\x89PNG\r\n\x1a\n"+c(b"IHDR",struct.pack(">IIBBBBB",2,2,8,6,0,0,0))+c(b"IDAT",zlib.compress(raw))+c(b"IEND",b""))' "$D/pic.png"

export T3_PORT=$PORT T3_NOTIFS=10 T3_TRAY=3 T3_NAME=$ICON T3_PIC=$D/pic.png
qs -p "$D/shell/images-harness.qml" >"$D/qs.log" 2>&1 &
QS=$!

# the harness owns both names once its notification server and tray watcher are up
for _ in $(seq 150); do
    names=$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.ListNames 2>/dev/null)
    case "$names" in *"'org.freedesktop.Notifications'"*) case "$names" in *StatusNotifierWatcher*) break ;; esac ;; esac
    sleep 0.1
done

python3 -I "$B/sni_item.py" remote-name "$U/trayA.png" "" >"$D/sni-a.log" 2>&1 &
python3 -I "$B/sni_item.py" remote-path sleepyshell-test-no-such-icon "$U/themes" >"$D/sni-b.log" 2>&1 &
python3 -I "$B/sni_item.py" theme-name "$ICON" "" >"$D/sni-c.log" 2>&1 &

# notify SUMMARY APP_ICON HINTS
notify() {
    gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify "sleepyshell-test" 0 "$2" "$1" "" '[]' "$3" 0 >>"$D/notify.log" 2>&1
}
notify "remote app icon" "$U/n1.png" '{}'
notify "remote image png" "" "{'image-path': <'$U/n2.png'>}"
notify "remote https ico" "$S/n3a.ico" "{'image-path': <'$S/n3.ico'>}"
notify "file url with host" "" "{'image-path': <'file://127.0.0.1:$PORT/n4.png'>}"
notify "theme name" "$ICON" '{}'
notify "local path" "$D/pic.png" '{}'
notify "missing image falls back" "$ICON" "{'image-path': <'/nonexistent/sleepyshell-test.png'>}"
notify "remote image, local app icon" "$ICON" "{'image-path': <'$U/n8.png'>}"
notify "unknown theme name" "" "{'image-path': <'sleepyshell-test-no-such-icon'>}"
notify "local file url image" "" "{'image-path': <'file://$D/pic.png'>}"

wait "$QS"
# a late fetch would still land in the counter
sleep 1
