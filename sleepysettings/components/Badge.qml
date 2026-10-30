import QtQuick
import qs

// The round "!" mark: unapplied changes (sidebar, Apply bar, leave dialog), and the base of
// InfoTip's hover badge.
Rectangle {
    id: bd
    property int size: 16
    property color fg: Theme.urgentFg
    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: Theme.urgent

    Text {
        anchors.centerIn: parent
        text: "!"
        font.family: Theme.font
        font.pixelSize: bd.size - 5
        font.bold: true
        color: bd.fg
    }
}
