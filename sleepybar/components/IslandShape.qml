import QtQuick
import QtQuick.Shapes

// The outline of an island that hangs from the screen's top edge, as ONE path in every state.
//
// The island's bottom edge is a skyline: three columns side by side, each { x0, x1, d } (left, right, depth), in the
// coordinates of the surface this shape covers. Closed, the centre island is a short side, the deeper clock part and
// another short side; open, it is the control centre's three columns. `from` and `to` are two such skylines, each with
// its own step radii ({ fillet, corner, cols }), and `t` (0..1) morphs one into the other, column by column.
//
// Every corner shrinks with the room it has (half the step it turns, half the columns beside it), down to 0. So a step
// that disappears, a column of zero width or a side as deep as the middle are the same path with other values: the
// element list never changes and no second drawing is needed. A zero-width column must take a neighbour's depth.
//
// Imports only QtQuick and QtQuick.Shapes, so the outline can be tested on its own (tests/bar/islandshape.test.sh).
//   radius     the island radius: the outer top fillets toward the screen edge and the outer bottom corners
//   fillItem   what fills the path: a texture provider the size of this shape (the island's content, its backdrop
//              included); with no fillTransform it is drawn in this shape's own coordinates
//   islandLeft/islandRight  the island's current outer edges (the top fillets reach `radius` beyond them)
//   cols       the current columns; maskRects the input rectangles they cover ({ x, y, width, height })
//   current    the skyline drawn right now ({ fillet, corner, cols }): a new morph that starts from it starts
//              exactly where the outline is
Shape {
    id: root

    required property var from
    required property var to
    required property real t
    required property real radius
    required property Item fillItem

    readonly property var cols: {
        const out = [];
        for (let i = 0; i < 3; i++) {
            const a = from.cols[i], b = to.cols[i];
            out.push({ x0: a.x0 + (b.x0 - a.x0) * t, x1: a.x1 + (b.x1 - a.x1) * t, d: a.d + (b.d - a.d) * t });
        }
        return out;
    }
    readonly property real fillet: from.fillet + (to.fillet - from.fillet) * t
    readonly property real corner: from.corner + (to.corner - from.corner) * t
    readonly property var current: ({ fillet: fillet, corner: corner, cols: cols })
    readonly property real islandLeft: cols[0].x0
    readonly property real islandRight: cols[2].x1
    readonly property var maskRects: cols.map(c => ({ x: c.x0, y: 0, width: Math.max(0, c.x1 - c.x0), height: c.d }))

    // every point and radius of the path, from the columns
    readonly property var g: {
        const c = cols;
        const f = fillet, k = corner;
        const w = c.map(col => Math.max(0, col.x1 - col.x0));
        // outer top fillets: never deeper than the side they lead into; outer bottom corners: within the side's width
        // and below the top fillet
        const topL = Math.max(0, Math.min(radius, c[0].d));
        const topR = Math.max(0, Math.min(radius, c[2].d));
        const botL = Math.max(0, Math.min(radius, w[0] / 2, c[0].d - topL));
        const botR = Math.max(0, Math.min(radius, w[2] / 2, c[2].d - topR));
        // the two steps, walked right to left along the bottom edge: from column i (right) to column i - 1 (left).
        // Going down: a concave fillet, then a convex corner; going up: the other way round. At a step of height 0
        // both radii are 0, so turning the direction there moves nothing.
        const steps = [];
        for (let i = 2; i >= 1; i--) {
            const xs = c[i].x0, hA = c[i].d, hB = c[i - 1].d;
            const down = hB >= hA;
            const room = Math.max(0, Math.min(Math.abs(hB - hA) / 2, w[i] / 2, w[i - 1] / 2));
            const fil = Math.min(f, room), cor = Math.min(k, room);
            const a = down ? fil : cor, b = down ? cor : fil, s = down ? 1 : -1;
            steps.push({
                x1: xs + a, y1: hA,
                x2: xs, y2: hA + s * a, r2: a, d2: down ? PathArc.Counterclockwise : PathArc.Clockwise,
                x3: xs, y3: hB - s * b,
                x4: xs - b, y4: hB, r4: b, d4: down ? PathArc.Clockwise : PathArc.Counterclockwise
            });
        }
        return { L: c[0].x0, R: c[2].x1, dL: c[0].d, dR: c[2].d, topL: topL, topR: topR, botL: botL, botR: botR, s: steps };
    }

    preferredRendererType: Shape.CurveRenderer
    containsMode: Shape.FillContains

    ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillItem: root.fillItem
        startX: root.g.L - root.g.topL
        startY: 0
        // top edge, top-right fillet, right side, bottom-right corner
        PathLine { x: root.g.R + root.g.topR; y: 0 }
        PathArc { x: root.g.R; y: root.g.topR; radiusX: root.g.topR; radiusY: root.g.topR; direction: PathArc.Counterclockwise }
        PathLine { x: root.g.R; y: root.g.dR - root.g.botR }
        PathArc { x: root.g.R - root.g.botR; y: root.g.dR; radiusX: root.g.botR; radiusY: root.g.botR; direction: PathArc.Clockwise }
        // the step between the right and the middle column
        PathLine { x: root.g.s[0].x1; y: root.g.s[0].y1 }
        PathArc { x: root.g.s[0].x2; y: root.g.s[0].y2; radiusX: root.g.s[0].r2; radiusY: root.g.s[0].r2; direction: root.g.s[0].d2 }
        PathLine { x: root.g.s[0].x3; y: root.g.s[0].y3 }
        PathArc { x: root.g.s[0].x4; y: root.g.s[0].y4; radiusX: root.g.s[0].r4; radiusY: root.g.s[0].r4; direction: root.g.s[0].d4 }
        // the step between the middle and the left column
        PathLine { x: root.g.s[1].x1; y: root.g.s[1].y1 }
        PathArc { x: root.g.s[1].x2; y: root.g.s[1].y2; radiusX: root.g.s[1].r2; radiusY: root.g.s[1].r2; direction: root.g.s[1].d2 }
        PathLine { x: root.g.s[1].x3; y: root.g.s[1].y3 }
        PathArc { x: root.g.s[1].x4; y: root.g.s[1].y4; radiusX: root.g.s[1].r4; radiusY: root.g.s[1].r4; direction: root.g.s[1].d4 }
        // bottom-left corner, left side, top-left fillet
        PathLine { x: root.g.L + root.g.botL; y: root.g.dL }
        PathArc { x: root.g.L; y: root.g.dL - root.g.botL; radiusX: root.g.botL; radiusY: root.g.botL; direction: PathArc.Clockwise }
        PathLine { x: root.g.L; y: root.g.topL }
        PathArc { x: root.g.L - root.g.topL; y: 0; radiusX: root.g.topL; radiusY: root.g.topL; direction: PathArc.Counterclockwise }
    }
}
