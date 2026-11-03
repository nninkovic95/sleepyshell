import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services
import qs.sleepybar.components

// Dropdown body for the volume (input: false) or microphone (input: true) pill:
// mute button + slider + percentage, the device list, and a link to the mixer.
ColumnLayout {
    id: root
    property bool input: false
    property bool showMixer: true
    readonly property real level: input ? Audio.micVolume : Audio.volume
    readonly property bool muted: input ? Audio.micMuted : Audio.muted
    readonly property var devices: input ? Audio.sources : Audio.sinks
    readonly property var current: input ? Audio.defaultSource : Audio.defaultSink
    readonly property var controlled: input ? Audio.source : Audio.sink
    spacing: 6
    Layout.fillWidth: true

    Text {
        Layout.leftMargin: 8
        text: root.input ? "Input" : "Output"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.bold: true
        color: Theme.fg
    }

    // The row mirrors itself and lines up with the device rows below it. The mute button is invisible until it is muted, so what the eye measures on the left is the glyph:
    // its cell starts 2 + 6 (the button's hpad) = 8 px in and the 16 px icon is drawn about 4 px inside its cell (its advance is 12), so it
    // starts 12 px in, like a device row's icon (8 px margin + 2). The percent box ends the same 12 px from the right edge. The row was
    // inset 4 on both sides: the glyph sat 16 px in and the box 4 px, beyond the chevron of the row below.
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 2
        Layout.rightMargin: 12
        spacing: 8

        BarButton {
            glyph: root.input ? Audio.micGlyph() : Audio.sinkGlyph()
            hpad: 6
            glued: false
            bg: root.muted ? Theme.urgent : "transparent"
            hoverBg: root.muted ? Theme.urgent : Theme.hoverBg   // keep the muted fill under the pointer
            fg: root.muted ? Theme.urgentFg : Theme.fg
            hoverFg: fg
            onClicked: root.input ? Audio.toggleMicMute() : Audio.toggleMute()
        }

        VSlider {
            Layout.fillWidth: true
            value: root.level
            muted: root.muted
            textWidth: 52
            textColor: Theme.fg
            onMoved: v => root.input ? Audio.setMicVolume(v) : Audio.setVolume(v)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.margins: 4
        implicitHeight: 1
        color: Theme.containerHighest
    }

    DeviceSelect {
        Layout.fillWidth: true
        input: root.input
        devices: root.devices
        current: root.current
        note: root.controlled && root.controlled !== root.current ? "level: " + Audio.deviceName(root.controlled) : ""
        onPick: n => root.input ? Audio.setSource(n) : Audio.setSink(n)
    }

    Rectangle {
        visible: root.showMixer
        Layout.fillWidth: true
        Layout.margins: 4
        implicitHeight: 1
        color: Theme.containerHighest
    }

    MenuItem {
        visible: root.showMixer
        icon: 0xF057E
        label: "Audio mixer"
        onClicked: {
            Popouts.current.open = false;
            Quickshell.execDetached(["pwvucontrol"]);
        }
    }
}
