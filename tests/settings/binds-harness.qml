// Harness of tests/settings/ask-first-writers.sh, copied into the root of the tree under test, whose sleepysettings.toml
// points the keybinds file (pathCustombinds) at a file the user wrote: the Keybinds tab's Apply, offscreen, through the
// real path (Keybinds.apply -> hyprconf.py write-binds). Adds a bind and applies: the write must stop at the question
// (customAsk, nothing written); then the yes (confirmWrite) writes it. Prints one line "RESULT <json>" and quits.
import QtQuick
import Quickshell
import qs.services

Scope {
    id: h
    property var r: ({ addError: "", ask: null, stagedAfterAsk: false, stagedAfterYes: true, writeError: "" })
    property int step: 0

    Timer {
        running: true
        interval: 2000
        onTriggered: {
            h.r.addError = Keybinds.add("SUPER + F9", "notify-send harness");
            h.step = 1;
            Keybinds.apply();
        }
    }

    Connections {
        target: Keybinds
        function onCustomAskChanged() {
            if (h.step !== 1 || !Keybinds.customAsk)
                return;
            const a = Keybinds.customAsk;
            h.r.ask = { path: a.path, removed: a.removed, added: a.added };
            h.r.stagedAfterAsk = Keybinds.staged !== null;
            h.step = 2;
            Keybinds.confirmWrite();
        }
        function onBusyChanged() {
            if (h.step === 2 && !Keybinds.busy) {
                h.r.stagedAfterYes = Keybinds.staged !== null;
                h.r.writeError = Keybinds.writeError;
                h.finish();
            }
        }
    }

    function finish() {
        h.step = 3;
        console.log("RESULT " + JSON.stringify(h.r));
        quit.start();
    }

    Timer {
        running: true
        interval: 20000
        onTriggered: if (h.step !== 3) h.finish()
    }

    Timer {
        id: quit
        interval: 500
        onTriggered: Qt.exit(0)
    }
}
