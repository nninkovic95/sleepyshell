pragma Singleton
import QtQuick
import Quickshell

// Every command the laptop power features run, in one place, so the test kit can
// replace them all with log lines (build_sandbox.py patches this file) and nothing outside the
// shell is started by a test. Argument arrays only, never a shell string (except `custom`: the user's own command line).
Singleton {
    id: root

    // the lid-switch inhibitor PowerPolicy holds for as long as the shell runs: logind then leaves the
    // lid to the shell. `property`, not readonly: the tests swap it for a command that fails.
    property var inhibitCommand: ["systemd-inhibit", "--what=handle-lid-switch", "--mode=block", "--who=sleepyshell", "--why=sleepyshell handles the lid itself", "sleep", "infinity"]

    // urgency: "low" | "normal" | "critical"
    function notify(urgency, title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Battery", "-u", urgency, "-i", urgency === "critical" ? "battery-empty" : "battery-low", title, body]);
    }

    // verb: "suspend" | "hibernate"
    function systemctl(verb) {
        Quickshell.execDetached(["systemctl", verb]);
    }

    // ---- BEGIN toml custom ----: the "Custom…" command of the lid and critical-battery pickers, run only when that event
    // happens. A shell string on purpose (the user wrote a command line); it comes from the user's own settings file and is never
    // run while it is typed or staged. SECURITY.md lists it.
    function custom(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd]);
    }
    // ---- END toml custom ----

    // `lock-session` ends in hypridle's lock_cmd (the lock screen), see scripts/idle.py
    function lockSession() {
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    // rewrite hypridle.conf for a power source: "battery" | "ac"
    function runIdle(source) {
        Quickshell.execDetached([Quickshell.shellPath("scripts/idle.py"), source === "battery" ? "--battery" : "--ac"]);
    }
}
