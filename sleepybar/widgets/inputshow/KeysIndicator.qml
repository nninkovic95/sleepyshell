import QtQuick
import qs
import qs.components
import qs.services

// The keybind overlay is on (services/InputShow.qml): shown only then, so it is never on unnoticed. Information only,
// like the Caps Lock indicator; the overlay is switched by its shortcut (Keybinds tab, Shell shortcuts).
Item {
    objectName: "keysIndicator"
    // read by the island's Loader, which hides itself (and frees the space) while this is false
    readonly property bool shown: InputShow.keysOn
    implicitWidth: glyph.implicitWidth + 16
    implicitHeight: Theme.buttonHeight

    Glyph {
        id: glyph
        anchors.centerIn: parent
        // the inset buttons beside it centre their content on the inset highlight, half an inset lower
        anchors.verticalCenterOffset: Theme.iconNudge + Theme.insetPad / 2
        cp: 0xF030C
        font.pixelSize: Theme.barIconSize
        // the current workspace's colour, like the bar's other state indicators (capturing ones use the alert colour)
        color: Theme.accent
    }
}
