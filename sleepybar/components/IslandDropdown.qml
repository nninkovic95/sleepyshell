import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.components

// Dropdown under a bar item. It hangs from the island the way the islands hang from the screen edge:
// square top flush with the island's bottom edge, inverted fillets outside the top corners where the
// island continues above them, rounded bottom. Closed by a click outside, one open at a time. Children
// go into a ColumnLayout.
//
// One shape with its island: the panel is drawn in the bar's own layer surface (Sleepybar.qml,
// `dropLayer`), the surface the side islands are drawn in, not in a surface of its own. Two surfaces
// meant two fills and two blurs meeting at a seam, and with a translucent fill whatever lay behind each
// (wallpaper above, a window below) showed as a line along the join. The bar grows its surface down
// while a dropdown is shown and takes input on the panel (Sleepybar.qml, "dropdowns"); this item only
// holds the state and the geometry and is never drawn itself.
//
// Styled like the centre island's control centre (GrowingIsland.qml): the same fill, the same padding,
// and it grows down from the island on the islands' one clock instead of appearing at once. The island it
// hangs from is found once at open and asked through the island host contract (SideIsland.qml's header);
// the island widens itself, the dropdown follows its sides. Under the centre island (which cannot widen)
// the panel floats a few pixels below it as a rounded card, drawn in the bar's surface as well.
//   hover: true    a hover panel: the anchor opens it and closes it after leaving both; no focus grab
//   wantsKeyboard  true while a text field inside needs keys (the bar's surface asks for them then)
Item {
    id: root

    // ---- API ----
    required property Item anchorItem
    required property var bar
    property int pad: Theme.panelPad
    property string name: ""
    property bool open: false
    property bool hover: false
    property bool wantsKeyboard: false
    // Keep the width constant while open: the panel is placed from its width at open.
    property int fixedWidth: 0
    default property alias content: col.data
    readonly property bool hovered: panelHover.hovered

    function toggle() {
        open = !open;
    }

    // the item itself takes no room where it is declared (inside a widget); `panel` is what is drawn
    visible: false
    width: 0
    height: 0

    // ---- motion ----
    // The panel grows and the content fades in, on the same duration and curve as the island's own
    // extension (SideIsland.qml), so the two move as one shape.
    property real progress: open ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: Theme.islandMs
            easing.type: Theme.islandEaseSlide
        }
    }
    // drawn while open and while closing; the bar keeps its surface tall enough and takes input on the
    // panel while this is true
    readonly property bool shown: open || progress > 0

    // ---- geometry, taken at open and held until close ----
    // A live binding missed the island moving (mapToItem is not a tracked dependency, and the right
    // island grows leftwards when a tray icon or a digit appears) and would move the panel while open.
    property var island: null          // the island host the anchor sits in, null when none
    property var hostWindow: null      // its window when that is not the bar (the centre island)
    property real hangY: Theme.barHeight
    property real anchorX: 0
    property real panelX: 0
    // Under an island that does not extend (the centre island, or any island with dropdownFit
    // "float") the panel floats a few pixels below it as a rounded card.
    readonly property bool floating: island !== null && !island.canExtend
    // The panel's sides follow the island's extension: it grows out of the island's straight bottom edge and shrinks back
    // into it on the island's own clock, so no part of it sticks out past a narrowing island.
    // edgeL / edgeR: where a side sits flush with the un-extended island; a panel that already fits
    // inside them keeps its width.
    property bool fitted: false
    property real edgeL: 0
    property real edgeR: 0
    readonly property real sideL: fitted ? Math.max(panelX, edgeL - island.extendLeft) : panelX
    readonly property real sideR: fitted ? Math.min(panelX + panelW, edgeR + island.extendRight) : panelX + panelW
    readonly property int fillet: Theme.islandRadius
    readonly property int panelW: (fixedWidth > 0 ? fixedWidth : col.implicitWidth) + pad * 2
    // where the panel's top sits in the bar's surface, and its full height (the bar sizes its surface
    // from these, not from the animated height, so it resizes once per open and once per close)
    readonly property real panelTop: hangY + (floating ? 6 : 0)
    readonly property real fullH: col.implicitHeight + pad * 2

    // the first ancestor that is an island host (has `attach`)
    function findIsland() {
        let i = anchorItem;
        while (i && i.attach === undefined)
            i = i.parent;
        return i ?? null;
    }

    // Centred under the anchor, then the island is asked to widen over it. A floating panel is
    // instead kept within the island's straight edge when it fits there. Positions are screen
    // coordinates, which are also the bar surface's: it spans the screen from its top-left corner.
    function placeUnderAnchor() {
        // bar is still unbound for a moment while a Loader creates the widget (Sleepyright.qml); a
        // dropdown opened in that moment (hover during a reload) is placed on the next event loop pass
        if (!bar) {
            Qt.callLater(placeUnderAnchor);
            return;
        }
        const i = findIsland();
        island = i;
        hostWindow = i ? i.hostWindow : null;
        hangY = i ? i.hangY : Theme.barHeight;
        anchorX = anchorItem.mapToItem(null, anchorItem.width / 2, 0).x + (i ? i.hostX : 0);

        const r = fillet;
        const sw = bar.screen.width;
        let x = anchorX - panelW / 2;
        if (i && !i.canExtend) {
            const e = i.straightEdge();
            if (panelW + 2 * r <= e.r - e.l)
                x = Math.max(e.l + r, Math.min(x, e.r - r - panelW));
        }
        panelX = Math.round(Math.max(8 + r, Math.min(x, sw - panelW - 8 - r)));

        fitted = i !== null && i.canExtend;
        if (fitted) {
            const fit = i.fitPanel(panelX, panelW);
            edgeL = fit.edgeL;
            edgeR = fit.edgeR;
        }
    }

    function releaseIsland() {
        if (fitted)
            island.releasePanel();
    }

    // ---- registration with the bar and Popouts ----
    // the bar's input region for the panel (Sleepybar.qml adds it to its mask while shown)
    readonly property Region region: Region {
        item: panel
    }
    onShownChanged: {
        if (!bar)
            return;
        if (shown)
            bar.dropShown(root);
        else
            bar.dropHidden(root);
    }
    Component.onCompleted: {
        if (name !== "")
            Popouts.register(name, root);
    }
    Component.onDestruction: {
        if (name !== "")
            Popouts.unregister(name, root);
        if (bar)
            bar.dropHidden(root);
    }

    // ---- open and close ----
    // The grab can only be armed once the panel is up, so arm it a moment after opening; a click
    // outside the bar (and the centre island, for a panel under it) clears it and closes the dropdown.
    // Hover panels skip it.
    HyprlandFocusGrab {
        id: grab
        windows: root.bar ? (root.hostWindow ? [root.bar, root.hostWindow] : [root.bar]) : []
        onCleared: root.open = false
    }

    Timer {
        id: armGrab
        interval: 80
        onTriggered: grab.active = root.open && !root.hover
    }

    onOpenChanged: {
        if (open) {
            // close the previous dropdown first: its releaseIsland() would otherwise wipe the
            // extension this one is about to set on the same island (review 3, F9)
            Popouts.opened(root);
            placeUnderAnchor();
            armGrab.restart();
        } else {
            grab.active = false;
            Popouts.closed(root);
            releaseIsland();
        }
    }

    // ---- drawing and content ----
    // the island's fill; theme changes fade like the islands do
    property color fill: Theme.barBg
    Behavior on fill {
        ColorAnimation {
            duration: 200
        }
    }

    // The panel lives in the bar's surface (`dropLayer`), positioned in its coordinates. It is a
    // property object, not a child: a child would be drawn where the dropdown is declared, inside the
    // widget and clipped by the island.
    readonly property Highlight panel: Highlight {
        parent: root.bar ? root.bar.dropLayer : null
        visible: root.shown
        x: root.sideL
        y: root.panelTop
        width: root.sideR - root.sideL
        height: Math.round(root.fullH * root.progress)
        radius: root.fillet
        // the fillets shrink with the panel, so none is left hanging once the panel is gone
        fillet: Math.min(root.fillet, height)
        glued: !root.floating
        color: root.fill

        HoverHandler {
            id: panelHover
        }

        // clips the content while the panel is still growing (the Highlight itself cannot clip:
        // its fillets are drawn outside its bounds)
        Item {
            anchors.fill: parent
            clip: true

            ColumnLayout {
                id: col
                x: root.pad - (root.sideL - root.panelX)   // the content stays put while the sides move
                y: root.pad
                width: root.fixedWidth > 0 ? root.fixedWidth : implicitWidth
                spacing: Theme.gap
                opacity: root.progress
            }
        }
    }
}
