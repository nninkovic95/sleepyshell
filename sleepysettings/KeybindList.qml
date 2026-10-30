import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// A scrolling list of keybinds ({combo, keys, action, flags, note, custom, index} from Keybinds): the key
// chips, the action, and a muted line under it ("added here" in the accent for a bind of sleepybinds.lua). A
// bind added here gets a remove button. Used by the Keybinds tab twice: the
// binds added here, and the read-only binds.lua ones. The list scrolls inside the height it is given.
ListView {
    id: list
    // a model entry with `header: true` ({header, group, count, open}) is a group header: a click asks for it to be folded or unfolded
    signal groupToggled(string group)
    // the window's Tooltip: a bind that came from a file says which on hover, and "Open" jumps to it
    property var tooltip: null
    clip: true
    spacing: 2
    boundsBehavior: Flickable.StopAtBounds

    delegate: Rectangle {
        id: row
        required property var modelData
        readonly property bool isHeader: modelData.header === true
        width: list.width
        height: isHeader ? 28 : Math.max(30, info.implicitHeight + 8)
        radius: Theme.radiusSm
        color: rowHover.hovered ? Theme.hoverBg : "transparent"

        HoverHandler {
            id: rowHover
            onHoveredChanged: {
                if (!list.tooltip || row.isHeader || !row.modelData.file)
                    return;
                if (hovered)
                    list.tooltip.show(row, Settings.tilde(row.modelData.file) + (row.modelData.line ? ":" + row.modelData.line : ""), false);
                else
                    list.tooltip.hide(row);
            }
        }

        // a group header: chevron, the group's name and how many binds it holds
        Row {
            visible: row.isHeader
            anchors.verticalCenter: parent.verticalCenter
            x: 4
            spacing: 8

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                cp: 0xF0142
                rotation: row.modelData.open ? 90 : 0
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: row.isHeader ? row.modelData.group : ""
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                font.weight: Font.Medium
                color: Theme.fg
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: row.isHeader ? "(" + row.modelData.count + ")" : ""
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
                color: Theme.fgMuted
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: row.isHeader
            cursorShape: Qt.PointingHandCursor
            onClicked: list.groupToggled(row.modelData.group)
        }

        // key chips
        Row {
            id: chips
            visible: !row.isHeader
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 180
            spacing: 3

            Repeater {
                model: row.isHeader ? [] : row.modelData.keys

                Rectangle {
                    required property string modelData
                    implicitWidth: chipText.implicitWidth + 10
                    implicitHeight: 20
                    radius: Theme.radiusXs
                    color: Theme.trackBg

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: parent.modelData
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.fg
                    }
                }
            }
        }

        ColumnLayout {
            id: info
            anchors.left: chips.right
            anchors.leftMargin: 10
            anchors.right: openBtn.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            visible: !row.isHeader
            spacing: 0

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: row.isHeader ? "" : row.modelData.action
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                color: Theme.fg
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                elide: Text.ElideRight
                text: row.isHeader ? "" : [row.modelData.custom ? (Keybinds.dirty ? "added here, not applied" : "added here") : ""].concat(row.modelData.flags).concat([row.modelData.note]).filter(x => x !== "").join(" · ")
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
                color: !row.isHeader && row.modelData.custom ? Theme.primary : Theme.fgMuted
            }
        }

        // jump to the file the bind is in (shown while the pointer is on the row)
        BarButton {
            id: openBtn
            objectName: "bindOpen"
            anchors.right: del.left
            anchors.verticalCenter: parent.verticalCenter
            visible: !row.isHeader && !!row.modelData.file
            width: visible ? implicitWidth : 0
            text: "Open"
            glyph: 0xF11E7
            glyphFirst: true
            glued: false
            hpad: 6
            // its room is always kept (the text would jump when the pointer comes), the button itself shows on hover
            enabled: rowHover.hovered && Deps.has(Keybinds.editorProgram)
            opacity: rowHover.hovered ? (Deps.has(Keybinds.editorProgram) ? 1 : 0.4) : 0
            onClicked: if (enabled) Keybinds.openFile(row.modelData.file)
        }

        BarButton {
            id: del
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !row.isHeader && row.modelData.custom
            width: visible ? implicitWidth : 0
            glyph: 0xF0156
            hpad: 4
            glued: false
            onClicked: Keybinds.remove(row.modelData.index)
        }
    }
}
