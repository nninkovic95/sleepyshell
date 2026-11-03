#!/bin/sh
# showoff.sh ACTION: send ACTION (record, ...) to the showoff Quickshell instance, starting it first when
# it is not running. Used by the Hyprland binds; the instance stays up afterwards (cheap when idle).
action="${1:?usage: showoff.sh ACTION}"
qs -c showoff ipc call showoff "$action" 2>/dev/null && exit 0
qs -c showoff -d >/dev/null 2>&1
# wait up to 3 s for the instance to answer
i=0
while [ "$i" -lt 30 ]; do
    sleep 0.1
    qs -c showoff ipc call showoff "$action" 2>/dev/null && exit 0
    i=$((i + 1))
done
notify-send -a showoff -u critical "showoff" "The showoff instance did not start (qs -c showoff log)."
exit 1
