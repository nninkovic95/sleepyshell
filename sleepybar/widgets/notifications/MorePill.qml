import QtQuick
import qs
import qs.components
import qs.services

// The end of the toast chain: how many notifications are not on screen, normal (arrivals past the
// compact rows during a hover) and critical (past the slots), merged into one pill: "+3 more",
// "+2 more critical" or "+3 more · 2 critical"; red border while critical ones are in it. A click
// opens the bell's list, where all of them are (NotifPopups).
Item {
    id: pill
    property int count: 0           // normal
    property int criticalCount: 0
    readonly property bool critical: criticalCount > 0
    implicitWidth: label.implicitWidth + 28
    implicitHeight: 30
    readonly property real radius: height / 2
    // above its neighbours while lifted, so the shadow is not covered
    z: surface.z

    // only the pill's background lifts; the text stays at scale 1 and sharp.
    // The holder keeps the lifted surface (z 1) from covering it.
    Item {
        anchors.fill: parent

        Rectangle {
            id: surface
            anchors.fill: parent
            radius: pill.radius
            color: mouse.containsMouse ? Qt.tint(Qt.alpha(Theme.containerHighest, 0.92), Theme.hoverBg) : Qt.alpha(Theme.containerHighest, 0.92)
            border.width: 1
            border.color: pill.critical ? Theme.urgent : Theme.trackBg

            Lift {
                radius: pill.radius
                level: mouse.containsMouse ? 1 : 0
            }
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: pill.count > 0 && pill.criticalCount > 0 ? "+" + pill.count + " more · " + pill.criticalCount + " critical" : pill.criticalCount > 0 ? "+" + pill.criticalCount + " more critical" : "+" + pill.count + " more"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.weight: Font.Medium
        color: pill.critical ? Theme.urgentFg : Theme.fg
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Notifs.togglePanel()
    }
}
