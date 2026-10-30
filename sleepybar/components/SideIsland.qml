import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Widgets
import qs
import qs.services

// A side island: a bar island with inverted (concave) corners where it meets a screen edge, so it
// looks carved out of the edge. No drop shadow: the islands are frosted glass (translucent fill +
// Hyprland blur), and a shadow showing through the translucent fillets cancelled their tint.
// `attach` decides which edges it is glued to:
//   "top"      hangs from the top edge: fillets at the top-left and top-right, round bottom corners
//   "topLeft"  sits in the top-left corner: fillet toward the top (top-right) and toward the left edge
//              (below its bottom-left), one round corner at the bottom-right
//   "topRight" mirror of topLeft
//
// Island host contract. A widget's IslandDropdown finds the island it sits in by walking up
// to the first ancestor with `attach`, then talks to it only through these members. SideIsland
// implements them for the side islands; GrowingIsland's panel item implements them for the centre:
//   attach, glueLeft, glueRight  which edges the island is glued to
//   hostX        left edge of the island's window on screen (0 here: the bar window spans the screen)
//   hostWindow   the island's window when it is not the bar (for the dropdown's focus grab), else null
//   hangY        where a dropdown's top edge sits (the island's bottom edge)
//   canExtend    true when the island widens itself so a dropdown hangs flush under its straight
//                bottom edge; false: the dropdown floats as a card under it
//   straightEdge()           the straight part of the bottom edge on screen, {l, r}, without any extension
//   fitPanel(panelX, panelW) widen the island over a panel at panelX..panelX+panelW; returns where the
//                            panel's sides sit flush with the island while it is not extended, {edgeL, edgeR}
//   releasePanel()           drop the extension again
// The island owns its geometry: a dropdown never writes extendLeft / extendRight itself.
Item {
    id: root

    // ---- API ----
    default property alias content: row.data
    property int padding: Theme.leftIslandPad
    property string attach: "top"

    // ---- host contract (see the header) ----
    readonly property bool glueLeft: attach === "topLeft"
    readonly property bool glueRight: attach === "topRight"
    readonly property real hostX: 0
    readonly property var hostWindow: null
    readonly property real hangY: Theme.barHeight
    readonly property bool canExtend: Settings.dropdownFit !== "float"

    function straightEdge() {
        const x = mapToItem(null, 0, 0).x + hostX + extendLeft;
        const w = width - extendLeft - extendRight;
        return {
            l: x + (glueLeft ? 0 : r),
            r: x + w - (glueRight ? 0 : r)
        };
    }

    // A free end grows until its straight bottom edge reaches past the panel by one fillet, so the
    // panel and its fillets sit under the straight part (a panel edge that landed on a
    // round corner left a notch, so the island is extended to fit it). A glued end is
    // the screen edge and never grows.
    function fitPanel(panelX, panelW) {
        const e = straightEdge();
        extendLeft = glueLeft ? 0 : Math.max(0, e.l + r - panelX);
        extendRight = glueRight ? 0 : Math.max(0, panelX + panelW + r - e.r);
        return {
            edgeL: glueLeft ? panelX : e.l + r,
            edgeR: glueRight ? panelX + panelW : e.r - r
        };
    }

    function releasePanel() {
        extendLeft = 0;
        extendRight = 0;
    }

    // ---- shape and motion ----
    readonly property int r: Theme.islandRadius
    // Extra width on a free end while a dropdown hangs past it; the content stays put. It moves on
    // the islands' one clock (Theme.islandMs), which the dropdown's growth shares, so the island
    // and its panel open as one shape.
    property int extendLeft: 0
    property int extendRight: 0
    Behavior on extendLeft {
        NumberAnimation {
            duration: Theme.islandMs
            easing.type: Theme.islandEaseSlide
        }
    }
    Behavior on extendRight {
        NumberAnimation {
            duration: Theme.islandMs
            easing.type: Theme.islandEaseSlide
        }
    }

    implicitWidth: row.implicitWidth + padding * 2 + extendLeft + extendRight
    implicitHeight: Theme.barHeight

    // ---- drawing: the pill with the content, then the four fillets ----
    // The pill is also the content's clip (Quickshell's ClippingRectangle replaced an
    // offscreen layer with a MultiEffect mask), so the island's fill and its contents are one item.
    // The content is clipped to the island's own shape because a lifted button (Lift.qml) grows and
    // casts a shadow, and in a rounded end of the island its inset highlight, concentric with the
    // island's corner, then poked out past the border.
    ClippingRectangle {
        id: pill
        anchors.fill: parent
        radius: root.r
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: root.glueLeft ? 0 : root.r
        bottomRightRadius: root.glueRight ? 0 : root.r
        color: Theme.barBg
        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }

        RowLayout {
            id: row
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: (root.extendLeft - root.extendRight) / 2
            spacing: Theme.gap
        }
    }

    Shape {
        anchors.fill: pill
        preferredRendererType: Shape.CurveRenderer

        // fillet outside the top-left corner, toward the top edge
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.glueLeft ? "transparent" : pill.color
            startX: -root.r
            startY: 0
            PathLine { x: 0; y: 0 }
            PathLine { x: 0; y: root.r }
            PathArc {
                x: -root.r
                y: 0
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
        }

        // fillet outside the top-right corner, toward the top edge
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.glueRight ? "transparent" : pill.color
            startX: pill.width + root.r
            startY: 0
            PathLine { x: pill.width; y: 0 }
            PathLine { x: pill.width; y: root.r }
            PathArc {
                x: pill.width + root.r
                y: 0
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
        }

        // fillet below the bottom-left corner, toward the left screen edge
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.glueLeft ? pill.color : "transparent"
            startX: 0
            startY: pill.height
            PathLine { x: 0; y: pill.height + root.r }
            PathArc {
                x: root.r
                y: pill.height
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine { x: 0; y: pill.height }
        }

        // fillet below the bottom-right corner, toward the right screen edge
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.glueRight ? pill.color : "transparent"
            startX: pill.width
            startY: pill.height
            PathLine { x: pill.width; y: pill.height + root.r }
            PathArc {
                x: pill.width - root.r
                y: pill.height
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine { x: pill.width; y: pill.height }
        }
    }
}
