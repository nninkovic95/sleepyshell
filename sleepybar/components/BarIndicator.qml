import QtQuick
import qs
import qs.components

// A state indicator on the right island (Caps Lock, keybind overlay, click circles, recording): the icon alone, in the
// accent colour (Theme.accent, as the palette gives it; the recording dot sets its own `tint`), on the same line as the buttons beside it, shown only while `shown` is true. Information only: no
// background, no hover, nothing to click (a clickable indicator, the privacy one, is a button and gets the hover
// highlight only on hover).
Item {
    id: ind
    // read by the island's Loader, which hides itself (and frees the space) while this is false
    property bool shown: false
    property int cp: 0
    // a glyph that fills more of its box than the others is drawn smaller, so it looks the same size
    property real glyphScale: 1
    property color tint: Theme.accent
    // a slow fade in and out, for a state that must not go unnoticed (a recording)
    property bool blink: false
    implicitWidth: glyph.implicitWidth + 16
    implicitHeight: Theme.buttonHeight

    Glyph {
        id: glyph
        anchors.centerIn: parent
        // the inset buttons beside it centre their content on their highlight, half an inset lower
        anchors.verticalCenterOffset: Theme.iconNudge + Theme.insetPad / 2
        cp: ind.cp
        font.pixelSize: Math.round(Theme.barIconSize * ind.glyphScale)
        color: ind.tint
    }

    // runs only while shown, so a hidden indicator does not redraw the bar every frame; kept out of the Glyph so the
    // icon stays a plain Glyph
    SequentialAnimation {
        running: ind.blink && ind.shown
        loops: Animation.Infinite
        onStopped: glyph.opacity = 1
        NumberAnimation {
            target: glyph
            property: "opacity"
            to: 0.25
            duration: 700
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: glyph
            property: "opacity"
            to: 1
            duration: 700
            easing.type: Easing.InOutSine
        }
    }
}
