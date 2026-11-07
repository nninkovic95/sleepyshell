// Harness of tools/default-settings.sh, copied into the root of a scratch copy of the shell that has no settings file:
// renders sleepysettings.toml from the schema defaults, without the notes that depend on this machine, into the file
// named by DEFAULTS_OUT, then quits. Exits 1 when the copy had a settings file (its values would not be the defaults).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Scope {
    id: h

    Component.onCompleted: {
        Settings.machineNotes = false;
        start.start();
    }

    // Settings reads its (missing) file first; render only after that, so nothing of a load is half done
    Timer {
        id: start
        interval: 500
        onTriggered: {
            if (Settings.broken || Settings.extras.length > 0) {
                console.warn("default-settings: the copy has a settings file; the defaults cannot be rendered from it");
                Qt.exit(1);
                return;
            }
            out.setText(Settings.render());
            quit.start();
        }
    }

    FileView {
        id: out
        path: Quickshell.env("DEFAULTS_OUT")
        atomicWrites: true
    }

    Timer {
        id: quit
        interval: 500
        onTriggered: Qt.exit(0)
    }
}
