pragma Singleton
import Quickshell

// Opens and closes the Keybinds window (sleepykeys.qml, its own Quickshell instance). `toggle()` first
// asks a running window to close over its IPC; when nothing answers, none is open and a new one starts.
// `qs -n` refuses a second instance, so two quick presses cannot open two windows.
// Callers: shell.qml on the `sleepyshell:keybinds` event (the SUPER + / bind) and the control centre's
// Keybinds tool.
Singleton {
    id: root

    readonly property string entry: Quickshell.shellPath("sleepykeys.qml")

    function toggle() {
        Quickshell.execDetached(["sh", "-c", 'qs -p "$1" ipc call sleepykeys close >/dev/null 2>&1 || exec qs -n -p "$1"', "sh", root.entry]);
    }
}
