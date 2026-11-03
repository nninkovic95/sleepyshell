import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs
import qs.components
import qs.services
import "Customs.js" as Customs
import qs.sleepysettings.components

// Settings tab: laptop power. Always in the sidebar (never hidden); on a machine with no battery and no backlight the entry is greyed and the
// page says no battery was found, keeps the live power profile, and dims the plugged-in and on-battery
// sections (they stay readable) instead of removing them.
// The live controls come first ("Now": the power profile and the screen brightness, applied at once, nothing
// staged), then the battery readouts (only with a battery), then one set of choices per power source,
// "Plugged in" and "On battery": the profile to switch to and what closing the lid does, and on battery
// the low-battery warning. The rare rows (battery health and cycles, the critical level and its action) are in
// Advanced. All idle timers, plugged in and on battery, are on the Idle tab (no key is on two tabs). The shell
// (services/PowerPolicy.qml) applies the set of the current source whenever the source changes; Apply here only
// saves the keys.
// The page scrolls inside a fixed height, like the System tab, so the window keeps its size.

TabPage {
    id: tab
    key: "power"
    label: "Power"
    icon: 0xF008E
    group: "power"
    dimmed: !Battery.present && !Brightness.available
    note: "Apply saves; the shell applies the set of the current power source"

    readonly property bool bat: Battery.present
    readonly property int lowPct: Settings.get("lowBatteryPct")
    readonly property int critPct: Settings.get("criticalPct")

    readonly property var profileOptions: [
        { value: "keep", label: "Keep current" },
        { value: "power-saver", label: "Power saver" },
        { value: "balanced", label: "Balanced" },
        { value: "performance", label: "Performance" }
    ]
    readonly property var lidOptions: [
        { value: "lock", label: "Lock" },
        { value: "suspend", label: "Sleep" },
        { value: "hibernate", label: "Hibernate" },
        { value: "nothing", label: "Do nothing" }
    ]

    // ---- BEGIN toml custom ----: "Custom…" for the lid and the critical level takes a shell command of your own. It is
    // stored as "cmd:" and the command, and run (PowerActions.custom, through sh -c) only when that event happens, never while it is typed.
    function commandSpec(when, extra) {
        return {
            placeholder: "Command to run, such as systemctl poweroff",
            toText: v => Customs.commandText(v),
            seed: v => "",
            parse: t => Customs.command(t),
            warn: "This command runs as you " + when + ", through the shell. Nothing checks it, so try it in a terminal first." + extra,
            describe: v => Customs.isCommand(v) ? "runs " + Customs.commandText(v) : ({ lock: "Lock", suspend: "Sleep", hibernate: "Hibernate", nothing: "Do nothing", none: "Do nothing" })[v] ?? String(v)
        };
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 268

        Flickable {
            id: flick
            anchors.fill: parent
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // a tip belongs to what is under the pointer; it does not follow the content out of sight
            onMovingChanged: if (moving && tab.tooltip) tab.tooltip.dismiss()

            ColumnLayout {
                id: col
                width: flick.width - (flick.contentHeight > flick.height ? 10 : 0)
                spacing: 8

                SmallText {
                    objectName: "noBattery"
                    visible: !tab.bat
                    Layout.leftMargin: 2
                    text: "No battery found"
                }

                // applied at once, nothing is staged (the control centre's tile and slider, here too)
                Section {
                    title: "Now"
                    visible: Battery.profilesAvailable || Brightness.available

                    SettingRow {
                        visible: Battery.profilesAvailable
                        label: "Current power profile"
                        info: "Changes at once, like the control centre's Power profile tile; nothing is staged. The plugged in and on battery settings below switch it when the power source changes."
                        tags: "performance balanced power saver"

                        Segmented {
                            value: Battery.profileName(PowerProfiles.profile)
                            options: [
                                { value: "power-saver", label: "Power saver" },
                                { value: "balanced", label: "Balanced" }
                            ].concat(PowerProfiles.hasPerformanceProfile || (Battery.sim && Battery.sim.performance) ? [{ value: "performance", label: "Performance" }] : [])
                            onPicked: v => Battery.setProfile(v)
                        }
                    }

                    SettingRow {
                        visible: Brightness.available
                        label: "Screen brightness"
                        // the backlight is written through logind with busctl (Brightness.write)
                        requires: ["busctl"]
                        info: "Changes at once, like the control centre's slider; nothing is staged."
                        tags: "backlight display dim"

                        VSlider {
                            Layout.fillWidth: true
                            value: Brightness.level
                            onMoved: v => Brightness.set(v)
                            text: Math.round(Brightness.level * 100) + " %"
                        }
                    }
                }

                Section {
                    title: "Battery"
                    visible: tab.bat
                    property bool searchOff: !tab.bat

                    ReadoutRow {
                        label: "Charge level"
                        value: Math.round(Battery.percent) + " %"
                        fraction: Battery.percent / 100
                        lowIsBad: true
                    }
                    ReadoutRow {
                        label: "Charging status"
                        value: Battery.statusText
                    }
                    ReadoutRow {
                        label: Battery.charging ? "Time to full" : "Time left"
                        visible: Battery.timeText !== ""
                        value: Battery.timeText
                    }
                }

                Section {
                    title: "Plugged in"
                    enabled: tab.bat
                    opacity: tab.bat ? 1 : 0.7

                    ChoiceRow {
                        label: "Power profile"
                        key: "profileAc"
                        info: "Switched to when the charger is connected. Keep current leaves the profile as it is."
                        tags: "performance balanced power saver mains ac profile when plugged in (plugged in)"
                        options: tab.profileOptions
                    }
                    ChoiceRow {
                        label: "When lid closes"
                        key: "lidAc"
                        info: "What closing the lid does while plugged in. The shell takes over the lid switch from logind, so this replaces its setting."
                        error: Battery.lidControl === "logind" ? "The shell could not take over the lid switch; logind decides what the lid does." : ""
                        tags: "laptop sleep suspend hibernate lock (plugged in)"
                        options: tab.lidOptions
                        custom: tab.commandSpec("the moment the lid closes", "")
                    }
                }

                Section {
                    title: "On battery"
                    enabled: tab.bat
                    opacity: tab.bat ? 1 : 0.7

                    ChoiceRow {
                        label: "Power profile"
                        key: "profileBat"
                        info: "Switched to when the charger is unplugged. Keep current leaves the profile as it is."
                        tags: "performance balanced power saver discharging profile when on battery (on battery)"
                        options: tab.profileOptions
                    }
                    ChoiceRow {
                        label: "When lid closes"
                        key: "lidBat"
                        info: "What closing the lid does on battery."
                        error: Battery.lidControl === "logind" ? "The shell could not take over the lid switch; logind decides what the lid does." : ""
                        tags: "laptop sleep suspend hibernate lock (on battery)"
                        options: tab.lidOptions
                        custom: tab.commandSpec("the moment the lid closes", "")
                    }
                    PairRow {
                        SwitchRow {
                            label: "Low battery warning"
                            key: "lowBatteryWarn"
                            info: "One notification when the charge falls to the level beside it while discharging. It comes again after the battery has been charging. The critical notification (Advanced) is always sent."
                            tags: "battery notification low"
                        }
                        NumberRow {
                            label: "Low battery level"
                            key: "lowBatteryPct"
                            suffix: " %"
                            enabled: Settings.get("lowBatteryWarn")
                            tags: "battery low level percent warn at"
                        }
                    }
                }

                AdvancedSection {
                    ReadoutRow {
                        label: "Battery health"
                        visible: Battery.health >= 0
                        value: Math.round(Battery.health) + " %"
                    }
                    ReadoutRow {
                        label: "Charge cycles"
                        visible: Battery.cycles >= 0
                        value: String(Battery.cycles)
                    }
                    NumberRow {
                        label: "Critical battery level"
                        key: "criticalPct"
                        enabled: tab.bat
                        suffix: " %"
                        error: tab.critPct >= tab.lowPct && Settings.get("lowBatteryWarn") ? "Critical level must be below the low battery level." : ""
                        tags: "battery critical level percent critical at"
                    }
                    ChoiceRow {
                        label: "Action at critical level"
                        key: "criticalAction"
                        enabled: tab.bat
                        info: "What happens 60 seconds after the critical-battery notification. Plugging in the charger cancels it."
                        tags: "battery sleep suspend hibernate shut down at critical"
                        options: [
                            { value: "suspend", label: "Sleep" },
                            { value: "hibernate", label: "Hibernate" },
                            { value: "none", label: "Do nothing" }
                        ]
                        custom: tab.commandSpec("when the countdown ends", " Plugging in the charger cancels it.")
                    }
                }
            }
        }

        // scroll position, shown only when the page is taller than the view
        Rectangle {
            visible: flick.contentHeight > flick.height
            anchors.right: flick.right
            y: flick.visibleArea.yPosition * flick.height
            width: 3
            height: Math.max(20, flick.visibleArea.heightRatio * flick.height)
            radius: width / 2
            color: Theme.trackBg
        }
    }
}
