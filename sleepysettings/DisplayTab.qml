import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// Settings tab: per-monitor display settings, ONE card per monitor (MonitorCard): resolution, refresh rate, interface scale and, over DDC/CI, brightness and contrast; under each card its Advanced fold holds the
// input source, colour preset, rotation, adaptive sync, 10-bit colour and HDR. "Several monitors" shows only with two or more real monitors;
// Night light is a warmth and a strength. Each setting has a "!" badge that explains it on hover and a revert arrow while its value differs. Edits
// are a draft in Displays.qml; Apply writes ~/.config/hypr/modules/monitors.lua (Hyprland reloads it), then a
// 15 s countdown reverts the file unless Keep is pressed (the window's Apply bar shows Revert and
// Keep meanwhile). The page scrolls, and its height is held small so opening Advanced does not
// resize the window (the other tabs set its height).
TabPage {
    id: tab
    key: "display"
    label: "Display"
    icon: 0xF0379
    // monitors.lua must be there, writable and loaded by Hyprland, else the tab greys out under a notice (FileChecks)
    fileIds: ["monitors"]
    // the tab also stages Settings keys (the main monitor, what the other monitors show, night light) beside
    // the monitors.lua draft: Apply writes both, and the keep-or-revert countdown is for monitors.lua only. The DDC controls of
    // each monitor are live like the volume, not staged.
    group: "display"
    dirty: (Displays.dirty || tab.changes > 0) && !Displays.pending
    pending: Displays.pending
    pendingText: "Keep these settings? Reverting in " + Displays.countdown + " s"
    applyStays: true
    // what Apply writes depends on what changed: monitors.lua (with the countdown) for the monitor draft, sleepysettings.toml for the
    // Settings keys (several monitors, night light); only the files in play are listed
    readonly property bool monitorsInPlay: Displays.dirty || Displays.pending
    note: tab.monitorsInPlay || tab.changes === 0 ? "Apply writes monitors.lua; a change not kept reverts after 15 s" : "Apply saves to " + Settings.tilde(Settings.path)
    files: {
        const f = [];
        if (tab.monitorsInPlay || tab.changes === 0)
            f.push(Settings.tilde(Displays.path));
        if (tab.changes > 0 && !Displays.pending)
            f.push(Settings.tilde(Settings.path));
        return f;
    }
    // Displays.apply does nothing while only Settings keys changed
    onApplying: Displays.apply()
    onDiscarding: Displays.resetDraft()
    onKeeping: Displays.keep()
    onReverting: Displays.revert()

    // nothing talks to a monitor before the tab is open
    Binding {
        target: MonitorCtl
        property: "active"
        value: tab.visible
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

            ColumnLayout {
                id: col
                // room for the scroll mark only when the page scrolls, so the card lines up with the other tabs'
                width: flick.width - (flick.contentHeight > flick.height ? 10 : 0)
                spacing: 8

                // one card per monitor, with its Advanced fold under it
                Repeater {
                    model: Displays.monitors

                    MonitorCard {
                        host: tab
                    }
                }

                // only with two or more monitors
                MonitorsSection {
                    visible: several
                    host: tab
                }

                NightLightSection {}
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
