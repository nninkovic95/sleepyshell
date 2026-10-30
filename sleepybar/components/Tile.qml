import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.components

// Control-centre tile: glyph, label, status line; click toggles, the chevron expands a detail list.
// `requires` names the programs it runs (services/Deps.qml): while one is missing the tile is
// greyed out, its click does nothing and the status line says "Needs ... (not installed)".
Item {
    id: root
    property int icon: 0
    property string label: ""
    property string sub: ""
    property bool active: false
    property bool expandable: false
    property bool expanded: false
    property var requires: []
    // a reason the tile cannot work that is not a missing program (no power-profiles-daemon); the sub line says it
    property string blocked: ""
    readonly property string needsText: root.blocked !== "" ? root.blocked : Deps.needs(root.requires)
    readonly property bool available: root.needsText === ""
    signal clicked()
    signal expand()

    readonly property color fgc: active && available ? Theme.accentFg : Theme.fg

    Layout.fillWidth: true
    implicitHeight: 52
    property real radius: Theme.radiusMd
    // above its neighbours while lifted, so the shadow is not covered
    z: surface.z
    opacity: root.available ? 1 : 0.5

    // Only the background lifts and leans (the chevron sits on top, so it counts as hovering the
    // tile); the glyph and text stay put at scale 1. Scaling the whole tile left them blurry on
    // hover. The holder keeps the lifted surface (z 1, set by Lift) from
    // covering the content: a lifted active tile is solid accent and hid its glyph and text.
    Item {
        anchors.fill: parent

        Rectangle {
            id: surface
            anchors.fill: parent
            radius: root.radius
            color: root.active && root.available ? Theme.accent : ((area.containsMouse || chev.containsMouse) && root.available ? Theme.hoverBg : Theme.tileBg)

            Lift {
                id: lift
                radius: root.radius
                tilt: true
                pointer: area
                level: (area.containsMouse || chev.containsMouse) && root.available ? 1 : 0
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.available)
            root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 6
        spacing: 8

        Glyph {
            cp: root.icon
            font.pixelSize: 18
            Layout.preferredWidth: 24
            Layout.alignment: Qt.AlignVCenter
            color: root.fgc
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.label
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
                color: root.fgc
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                visible: root.sub !== "" || !root.available
                text: root.available ? root.sub : root.needsText
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
                color: root.fgc
                opacity: 0.75
            }
        }

        Rectangle {
            visible: root.expandable
            implicitWidth: 24
            implicitHeight: 24
            radius: height / 2
            color: chev.containsMouse ? Qt.alpha(root.fgc, 0.2) : "transparent"

            Glyph {
                anchors.centerIn: parent
                cp: root.expanded ? 0xF0143 : 0xF0140
                color: root.fgc
            }

            MouseArea {
                id: chev
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expand()
            }

            // The chevron's MouseArea takes the hover from `area`, so the tilt would freeze while
            // the pointer is over it: aim from here too, in `area`'s coordinates.
            Connections {
                target: chev
                function onPositionChanged(e) {
                    const p = chev.mapToItem(area, e.x, e.y);
                    lift.aim(p.x, p.y);
                }
                function onContainsMouseChanged() {
                    if (chev.containsMouse) {
                        const p = chev.mapToItem(area, chev.mouseX, chev.mouseY);
                        lift.aim(p.x, p.y);
                    }
                }
            }
        }
    }
}
