import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// The header of a collapsible group of settings (the Display tab's "Advanced options"; the Advanced
// sections of the other tabs reuse it): a chevron and the title, nothing else. The one extra element
// allowed (the fold holds only options, no text) is the
// accent count pill, and only while a setting inside has an unapplied change (`pending` > 0), so a closed
// group cannot hide a change. Click or press toggles `open`, which the parent sets.
Rectangle {
    id: ch
    property string title: ""
    property bool open: false
    // how many settings inside have an unapplied change; 0 hides the pill
    property int pending: 0
    signal toggled()
    Layout.fillWidth: true
    implicitHeight: 30
    radius: Theme.radiusSm
    color: mouse.containsMouse ? Theme.hoverBg : "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 6
        spacing: 8

        Glyph {
            cp: 0xF0142
            rotation: ch.open ? 90 : 0
            Behavior on rotation {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
        }

        Text {
            text: ch.title
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.weight: Font.Medium
            color: Theme.fg
        }

        CountPill {
            objectName: "collapsePill"
            visible: ch.pending > 0
            count: ch.pending
        }

        Item {
            Layout.fillWidth: true
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ch.toggled()
    }
}
