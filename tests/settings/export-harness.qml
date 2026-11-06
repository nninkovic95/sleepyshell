// Harness of tests/settings/ask-first-writers.sh, copied into the root of the tree under test: the Keybinds tab's
// Export, offscreen, through the real path (Keybinds.exportTo -> hyprconf.py export-binds, the text on stdin).
// Exports to a new file, then to a file that exists (it must not be written, and exportAsk must name it), then
// again with the yes (replace). Prints one line "RESULT <json>" and quits.
import QtQuick
import Quickshell
import qs.services

Scope {
    id: h
    readonly property string dir: Quickshell.env("EXPORT_DIR")
    property int step: 0
    property var r: ({ text: "", steps: [] })

    function go() {
        h.r.text = Keybinds.exportText(false);
        h.step = 1;
        Keybinds.exportTo(h.dir + "/new.lua", false);
    }

    Timer {
        running: true
        interval: 1500
        onTriggered: h.go()
    }

    Connections {
        target: Keybinds
        function onExportMessageChanged() {
            if (Keybinds.exportMessage === "" || h.step === 0)
                return;
            h.r.steps.push({ step: h.step, message: Keybinds.exportMessage, failed: Keybinds.exportFailed, ask: Keybinds.exportAsk });
            if (h.step === 1) {
                h.step = 2;
                Keybinds.exportTo(h.dir + "/existing.lua", false);
            } else if (h.step === 2) {
                h.step = 3;
                Keybinds.exportTo(h.dir + "/existing.lua", true);
            } else {
                h.step = 0;
                h.finish();
            }
        }
    }

    function finish() {
        console.log("RESULT " + JSON.stringify(h.r));
        quit.start();
    }

    // never hang: report what there is
    Timer {
        running: true
        interval: 20000
        onTriggered: h.finish()
    }

    Timer {
        id: quit
        interval: 500
        onTriggered: Qt.exit(0)
    }
}
