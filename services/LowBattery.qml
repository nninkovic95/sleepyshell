import QtQuick
import Quickshell
import qs.services

// Low-battery behaviour: while discharging, one notification when the charge
// falls to lowBatteryPct, and at criticalPct a critical one that announces criticalAction after a
// grace period (60 s). Plugging in cancels the countdown and re-arms both. The notifications and
// the action go through PowerActions. Settings are read stored, never staged: a draft must not
// fire a suspend. `graceSeconds` is a property so a test can shorten the wait.
// lowBatteryWarn gates only the low notification; the critical one is always sent, and
// criticalAction "none" sends it without a countdown.
Scope {
    id: root

    property int graceSeconds: 60
    // seconds left of the countdown, 0 when none runs
    property int countdown: 0
    property bool lowArmed: true
    property bool criticalArmed: true

    readonly property string verb: Settings.criticalAction === "hibernate" ? "hibernate" : "suspend"
    // ---- BEGIN toml custom ----: criticalAction "cmd:<command line>" runs the user's own command when the countdown ends
    readonly property bool customAction: Settings.criticalAction.startsWith("cmd:") && Settings.criticalAction.length > 4
    readonly property string customCommand: root.customAction ? Settings.criticalAction.slice(4) : ""
    // ---- END toml custom ----
    // re-evaluates whenever the battery, its state or a threshold changes. ceil, not round: for whole
    // thresholds `p <= T` equals `ceil(p) <= T`, so the string changes exactly when one is crossed
    readonly property string watch: Battery.present + "|" + Battery.status + "|" + Math.ceil(Battery.percent) + "|" + Battery.onBattery + "|" + Settings.lowBatteryPct + "|" + Settings.criticalPct + "|" + Settings.lowBatteryWarn
    onWatchChanged: root.check()
    Component.onCompleted: root.check()

    function check() {
        if (!Battery.present)
            return;
        if (!Battery.discharging) {
            // charging, full or unknown: the battery is not running down
            if (root.countdown > 0)
                root.cancel();
            root.lowArmed = true;
            root.criticalArmed = true;
            return;
        }
        const p = Battery.percent;
        if (root.criticalArmed && p <= Settings.criticalPct) {
            root.criticalArmed = false;
            root.lowArmed = false;
            root.critical(p);
        } else if (root.lowArmed && Settings.lowBatteryWarn && p <= Settings.lowBatteryPct && p > Settings.criticalPct) {
            root.lowArmed = false;
            PowerActions.notify("normal", "Battery low", Math.round(p) + " % left. Plug in the charger.");
        }
        // charge back above the thresholds while still discharging (a recalibration): arm again
        if (p > Settings.lowBatteryPct)
            root.lowArmed = true;
        if (p > Settings.criticalPct)
            root.criticalArmed = true;
    }

    function critical(p) {
        const pct = Math.round(p);
        if (Settings.criticalAction === "none") {
            PowerActions.notify("critical", "Battery critical", pct + " % left. Plug in the charger now.");
            return;
        }
        root.countdown = root.graceSeconds;
        PowerActions.notify("critical", "Battery critical", pct + " % left. " + (root.customAction ? "Your command will run" : "The machine will " + root.verb) + " in " + root.graceSeconds + " seconds unless you plug in the charger.");
        tick.restart();
    }

    function cancel() {
        tick.stop();
        root.countdown = 0;
        PowerActions.notify("low", "Charger connected", root.customAction ? "Your command was cancelled." : "The " + root.verb + " was cancelled.");
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown > 0)
                return;
            tick.stop();
            root.countdown = 0;
            // the action and the threshold are read again: a setting applied during the countdown counts
                    if (Battery.discharging && Settings.criticalAction !== "none" && Battery.percent <= Settings.criticalPct) {
                if (root.customAction)
                    PowerActions.custom(root.customCommand);
                else
                    PowerActions.systemctl(root.verb);
                rearm.restart();
            }
        }
    }

    // After the action the critical warning is armed again, so a machine that wakes up still at or
    // below criticalPct is warned and suspended once more. Delayed, so the
    // percent changes before the suspend takes effect do not start a second countdown.
    Timer {
        id: rearm
        interval: 120000
        onTriggered: {
            root.criticalArmed = true;
            root.check();
        }
    }
}
