// The bar's settings window as its own Quickshell instance:
//   qs -p ~/.config/quickshell/sleepyshell/sleepysettings.qml
// It shares this folder's modules (qs, qs.services, qs.components, qs.sleepysettings) with the
// bar, but the bar never loads the settings files, so a change to them reloads this instance
// alone and the window cannot take the bar down. The bar launches it (`qs -c sleepyshell ipc call sleepybar
// toggle settings`, the control centre's Settings entry) and so does the launcher's entry
// (~/.local/share/applications/sleepyshell-settings.desktop); the two talk over a socket
// (services/SettingsServer.qml in the bar, sleepysettings/BarLink.qml here). The process ends
// once the window is closed and nothing is still running, so a draft lives as long as the window;
// closing with unapplied changes asks first.
// IPC: qs -p ~/.config/quickshell/sleepyshell/sleepysettings.qml ipc call sleepysettings close
import QtQuick
import Quickshell
import Quickshell.Io
import qs.sleepysettings
import qs.components

ShellRoot {
    id: root

    Sleepysettings {
        id: win
        open: true
    }

    // The process ends once the window is hidden (Escape, the close button, the bar's toggle, the
    // compositor) and no tab is still at work: a theme run or a commit waiting for the bar's
    // answer (the Theme tab is busy), or the Display tab's keep-or-revert countdown, which puts a
    // bad mode back on its own when the window went away under it. Shown again in time (the
    // bar's toggle), it stays.
    readonly property bool idle: win.pages.every(p => !p.busy && !p.pending)
    readonly property bool done: !win.visible && idle
    onDoneChanged: done ? quit.start() : quit.stop()

    // a moment for the last socket message (the preview ending) to go out
    Timer {
        id: quit
        interval: 150
        onTriggered: Qt.exit(0)
    }

    // themed replacement for Quickshell's reload popups, as in the bar (a settings file edited
    // while the window is up reloads this instance)
    ReloadToast {}

    IpcHandler {
        target: "sleepysettings"

        function close(): void {
            win.leave(() => win.open = false);
        }
    }
}
