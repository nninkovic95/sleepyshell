import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// An orderable list of rows for a Section: grip, name, shown. Drag only (the
// grip is the handle). It is a Repeater, so
// its rows sit in the Section's card like any SettingRow (hairlines between them). Used by the
// Right island tab (rightOrder, rightHidden); the Centre island tab's tools are a grid
// (ToolsGridEditor). The orders and the stage functions are Settings' (by key).
//
// The grip drags a row; the rows between its old and new slot make room by sliding one pitch
// (Translate, so the layout stays put), and the drop stages the order through Settings.
// dragFrom is the index of the row being dragged (-1 when none), dragDy how far the pointer
// has moved since the press, dragTo the slot it would drop into.
Repeater {
    id: list

    // the Settings keys of the order and of the hidden names, the names' labels, the sidebar search
    // in lower case (the tab's `query`) and the word the search finds a row by besides its label
    property string orderKey: ""
    property string hiddenKey: ""
    property var labels: ({})
    property string query: ""
    property string noun: ""

    property int dragFrom: -1
    property real dragDy: 0
    property int dragTo: -1

    model: Settings.stagedOrder(orderKey)

    Item {
        id: wrow
        required property string modelData
        required property int index
        readonly property bool shown: Settings.stagedShown(list.hiddenKey, modelData)
        readonly property string label: list.labels[modelData] ?? modelData
        // found by the settings search like a SettingRow
        readonly property string searchText: Settings.norm(label + " " + list.noun)
        readonly property bool searchHit: Settings.searchMatch(searchText, list.query)
        readonly property int count: list.count
        readonly property bool dragging: list.dragFrom === index
        // from one row's top to the next: the row and the gap the Section puts between rows
        readonly property real pitch: height + (parent?.spacing ?? 0)
        // how far the row is shifted from its place in the layout
        readonly property real shift: {
            const from = list.dragFrom, to = list.dragTo;
            if (from < 0)
                return 0;
            if (dragging)
                return Math.max(-from * pitch, Math.min((count - 1 - from) * pitch, list.dragDy));
            if (from < to && index > from && index <= to)
                return -pitch;
            if (from > to && index < from && index >= to)
                return pitch;
            return 0;
        }
        Layout.fillWidth: true
        Layout.preferredHeight: 30
        opacity: searchHit ? 1 : 0.3

        transform: Translate {
            y: wrow.shift
            // the dragged row follows the pointer, the others glide
            Behavior on y {
                enabled: !wrow.dragging
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }

        // above the other rows while dragged, so its shadow is not covered
        z: surface.z

        // the dragged row's shadow lifts with an empty surface; the grip, label and buttons stay at
        // scale 1 and sharp. The holder keeps the lifted surface (z 1) from
        // covering them.
        Item {
            anchors.fill: parent

            Rectangle {
                id: surface
                anchors.fill: parent
                radius: Theme.radiusSm
                color: "transparent"

                Lift {
                    level: wrow.dragging ? 1 : 0
                    radius: parent.radius
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 6

            // grip: press and drag to move the row
            Item {
                Layout.preferredWidth: grip.width
                Layout.fillHeight: true

                Glyph {
                    id: grip
                    anchors.centerIn: parent
                    cp: 0xF01DD
                    color: gripArea.containsMouse || wrow.dragging ? Theme.fg : Theme.fgMuted
                }

                MouseArea {
                    id: gripArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: wrow.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    // the pointer in the Section's coordinates, which hold still while
                    // the row moves under it
                    property real pressY: 0

                    function pointerY(e) {
                        return mapToItem(wrow.parent, e.x, e.y).y;
                    }

                    onPressed: e => {
                        pressY = pointerY(e);
                        list.dragDy = 0;
                        list.dragTo = wrow.index;
                        list.dragFrom = wrow.index;
                    }
                    onPositionChanged: e => {
                        if (!pressed)
                            return;
                        list.dragDy = pointerY(e) - pressY;
                        list.dragTo = Math.max(0, Math.min(wrow.count - 1, wrow.index + Math.round(list.dragDy / wrow.pitch)));
                    }
                    onReleased: {
                        const to = list.dragTo;
                        list.dragFrom = -1;
                        list.dragDy = 0;
                        list.dragTo = -1;
                        Settings.stageMoveTo(list.orderKey, wrow.modelData, to);
                    }
                    onCanceled: {
                        list.dragFrom = -1;
                        list.dragDy = 0;
                        list.dragTo = -1;
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: wrow.label
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: wrow.shown ? Theme.fg : Theme.fgMuted
            }

            Toggle {
                checked: wrow.shown
                onClicked: Settings.stageShown(list.hiddenKey, wrow.modelData, !wrow.shown)
            }
        }
    }
}
