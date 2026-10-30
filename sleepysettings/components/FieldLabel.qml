import QtQuick
import QtQuick.Layouts
import qs

// The label column of a SettingRow, fixed width so every tab's controls start at the same x.
// With `info` set (and a Tooltip to show it in) a "!" badge follows the text and explains the
// setting on hover. `marked` (an unapplied change on the row) draws a short accent bar in the
// card's margin left of the label.
Item {
    id: fl
    property string text: ""
    property string info: ""
    property bool warn: false
    property bool marked: false
    property var tooltip: null
    Layout.preferredWidth: 180
    implicitWidth: 180
    implicitHeight: Math.max(label.implicitHeight, 16)
    // the room this label wants: its text and the "!" badge (the row sizes the column from it)
    readonly property real natural: Math.ceil(label.implicitWidth) + (info !== "" && tooltip !== null ? 22 : 0)

    Rectangle {
        x: -8
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: 16
        radius: width / 2
        color: Theme.primary
        opacity: fl.marked ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }
    }

    Text {
        id: label
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, fl.width - (badge.visible ? 22 : 0))
        // one line, always: the label column is sized for the longest label
        // (TabPage.labelCol, PairRow); only past the cap is a label cut, and then the full text
        // shows in the tooltip on hover
        elide: Text.ElideRight
        text: fl.text
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fg

        HoverHandler {
            enabled: label.truncated && fl.tooltip !== null
            onHoveredChanged: {
                if (hovered)
                    fl.tooltip.show(label, fl.text, false);
                else
                    fl.tooltip.hide(label);
            }
        }
    }

    InfoTip {
        id: badge
        visible: fl.info !== "" && fl.tooltip !== null
        anchors.left: label.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        tooltip: fl.tooltip
        text: fl.info
        warn: fl.warn
    }
}
