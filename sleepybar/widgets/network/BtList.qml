import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs
import qs.components
import qs.sleepybar.components

// Bluetooth devices of the default adapter. Discovers while `scanning` is true and the adapter is on.
// Left click connects / disconnects (pairs an unknown device first), right click forgets a paired one.
// Nameless neighbours are skipped and the list is capped, so the panel cannot outgrow the screen.
ColumnLayout {
    id: root
    property bool scanning: false
    readonly property int maxRows: 8
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    readonly property var devices: adapter ? adapter.devices.values.filter(d => d.name && d.name !== "").sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name)) : []
    readonly property var shown: on ? devices.slice(0, maxRows) : []
    spacing: 2

    function syncScan() {
        if (adapter && adapter.enabled)
            adapter.discovering = scanning;
    }

    onScanningChanged: syncScan()
    onOnChanged: syncScan()
    Component.onCompleted: syncScan()

    function glyph(d) {
        const i = d.icon || "";
        if (i.includes("headset") || i.includes("headphone"))
            return 0xF02CB;
        if (i.includes("mouse"))
            return 0xF037D;
        if (i.includes("keyboard"))
            return 0xF030C;
        if (i.includes("phone"))
            return 0xF011C;
        if (i.includes("audio") || i.includes("speaker"))
            return 0xF04C3;
        if (i.includes("gaming") || i.includes("joystick"))
            return 0xF0297;
        return 0xF00AF;
    }

    Text {
        visible: !root.adapter || !root.on || root.devices.length === 0
        Layout.margins: 8
        text: !root.adapter ? "No Bluetooth adapter" : !root.on ? "Bluetooth is off" : "Scanning…"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fgMuted
    }

    Repeater {
        // ScriptModel diffs by object: a re-sorted list moves rows instead of rebuilding them
        model: ScriptModel {
            values: root.shown
        }

        DeviceRow {
            id: btRow
            required property var modelData
            // trust is granted once pairing has succeeded, not before: a rejected or timed-out
            // pairing used to leave the device trusted in BlueZ (review 4)
            property bool trustWhenPaired: false
            Connections {
                target: btRow.modelData
                function onPairedChanged() {
                    if (btRow.modelData.paired && btRow.trustWhenPaired) {
                        btRow.trustWhenPaired = false;
                        btRow.modelData.trusted = true;
                    }
                }
            }
            icon: root.glyph(modelData)
            title: modelData.name
            sub: modelData.connected ? ("Connected" + (modelData.batteryAvailable ? ", " + Math.round(modelData.battery * 100) + "%" : "")) : modelData.paired ? "Paired" : ""
            active: modelData.connected
            busy: modelData.pairing || modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
            onClicked: {
                if (modelData.connected)
                    modelData.disconnect();
                else if (modelData.paired)
                    modelData.connect();
                else {
                    trustWhenPaired = true;
                    modelData.pair();
                }
            }
            onSecondary: {
                if (modelData.paired)
                    modelData.forget();
            }
        }
    }

    Text {
        visible: root.on && root.devices.length > root.maxRows
        Layout.margins: 8
        text: "+" + (root.devices.length - root.maxRows) + " more"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fgMuted
    }
}
