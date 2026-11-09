import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import "CentreGeometry.js" as Geometry

// The centre island, as its own layer surface, which grows into a panel. Collapsed it is
// exactly the island (title pill at the top centre); hovered or clicked it animates to the full
// panel. One surface and one outline for both states, so hover never jumps between windows and the
// open shape is the closed one grown: the closed step (sides bar-high, the clock part deeper)
// becomes the open uneven panel (sides shorter, the middle column deeper), its corners growing
// from Theme.stepFillet / stepCorner to islandRadius on the way.
//   title, subtitle  the clock and the date line under it ("" for one line)
//   leftComponent / rightComponent   widgets beside the title in the island (CPU and memory on the
//                    left, audio on the right; Settings.centreLeft swaps them);
//                    only the title opens the panel
//   middleItem, leftSide, rightSide  the open panel's columns (see "geometry")
//   peek / peeking   an optional row (the volume OSD) the collapsed island reveals under its title
//   wantsKeyboard    true while a text field inside needs keys (layer surfaces get none by default)
//   growing          how much taller the body is still animating towards (the control centre's
//                    list sliding open), so the surface takes its end size in one step
// The island item is this island's host for dropdowns of the widgets in it (SideIsland.qml's header).
PanelWindow {
    id: root

    // ---- API ----
    required property var bar
    property string name: ""
    property bool open: false
    property string title: ""
    property string subtitle: ""
    property string titleFont: Theme.font
    property int titleSize: Theme.fontSize
    property int pad: Theme.panelPad
    property Component leftComponent: null
    property Component rightComponent: null
    readonly property Item leftItem: header.leftItem
    readonly property Item rightItem: header.rightItem
    property Item middleItem: null
    property Item leftSide: null
    property Item rightSide: null
    property Item peek: null
    property bool peeking: false
    property bool wantsKeyboard: false
    property real growing: 0
    default property alias content: col.data

    // ---- state and motion ----
    // progress runs 0 (island) to 1 (panel) on the islands' one clock; the panel body fades on it
    property real progress: open ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: Theme.islandMs
            easing.type: Theme.islandEaseGrow
        }
    }
    // The volume peek row, only while closed and with no card open (a card needs the same room beside the clock; a peek
    // still within its time shows once the card closes), widens the clock part to peekW and deepens it under the
    // clock. The outline's morph animates the change (IslandMorph), so these are plain targets.
    readonly property bool showPeek: peeking && !open && card === null && peek !== null
    readonly property real peekW: Math.max(header.clockW, 220)
    readonly property real centreW: aim.peek ? peekW : header.clockW
    readonly property real baseH: aim.peek ? startH + peek.implicitHeight + 10 : startH
    // theme changes fade like the side islands do (SideIsland.qml animates its pill colour)
    property color fill: Theme.barBg
    Behavior on fill {
        ColorAnimation {
            duration: 200
        }
    }

    // ---- geometry: the size rules (CentreGeometry.js), from what the content measures ----
    // `middle` is the body column that hangs to the full depth open (none with Settings.centreUneven off); leftSide and
    // rightSide are the columns beside it
    readonly property Item middle: Settings.centreUneven ? middleItem : null
    readonly property real sideDepth: Math.max(leftSide ? leftSide.implicitHeight : 0, rightSide ? rightSide.implicitHeight : 0)
    readonly property var size: Geometry.sizes({
        headerW: header.implicitWidth, clockH: header.clockH, bodyW: col.implicitWidth, bodyH: col.implicitHeight,
        sideDepth: sideDepth, uneven: middle !== null, stepped: Settings.centreStep && (header.leftShown || header.rightShown),
        pad: pad, barH: Theme.barHeight, radius: Theme.islandRadius, stepFillet: Theme.stepFillet, stepCorner: Theme.stepCorner
    })
    readonly property real startH: size.startH
    readonly property var sky: Geometry.skylines(size, {
        headerW: header.implicitWidth, clockX: header.clockX, clockW: header.clockW, centreW: centreW, baseH: baseH,
        left: header.leftShown, right: header.rightShown, step: Settings.centreStep,
        middle: middle ? { x: middle.x, width: middle.width } : null,
        card: aim.card ? { side: aim.card.side, width: aim.card.width, height: aim.card.drop.fullH } : null,
        pad: pad, barH: Theme.barHeight, radius: Theme.islandRadius, stepFillet: Theme.stepFillet, stepCorner: Theme.stepCorner
    })
    // a slot's card, one deeper part of the outline under its slot: { side, width, drop } (drop: its IslandDropdown),
    // set through the host contract (fitPanel, releasePanel)
    property var card: null
    onCardChanged: restartMorph()

    // ---- the outline's one morph (IslandMorph.qml) ----
    // A new target (open or closed, the peek or a card while closed) starts it from the shape drawn right now, so the
    // peek ending as the island opens cannot pull the outline in. `aim`, the state the outline heads for, is switched
    // only after that start is taken and in one assignment, so it never depends on which binding updates first.
    property var aim: ({ open: false, peek: false, card: null })
    IslandMorph {
        id: morph
        target: root.aim.open ? root.sky.open : root.sky.closed
        duration: Theme.islandMs
        easing: Theme.islandEaseGrow
    }
    function restartMorph() {
        morph.start(outline.current);
        aim = { open: open, peek: showPeek, card: card };
    }
    onShowPeekChanged: restartMorph()

    // ---- surface height ----
    // The layer surface only ever grows, and in steps. The outline is drawn at the animated height
    // inside a surface that is already big enough; the space below it is transparent and
    // outside the input mask.
    //   - Never per frame: every resize is a round trip to the compositor, and one per frame of a body
    //     animating its height made the open panel shake. The surface takes the end size at once (fullH
    //     plus what `growing` says is still to come).
    //   - Never smaller: while the surface shrank after a fold, a closed Wi-Fi list left a grey box under
    //     the panel and the dropdowns jittered (seen on Hyprland 0.57; likely the area a shrinking layer
    //     surface gives up is not repainted at once). Keeping the largest size needed this session
    //     removed both.
    // (a card can reach deeper than the open panel)
    readonly property real wantH: Math.ceil(Math.max(size.fullH + Math.max(0, growing), sky.closed.cols[0].d, sky.closed.cols[2].d))
    property real surfaceH: wantH
    onWantHChanged: {
        if (wantH > surfaceH)
            surfaceH = wantH;
    }

    // ---- surface and input ----
    screen: bar.screen
    visible: true
    color: "transparent"
    anchors.top: true
    anchors.left: true
    margins.top: 0
    margins.left: Math.round((bar.screen.width - implicitWidth) / 2)
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: size.surfaceW
    implicitHeight: surfaceH
    WlrLayershell.namespace: "sleepyshell-popup"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: wantsKeyboard || (card !== null && card.drop.wantsKeyboard) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    // input only where the island is drawn, the outline's three columns (rounded outward to whole pixels), so the
    // empty corners under a stepped edge stay click-through and do not hold the panel open
    mask: Region {
        regions: [
            Region {
                x: Math.floor(outline.maskRects[0].x)
                width: Math.ceil(outline.maskRects[0].x + outline.maskRects[0].width) - x
                height: Math.ceil(outline.maskRects[0].height)
            },
            Region {
                x: Math.floor(outline.maskRects[1].x)
                width: Math.ceil(outline.maskRects[1].x + outline.maskRects[1].width) - x
                height: Math.ceil(outline.maskRects[1].height)
            },
            Region {
                x: Math.floor(outline.maskRects[2].x)
                width: Math.ceil(outline.maskRects[2].x + outline.maskRects[2].width) - x
                height: Math.ceil(outline.maskRects[2].height)
            }
        ]
    }

    // ---- open and close ----
    function adoptPeek() {
        if (peek) {
            peek.parent = peekSlot;
            peek.width = Qt.binding(() => peekSlot.width);
        }
    }
    onPeekChanged: adoptPeek()

    Component.onCompleted: {
        if (name !== "")
            Popouts.register(name, root);
        adoptPeek();
    }
    Component.onDestruction: {
        if (name !== "")
            Popouts.unregister(name, root);
    }

    // A click outside the panel or the bar clears the grab and closes the panel; the grab is
    // armed a moment after opening (it needs the state settled).
    HyprlandFocusGrab {
        id: grab
        windows: [root, root.bar]
        onCleared: root.open = false
    }

    Timer {
        id: armGrab
        interval: 80
        onTriggered: grab.active = root.open
    }

    onOpenChanged: {
        restartMorph();
        if (open) {
            Popouts.opened(root);
            armGrab.restart();
        } else {
            grab.active = false;
            Popouts.closed(root);
        }
    }

    // Hover: entering the island opens the panel, leaving the panel closes it after a moment.
    // Not while a text field has the keyboard (a half-typed password would be lost); the panel
    // closes once typing ends with the pointer still outside.
    Timer {
        id: leaveTimer
        interval: Settings.hoverCloseMs
        onTriggered: {
            // with hover opening off (settings) the panel was opened by a click and stays until
            // a click outside clears the focus grab
            if (!panelHover.hovered && !root.wantsKeyboard && Settings.hoverOpen)
                root.open = false;
        }
    }
    onWantsKeyboardChanged: {
        if (!wantsKeyboard && !panelHover.hovered)
            leaveTimer.restart();
    }

    // The whole surface: the outline and the content are placed in its coordinates (see the skylines above).
    Item {
        id: island
        anchors.fill: parent

        // ---- host contract (SideIsland.qml's header) ----
        // An island in another window than the bar (hostX: that window's left edge on screen, hostWindow for the
        // focus grab). It draws a slot's card itself, as one deeper part of its outline under that slot (drawsPanel,
        // in dropLayer, inside the fill), hanging from that side's bottom edge (hangY).
        readonly property string attach: "top"
        readonly property real hostX: root.margins.left
        readonly property var hostWindow: root
        readonly property real hangY: root.sky.cardY
        readonly property bool canExtend: true
        readonly property bool drawsPanel: true
        readonly property Item dropLayer: dropLayerItem
        readonly property bool needsAnchor: true
        // the card takes the side of the slot it sits under; its place comes back on screen
        function fitPanel(panelX, panelW, drop) {
            root.card = { side: panelX + panelW / 2 < hostX + root.sky.clockMid ? "left" : "right", width: panelW, drop: drop };
            return { edgeL: hostX + root.sky.cardX, edgeR: hostX + root.sky.cardX + panelW };
        }
        function releasePanel(drop) {
            if (root.card && root.card.drop === drop)
                root.card = null;
        }

        // hovering anywhere on the island (clock, CPU/memory, audio) opens the panel; leaving it
        // closes the panel after a moment. Not while a card is open: the pointer on the card is for the card (a
        // click on the clock still opens the panel).
        HoverHandler {
            id: panelHover
            onHoveredChanged: {
                if (hovered) {
                    leaveTimer.stop();
                    if (!root.open && Settings.hoverOpen && root.card === null)
                        root.open = true;
                } else {
                    leaveTimer.restart();
                }
            }
        }

        // ---- drawing: the outline ----
        // One path in every state (IslandShape.qml). Closed it is stepped (Settings.centreStep): the sides with the
        // widgets are as tall as the side islands (barHeight), only the clock part reaches down to fit the date, with
        // small inverted fillets where they meet. Opening morphs the closed skyline into the open one: the sides'
        // bottom edges drop to the ends of their columns (the side depth), the clock part widens to the middle column,
        // which alone reaches the bottom, and the corners grow from Theme.stepFillet / stepCorner to islandRadius.
        // Outer top fillets toward the screen edge as on every island.
        IslandShape {
            id: outline
            anchors.fill: parent
            from: morph.from
            to: morph.target
            t: morph.t
            radius: Theme.islandRadius
            fillItem: contentFill
        }

        // ---- content: header, peek row, panel body ----
        // The content is the outline's fill: it is drawn only through the path, never on its own (hideSource), so
        // nothing it draws can show outside the island, in motion or at rest (a short side's column while the island
        // grows, a lifted tile's shadow at the edge). It still takes hover and clicks where it is.
        ShaderEffectSource {
            id: contentFill
            anchors.fill: content
            sourceItem: content
            hideSource: true
            visible: false
        }

        Item {
            id: content
            anchors.fill: parent

            // the island's colour, as the fill's backdrop
            Rectangle {
                anchors.fill: parent
                color: root.fill
            }

            // the island's top row (CentreHeader.qml); a click on the clock opens the panel too
            CentreHeader {
                id: header
                x: root.size.headerX
                y: 0
                leftComponent: root.leftComponent
                rightComponent: root.rightComponent
                title: root.title
                subtitle: root.subtitle
                titleFont: root.titleFont
                titleSize: root.titleSize
                closedH: root.startH
                onClockClicked: root.open = true
            }

            // the peek row sits under the title, inside the collapsed island's width
            Item {
                id: peekSlot
                x: root.sky.clockMid - root.peekW / 2 + 8
                y: root.startH - 4
                width: root.peekW - 16
                height: root.peek ? root.peek.implicitHeight : 0
                opacity: root.showPeek ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                    }
                }
            }

            // The body stays where it ends up, centred in the window, and the outline grows over it (the side
            // islands' dropdowns keep their content still the same way, IslandDropdown.qml).
            ColumnLayout {
                id: col
                x: root.size.colX
                y: root.startH + 4
                width: implicitWidth
                spacing: Theme.gap
                opacity: root.progress
                visible: root.progress > 0
            }

            // a slot's card (IslandDropdown places its panel here, in this surface's coordinates)
            Item {
                id: dropLayerItem
                anchors.fill: parent
            }
        }
    }
}
