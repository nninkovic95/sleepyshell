import QtQuick
import QtQuick.Layouts
import qs
import qs.services

// One row of the clock dropdown menu: nerd-font glyph, label, hover highlight.
// `requires` names the programs the row runs (services/Deps.qml): while one is missing the row is
// greyed out, does not react, never emits clicked(), and hovering it shows "Needs ... (not
// installed)" in place of the label.
Item {
    id: root
    property int icon: 0
    property string label: ""
    property int iconSize: Theme.iconSize
    // glyph and label centred in the row instead of from the left
    property bool centred: false
    // turns red on hover, for an entry that leads to powering off (Power)
    property bool danger: false
    // a chosen row (the settings window's file browser): the hover colour stays on it
    property bool selected: false
    property real radius: Theme.radiusSm
    property var requires: []
    // a reason this row cannot run that is not a missing program (a custom tool whose app is gone): shown like "Needs ..."
    property string blocked: ""
    readonly property string needsText: root.blocked !== "" ? root.blocked : Deps.needs(root.requires)
    readonly property bool available: root.needsText === ""
    signal clicked()
    signal doubleClicked()

    Layout.fillWidth: true
    implicitHeight: Math.max(labelText.implicitHeight, iconSize) + 12
    // above its neighbours while lifted, so the shadow is not covered
    z: surface.z
    opacity: root.available ? 1 : 0.5

    // Edge tilt like the big cards,
    // gentler, since the tiles are short. Only the background lifts and leans; the glyph and label
    // stay put at scale 1, since scaling the whole row leaves them blurry on hover.
    // The holder keeps the lifted surface (z 1, set by Lift) from covering the label: a lifted
    // danger row is solid red and hid it.
    Item {
        anchors.fill: parent

        Rectangle {
            id: surface
            anchors.fill: parent
            radius: root.radius
            color: root.selected ? Qt.alpha(Theme.primary, 0.22) : !mouse.containsMouse || !root.available ? "transparent" : root.danger ? Theme.urgent : Theme.hoverBg
            Behavior on color {
                ColorAnimation {
                    duration: 120
                }
            }

            Lift {
                radius: root.radius
                level: mouse.containsMouse && root.available ? 1 : 0
                tilt: true
                tiltMax: 6
                tiltMinHeight: 28
                pointer: mouse
            }
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: root.centred ? Math.round((root.width - width) / 2) : 10
        spacing: 6 + (root.iconSize - Theme.iconSize) / 2

        Glyph {
            visible: root.icon !== 0
            cp: root.icon
            font.pixelSize: root.iconSize
            color: root.danger && mouse.containsMouse ? Theme.urgentFg : Theme.fg
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: labelText
            anchors.verticalCenter: parent.verticalCenter
            // the message instead of the label while the pointer is on a row that cannot run
            text: !root.available && mouse.containsMouse ? root.needsText : root.label
            width: Math.min(implicitWidth, Math.max(40, root.width - 20 - (root.icon !== 0 ? root.iconSize + 6 : 0)))
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            color: root.danger && mouse.containsMouse ? Theme.urgentFg : Theme.fg
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.available)
            root.clicked()
        onDoubleClicked: if (root.available)
            root.doubleClicked()
    }
}
