import QtQuick
import QtQuick.Effects
import qs
import qs.services

// Hover lift for clickable things: put one inside the item as a direct child.
// It scales the item itself (Theme.liftScale, but never by more than Theme.liftMaxPx), raises it
// above its siblings and grows a soft shadow under `shape`.
// `level` (0..1) drives it; by default the pointer over the item, but it can be bound to anything
// (the workspace dots follow the sliding pill). `pill` adds a rounded hover background for bare
// text or glyph buttons. `tilt` leans the item toward the pointer, only on items at least
// 120 x 48 (cards and tiles; thin rows would just shear). Not for passive readouts.
// Scaling re-rasterises everything inside the target, so text and glyphs inside it blur:
// put the Lift in a background child of the item and keep the content beside it at
// scale 1 (see MenuItem, Tile, BarButton); the item's own `z: surface.z` keeps it above neighbours.
Item {
    id: lift
    readonly property Item target: parent
    // the visible surface the shadow and pill follow; the item itself unless set
    property Item shape: target
    property real radius: Theme.radiusSm
    property real peak: Theme.liftScale
    property real maxPx: Theme.liftMaxPx
    // scale from the top edge (buttons glued to the island top) instead of the centre
    property bool fromTop: false
    property bool pill: false
    property bool tilt: false
    // the most a tilted item leans, in degrees, with the pointer at its edge
    property real tiltMax: 10
    property bool shadow: true
    property real level: hover.hovered ? 1 : 0
    readonly property bool hovered: hover.hovered

    // eased: false for a level that changes every frame (the workspace wave follows the sliding
    // pill): the Behavior restarted on each new value and never moved
    property bool eased: true
    property real amount: level
    Behavior on amount {
        enabled: lift.eased
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    readonly property real gain: Math.min(peak - 1, maxPx / Math.max(1, target.width))
    // Settings: big cards tilt toward the pointer ("tilt") or only lift ("lift")
    // the smallest item that tilts; lower for wide, short tiles with a small tiltMax (MenuItem)
    property real tiltMinHeight: 48
    // ---- BEGIN toml custom ----: cardHover is "lift", "tilt", or a number: the lean in percent of the standard (10 to 300)
    readonly property real tiltScale: {
        const c = String(Settings.cardHover);
        if (c === "tilt")
            return 1;
        return /^[0-9]+$/.test(c) ? Math.max(0.1, Math.min(3, parseInt(c, 10) / 100)) : 0;
    }
    readonly property bool tilts: tilt && tiltScale > 0 && target.width >= 120 && target.height >= tiltMinHeight
    // ---- END toml custom ----
    // shape geometry in the target's coordinates
    readonly property rect area: shape === target ? Qt.rect(0, 0, target.width, target.height) : Qt.rect(shape.x, shape.y, shape.width, shape.height)

    anchors.fill: parent
    z: -1

    Binding {
        target: lift.target
        property: "scale"
        value: 1 + lift.amount * lift.gain
    }
    Binding {
        target: lift.target
        property: "transformOrigin"
        value: lift.fromTop ? Item.Top : Item.Center
    }
    Binding {
        target: lift.target
        property: "z"
        value: lift.amount > 0.01 ? 1 : 0
    }

    // the last pointer position over the item, -0.5..0.5 from its centre; kept after the pointer
    // leaves so the tilt eases out with `amount` instead of snapping flat
    property real nx: 0
    property real ny: 0

    // where the pointer is: an item with its own hover MouseArea passes it as `pointer`, since that
    // MouseArea takes the hover and the HoverHandler under it (z -1) never sees the pointer; a
    // HoverHandler on top would take the hover from the MouseArea instead
    property MouseArea pointer: null

    function aim(x, y) {
        const p = pointer.mapToItem(lift, x, y);
        nx = p.x / Math.max(1, width) - 0.5;
        ny = p.y / Math.max(1, height) - 0.5;
    }

    Connections {
        target: lift.pointer
        function onPositionChanged(e) {
            lift.aim(e.x, e.y);
        }
        function onContainsMouseChanged() {
            if (lift.pointer.containsMouse)
                lift.aim(lift.pointer.mouseX, lift.pointer.mouseY);
        }
    }

    HoverHandler {
        id: hover
        enabled: lift.pointer === null
        onPointChanged: {
            if (hovered) {
                lift.nx = point.position.x / Math.max(1, lift.width) - 0.5;
                lift.ny = point.position.y / Math.max(1, lift.height) - 0.5;
            }
        }
    }

    // tilt: the side under the pointer sinks, up to 10 degrees at an edge, seen from 400 px away.
    // Not a Rotation: its fixed 1024 px eye distance left a 6 degree tilt of a 167 px tile at
    // well under a pixel.
    Matrix4x4 {
        id: rot
        matrix: {
            const r = Math.hypot(lift.nx, lift.ny);
            const a = lift.amount * 2 * lift.tiltMax * lift.tiltScale * Math.min(0.5, r) * Math.PI / 180;
            // axis in the screen plane, at right angles to the pointer's offset from the centre
            const ux = r > 0 ? -lift.ny / r : 0, uy = r > 0 ? lift.nx / r : 0;
            const c = Math.cos(a), s = Math.sin(a), t = 1 - c;
            const cx = lift.width / 2, cy = lift.height / 2, d = 400;
            const rotate = Qt.matrix4x4(c + ux * ux * t, ux * uy * t, uy * s, 0,
                                        uy * ux * t, c + uy * uy * t, -ux * s, 0,
                                        -uy * s, ux * s, c, 0,
                                        0, 0, 0, 1);
            const perspective = Qt.matrix4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, -1 / d, 1);
            // then drop the depth, as Qt's own Rotation does (projectedRotate): Qt Quick clips
            // anything more than about a pixel off the item's plane, and on a wide card the receding
            // edge was cut off on a diagonal, which read as a much steeper lean
            const flatten = Qt.matrix4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1);
            const toCentre = Qt.matrix4x4(1, 0, 0, -cx, 0, 1, 0, -cy, 0, 0, 1, 0, 0, 0, 0, 1);
            const back = Qt.matrix4x4(1, 0, 0, cx, 0, 1, 0, cy, 0, 0, 1, 0, 0, 0, 0, 1);
            return back.times(flatten.times(perspective.times(rotate.times(toCentre))));
        }
    }
    // the matrix only while lifted: kept on at rest it left text and glyphs soft
    // (most visible on the tilted tools grid), and an item without it is drawn
    // pixel-exact
    readonly property bool tiltOn: tilts && amount > 0.001
    onTiltOnChanged: target.transform = tiltOn ? [rot] : []
    Component.onCompleted: {
        if (tiltOn)
            target.transform = [rot];
    }

    // The shadow is cut out under the surface: most surfaces here are translucent (hoverBg, the
    // island fill), and a whole blurred rectangle behind them showed as a dark box. The shadow is
    // drawn off screen in a box with room for its blur, then masked by the surface's own shape,
    // inverted. Built only while lifted.
    Loader {
        readonly property int m: 20
        active: lift.shadow && lift.amount > 0.01
        x: lift.area.x - m
        y: lift.area.y - m
        width: lift.area.width + 2 * m
        height: lift.area.height + 2 * m

        sourceComponent: Item {
            Item {
                id: shadowSrc
                anchors.fill: parent
                visible: false

                RectangularShadow {
                    x: parent.width / 2 - width / 2
                    y: parent.height / 2 - height / 2
                    width: lift.area.width
                    height: lift.area.height
                    radius: lift.radius
                    blur: 4 + 10 * lift.amount
                    offset.y: 1 + 3 * lift.amount
                    color: Qt.alpha("black", 0.35 * lift.amount)
                }
            }

            Item {
                id: shadowMask
                anchors.fill: parent
                visible: false
                layer.enabled: true

                Rectangle {
                    x: parent.width / 2 - width / 2
                    y: parent.height / 2 - height / 2
                    width: lift.area.width
                    height: lift.area.height
                    radius: lift.radius
                }
            }

            MultiEffect {
                anchors.fill: parent
                source: shadowSrc
                maskEnabled: true
                maskSource: shadowMask
                maskInverted: true
            }
        }
    }

    Rectangle {
        visible: lift.pill && lift.amount > 0.01
        x: lift.area.x
        y: lift.area.y
        width: lift.area.width
        height: lift.area.height
        radius: height / 2
        color: Theme.hoverBg
        opacity: lift.amount
    }
}
