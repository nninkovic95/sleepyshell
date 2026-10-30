import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// One row of a device or network list. Left click: primary action, right click: secondary.
Item {
    id: root
    property int icon: 0
    property string title: ""
    property string sub: ""
    property bool active: false
    property bool busy: false
    property int trailing: 0      // glyph shown at the right when not busy
    signal clicked()
    signal secondary()

    Layout.fillWidth: true
    implicitHeight: 36
    property real radius: Theme.radiusMd
    // above its neighbours while lifted, so the shadow is not covered
    z: surface.z

    // Only the background lifts (scaling the whole row left the glyphs and
    // text blurry on hover); the row's content stays at scale 1. The holder keeps the lifted
    // surface (z 1) below the row's MouseArea, and the Lift reads the pointer from that MouseArea:
    // without both, the surface rose over it, took the hover, dropped, and the row blinked.
    Item {
        anchors.fill: parent

        Rectangle {
            id: surface
            anchors.fill: parent
            radius: root.radius
            color: m.containsMouse ? Theme.hoverBg : "transparent"

            // edge tilt like the tools grid, gentle,
            // since the row is short
            Lift {
                radius: root.radius
                pointer: m
                level: m.containsMouse ? 1 : 0
                tilt: true
                tiltMax: 5
                tiltMinHeight: 30
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        Glyph {
            cp: root.icon
            Layout.preferredWidth: Theme.iconCell
            Layout.alignment: Qt.AlignVCenter
            color: root.active ? Theme.primary : Theme.fg
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.title
                // network and device names are set by other people's hardware: never markup (review 4)
                textFormat: Text.PlainText
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: root.active
                color: Theme.fg
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                visible: root.sub !== ""
                text: root.sub
                textFormat: Text.PlainText
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
                color: Theme.fgMuted
            }
        }

        Glyph {
            visible: root.busy || root.trailing !== 0
            cp: root.busy ? 0xF0772 : root.trailing
            Layout.preferredWidth: Theme.iconCell
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: 14
            color: Theme.fgMuted
        }
    }

    MouseArea {
        id: m
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => e.button === Qt.RightButton ? root.secondary() : root.clicked()
    }
}
