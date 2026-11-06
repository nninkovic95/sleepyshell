pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Caps Lock state, read from the keyboard LEDs (<leds>/*::capslock/brightness; any keyboard lit counts). The shell reads
// the files itself, in its own process, every 150 ms: Hyprland sends no event for lock keys and inotify does not fire on
// sysfs files, and a read timed after a key press missed LEDs that switch late, so the indicator caught up only on a
// later press. The LED files are listed at start and every 30 s (a keyboard plugged in later); that listing is the only
// process started.
// `keyRead` when the state changes, and after a read a key press asked for (`refresh()`, from shell.qml's
// sleepyshell:capslock event when the user's config still has a Caps_Lock bind; optional): OsdState flashes on it, so
// two quick presses that end where they began still flash. The first read sets the state without a flash.
// SLEEPYSHELL_TEST_LEDS points the tests at a folder of their own instead of /sys/class/leds.
Singleton {
    id: root

    property bool on: false
    signal keyRead

    readonly property string ledsDir: Quickshell.env("SLEEPYSHELL_TEST_LEDS") || "/sys/class/leds"
    property var files: []
    property bool primed: false
    property bool keyed: false

    function refresh() {
        root.keyed = true;
        root.read();
    }

    function read() {
        let lit = false;
        for (let i = 0; i < views.count; i++) {
            const v = views.objectAt(i);
            if (!v)
                continue;
            v.reload();
            const t = v.text().trim();
            if (t !== "" && t !== "0")
                lit = true;
        }
        const changed = lit !== root.on;
        root.on = lit;
        if (!root.primed) {
            root.primed = true;
            root.keyed = false;
            return;
        }
        if (changed || root.keyed) {
            root.keyed = false;
            root.keyRead();
        }
    }

    Instantiator {
        id: views
        model: root.files
        delegate: FileView {
            required property string modelData
            path: modelData
            blockLoading: true
        }
    }

    Timer {
        interval: 150
        running: root.files.length > 0
        repeat: true
        onTriggered: root.read()
    }

    Process {
        id: finder
        running: true
        command: ["sh", "-c", 'for f in "$1"/*::capslock/brightness; do [ -e "$f" ] && echo "$f"; done', "sh", root.ledsDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(x => x !== "");
                if (JSON.stringify(list) !== JSON.stringify(root.files))
                    root.files = list;
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: finder.running = true
    }
}
