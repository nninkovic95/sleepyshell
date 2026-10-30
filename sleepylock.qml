// Sleepylock, sleepyshell's lock screen, as its own Quickshell instance:
//   qs -n -p ~/.config/quickshell/sleepyshell/sleepylock.qml
// It locks the session as soon as it starts and ends once the session is unlocked, so the bar
// never loads the lock files and a bar reload or crash cannot touch a locked session. Launched by
// the SUPER+L bind (binds.lua, directly, so it works without the bar and also while the session
// is locked, to replace a dead lock client), by `qs -c sleepyshell ipc call sleepybar sleepylock`, and by the bar's
// services/SleepylockLauncher.qml when logind's Session.Lock signal arrives (the session menu's Lock
// runs `loginctl lock-session`). `-n` keeps a second press from starting a second lock. The way
// out without the password: `loginctl unlock-session` from a TTY (Sleepylock.qml listens for
// Session.Unlock). `qs -p ~/.config/quickshell/sleepyshell/sleepylock.qml kill` ends the process but leaves
// the session locked (misc.lua: allow_session_lock_restore), so a new
// `qs -n -p ~/.config/quickshell/sleepyshell/sleepylock.qml` (SUPER+L) can take the lock over.
import QtQuick
import Quickshell
import qs.sleepylock
import qs.components

ShellRoot {
    id: root
    // the compositor confirmed the lock at least once: an unlock after that is a normal end, never "did not take the lock"
    property bool taken: false

    Sleepylock {
        id: lock
        Component.onCompleted: lock.lock()
        onSecureChanged: if (secure) root.taken = true
        // unlocked: a moment for the compositor to take the unlock, then the process ends;
        // locked again inside that moment (logind's Session.Lock): it stays
        // (a lock the compositor refused or ended later also unlocks: Sleepylock.qml's watchdog)
        onLockedChanged: locked ? quit.stop() : quit.start()
    }

    // never acknowledged and never refused: end, so that -n does not keep the next launch out
    Timer {
        interval: 3000
        running: true
        onTriggered: {
            if (!lock.secure && !root.taken) {
                console.warn("lock: the compositor did not take the lock within 3 s");
                Qt.exit(1);
            }
        }
    }

    Timer {
        id: quit
        interval: 500
        onTriggered: if (!lock.locked || !lock.secure) Qt.exit(0)
    }

    // keeps Quickshell's own reload popup away, as in the bar (a lock file edited while locked
    // reloads this instance; the lock state survives the reload, see Sleepylock.qml)
    ReloadToast {}
}
