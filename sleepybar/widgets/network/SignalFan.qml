import QtQuick
import QtQuick.Effects
import qs
import qs.components

// The Wi-Fi strength drawn to the exact percentage, not in the icon font's four steps: the outline fan, and over it
// the solid fan cut by a circle around the fan's tip, its radius the strength's share of the fan's height, so the fill
// reaches as far up the fan as the percentage says. A fill by area read fuller than its number: the fan is widest at
// the top, so 60 % of the area already reached three quarters of the way up. Without internet both glyphs are the "!" variants (the same fan with a "!" cut into its
// lower right) and the "!" stays in full colour at any strength.
Item {
    id: root
    property real level: 0
    property bool alert: false
    property int pixelSize: Theme.barIconSize
    property color color: Theme.fg
    property color emptyColor: Theme.fgMuted

    implicitWidth: base.width
    implicitHeight: base.implicitHeight

    // the full fan's ink box in this item, from the font itself, so the cut follows the glyph at any size
    TextMetrics {
        id: ink
        font: base.font
        text: String.fromCodePoint(0xF0928)
    }
    readonly property rect box: Qt.rect((base.width - ink.advanceWidth) / 2 + ink.tightBoundingRect.x,
                                        base.baselineOffset + ink.tightBoundingRect.y,
                                        ink.tightBoundingRect.width, ink.tightBoundingRect.height)

    Glyph {
        id: base
        cp: root.alert ? 0xF092B : 0xF092F
        font.pixelSize: root.pixelSize
        color: root.emptyColor
    }

    Glyph {
        id: solid
        visible: false
        cp: root.alert ? 0xF0929 : 0xF0928
        font.pixelSize: root.pixelSize
        color: root.color
    }

    Item {
        id: mask
        width: base.width
        height: base.height
        visible: false
        layer.enabled: true

        Rectangle {
            // full strength covers the whole fan with room to spare (the tip's rounding sits a little below the
            // sector's corner)
            readonly property real r: root.level >= 0.995 ? root.box.height * 1.3 : Math.max(0, root.level) * root.box.height
            x: root.box.x + root.box.width / 2 - r
            y: root.box.y + root.box.height - r
            width: 2 * r
            height: 2 * r
            radius: r
            color: "white"
        }

        // the "!" of the alert glyph, measured from the font: right of the fan's notch, below the arc's end
        Rectangle {
            visible: root.alert
            x: root.box.x + 0.87 * root.box.width
            y: root.box.y + 0.36 * root.box.height
            width: 0.13 * root.box.width
            height: 0.64 * root.box.height
            color: "white"
        }
    }

    MultiEffect {
        width: base.width
        height: base.height
        source: solid
        maskEnabled: true
        maskSource: mask
    }
}
