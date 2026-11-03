pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Caps Lock state, read from the keyboard LEDs (/sys/class/leds/*::capslock, any keyboard lit
// counts): once at start, and on every Caps Lock press. Hyprland sends no event for lock keys, and
// inotify does not fire on sysfs files, so a non-consuming Caps_Lock bind in binds.lua is the
// trigger: `hl.dsp.event("sleepyshell:capslock")`, a custom event on Hyprland's socket that
// shell.qml passes to refresh with no process started (an IPC call per press
// was used before).
// `keyRead` after every read a key press asked for, which OsdState flashes on: also when two quick
// presses end where they began.
Singleton {
    id: root

    property bool on: false
    signal keyRead

    // a key press came in while a read was running: that read may predate the LED change, so one
    // more runs after it
    property bool again: false
    property bool keyed: false

    function refresh() {
        root.keyed = true;
        // throttled, not debounced: a burst of presses still reads every 40 ms (restarting the
        // timer on each press held the widget back until the burst ended)
        if (!soon.running)
            soon.start();
        // and once more after the burst, for an LED that changed after the last read
        settle.restart();
    }

    function read() {
        if (reader.running)
            root.again = true;
        else
            reader.running = true;
    }

    // the LED follows the key a moment after the bind fires
    Timer {
        id: soon
        interval: 40
        onTriggered: root.read()
    }

    Timer {
        id: settle
        interval: 150
        onTriggered: root.read()
    }

    Process {
        id: reader
        running: true
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.on = text.split("\n").some(l => l.trim() !== "" && l.trim() !== "0")
        }
        onExited: {
            if (root.again) {
                root.again = false;
                running = true;
            } else if (root.keyed) {
                root.keyed = false;
                root.keyRead();
            }
        }
    }
}
