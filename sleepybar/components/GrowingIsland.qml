import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.components

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
// The panel item is this island's host for dropdowns of the widgets in it (SideIsland.qml's header).
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
    readonly property Item leftItem: leftSlot.item
    readonly property Item rightItem: rightSlot.item
    property Item middleItem: null
    property Item leftSide: null
    property Item rightSide: null
    property Item peek: null
    property bool peeking: false
    property bool wantsKeyboard: false
    default property alias content: col.data

    function toggle() {
        open = !open;
    }

    // ---- state and motion ----
    // progress runs 0 (island) to 1 (panel) on the islands' one clock; every size below is
    // interpolated from it, so the outline, the mask and the content move together.
    property real progress: open ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: Theme.islandMs
            easing.type: Theme.islandEaseGrow
        }
    }
    // collapsed height, taller while the peek row shows (never while the panel is open)
    readonly property bool showPeek: peeking && !open && peek !== null
    // width of the island's taller clock part; wider while the volume peek shows under the clock
    property real centreW: showPeek ? Math.max(clockBox.width, 220) : clockBox.width
    Behavior on centreW {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }
    property real baseH: showPeek ? startH + peek.implicitHeight + 10 : startH
    Behavior on baseH {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }
    // theme changes fade like the side islands do (SideIsland.qml animates its pill colour)
    property color fill: Theme.barBg
    Behavior on fill {
        ColorAnimation {
            duration: 200
        }
    }

    // ---- geometry ----
    readonly property real startW: header.implicitWidth + 2 * Theme.islandRadius
    // The collapsed island grows to fit a two-line header (clock and date, 5 px above and below it).
    // While stepped (Settings.centreStep) and with side widgets, the clock part reaches at least
    // stepCorner + stepFillet below the sides, so the step has room for its corners and fillets.
    readonly property bool hasSides: leftSlot.visible || rightSlot.visible
    readonly property real stepDepth: Settings.centreStep && hasSides ? Theme.barHeight + Theme.stepCorner + Theme.stepFillet : 0
    readonly property real startH: Math.max(Theme.barHeight, Math.ceil(clockCol.implicitHeight) + 10, stepDepth)
    readonly property real fullW: Math.max(startW, col.implicitWidth + pad * 2)
    // the body starts 4 px under the collapsed header
    readonly property real fullH: startH + 4 + col.implicitHeight + pad
    // Open, the outer columns end higher than the middle one (same width): `middle` is
    // the content column that hangs to the full depth, leftSide and rightSide the columns beside
    // it, all top-aligned in one row at the top of the content. Both sides end where the deeper
    // of the two columns does, not each at its own depth.
    // Without a middle column (none given, or
    // Settings.centreUneven off) the open panel is the plain rectangle.
    readonly property Item middle: Settings.centreUneven ? middleItem : null
    readonly property real sideDepth: Math.max(leftSide ? leftSide.implicitHeight : 0, rightSide ? rightSide.implicitHeight : 0)
    readonly property real leftH: middle ? Math.min(fullH, startH + 4 + sideDepth + pad) : fullH
    readonly property real rightH: leftH

    // ---- surface and input ----
    screen: bar.screen
    visible: true
    color: "transparent"
    anchors.top: true
    anchors.left: true
    margins.top: 0
    margins.left: Math.round((bar.screen.width - implicitWidth) / 2)
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: Math.ceil(fullW) + 2 * Theme.islandRadius
    implicitHeight: Math.ceil(fullH)
    WlrLayershell.namespace: "sleepyshell-popup"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: wantsKeyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    // input only where the island is drawn: the full-width top part and the tall middle part, so
    // the empty corners under a stepped edge stay click-through and do not hold the panel open
    mask: Region {
        item: maskLeft
        regions: [
            Region {
                item: maskMiddle
            },
            Region {
                item: maskRight
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

    Item {
        id: panel
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(root.startW + (root.fullW - root.startW) * root.progress)
        height: Math.round(root.baseH + (root.fullH - root.baseH) * root.progress)

        // ---- host contract (SideIsland.qml's header) ----
        // An island in another window than the bar (hostX: that window's left edge on screen,
        // hostWindow for the focus grab); a dropdown hangs from its collapsed bottom edge (hangY).
        // It cannot widen itself for a dropdown, so one under it floats as a card.
        readonly property string attach: "top"
        readonly property bool glueLeft: false
        readonly property bool glueRight: false
        readonly property real hostX: root.margins.left
        readonly property var hostWindow: root
        readonly property real hangY: root.startH
        readonly property bool canExtend: false
        function straightEdge() {
            const x = mapToItem(null, 0, 0).x + hostX;
            return {
                l: x + Theme.islandRadius,
                r: x + width - Theme.islandRadius
            };
        }

        // hovering anywhere on the island (clock, CPU/memory, audio) opens the panel; leaving it
        // closes the panel after a moment
        HoverHandler {
            id: panelHover
            onHoveredChanged: {
                if (hovered) {
                    leaveTimer.stop();
                    if (!root.open && Settings.hoverOpen)
                        root.open = true;
                } else {
                    leaveTimer.restart();
                }
            }
        }

        // ---- drawing: the outline ----
        // Collapsed it is stepped (Settings.centreStep): the sides with the widgets
        // are as tall as the side islands (barHeight), only the clock part reaches down to fit the
        // date, with small inverted fillets where the two meet. Opening lowers the sides' bottom
        // edges to the ends of their columns (leftH, rightH) and widens the clock part to the
        // middle column, which alone reaches the bottom; once the step is too small for its corners
        // it is the plain hanging rectangle. Outer top fillets toward the screen edge as on every
        // island.
        Item {
            id: outline
            anchors.fill: parent
            readonly property real r: Theme.islandRadius
            // inverted fillet where the tall part meets a side, and the tall part's own bottom
            // corners: the step tokens around the clock, the island radius on the open panel
            // (the inner corner under a side is rounded too)
            readonly property real f: Theme.stepFillet + (Theme.islandRadius - Theme.stepFillet) * root.progress
            readonly property real rc: Theme.stepCorner + (Theme.islandRadius - Theme.stepCorner) * root.progress
            readonly property real w: width
            readonly property real h2: height
            // the sides' bottom edges: bar-high while closed and stepped (flush with the bottom when
            // not stepped), at the end of their columns when open
            readonly property real h1Closed: Settings.centreStep ? Theme.barHeight : height
            readonly property real h1L: h1Closed + ((root.middle ? root.leftH : height) - h1Closed) * root.progress
            readonly property real h1R: h1Closed + ((root.middle ? root.rightH : height) - h1Closed) * root.progress
            readonly property real h1: Math.max(h1L, h1R)
            // the tall part: the clock part collapsed, the middle column (halfway into the 12 px
            // gaps beside it, past the column dividers) open
            readonly property real cx0Closed: header.x + clockBox.x + clockBox.width / 2 - root.centreW / 2
            readonly property real cx0Open: root.middle ? col.x + root.middle.x - 6 : cx0Closed
            readonly property real cx1Open: root.middle ? col.x + root.middle.x + root.middle.width + 6 : cx0Closed + root.centreW
            readonly property real cx0: cx0Closed + (cx0Open - cx0Closed) * root.progress
            readonly property real cx1: cx0Closed + root.centreW + (cx1Open - cx0Closed - root.centreW) * root.progress
            readonly property bool stepped: h2 - h1 >= rc + f && cx0 - f >= r && w - cx1 - f >= r

            Shape {
                anchors.fill: parent
                visible: outline.stepped
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: root.fill
                    startX: -outline.r
                    startY: 0
                    PathLine { x: outline.w + outline.r; y: 0 }
                    PathArc { x: outline.w; y: outline.r; radiusX: outline.r; radiusY: outline.r; direction: PathArc.Counterclockwise }
                    PathLine { x: outline.w; y: outline.h1R - outline.r }
                    PathArc { x: outline.w - outline.r; y: outline.h1R; radiusX: outline.r; radiusY: outline.r; direction: PathArc.Clockwise }
                    PathLine { x: outline.cx1 + outline.f; y: outline.h1R }
                    PathArc { x: outline.cx1; y: outline.h1R + outline.f; radiusX: outline.f; radiusY: outline.f; direction: PathArc.Counterclockwise }
                    PathLine { x: outline.cx1; y: outline.h2 - outline.rc }
                    PathArc { x: outline.cx1 - outline.rc; y: outline.h2; radiusX: outline.rc; radiusY: outline.rc; direction: PathArc.Clockwise }
                    PathLine { x: outline.cx0 + outline.rc; y: outline.h2 }
                    PathArc { x: outline.cx0; y: outline.h2 - outline.rc; radiusX: outline.rc; radiusY: outline.rc; direction: PathArc.Clockwise }
                    PathLine { x: outline.cx0; y: outline.h1L + outline.f }
                    PathArc { x: outline.cx0 - outline.f; y: outline.h1L; radiusX: outline.f; radiusY: outline.f; direction: PathArc.Counterclockwise }
                    PathLine { x: outline.r; y: outline.h1L }
                    PathArc { x: 0; y: outline.h1L - outline.r; radiusX: outline.r; radiusY: outline.r; direction: PathArc.Clockwise }
                    PathLine { x: 0; y: outline.r }
                    PathArc { x: -outline.r; y: 0; radiusX: outline.r; radiusY: outline.r; direction: PathArc.Counterclockwise }
                }
            }

            Highlight {
                anchors.fill: parent
                visible: !outline.stepped
                radius: Theme.islandRadius
                fillet: Theme.islandRadius
                color: root.fill
            }
        }

        // the window mask's three parts (see `mask`); unstepped, the left one covers the panel
        Item {
            id: maskLeft
            width: outline.stepped ? outline.cx0 : panel.width
            height: outline.stepped ? outline.h1L : panel.height
        }
        Item {
            id: maskMiddle
            x: outline.cx0
            width: outline.cx1 - outline.cx0
            height: panel.height
        }
        Item {
            id: maskRight
            x: outline.cx1
            width: outline.stepped ? panel.width - outline.cx1 : 0
            height: outline.h1R
        }

        // ---- content: header, peek row, panel body ----
        // While the island grows the content is clipped to the outline itself, not to the panel's
        // rectangle: a side's bottom edge is still short then, and its column showed below it, outside
        // the island, and the middle seemed to open unevenly. At rest everything is inside the outline,
        // so the mask is only on while the island moves and the resting pixels are drawn directly.
        ShaderEffectSource {
            id: outlineMask
            anchors.fill: outline
            sourceItem: outline
            hideSource: false
            visible: false
        }

        Item {
            anchors.fill: parent
            clip: true
            layer.enabled: root.progress > 0 && root.progress < 1
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: outlineMask
                maskSpreadAtMin: 1
            }

            // the island's top row: left widgets, the clock (title over subtitle), right widgets.
            // The widgets hang from the top edge like the side islands' buttons; the clock is centred
            // in the collapsed height. A click on the clock opens the panel too.
            Row {
                id: header
                x: Math.round((panel.width - width) / 2)
                y: 0
                spacing: Theme.gap

                Loader {
                    id: leftSlot
                    sourceComponent: root.leftComponent
                    visible: item !== null && (item.shown ?? true)
                }

                Item {
                    id: clockBox
                    width: clockCol.implicitWidth + 24
                    height: root.startH - 2

                    Column {
                        id: clockCol
                        anchors.centerIn: parent
                        spacing: -1

                        // the clock, in the lock screen clock's font and weight
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.title
                            font.family: root.titleFont
                            font.pixelSize: root.titleSize
                            color: Theme.fg
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.subtitle !== ""
                            text: root.subtitle
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                            font.letterSpacing: 1
                            font.capitalization: Font.AllUppercase
                            color: Theme.fgMuted
                        }
                    }

                    // the plain arrow: hovering opens the panel already, a hand promised more
                    MouseArea {
                        anchors.fill: parent
                        // open, not toggle: hover has usually opened the panel already, so a click must not close it
                        onClicked: root.open = true
                    }
                }

                Loader {
                    id: rightSlot
                    sourceComponent: root.rightComponent
                    visible: item !== null && (item.shown ?? true)
                }
            }

            // the peek row sits under the title, inside the collapsed island's width
            Item {
                id: peekSlot
                x: outline.cx0 + 8
                y: root.startH - 4
                width: root.centreW - 16
                height: root.peek ? root.peek.implicitHeight : 0
                opacity: root.showPeek ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                    }
                }
            }

            // The body stays where it ends up, centred in the window, and the outline grows over it.
            // It used to sit at the panel's left edge, which moves outward as the panel grows from the
            // centre, so the columns slid across the middle while opening; the side
            // islands' dropdowns keep their content still the same way (IslandDropdown.qml).
            ColumnLayout {
                id: col
                x: Math.round(root.pad - (root.fullW - panel.width) / 2)
                y: root.startH + 4
                width: implicitWidth
                spacing: Theme.gap
                opacity: root.progress
                visible: root.progress > 0
            }
        }
    }
}
