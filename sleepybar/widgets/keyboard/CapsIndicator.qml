import QtQuick
import qs
import qs.components
import qs.services

// Caps Lock on the right island: shown only while it is on. Information
// only, like the Bluetooth status; the OSD flashes the change itself (OsdState).
Item {
    id: root

    // read by the Loader in Sleepybar.qml, which hides itself (and frees the space) while this is false
    readonly property bool shown: CapsLock.on
    implicitWidth: glyph.implicitWidth + 16
    implicitHeight: Theme.buttonHeight

    Glyph {
        id: glyph
        anchors.centerIn: parent
        // the inset buttons beside it centre their content on the inset highlight, half an inset lower
        anchors.verticalCenterOffset: Theme.iconNudge + Theme.insetPad / 2
        cp: 0xF0A9B
        font.pixelSize: Theme.barIconSize
        // the current workspace's colour, like the bar's other state indicators (capturing ones use the alert colour)
        color: Theme.accent
    }
}
