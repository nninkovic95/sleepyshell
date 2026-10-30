import QtQuick
import qs

// A small "!" badge; hovering it shows `text` in the window's Tooltip (passed in as tooltip).
// warn: true draws it in the urgent tones.
Badge {
    id: it
    required property var tooltip
    property string text: ""
    property bool warn: false
    readonly property color tint: warn ? Theme.urgentFg : Theme.primary
    fg: tint
    color: hover.hovered ? Qt.alpha(tint, 0.3) : Qt.alpha(tint, 0.14)

    HoverHandler {
        id: hover
        cursorShape: Qt.WhatsThisCursor
        onHoveredChanged: hovered ? it.tooltip.show(it, it.text, it.warn) : it.tooltip.hide(it)
    }
}
