import QtQuick
import qs

// The centre island's top row (GrowingIsland.qml): the left slot's widgets, the clock (title over subtitle), the
// right slot's widgets. The widgets hang from the top edge like the side islands' buttons; the clock is centred in
// the closed height. A click on the clock asks for the panel (`clockClicked`).
//   leftComponent / rightComponent  the slots' widgets (a widget with `shown: false` hides its slot)
//   closedH            the island's closed height
//   leftItem, rightItem, leftShown, rightShown   the slots' widgets and whether each shows
//   clockX, clockW     the clock box in this row; clockH the clock column's own height
Row {
    id: root

    required property Component leftComponent
    required property Component rightComponent
    required property string title
    required property string subtitle
    required property string titleFont
    required property int titleSize
    required property real closedH
    signal clockClicked

    readonly property Item leftItem: leftSlot.item
    readonly property Item rightItem: rightSlot.item
    readonly property bool leftShown: leftSlot.visible
    readonly property bool rightShown: rightSlot.visible
    readonly property real clockX: clockBox.x
    readonly property real clockW: clockBox.width
    readonly property real clockH: clockCol.implicitHeight

    spacing: Theme.gap

    Loader {
        id: leftSlot
        sourceComponent: root.leftComponent
        visible: item !== null && (item.shown ?? true)
    }

    Item {
        id: clockBox
        width: Math.ceil(clockCol.implicitWidth) + 24
        height: root.closedH - 2

        Column {
            id: clockCol
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
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
            onClicked: root.clockClicked()
        }
    }

    Loader {
        id: rightSlot
        sourceComponent: root.rightComponent
        visible: item !== null && (item.shown ?? true)
    }
}
