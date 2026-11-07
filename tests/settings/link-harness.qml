// Harness of tests/settings/*.sh, copied into the root of the tree under test: the settings window's end of the
// socket (the tree's real sleepysettings/BarLink.qml and services/Settings.qml) without the window, run offscreen.
// Logs "SOCK <path>" once the socket's path is known. T3_ACTION:
//   probe   wait T3_WAIT ms, then report
//   apply   once linked, in one go: save barFontSize = 15 at once (Settings.setNow), stage barHeight = 33 and Apply
//           it (Settings.commit, as a tab's Apply does); report T3_WAIT ms later
//   twice   once linked, in one go: Apply barHeight = 33, Apply barHeight = 34, then stage barHeight = 35 without
//           applying it; report T3_WAIT ms later
// The report is one line "RESULT <json>": the socket path, whether linked, the staged values, the stored values of
// both keys, and the keys of every `committed` and `unsaved` signal. Then it quits.
import QtQuick
import Quickshell
import qs.services
import qs.sleepysettings

Scope {
    id: h
    readonly property string action: Quickshell.env("T3_ACTION") ?? "probe"
    readonly property int wait: Number(Quickshell.env("T3_WAIT") ?? "3000")
    property var committedKeys: []
    property var unsavedKeys: []
    property bool applied: false
    property bool reported: false

    // what BarLink calls on the window
    QtObject {
        id: fakeWindow
        property bool open: true
        property string tab: ""
        property var pages: []
        function leave(then) {
            then();
        }
    }

    BarLink {
        id: link
        window: fakeWindow
    }

    Connections {
        target: Settings
        function onCommitted(keys) {
            h.committedKeys = h.committedKeys.concat(keys);
        }
        function onUnsaved(keys) {
            h.unsavedKeys = h.unsavedKeys.concat(keys);
        }
        ignoreUnknownSignals: true
    }

    function report() {
        if (h.reported)
            return;
        h.reported = true;
        console.log("RESULT " + JSON.stringify({
            sock: Settings.socketPath,
            linked: link.connected,
            applied: h.applied,
            pending: Settings.pending,
            storedBarHeight: Settings.stored("barHeight"),
            storedBarFontSize: Settings.stored("barFontSize"),
            committed: h.committedKeys,
            unsaved: h.unsavedKeys
        }));
        quit.start();
    }

    Timer {
        running: Settings.socketPath !== ""
        interval: 50
        onTriggered: console.log("SOCK " + Settings.socketPath)
    }

    // probe: report after the wait
    Timer {
        running: h.action === "probe"
        interval: h.wait
        onTriggered: h.report()
    }

    // apply: once linked, both kinds of save in one go, then the report after the wait
    Timer {
        running: (h.action === "apply" || h.action === "twice") && link.connected && !h.applied
        interval: 300
        onTriggered: {
            h.applied = true;
            if (h.action === "twice") {
                Settings.stage("barHeight", 33);
                Settings.commit(["barHeight"]);
                Settings.stage("barHeight", 34);
                Settings.commit(["barHeight"]);
                Settings.stage("barHeight", 35);
            } else {
                Settings.setNow("barFontSize", 15);
                Settings.stage("barHeight", 33);
                Settings.commit(["barHeight"]);
            }
            after.start();
        }
    }
    Timer {
        id: after
        interval: h.wait
        onTriggered: h.report()
    }

    // never linked: report what there is
    Timer {
        running: h.action === "apply" || h.action === "twice"
        interval: 20000
        onTriggered: h.report()
    }

    Timer {
        id: quit
        interval: 200
        onTriggered: Qt.exit(0)
    }
}
