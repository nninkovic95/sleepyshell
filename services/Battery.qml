pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// The laptop battery and the power source, over Quickshell.Services.UPower,
// laptop power features). Shared by the bar (widget, low-battery service, power policy)
// and the settings window (Power tab), so it holds state only; what reacts to it is in
// LowBattery.qml and PowerPolicy.qml, and every outside command is in PowerActions.qml.
// This machine is a desktop (no battery): `present` is false there and everything laptop-only
// stays hidden. `simulate` replaces the real readings for tests (the sandbox sets it over IPC):
//   { present: bool, percent: 0..100, status: "charging"|"discharging"|"full",
//     ac: bool (default: status is not discharging), timeToEmpty: s, timeToFull: s,
//     health: 0..100 (omit: unknown), cycles: n (omit: hidden), profiles: bool (default true) }
// Untested on real hardware (no battery here): the UPower readings below, in particular that
// `energy` / `energyCapacity` are Wh and the times are seconds.
Singleton {
    id: root

    property var simulate: null
    readonly property var sim: root.simulate

    // ---- real readings ----
    // the aggregated "display device" gives charge, state and times; the physical battery gives health
    readonly property var display: UPower.displayDevice
    readonly property var cell: UPower.devices.values.find(d => d.isLaptopBattery && d.isPresent) ?? null
    readonly property var meter: root.cell !== null && root.display && root.display.ready && root.display.isPresent ? root.display : root.cell

    readonly property string realStatus: {
        const m = root.meter;
        if (!m)
            return "unknown";
        switch (m.state) {
        case UPowerDeviceState.Charging:
        case UPowerDeviceState.PendingCharge:
            return "charging";
        case UPowerDeviceState.Discharging:
        case UPowerDeviceState.PendingDischarge:
        case UPowerDeviceState.Empty:
            return "discharging";
        case UPowerDeviceState.FullyCharged:
            return "full";
        }
        return "unknown";
    }
    // charge in %: energy / energy-full, which does not depend on the scale `percentage` uses
    readonly property real realPercent: {
        const m = root.meter;
        if (!m)
            return 0;
        if (m.energyCapacity > 0)
            return Math.max(0, Math.min(100, m.energy / m.energyCapacity * 100));
        return m.percentage <= 1 ? m.percentage * 100 : m.percentage;
    }
    // energy-full / energy-full-design, as UPower computes it (a fraction or a percent, by scale)
    readonly property real realHealth: {
        const c = root.cell;
        if (!c || !c.healthSupported || c.healthPercentage <= 0)
            return -1;
        return c.healthPercentage <= 1.5 ? c.healthPercentage * 100 : c.healthPercentage;
    }

    // ---- what the shell reads ----
    readonly property bool present: root.sim ? !!root.sim.present : root.cell !== null
    // "charging" | "discharging" | "full" | "unknown"
    readonly property string status: !root.present ? "unknown" : root.sim ? (root.sim.status ?? "discharging") : root.realStatus
    readonly property real percent: !root.present ? 0 : root.sim ? (root.sim.percent ?? 0) : root.realPercent
    readonly property bool discharging: root.present && root.status === "discharging"
    readonly property bool charging: root.present && root.status === "charging"
    // running on the battery, as opposed to mains power (a battery that is full on the charger is not)
    readonly property bool onBattery: root.present && (root.sim ? (root.sim.ac === undefined ? root.sim.status === "discharging" : !root.sim.ac) : UPower.onBattery)
    // seconds until empty (discharging) or full (charging); 0: not known
    readonly property real seconds: !root.present ? 0 : root.sim ? ((root.discharging ? root.sim.timeToEmpty : root.charging ? root.sim.timeToFull : 0) ?? 0) : root.discharging ? root.meter.timeToEmpty : root.charging ? root.meter.timeToFull : 0
    // battery health in % (-1: unknown)
    readonly property real health: !root.present ? -1 : root.sim ? (root.sim.health ?? -1) : root.realHealth
    // charge cycles (-1: hidden). Quickshell's UPower module does not expose ChargeCycles (checked
    // 0.3.2), so only a simulation has one; read /sys/class/power_supply/BAT*/cycle_count here if wanted
    readonly property int cycles: root.sim ? (root.sim.cycles ?? -1) : -1

    // who handles the lid: "shell" (PowerPolicy holds the inhibitor), "logind" (it could not, logind
    // decides), "" unknown. Set by PowerPolicy in the bar and mirrored to the settings window by SettingsServer.
    property string lidControl: ""

    readonly property string statusText: !root.present ? "No battery" : root.status === "charging" ? "Charging" : root.status === "full" ? "Fully charged" : root.status === "discharging" ? "Discharging" : (root.onBattery ? "On battery" : "Plugged in")

    // "1 h 12 min", "5 min"
    function span(s) {
        const m = Math.round((Number(s) || 0) / 60);
        const h = Math.floor(m / 60);
        return h > 0 ? h + " h " + (m % 60) + " min" : Math.max(1, m) + " min";
    }

    readonly property string timeText: root.seconds > 0 ? root.span(root.seconds) : ""

    // battery glyph for the bar and the tab: level steps in tens, a charging variant while charging
    function glyph() {
        const p = root.percent;
        if (root.charging || (root.status === "full" && !root.onBattery)) {
            const c = [0xF089C, 0xF0086, 0xF0087, 0xF0088, 0xF089D, 0xF0089, 0xF089E, 0xF008A, 0xF008B, 0xF0085];
            return c[Math.max(0, Math.min(9, Math.round(p / 10) - 1))];
        }
        if (p < 6)
            return 0xF0083;
        const d = [0xF007A, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079];
        return d[Math.max(0, Math.min(10, Math.round(p / 10)))];
    }

    // ---- power profiles (power-profiles-daemon over Quickshell's PowerProfiles) ----
    // Quickshell has no "service is there" flag, so the daemon is probed once on its bus name.
    property bool probed: false
    // the probe has answered: until then the profile tile is not greyed
    property bool probeDone: false
    readonly property bool profilesAvailable: root.sim ? root.sim.profiles !== false : root.probed
    // known to be missing (the control centre's Power profile tile greys out on this)
    readonly property bool profilesMissing: root.sim ? root.sim.profiles === false : (root.probeDone && !root.probed)
    readonly property var profileNames: ({
            "power-saver": PowerProfile.PowerSaver,
            "balanced": PowerProfile.Balanced,
            "performance": PowerProfile.Performance
        })

    function profileName(p) {
        return p === PowerProfile.Performance ? "performance" : p === PowerProfile.PowerSaver ? "power-saver" : "balanced";
    }

    // name: "power-saver" | "balanced" | "performance"; a performance profile the hardware lacks is skipped
    function setProfile(name) {
        const p = root.profileNames[name];
        if (p === undefined || (p === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile && !(root.sim && root.sim.performance)))
            return;
        PowerProfiles.profile = p;
    }

    Process {
        command: ["busctl", "--system", "get-property", "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles", "ActiveProfile"]
        running: true
        onExited: code => {
            root.probed = code === 0;
            root.probeDone = true;
        }
    }
}
