import QtQuick
import QtQuick.Shapes
import qs

// Highlight surface for bar widgets: hangs from the island's top edge like the islands hang
// from the screen edge. Square top corners with small concave fillets outside them, rounded bottom.
// glued: false gives a plain rounded rectangle, for buttons inside panels (nothing to hang from).
Item {
    id: root
    property color color: "transparent"
    property int radius: Theme.radiusSm
    property int fillet: Theme.radiusXs
    property bool glued: true
    // a fillet can be dropped on one side (a dropdown whose edge runs past the island above it)
    property bool filletLeft: true
    property bool filletRight: true

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        topLeftRadius: root.glued ? 0 : root.radius
        topRightRadius: root.glued ? 0 : root.radius
        color: root.color
    }

    Shape {
        anchors.fill: parent
        visible: root.glued && root.color.a > 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.filletLeft ? root.color : "transparent"
            startX: -root.fillet
            startY: 0
            PathLine { x: 0; y: 0 }
            PathLine { x: 0; y: root.fillet }
            PathArc {
                x: -root.fillet
                y: 0
                radiusX: root.fillet
                radiusY: root.fillet
                direction: PathArc.Counterclockwise
            }
        }

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.filletRight ? root.color : "transparent"
            startX: root.width + root.fillet
            startY: 0
            PathLine { x: root.width; y: 0 }
            PathLine { x: root.width; y: root.fillet }
            PathArc {
                x: root.width + root.fillet
                y: 0
                radiusX: root.fillet
                radiusY: root.fillet
                direction: PathArc.Clockwise
            }
        }
    }
}
