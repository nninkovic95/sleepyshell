import QtQuick
import QtQuick.Window

// Wraps a card's text and glyphs so they lean with the card (list it in the card's Lift `carry`). The content
// goes inside as usual and fills the card; Lift leans it and, only while it leans, this box draws it at twice
// the size and scales it down. Thin strokes at a slight angle drawn straight onto the screen came out either
// soft or stair-stepped; drawn large and shrunk they stay smooth and keep their colour-fringe sharpness. At
// rest nothing of this is on, and the text is drawn directly, pixel-exact.
// The box reaches `pad` past the card on every side, so the leaning corners are not cut off.
Item {
    id: box
    readonly property int pad: 8
    default property alias content: leanInner.data
    // what Lift leans
    readonly property Item inner: leanInner

    anchors.fill: parent
    anchors.margins: -pad
    // twice the screen's own pixels, on a scaled screen too
    layer.textureSize: Qt.size(Math.ceil(width * 2 * Screen.devicePixelRatio), Math.ceil(height * 2 * Screen.devicePixelRatio))
    layer.smooth: true
    layer.mipmap: true

    Item {
        id: leanInner
        x: box.pad
        y: box.pad
        width: box.width - 2 * box.pad
        height: box.height - 2 * box.pad
    }
}
