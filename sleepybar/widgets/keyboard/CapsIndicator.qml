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
        anchors.verticalCenterOffset: Theme.iconNudge
        cp: 0xF0A9B
        font.pixelSize: Theme.barIconSize
        color: Theme.primary
    }
}
