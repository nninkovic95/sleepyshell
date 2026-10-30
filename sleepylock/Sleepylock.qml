import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs

// Session lock (ext-session-lock), so no hyprlock or hypridle is needed. It is
// hosted by its own Quickshell instance, sleepylock.qml (`qs -n -p ~/.config/quickshell/sleepyshell/sleepylock.qml`),
// which locks on start and ends on unlock; the bar's services/SleepylockLauncher.qml starts it on
// `qs -c sleepyshell ipc call sleepybar sleepylock` and on logind's Session.Lock signal, the SUPER+L bind starts it
// directly. One instance in sleepylock.qml; it owns the lock, the PAM conversation and the state every
// screen's SleepylockSurface shows. The lock is requested over D-Bus: `loginctl lock-session` (the
// session menu's Lock) emits Session.Lock on logind, which `gdbus monitor` prints as
//   /org/freedesktop/login1/session/_33: org.freedesktop.login1.Session.Lock ()
// Suspend (PrepareForSleep) does not lock: locking before sleep is left out on purpose.
// Session.Unlock unlocks again (the monitor below), so
// `loginctl unlock-session <id>` from a TTY is the way out while this process is alive.
// PAM config "login" is PamContext's default: /etc/pam.d/login -> system-local-login ->
// system-login -> system-auth (pam_shells, pam_nologin, pam_faillock, pam_unix). Only its auth
// rules run. The wallpaper per output comes from `awww query`, one line per output:
//   ": DP-1: 2560x1440, scale: 1, currently displaying: image: /path/file.png"
// (awww prints "<namespace>: " first, the namespace is empty); a colour or no daemon gives no image.
Scope {
    id: root

    readonly property bool locked: persist.locked
    // the compositor holds the lock for this instance (sleepylock.qml ends when it never comes or goes)
    readonly property bool secure: sessionLock.secure
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    // Caps Lock state, polled from the keyboard LEDs only while locked and shown by every screen
    property bool capsLock: false
    // Black over every screen while logind prepares to sleep (the before-sleep lock), so the lock face does not
    // flash up just before the screens go off. Starts black until logind has answered, so the first frame is
    // never the face; cleared when the system wakes (PrepareForSleep false) or on any key or pointer input.
    property bool sleeping: false

    function wake(why) {
        if (!sleeping)
            return;
        console.info("lock: sleep cover lifted: " + why);
        sleeping = false;
    }
    property var wallpapers: ({})

    // the lock state survives a hot reload (a QML save while locked): the new instance takes the
    // lock over only if it starts locked, otherwise the reload would unlock the session
    PersistentProperties {
        id: persist
        reloadableId: "sessionLock"
        property bool locked: false
    }

    // after a hot reload while locked lock() never runs, so fetch the wallpapers here too
    Component.onCompleted: if (persist.locked) wallpaperQuery.running = true

    onCurrentTextChanged: showFailure = false
    // clear the last reading on unlock so the next lock does not flash a stale warning
    onLockedChanged: if (!locked) {
        capsLock = false;
        sleeping = false;
    }

    function lock() {
        if (persist.locked)
            return;
        currentText = "";
        unlockInProgress = false;
        showFailure = false;
        sleeping = true;
        sleepQuery.running = true;
        wallpaperQuery.running = true;
        persist.locked = true;
    }

    function tryUnlock() {
        if (currentText === "" || unlockInProgress)
            return;
        unlockInProgress = true;
        if (!pam.start()) {
            // the typed text is not kept when the check could not even start
            currentText = "";
            unlockInProgress = false;
            showFailure = true;
        }
    }

    function parseWallpapers(out) {
        const map = {};
        for (const line of out.split("\n")) {
            const m = line.match(/^[:\s]*([^:\s]+):.*?displaying:\s*image:\s*(.+)$/);
            if (m)
                map[m[1]] = m[2].trim();
        }
        wallpapers = map;
    }

    // what a correct password does; also logind's Session.Unlock
    function unlock() {
        persist.locked = false;
    }

    // Only this session's own signals count (security review): logind sends Unlock for every session
    // on the machine, and `loginctl unlock-session` by another user for their own session, or by this user for
    // another of their sessions, unlocked this one too while any "Session.Unlock ()" line was taken.
    function handleLogind(line) {
        if (root.sessionPath === "" || !line.startsWith(root.sessionPath + ": "))
            return;
        if (line.endsWith(": org.freedesktop.login1.Session.Unlock ()"))
            unlock();
        else if (line.endsWith(": org.freedesktop.login1.Session.Lock ()"))
            lock();
    }

    // this session's logind object path (e.g. /org/freedesktop/login1/session/_33), asked of logind for
    // XDG_SESSION_ID ("auto": the session of the asking process); until it is known no logind signal is taken
    property string sessionPath: ""

    PamContext {
        id: pam
        config: "login"
        onPamMessage: {
            if (pam.responseRequired)
                pam.respond(root.currentText);
        }
        onCompleted: result => {
            root.currentText = "";
            // unlockInProgress clears before showFailure is set: SleepylockSurface shakes its card when
            // showFailure turns true and skips the shake while a check is still running
            root.unlockInProgress = false;
            if (result == PamResult.Success)
                root.unlock();
            else
                root.showFailure = true;
        }
    }

    Process {
        id: wallpaperQuery
        command: ["sh", "-c", "awww query 2>/dev/null || swww query 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.parseWallpapers(text)
        }
    }

    Process {
        id: sleepQuery
        command: ["gdbus", "call", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1",
            "--method", "org.freedesktop.DBus.Properties.Get", "org.freedesktop.login1.Manager", "PreparingForSleep"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.indexOf("true") === -1)
                    root.wake("not going to sleep");
            }
        }
        // no answer from logind: the face, never a black screen with nothing to clear it
        onExited: code => {
            if (code !== 0)
                root.wake("no answer from logind");
        }
    }

    // runs only while black; logind sends PrepareForSleep (false,) once the system is back
    Process {
        id: sleepWatch
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        running: root.sleeping
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("org.freedesktop.login1.Manager.PrepareForSleep (false") !== -1)
                    root.wake("system woke");
            }
        }
    }

    // The capslock LED in sysfs is a cheap source needing no helper package; any *capslock device
    // at 1 counts as on, since both the laptop and an external keyboard can register one.
    Process {
        id: capsQuery
        command: ["sh", "-c", "cat /sys/class/leds/*capslock/brightness 2>/dev/null | grep -q 1 && echo on || echo off"]
        stdout: StdioCollector {
            onStreamFinished: root.capsLock = text.trim() === "on"
        }
    }

    // polls only while locked; a poll that is still running ignores the next tick's running = true
    Timer {
        id: capsPoll
        interval: 500
        repeat: true
        running: root.locked
        triggeredOnStart: true
        onTriggered: capsQuery.running = true
    }

    Process {
        id: sessionQuery
        command: ["gdbus", "call", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1",
            "--method", "org.freedesktop.login1.Manager.GetSession", Quickshell.env("XDG_SESSION_ID") || "auto"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/'(\/org\/freedesktop\/login1\/session\/[A-Za-z0-9_]+)'/);
                root.sessionPath = m ? m[1] : "";
            }
        }
        // no answer yet (logind restarting): ask again
        onExited: if (root.sessionPath === "") sessionRetry.start()
    }

    Timer {
        id: sessionRetry
        interval: 2000
        onTriggered: sessionQuery.running = true
    }

    Process {
        id: logind
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", root.sessionPath]
        running: root.sessionPath !== ""
        stdout: SplitParser {
            onRead: line => root.handleLogind(line)
        }
        onExited: logindRestart.start()
    }

    Timer {
        id: logindRestart
        interval: 2000
        onTriggered: logind.running = true
    }

    // The compositor can refuse the lock (ext_session_lock finished: another lock client is
    // alive) or end it later. WlSessionLock.locked then reads false (it is true as soon as the
    // request is made; `secure` is the compositor's confirmation) while persist.locked stays
    // true, which would leave sleepylock.qml idling without surfaces and its -n keeping every later
    // launch out. Giving persist.locked up then ends sleepylock.qml; nothing is left to unlock on the
    // compositor. A hot reload hands the lock over before the first tick.
    Timer {
        interval: 1000
        repeat: true
        running: persist.locked
        onTriggered: if (!sessionLock.locked) persist.locked = false
    }

    WlSessionLock {
        id: sessionLock
        locked: persist.locked

        WlSessionLockSurface {
            id: surface
            color: Theme.surface

            SleepylockSurface {
                anchors.fill: parent
                context: root
                screenName: surface.screen ? surface.screen.name : ""
            }

            Rectangle {
                anchors.fill: parent
                visible: root.sleeping
                color: Theme.blackout

                // a new surface under the pointer gets a position event without any movement, so only a
                // move away from the first position seen counts
                MouseArea {
                    property point first: Qt.point(-1, -1)
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: mouse => {
                        if (first.x < 0)
                            first = Qt.point(mouse.x, mouse.y);
                        else if (Math.abs(mouse.x - first.x) + Math.abs(mouse.y - first.y) > 8)
                            root.wake("pointer");
                    }
                    onPressed: root.wake("click")
                }
            }
        }
    }
}
