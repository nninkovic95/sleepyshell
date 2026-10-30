import QtQuick
import Quickshell.Bluetooth
import qs
import qs.components

// Bluetooth status on the right island: shown only while the adapter is on, with the number of
// connected devices before the glyph when there are any. Information only:
// no click action and no dropdown; Bluetooth is switched and paired in the control centre.
Item {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    readonly property int connected: adapter ? adapter.devices.values.filter(d => d.connected).length : 0

    // read by the Loader in Sleepybar.qml, which hides itself (and frees the space) while this is false
    readonly property bool shown: on
    implicitWidth: row.implicitWidth + 16
    implicitHeight: Theme.buttonHeight

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.connected > 0
            text: String(root.connected)
            font.family: Theme.font
            font.pixelSize: Theme.barFontSize
            color: Theme.fg
        }

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Theme.iconNudge
            // connected / on
            cp: root.connected > 0 ? 0xF00B1 : 0xF00AF
            font.pixelSize: Theme.barIconSize
            color: root.connected > 0 ? Theme.primary : Theme.fgMuted
        }
    }
}
