import QtQuick
import Quickshell
import Quickshell.Io

// Starts the lock screen, which is its own Quickshell instance (sleepylock.qml, run
// as `qs -n -p ~/.config/quickshell/sleepyshell/sleepylock.qml`; it ends when the session is unlocked).
// Instantiated once in shell.qml: `qs -c sleepyshell ipc call sleepybar sleepylock` calls lock(), and logind's
// Session.Lock signal launches it too (the session menu's Lock runs `loginctl lock-session`;
// `gdbus monitor` prints the signal as
//   /org/freedesktop/login1/session/_33: org.freedesktop.login1.Session.Lock ()
// PrepareForSleep is not watched here: hypridle's before_sleep_cmd runs `loginctl lock-session`, which arrives as Lock.
// The SUPER+L bind launches sleepylock.qml directly (binds.lua), so it works without the bar.
QtObject {
    id: root

    // hypridle's lock_cmd answers the same Lock signal in the same instant, and qs -n alone loses that
    // race (both start, one is refused by the compositor and fails its 3 s check): both take
    // $XDG_RUNTIME_DIR/sleepylock.lock with flock first, and the one that finds it taken exits 75 quietly.
    // -n still keeps out a second lock while the SUPER+L one runs. A lock that fails to start (qs exits
    // 255 on a load error) says so in a notification, since the bar no longer loads the lock
    // files and would not notice otherwise.
    function lock() {
        Quickshell.execDetached(["sh", "-c", 'f="${XDG_RUNTIME_DIR:-/tmp}/sleepylock.lock"; if command -v flock >/dev/null; then flock -n -E 75 "$f" qs -n -p "$1"; else qs -n -p "$1"; fi; rc=$?; [ "$rc" -eq 0 ] || [ "$rc" -eq 75 ] || notify-send -u critical -a "Sleepylock" "The lock screen did not start" "See: qs -p $1 log"', "sh", Quickshell.shellDir + "/sleepylock.qml"]);
    }

    // only this session's Lock signal starts the lock (logind sends one per session on the machine; security
    // review): the session's object path is asked of logind first, as Sleepylock.qml does
    property string sessionPath: ""

    readonly property Process sessionQuery: Process {
        command: ["gdbus", "call", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1",
            "--method", "org.freedesktop.login1.Manager.GetSession", Quickshell.env("XDG_SESSION_ID") || "auto"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/'(\/org\/freedesktop\/login1\/session\/[A-Za-z0-9_]+)'/);
                root.sessionPath = m ? m[1] : "";
            }
        }
        onExited: if (root.sessionPath === "") restart.start()
    }

    readonly property Process logind: Process {
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", root.sessionPath]
        running: root.sessionPath !== ""
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith(root.sessionPath + ": ") && line.endsWith(": org.freedesktop.login1.Session.Lock ()"))
                    root.lock();
            }
        }
        onExited: restart.start()
    }

    readonly property Timer restart: Timer {
        interval: 2000
        onTriggered: root.sessionPath === "" ? (root.sessionQuery.running = true) : (root.logind.running = true)
    }
}
