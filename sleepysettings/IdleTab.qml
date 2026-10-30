import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.sleepysettings.components

// Settings tab: what happens when the machine sits idle: dim the screens,
// lock, suspend, and lock before any sleep, for the plugged-in set and (on a laptop) the on-battery set. The keys are staged like every tab; Apply saves them
// and then runs scripts/idle.py, which writes ~/.config/hypr/hypridle.conf from sleepysettings.toml and
// restarts hypridle.service if it is running. Same order as the Theme tab: the script reads the
// file, so it waits for Settings.committed (the keys are on disk) before it starts.
// The minutes rows dim while their switch is off. A step that is not later than the one before it
// shows a red hint; Apply is not blocked (hypridle copes, the order is only odd).
TabPage {
    id: tab
    key: "idle"
    label: "Idle"
    icon: 0xF04B2
    group: "idle"
    // hypridle.conf is written by scripts/idle.py (python3) for hypridle; without them the tab is greyed out
    requires: ["hypridle", "python3"]
    // the folder of hypridle.conf must exist and the file be writable, else the tab greys out under a notice (FileChecks)
    fileIds: ["hypridle"]
    files: [Settings.tilde(Settings.path), Settings.tilde(Settings.pathHypridle)]
    busy: tab.running
    // the plugged-in set and (on a laptop) the on-battery set are both here
    note: "Apply saves and rewrites hypridle.conf"

    property bool running: false
    property bool awaitingCommit: false

    // the minutes of the step before this one that is switched on, 0 for none
    readonly property bool dimOn: Settings.get("idleDim")
    readonly property bool lockOn: Settings.get("idleLock")
    readonly property bool suspendOn: Settings.get("idleSuspend")
    readonly property int dimMin: Settings.get("idleDimMin")
    readonly property int lockMin: Settings.get("idleLockMin")
    readonly property int suspendMin: Settings.get("idleSuspendMin")
    readonly property int beforeLock: tab.dimOn ? tab.dimMin : 0
    readonly property int beforeSuspend: tab.lockOn ? tab.lockMin : tab.dimOn ? tab.dimMin : 0

    function orderHint(on, min, before, what) {
        return on && before > 0 && min <= before ? "Later than " + what + " (" + before + " min), or this step never comes first." : "";
    }

    // run idle.py once the keys are in sleepysettings.toml (the bar writes the file; the script reads it)
    function run() {
        runner.command = [Quickshell.shellPath("scripts/idle.py")];
        runner.running = true;
    }

    onApplying: {
        // greyed out (hypridle or python3 missing, or the config file cannot be written): Apply only saves the keys, it runs nothing
        if (tab.needsText !== "" || tab.fileText !== "")
            return;
        tab.running = true;
        tab.awaitingCommit = true;
        ackWait.restart();
    }

    function afterCommit() {
        tab.awaitingCommit = false;
        ackWait.stop();
        tab.run();
    }

    Connections {
        target: Settings
        function onCommitted(keys) {
            if (tab.awaitingCommit && keys.some(k => tab.keys.includes(k)))
                tab.afterCommit();
        }
    }

    // no word from the bar within three seconds (it went away mid-apply): run anyway
    Timer {
        id: ackWait
        interval: 3000
        onTriggered: {
            if (!tab.awaitingCommit)
                return;
            console.warn("idle: no word from the bar that the idle settings were saved, running idle anyway");
            tab.afterCommit();
        }
    }

    Process {
        id: runner
        onExited: tab.running = false
    }

    // each step's switch sits beside its minutes (PairRow). All the
    // idle timers are on this tab, the plugged-in set and (on a laptop) the on-battery set; labels do not repeat the
    // Section's title, which the search still finds through the row's section title
    Section {
        title: "Idle timers"

        PairRow {
            SwitchRow {
                label: "Dim screens when idle"
                key: "idleDim"
                info: "Darkens the screens with sleepyshell's own overlay after this long without input; any key or mouse movement clears it. Keep awake in the control centre pauses every idle step."
                tags: "idle screen dark brightness hypridle caffeine inhibitor plugged in (plugged in)"
            }
            NumberRow {
                label: "Dim after"
                key: "idleDimMin"
                suffix: " min"
                enabled: tab.dimOn
                tags: "dim idle timeout after (plugged in)"
            }
        }
        PairRow {
            SwitchRow {
                label: "Lock screen when idle"
                key: "idleLock"
                info: "Starts the lock screen after this long without input. Keep awake in the control centre pauses this step."
                tags: "idle hypridle caffeine inhibitor plugged in (plugged in)"
            }
            NumberRow {
                label: "Lock after"
                key: "idleLockMin"
                suffix: " min"
                enabled: tab.lockOn
                error: tab.orderHint(tab.lockOn, tab.lockMin, tab.beforeLock, "dimming")
                tags: "lock idle timeout after (plugged in)"
            }
        }
    }

    // the set used while on battery (moved here from the Power tab; same keys); only on a machine with a battery
    Section {
        title: "On battery"
        visible: Battery.present
        property bool searchOff: !Battery.present

        PairRow {
            SwitchRow {
                label: "Dim when idle"
                key: "idleBatDim"
                info: "The idle steps used while on battery, shorter by default. The plugged-in steps are in Idle timers."
                tags: "idle screen dark discharging dim screens (on battery)"
            }
            NumberRow {
                label: "Dim after"
                key: "idleBatDimMin"
                suffix: " min"
                enabled: Settings.get("idleBatDim")
                tags: "dim idle timeout battery (on battery)"
            }
        }
        PairRow {
            SwitchRow {
                label: "Lock when idle"
                key: "idleBatLock"
                tags: "idle discharging lock screen (on battery)"
            }
            NumberRow {
                label: "Lock after"
                key: "idleBatLockMin"
                suffix: " min"
                enabled: Settings.get("idleBatLock")
                tags: "lock idle timeout battery (on battery)"
            }
        }
    }

    AdvancedSection {
        PairRow {
            SwitchRow {
                label: Battery.present ? "Sleep when idle (plugged in)" : "Sleep when idle"
                key: "idleSuspend"
                info: "Puts the computer to sleep after this long without input. Off by default. Keep awake in the control centre pauses this step."
                tags: "sleep idle hypridle caffeine inhibitor plugged in"
            }
            NumberRow {
                label: Battery.present ? "Sleep after (plugged in)" : "Sleep after"
                key: "idleSuspendMin"
                suffix: " min"
                enabled: tab.suspendOn
                error: tab.orderHint(tab.suspendOn, tab.suspendMin, tab.beforeSuspend, tab.lockOn ? "locking" : "dimming")
                tags: "sleep idle timeout after"
            }
        }
        PairRow {
            visible: Battery.present
            property bool searchOff: !Battery.present

            SwitchRow {
                label: "Sleep when idle (on battery)"
                key: "idleBatSuspend"
                tags: "sleep idle discharging"
            }
            NumberRow {
                label: "Sleep after (on battery)"
                key: "idleBatSuspendMin"
                suffix: " min"
                enabled: Settings.get("idleBatSuspend")
                tags: "sleep idle timeout battery"
            }
        }
        SwitchRow {
            label: "Lock before sleep"
            key: "lockBeforeSleep"
            info: "Locks the screen just before the machine goes to sleep, however it got there (the Sleep step, the session menu, the lid or the power button), so it wakes to the lock screen."
            tags: "suspend lid hypridle sleep"
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
