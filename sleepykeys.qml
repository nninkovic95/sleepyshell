// Sleepykeys, the Keybinds window, as its own Quickshell instance:
//   qs -n -p ~/.config/quickshell/sleepyshell/sleepykeys.qml
// A read-only list of every Hyprland keybind (sleepykeys/Sleepykeys.qml). Its own process, like the
// settings window and the lock, so the bar never loads these files and a problem here cannot take the
// bar down. The shell starts and closes it (services/SleepykeysLauncher.qml) on the
// `sleepyshell:keybinds` event (SUPER + /) and from the control centre's Keybinds tool; `-n` keeps a
// second start from opening a second window. The process ends once the window is closed.
// IPC: qs -p ~/.config/quickshell/sleepyshell/sleepykeys.qml ipc call sleepykeys close
import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.sleepykeys

ShellRoot {
    Sleepykeys {
        id: win
        visible: true
        onVisibleChanged: if (!visible)
            Qt.exit(0)
    }

    // themed replacement for Quickshell's reload popups, as in the bar
    ReloadToast {}

    IpcHandler {
        target: "sleepykeys"

        // the launcher's toggle: an open window is closed (and the process ends)
        function close(): void {
            win.visible = false;
        }
    }
}
