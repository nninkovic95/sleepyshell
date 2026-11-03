import QtQuick
import Quickshell
import qs
import qs.components

// One role of the theme on the Theme tab's "Colours in use" card: a tile
// filled with the colour, the role name and the hex written inside it in its matching on-colour (`matching`,
// else black or white by luminance), corners from the radius tokens, a hairline so a dark tile does not
// vanish into the card. A click copies the hex and the tile says "Copied" for a moment. `shade` is a live
// Theme colour, so a matugen run recolours the tile.
Item {
    id: tile
    property string role: ""
    property color shade: "transparent"
    // the matching on-colour (accentFg on accent); transparent: pick black or white by the shade's luminance
    property color matching: "transparent"
    // always opaque: a token with an alpha would
    // mix the card into the tile and make the dark surfaces look alike; the fill and the hex are the token's rgb
    readonly property color solid: Qt.rgba(tile.shade.r, tile.shade.g, tile.shade.b, 1)
    readonly property string hex: String(tile.solid).toLowerCase()
    readonly property real luminance: 0.2126 * tile.solid.r + 0.7152 * tile.solid.g + 0.0722 * tile.solid.b
    readonly property color ink: tile.matching.a > 0 ? tile.matching : (tile.luminance > 0.5 ? Qt.rgba(0, 0, 0, 0.87) : Qt.rgba(1, 1, 1, 0.92))
    property bool copied: false
    implicitHeight: 54
    implicitWidth: 120
    // above its neighbours while lifted, so the shadow is not covered
    z: face.z

    Timer {
        id: copiedTimer
        interval: 1200
        onTriggered: tile.copied = false
    }

    // only the face lifts; the text is a sibling at scale 1 and stays sharp
    Item {
        anchors.fill: parent

        Rectangle {
            id: face
            anchors.fill: parent
            radius: Theme.radiusMd
            color: tile.solid
            // a hairline a little lighter than the card, so a tile's edge shows even when two colours are close
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.22)

            Lift {
                radius: face.radius
                level: mouse.containsMouse ? 1 : 0
            }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            text: tile.role
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            font.weight: Font.Medium
            color: tile.ink
        }

        Text {
            text: tile.copied ? "Copied" : tile.hex
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            color: tile.ink
            opacity: 0.85
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Quickshell.clipboardText = tile.hex;
            tile.copied = true;
            copiedTimer.restart();
        }
    }
}
