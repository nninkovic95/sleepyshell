import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// Which monitor is the main one and what the others show. Two staged Settings keys,
// applied with the tab's Apply bar and read by services/MonitorPolicy.qml (the bar windows follow at once while the draft
// is open): mainMonitor (a connected output, default the first) and otherMonitors ("full", "lean" or "none").
Section {
    id: ms
    objectName: "severalMonitors"
    title: "Several monitors"
    // the Display tab (its picker)
    required property var host
    // test hook, never set by the window: a list of { name, model } in place of the connected screens
    property var screensOverride: null
    readonly property var screens: ms.screensOverride ?? Array.from(Quickshell.screens).filter(s => !String(s.name).startsWith("sleepytest"))  // not the test kit's virtual monitors
    readonly property var names: ms.screens.map(s => s.name)
    readonly property bool several: ms.screens.length > 1
    // the stored name when it is connected, else the first screen (what MonitorPolicy does too)
    readonly property string mainNow: ms.names.includes(Settings.get("mainMonitor")) ? Settings.get("mainMonitor") : (ms.names[0] ?? "")

    SettingRow {
        objectName: "rowMainMonitor"
        key: "mainMonitor"
        label: "Main monitor"
        info: "The monitor with the full bar, and where notifications appear when you are not looking at another one. By default it is the first one."
        tags: "primary screen bar notifications multi monitor"
        enabled: ms.several
        hint: ms.several ? "" : "Only one monitor is connected."
        format: v => v === "" ? "the first monitor" : v

        Combo {
            picker: ms.host.picker
            value: ms.mainNow
            options: ms.screens.map(s => ({
                        value: s.name,
                        label: s.name + (s.model ? "  ·  " + String(s.model).replace(/[<>&]/g, "") : "")
                    }))
            onPicked: v => Settings.stage("mainMonitor", v)
        }
    }

    ComboRow {
        objectName: "rowOtherMonitors"
        key: "otherMonitors"
        label: "Other monitors"
        info: "What every monitor except the main one shows. The main monitor always keeps its full bar."
        tags: "secondary screen bar multi monitor"
        enabled: ms.several
        picker: ms.host.picker
        options: [
            { value: "full", label: "Full bar without tray and bell" },
            { value: "lean", label: "Workspaces and clock" },
            { value: "none", label: "No bar" }
        ]
    }
}
