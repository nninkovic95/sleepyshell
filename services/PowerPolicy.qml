import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// What the shell does for the power source and the lid. Instantiated once
// in shell.qml, next to LowBattery.
//  - Source: when the machine goes from the charger to the battery or back (Battery.onBattery), switch
//    the power profile to the source's choice (profileAc / profileBat, "keep" leaves it) and rewrite
//    hypridle.conf for that source (scripts/idle.py --battery / --ac). The profile is not touched at
//    start-up, only on a change, so a hot reload does not undo a profile picked by hand. A commit of a
//    profile key from the settings window applies it at once. Laptops only (Battery.present).
//  - Lid: logind would suspend on its own, so the shell holds a handle-lid-switch inhibitor
//    (PowerActions.inhibitCommand) and does what lidAc / lidBat says when Hyprland reports the lid
//    (`switch:on:Lid Switch` bound to the custom event "sleepyshell:lid:closed", shell.qml hands it to
//    lid()). If the inhibitor cannot be taken, logind stays in charge: lid() then does nothing
//    (or both would act) and Battery.lidControl says "logind", which the Power tab shows.
QtObject {
    id: root

    // "off" | "starting" | "active" | "failed"
    property string inhibitor: "off"
    // the source the last set was applied for ("ac" | "battery" | "")
    property string applied: ""
    property string lidState: "open"

    readonly property string source: Battery.onBattery ? "battery" : "ac"
    readonly property string sourceWatch: Battery.present ? root.source : ""
    onSourceWatchChanged: {
        if (root.sourceWatch === "")
            return;
        // a change, not the first reading: that only refreshes the idle config (a boot on battery)
        root.applySource(root.applied !== "" && root.applied !== root.sourceWatch);
        root.applied = root.sourceWatch;
    }
    Component.onCompleted: {
        if (root.sourceWatch !== "") {
            root.applySource(false);
            root.applied = root.sourceWatch;
        }
    }

    function applySource(withProfile) {
        if (withProfile)
            root.applyProfile();
        PowerActions.runIdle(root.source);
    }

    function applyProfile() {
        const want = Battery.onBattery ? Settings.profileBat : Settings.profileAc;
        if (want !== "keep" && Battery.profilesAvailable)
            Battery.setProfile(want);
    }

    // a profile key was saved from the settings window: apply the one of the current source
    readonly property Connections committed: Connections {
        target: Settings
        function onCommitted(keys) {
            if (Battery.present && keys.some(k => k === "profileAc" || k === "profileBat"))
                root.applyProfile();
        }
    }

    // ---- lid ----
    // arg: "closed" | "open"
    function lid(arg) {
        root.lidState = arg;
        if (arg !== "closed" || root.inhibitor !== "active")
            return;
        root.lidAction(Battery.onBattery ? Settings.lidBat : Settings.lidAc);
    }

    // action: "suspend" | "lock" | "hibernate" | "nothing"
    function lidAction(action) {
        // ---- BEGIN toml custom ---- "cmd:<command line>" is the pickers' Custom… (run through the shell, only now, when the lid closes)
        if (typeof action === "string" && action.startsWith("cmd:") && action.length > 4)
            PowerActions.custom(action.slice(4));
        else if (action === "suspend" || action === "hibernate")
        // ---- END toml custom ----
            PowerActions.systemctl(action);
        else if (action === "lock")
            PowerActions.lockSession();
    }

    // the inhibitor lives as long as the process does; it is taken only on a machine with a battery
    // (a laptop), so a desktop never holds a lid inhibitor
    readonly property Process hold: Process {
        command: PowerActions.inhibitCommand
        running: Battery.present
        onRunningChanged: {
            if (running) {
                root.inhibitor = "starting";
                settle.restart();
            } else {
                // gone while wanted: refused or killed, logind decides again; gone because the battery went: off
                settle.stop();
                root.inhibitor = Battery.present ? "failed" : "off";
            }
        }
    }

    // still running a moment after the start: the inhibitor was granted
    readonly property Timer settle: Timer {
        interval: 1200
        onTriggered: if (root.hold.running)
            root.inhibitor = "active"
    }

    readonly property string control: root.inhibitor === "active" ? "shell" : root.inhibitor === "failed" ? "logind" : ""
    onControlChanged: Battery.lidControl = root.control
}
