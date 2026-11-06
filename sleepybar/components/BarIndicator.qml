import QtQuick
import qs
import qs.components

// A state indicator on the right island (Caps Lock, keybind overlay, click circles, recording): the icon alone, in the
// warning colour (Theme.alertIcon), on the same line as the buttons beside it, shown only while `shown` is true. Information only: no
// background, no hover, nothing to click (a clickable indicator, the privacy one, is a button and gets the hover
// highlight only on hover).
Item {
    id: ind
    // read by the island's Loader, which hides itself (and frees the space) while this is false
    property bool shown: false
    property int cp: 0
    // a glyph that fills more of its box than the others is drawn smaller, so it looks the same size
    property real glyphScale: 1
    implicitWidth: glyph.implicitWidth + 16
    implicitHeight: Theme.buttonHeight

    Glyph {
        id: glyph
        anchors.centerIn: parent
        // the inset buttons beside it centre their content on their highlight, half an inset lower
        anchors.verticalCenterOffset: Theme.iconNudge + Theme.insetPad / 2
        cp: ind.cp
        font.pixelSize: Math.round(Theme.barIconSize * ind.glyphScale)
        // the warning colour, made readable on the bar (Theme.alertIcon)
        color: Theme.alertIcon
    }
}
