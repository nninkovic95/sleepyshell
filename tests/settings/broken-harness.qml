// Harness of tests/settings/broken-file.sh, copied into the root of the tree under test, whose sleepysettings.toml
// does not parse: what the bar does then, offscreen. Asks Settings.okToRun three times (the wallpaper twice, the
// power source once) and has PowerActions rewrite hypridle.conf for the battery, then prints one line
// "RESULT <json>" and quits.
import QtQuick
import Quickshell
import qs.services

Scope {
    id: h
    // Settings is created on first use and loads its file then; as in the bar, it is used from the start
    readonly property bool broken: Settings.broken
    property bool done: false

    onBrokenChanged: if (broken) check.start()

    Timer {
        id: check
        interval: 300
        onTriggered: h.run()
    }
    // the file never counted as broken: report that
    Timer {
        running: true
        interval: 5000
        onTriggered: h.run()
    }

    function run() {
        if (h.done)
            return;
        h.done = true;
        const r = {
            broken: Settings.broken,
            line: Settings.brokenLine,
            note: Settings.brokenNote("The wallpaper wasn't changed"),
            wallpaper1: Settings.okToRun("The wallpaper wasn't changed"),
            wallpaper2: Settings.okToRun("The wallpaper wasn't changed"),
            power: Settings.okToRun("The idle timers weren't switched to the new power source")
        };
        PowerActions.runIdle("battery");
        console.log("RESULT " + JSON.stringify(r));
        quit.start();
    }

    Timer {
        id: quit
        interval: 1500
        onTriggered: Qt.exit(0)
    }
}
