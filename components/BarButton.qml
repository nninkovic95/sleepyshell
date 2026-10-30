import QtQuick
import qs

// Text button glued to the island's top edge. Its highlight (hover, or a fixed bg) is a
// Highlight: square top with small inverted fillets, rounded bottom.
// The label is text in the bar font; an icon is a Glyph beside it (glyph: a codepoint, or
// glyphText: several glyphs). The bar's order for readouts is figure then glyph (glyphFirst false).
Item {
    id: root
    property alias text: label.text
    property int glyph: 0
    property string glyphText: glyph ? String.fromCodePoint(glyph) : ""
    property bool glyphFirst: false
    // on the bar (glued) the bar sizes, inside panels the panel sizes
    property int glyphSize: glued ? Theme.barIconSize : Theme.iconSize
    property color bg: "transparent"
    property color fg: Theme.fg
    property color hoverBg: Theme.hoverBg
    property color hoverFg: fg
    property int hpad: 8
    property int minWidth: 0
    property bool glued: true    // false inside panels: plain rounded highlight, no fillets
    property bool lift: true     // hover lift (Lift.qml); off for parts of passive readouts
    // right island: the highlight floats Theme.insetPad in from the island
    // edges with a nested radius, instead of hanging from the top
    property bool inset: false
    // the pointing hand over the button; off where hovering already opens what a click would
    // (the readouts beside the clock)
    property bool handCursor: true
    readonly property bool hovered: mouse.containsMouse
    readonly property color currentFg: hovered ? hoverFg : fg

    signal clicked(int button)   // Qt.LeftButton / RightButton / MiddleButton
    signal scrolled(int delta)

    implicitWidth: Math.max(minWidth, content.implicitWidth + hpad * 2)
    implicitHeight: Theme.buttonHeight

    // above its neighbours while lifted, so the shadow is not covered
    z: surface.z

    // Only the highlight lifts (scaling the whole button leaves the glyph and
    // text blurry on hover); the content below sits on top of it at scale 1. The holder keeps the
    // lifted surface (z 1) under the content and the MouseArea, and the Lift reads the pointer from
    // that MouseArea: without both a lifted surface covered the glyph and took the hover, so the
    // button could blink.
    Item {
        anchors.fill: parent

    Item {
        id: surface
        anchors.fill: parent

        Lift {
            pointer: mouse
            level: root.lift && root.hovered ? 1 : 0
            shape: highlight
            // a glued button grows down from the island top instead of poking above it
            fromTop: root.glued && !root.inset
            radius: highlight.radius
        }

        Highlight {
            id: highlight
            anchors.fill: parent
            anchors.topMargin: root.inset ? Theme.insetPad : 0
            glued: root.glued && !root.inset
            radius: root.inset ? Theme.insetRadius : Theme.radiusSm
            color: root.hovered ? root.hoverBg : root.bg
        }
    }
    }

    Row {
        id: content
        anchors.centerIn: parent
        // centre on the inset highlight, not on the full button
        anchors.verticalCenterOffset: root.inset ? Theme.insetPad / 2 : 0
        spacing: 4
        layoutDirection: root.glyphFirst ? Qt.LeftToRight : Qt.RightToLeft

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Theme.iconNudge
            text: root.glyphText
            visible: text !== ""
            font.pixelSize: root.glyphSize
            color: root.currentFg
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            // labels can come from apps (notification actions); Qt's default AutoText would
            // render a <b> or <img> in them as rich text (review 4)
            textFormat: Text.PlainText
            font.family: Theme.font
            font.pixelSize: root.glued ? Theme.barFontSize : Theme.fontSize
            color: root.currentFg
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.handCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: m => root.clicked(m.button)
        // a tilt-wheel or horizontal scroll event has y == 0; it must not count as "down"
        onWheel: w => {
            if (w.angleDelta.y !== 0)
                root.scrolled(w.angleDelta.y);
        }
    }
}
