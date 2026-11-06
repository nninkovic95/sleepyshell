import QtQuick
import qs
import qs.components
import qs.services

// A screen recording runs (services/Recording.qml): shown only then, in the alert colour. Information only; the
// recorder is started and stopped by its own shortcut.
Item {
    objectName: "recordingIndicator"
    // read by the island's Loader, which hides itself (and frees the space) while this is false
    readonly property bool shown: Recording.on
    implicitWidth: glyph.implicitWidth + 16
    implicitHeight: Theme.buttonHeight

    Glyph {
        id: glyph
        anchors.centerIn: parent
        // the inset buttons beside it centre their content on the inset highlight, half an inset lower
        anchors.verticalCenterOffset: Theme.iconNudge + Theme.insetPad / 2
        cp: 0xF044A
        font.pixelSize: Theme.barIconSize
        color: Theme.urgentFg
    }
}
