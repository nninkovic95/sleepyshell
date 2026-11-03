import QtQuick
import QtQuick.Shapes
import qs

// One mark of the workspace dots: a circle, a rounded square or a rounded equilateral
// triangle pointing up, filled or an outline, in the box width x height. `kind` is the Settings
// `workspaceShape`. Circle and square are a Rectangle (square corners from `cornerRadius`, a radius
// token); the triangle is a Shape with curve-rendered, antialiased edges whose three corners are
// rounded by `cornerRadius` too. A stroke is drawn inside the box, so a ring and a disc of the same
// size cover the same area. The triangle sits a little high in its box (optical centre: a triangle
// looks low when its bounding box is centred).
Item {
    id: sm
    property string kind: "circle"
    property color fill: "transparent"
    property color stroke: "transparent"
    property real strokeWidth: 0
    // the corner radius of a square or a triangle (a token from Theme); a circle is always round
    property real cornerRadius: 3
    readonly property bool triangle: sm.kind === "triangle"
    Behavior on fill {
        ColorAnimation {
            duration: 150
        }
    }

    Rectangle {
        visible: !sm.triangle
        anchors.fill: parent
        radius: sm.kind === "square" ? Math.min(sm.cornerRadius, Math.min(sm.width, sm.height) / 2) : Math.min(sm.width, sm.height) / 2
        color: sm.fill
        border.width: sm.strokeWidth
        border.color: sm.stroke
    }

    // the path of a rounded equilateral triangle of side `side` (SVG, clockwise: top, bottom right, bottom left),
    // centred on x = cx; its top at y = top. Corner radius r (the tangent points are r / tan(30 deg) from a corner).
    function trianglePath(cx, topY, sideLen, r) {
        const h = sideLen * Math.sqrt(3) / 2;
        const V = [[cx, topY], [cx + sideLen / 2, topY + h], [cx - sideLen / 2, topY + h]];
        const d = r * Math.sqrt(3);
        let p = "";
        for (let i = 0; i < 3; i++) {
            const v = V[i], prev = V[(i + 2) % 3], next = V[(i + 1) % 3];
            const lp = Math.hypot(prev[0] - v[0], prev[1] - v[1]), ln = Math.hypot(next[0] - v[0], next[1] - v[1]);
            const a = [v[0] + (prev[0] - v[0]) / lp * d, v[1] + (prev[1] - v[1]) / lp * d];
            const b = [v[0] + (next[0] - v[0]) / ln * d, v[1] + (next[1] - v[1]) / ln * d];
            p += (i === 0 ? "M " : "L ") + a[0] + " " + a[1] + " ";
            p += r > 0.01 ? "A " + r + " " + r + " 0 0 1 " + b[0] + " " + b[1] + " " : "L " + b[0] + " " + b[1] + " ";
        }
        return p + "Z";
    }

    Shape {
        id: shape
        visible: sm.triangle
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        // the stroke is centred on the path, so the path is the box's triangle taken in by half of it
        readonly property real triInset: sm.strokeWidth / 2
        readonly property real triSide: Math.max(2, Math.min(sm.width, sm.height / (Math.sqrt(3) / 2)) - triInset * 2 * Math.sqrt(3))
        readonly property real triH: triSide * Math.sqrt(3) / 2
        // optical centre: up by a twelfth of the height from the bounding box's centre
        readonly property real triTop: (sm.height - triH) / 2 - triH / 12

        ShapePath {
            fillColor: sm.fill
            strokeColor: sm.strokeWidth > 0 ? sm.stroke : "transparent"
            strokeWidth: sm.strokeWidth
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: sm.trianglePath(sm.width / 2, shape.triTop, shape.triSide, Math.max(0, Math.min(sm.cornerRadius - shape.triInset, shape.triSide / 6)))
            }
        }
    }
}
