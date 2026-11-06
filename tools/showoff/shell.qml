import QtQuick
import Quickshell
import Quickshell.Io

// showoff: a demo tool kept out of sleepyshell, for recording the shell.
//   - screen recorder (Recorder.qml): SUPER + SHIFT + R starts and stops it; while it records, sleepyshell's right
//     island shows a recording dot (told over the shell's IPC: `sleepybar recording true|false`)
// (the keybind overlay and the click circles are features of sleepyshell itself: services/InputShow.qml)
// Run on demand: ~/.config/quickshell/showoff/showoff.sh record starts this instance if needed and
// sends the action over IPC (`qs -c showoff ipc call showoff <action>`).
ShellRoot {
    id: shellRoot

    Recorder {
        id: recorder
        onRecordingChanged: shellRoot.tellShell(recording)
    }

    // the shell shows the dot; a stale one is cleared when this instance starts and when it ends
    function tellShell(on) {
        Quickshell.execDetached(["qs", "-c", "sleepyshell", "ipc", "call", "sleepybar", "recording", on ? "true" : "false"]);
    }
    Component.onCompleted: shellRoot.tellShell(false)
    Component.onDestruction: shellRoot.tellShell(false)

    IpcHandler {
        target: "showoff"

        // start or stop a screen recording
        function record(): void {
            recorder.toggle();
        }
    }
}
