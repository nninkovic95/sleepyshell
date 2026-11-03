import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// The control centre's tools (or its quick-setting tiles) laid out as the real grid is (sleepybar/widgets/clock/ControlCentre.qml): two
// tiles to a row, in order row by row, so the editor looks like what it edits. The tiles come
// from Settings (toolNames, toolLabels, toolIcons, powerIcon, powerLabel; tileNames, tileLabels, tileIcons), so both share them.
// `kind` "tools" is the tools grid: Power last across the full width, fixed; the "+ Add tool" tile before it; a pencil on every
// tool (edit the label and icon, for a custom tool also what it runs), a bin on the user's own tools, a revert arrow on a built-in
// whose label or icon was changed. `kind` "tiles" is the quick-setting tiles (Wi-Fi ... Night light):
// the same grips and eyes on tiles drawn like the real ones (icon, bold label, a muted second line).
//
// A tile is dragged by its grip (the dotted handle at its left; drag only, there are no
// back and forward arrows): it follows the pointer and the others slide into the
// cells they would have after the drop; the drop stages the order through Settings.stageMoveTo.
// The eye shows or hides it.
// A hidden tile stays in its cell, dimmed, so it can be shown again. A tool whose programs are
// missing (Settings.toolRequires, services/Deps.qml) is dimmed with a warning mark, and the tip says what to install. Power cannot move or
// hide: it is drawn flat and dimmer, with a lock. The tiles are plain Items placed by x and y
// (not a GridLayout) so a tile can follow the pointer while the others glide to their cells.
// dragFrom is the index of the tile being dragged (-1 when none), dragDx and dragDy how far the
// pointer has moved since the press, dragTo the cell it would drop into.
Item {
    id: ed

    // the Settings keys of the order and of the hidden names, the sidebar search in lower case
    // (the tab's `query`) and the word the search finds a tile by besides its label
    property string orderKey: ""
    property string hiddenKey: ""
    property string query: ""
    property string noun: ""
    // "tools" or "tiles"
    property string kind: "tools"
    readonly property bool isTiles: ed.kind === "tiles"
    // the window's tooltip, for the "needs ..." tip of a tool that cannot run here
    property var tooltip: null

    // pencil (edit), "+ Add tool" (add)
    signal editRequested(string name)
    signal addRequested()

    property int dragFrom: -1
    property real dragDx: 0
    property real dragDy: 0
    property int dragTo: -1

    readonly property var names: Settings.stagedOrder(orderKey)
    readonly property int columns: 2
    readonly property real gap: 6
    // as tall as the real grid's rows (icon + 6 px, 12 px of padding), or the real tiles' 52
    readonly property real cellH: ed.isTiles ? 52 : Theme.iconSize + 6 + 12
    readonly property real cellW: (width - gap * (columns - 1)) / columns
    // the "+ Add tool" tile takes the cell after the last tool
    readonly property bool hasAdd: !ed.isTiles
    readonly property int rows: Math.ceil((names.length + (hasAdd ? 1 : 0)) / columns)
    readonly property real gridBottom: rows * (cellH + gap) - gap

    // what a name shows: label, icon, the second line (tiles), why it cannot run ("" when it can), whether it is the user's own tool,
    // whether a built-in carries another label or icon
    function infoOf(n) {
        if (ed.isTiles)
            return { label: Settings.tileLabels[n] ?? n, icon: Settings.tileIcons[n] ?? 0, sub: Settings.tileSubs[n] ?? "",
                needs: n === "profile" && Battery.profilesMissing ? "Needs power-profiles-daemon (not running)" : "", custom: false, overridden: false, value: "" };
        const c = Settings.customTool(n, true);
        const need = c ? ToolRun.needs(c) : Deps.needs(Settings.toolRequires[n] ?? []);
        // an optional tool (Calendar) that cannot run is not in the control centre at all: here it is listed dimmed, with what it needs, and
        // its eye is off
        const gone = !c && Settings.toolOptional[n] === true && need !== "";
        return { label: Settings.toolLabel(n, true) + (gone ? " (needs " + Deps.missing(Settings.toolRequires[n] ?? []).join(", ") + ")" : ""), icon: Settings.toolIcon(n, true), sub: "",
            needs: need, custom: c !== null, overridden: !c && Settings.overridden(n, true), absent: gone,
            value: c ? String(c.value) : "" };
    }

    Layout.fillWidth: true
    implicitHeight: gridBottom + (ed.isTiles ? 0 : gap + cellH)
    Layout.preferredHeight: implicitHeight

    function endDrag() {
        dragFrom = -1;
        dragDx = 0;
        dragDy = 0;
        dragTo = -1;
    }

    // a command tool's first word has to be known to Deps before the tile can say it is missing
    onNamesChanged: if (!ed.isTiles)
        ToolRun.want(Settings.customList(true))

    Repeater {
        model: ed.names

        Item {
            id: tile
            required property string modelData
            required property int index
            readonly property bool shown: Settings.stagedShown(ed.hiddenKey, modelData)
            readonly property var meta: ed.infoOf(modelData)
            readonly property string label: meta.label
            // found by the settings search like a SettingRow
            readonly property string searchText: Settings.norm(label + " " + ed.noun + " " + meta.value)
            readonly property bool searchHit: Settings.searchMatch(searchText, ed.query)
            readonly property int count: ed.names.length
            // what the tool needs and does not have, "" when it can run
            readonly property string needsText: meta.needs
            readonly property bool dragging: ed.dragFrom === index
            // the cell it sits in: its own, or one over while another tile is dragged past it
            readonly property int slot: {
                const from = ed.dragFrom, to = ed.dragTo;
                if (from < 0 || dragging)
                    return index;
                if (from < to && index > from && index <= to)
                    return index - 1;
                if (from > to && index < from && index >= to)
                    return index + 1;
                return index;
            }
            readonly property real homeX: (slot % ed.columns) * (ed.cellW + ed.gap)
            readonly property real homeY: Math.floor(slot / ed.columns) * (ed.cellH + ed.gap)

            width: ed.cellW
            height: ed.cellH
            x: dragging ? Math.max(0, Math.min(ed.width - width, homeX + ed.dragDx)) : homeX
            y: dragging ? Math.max(0, Math.min(ed.gridBottom - height, homeY + ed.dragDy)) : homeY
            opacity: (shown ? 1 : 0.45) * (needsText === "" ? 1 : meta.absent === true ? 0.45 : 0.6) * (searchHit ? 1 : 0.3)

            HoverHandler {
                id: tileHover
                onHoveredChanged: {
                    if (!ed.tooltip || tile.needsText === "") {
                        if (ed.tooltip)
                            ed.tooltip.hide(tile);
                        return;
                    }
                    if (hovered)
                        ed.tooltip.show(tile, tile.needsText, true);
                    else
                        ed.tooltip.hide(tile);
                }
            }

            // the dragged tile follows the pointer, the others glide
            Behavior on x {
                enabled: !tile.dragging
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on y {
                enabled: !tile.dragging
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            // above the other tiles while dragged, so its shadow is not covered
            z: surface.z

            // only the background lifts while dragged; the glyph, label and buttons stay at scale 1
            // and sharp. The holder keeps the lifted surface (z 1) from
            // covering them.
            Item {
                anchors.fill: parent

                Rectangle {
                    id: surface
                    anchors.fill: parent
                    radius: ed.isTiles ? Theme.radiusMd : Theme.radiusSm
                    color: tile.dragging ? Theme.hoverBg : Theme.tileBg

                    Lift {
                        level: tile.dragging ? 1 : 0
                        radius: parent.radius
                    }
                }
            }

            // the grip drags; it is the handle, and the eye sits beside it
            MouseArea {
                id: body
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 30
                hoverEnabled: true
                cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                // the pointer in the editor's coordinates, which hold still while the tile
                // moves under it
                property real pressX: 0
                property real pressY: 0

                function pointer(e) {
                    return mapToItem(ed, e.x, e.y);
                }

                onPressed: e => {
                    const p = pointer(e);
                    pressX = p.x;
                    pressY = p.y;
                    ed.dragDx = 0;
                    ed.dragDy = 0;
                    ed.dragTo = tile.index;
                    ed.dragFrom = tile.index;
                }
                onPositionChanged: e => {
                    if (!pressed)
                        return;
                    const p = pointer(e);
                    ed.dragDx = p.x - pressX;
                    ed.dragDy = p.y - pressY;
                    // the cell under the middle of the tile
                    const cx = tile.x + tile.width / 2, cy = tile.y + tile.height / 2;
                    const col = Math.max(0, Math.min(ed.columns - 1, Math.floor(cx / (ed.cellW + ed.gap))));
                    const row = Math.max(0, Math.min(ed.rows - 1, Math.floor(cy / (ed.cellH + ed.gap))));
                    ed.dragTo = Math.min(tile.count - 1, row * ed.columns + col);
                }
                onReleased: {
                    const to = ed.dragTo;
                    ed.endDrag();
                    Settings.stageMoveTo(ed.orderKey, tile.modelData, to);
                }
                onCanceled: ed.endDrag()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 4
                spacing: 2

                // grip: the drag handle (the MouseArea above covers this slot)
                Glyph {
                    Layout.preferredWidth: 20
                    Layout.rightMargin: 2
                    horizontalAlignment: Text.AlignHCenter
                    cp: 0xF01DD
                    color: body.containsMouse || tile.dragging ? Theme.fg : Theme.fgMuted
                }

                // the real grid's icon size and gap
                Glyph {
                    Layout.rightMargin: ed.isTiles ? 3 : 7
                    cp: tile.meta.icon
                    font.pixelSize: ed.isTiles ? 18 : Theme.iconSize + 6
                    color: tile.shown ? Theme.fg : Theme.fgMuted
                }

                // a tile: bold label over a muted line, as the real tile; a tool: the label alone
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: tile.label
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        font.bold: ed.isTiles
                        color: tile.shown ? Theme.fg : Theme.fgMuted
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: ed.isTiles
                        elide: Text.ElideRight
                        text: tile.needsText !== "" ? tile.needsText : tile.meta.sub
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.fgMuted
                    }
                }

                // a tool that cannot run here (its programs are missing)
                Glyph {
                    visible: tile.needsText !== ""
                    cp: 0xF0026
                    color: Theme.urgentFg
                }

                // a built-in tool shown with another label or icon: back to its own (staged, like the rest)
                BarButton {
                    id: revertBtn
                    objectName: "toolRevert"
                    visible: tile.meta.overridden
                    glyph: 0xF054C
                    hpad: 3
                    glued: false
                    fg: Theme.fgMuted
                    hoverFg: Theme.fg
                    onClicked: Settings.clearToolOverride(tile.modelData)
                    onHoveredChanged: {
                        if (!ed.tooltip)
                            return;
                        if (hovered)
                            ed.tooltip.show(revertBtn, "Back to the original name and icon.", false);
                        else
                            ed.tooltip.hide(revertBtn);
                    }
                }

                // edit: the label and icon, and for the user's own tool what it runs
                BarButton {
                    id: editBtn
                    objectName: "toolEdit"
                    visible: !ed.isTiles
                    glyph: 0xF03EB
                    hpad: 3
                    glued: false
                    fg: Theme.fgMuted
                    hoverFg: Theme.fg
                    onClicked: ed.editRequested(tile.modelData)
                    onHoveredChanged: {
                        if (!ed.tooltip)
                            return;
                        if (hovered)
                            ed.tooltip.show(editBtn, tile.meta.custom ? "Edit this tool" : "Change the name or icon", false);
                        else
                            ed.tooltip.hide(editBtn);
                    }
                }

                // delete: only the user's own tools
                BarButton {
                    id: delBtn
                    objectName: "toolDelete"
                    visible: tile.meta.custom
                    glyph: 0xF01B4
                    hpad: 3
                    glued: false
                    fg: Theme.fgMuted
                    hoverFg: Theme.urgentFg
                    onClicked: Settings.removeCustomTool(tile.modelData)
                    onHoveredChanged: {
                        if (!ed.tooltip)
                            return;
                        if (hovered)
                            ed.tooltip.show(delBtn, "Remove this tool", false);
                        else
                            ed.tooltip.hide(delBtn);
                    }
                }

                // eye: shown in the grid, or crossed out and hidden from it
                BarButton {
                    objectName: "toolEye"
                    glyph: tile.shown ? 0xF06D0 : 0xF06D1
                    hpad: 3
                    glued: false
                    fg: tile.shown ? Theme.primary : Theme.fgMuted
                    hoverFg: Theme.fg
                    // off for an optional tool that is not installed: it is not in the control centre either way
                    enabled: tile.meta.absent !== true
                    opacity: enabled ? 1 : 0.4
                    onClicked: if (enabled)
                        Settings.stageShown(ed.hiddenKey, tile.modelData, !tile.shown)
                }
            }
        }
    }

    // "+ Add tool": the cell after the last tool, outlined like an empty slot
    Item {
        id: addTile
        objectName: "addTool"
        visible: ed.hasAdd
        readonly property int slot: ed.names.length
        readonly property string searchText: Settings.norm("add tool new custom app command link " + ed.noun)
        readonly property bool searchHit: Settings.searchMatch(searchText, ed.query)
        x: (slot % ed.columns) * (ed.cellW + ed.gap)
        y: Math.floor(slot / ed.columns) * (ed.cellH + ed.gap)
        width: ed.cellW
        height: ed.cellH
        opacity: searchHit ? 1 : 0.3

        Behavior on x {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusSm
            color: addArea.containsMouse ? Theme.hoverBg : "transparent"
            border.width: 1
            border.color: Qt.alpha(Theme.fg, addArea.containsMouse ? 0.3 : 0.18)
        }

        Row {
            anchors.centerIn: parent
            spacing: 6 + 3

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                cp: 0xF0415
                font.pixelSize: Theme.iconSize + 6
                color: addArea.containsMouse ? Theme.fg : Theme.fgMuted
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Add tool"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: addArea.containsMouse ? Theme.fg : Theme.fgMuted
            }
        }

        MouseArea {
            id: addArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ed.addRequested()
        }
    }

    // Power: last and across the full width in the real grid, and not an entry of the order, so
    // it is drawn outlined and dimmer, with a lock where the others have buttons
    Item {
        id: power
        visible: !ed.isTiles
        readonly property string label: Settings.powerLabel
        readonly property string searchText: Settings.norm(label + " " + ed.noun)
        readonly property bool searchHit: Settings.searchMatch(searchText, ed.query)

        y: ed.gridBottom + ed.gap
        width: ed.width
        height: ed.cellH
        opacity: 0.6 * (searchHit ? 1 : 0.5)

        // a joke, kept exactly: hovering the locked tile says this; only here, in the editor,
        // not on the real control centre's Power button
        readonly property string joke: "Buy battle-pass to unlock this option xD"

        HoverHandler {
            onHoveredChanged: {
                if (!ed.tooltip)
                    return;
                if (hovered)
                    ed.tooltip.show(power, power.joke, false);
                else
                    ed.tooltip.hide(power);
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusSm
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.14)
        }

        // glyph and label centred, as the real button's
        Row {
            anchors.centerIn: parent
            spacing: 6 + 3

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                cp: Settings.powerIcon
                font.pixelSize: Theme.iconSize + 6
                color: Theme.fgMuted
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: power.label
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: Theme.fgMuted
            }
        }

        Glyph {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            cp: 0xF033E
            color: Theme.fgMuted
        }
    }
}
