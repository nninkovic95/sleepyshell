import QtQuick
import QtQuick.Layouts
import qs.services

// Collapsible device chooser: one row with the current device and a chevron;
// click to unfold the list, pick a device to fold it again.
ColumnLayout {
    id: root
    property var devices: []
    property var current: null
    property bool input: false
    property bool expanded: false
    property string note: ""      // shown under the current device, e.g. the hardware node controlled
    signal pick(var node)
    spacing: 2

    function glyph(n) {
        if (root.input)
            return 0xF036C;
        return n && n.name.includes("bluez") ? 0xF02CB : 0xF04C3;
    }

    DeviceRow {
        icon: root.glyph(root.current)
        title: root.current ? Audio.deviceName(root.current) : "No device"
        sub: root.note !== "" ? root.note : (root.devices.length === 1 ? "1 device" : root.devices.length + " devices")
        trailing: root.expanded ? 0xF0143 : 0xF0140
        onClicked: root.expanded = !root.expanded
    }

    Repeater {
        model: root.expanded ? root.devices : []

        DeviceRow {
            required property var modelData
            Layout.leftMargin: 18
            icon: root.glyph(modelData)
            title: Audio.deviceName(modelData)
            active: modelData === root.current
            onClicked: {
                root.pick(modelData);
                root.expanded = false;
            }
        }
    }
}
