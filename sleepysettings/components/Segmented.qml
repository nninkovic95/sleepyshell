import QtQuick
import qs

// A few choices on one track; an accent pill slides to the current one (like the workspace
// disc). options: [{value, label}]. The segment showing `value` reports itself as `selected`.
// The pill slides only while the pointer is on the control (a pick); the first layout of a page,
// Defaults, a reset or Discard move it at once.
Rectangle {
    id: sg
    property var options: []
    property var value
    property Item selected: null
    signal picked(var v)
    implicitWidth: segs.implicitWidth + 6
    implicitHeight: 30
    radius: Theme.radiusMd
    color: Theme.tileBg

    Rectangle {
        visible: sg.selected !== null
        x: sg.selected ? segs.x + sg.selected.x : 3
        y: 3
        width: sg.selected ? sg.selected.width : 0
        height: sg.height - 6
        radius: Theme.radiusSm
        color: Theme.accent
        Behavior on x {
            enabled: sgHover.hovered
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
        Behavior on width {
            enabled: sgHover.hovered
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
    }

    HoverHandler {
        id: sgHover
    }

    Row {
        id: segs
        x: 3
        y: 3
        spacing: 2

        Repeater {
            model: sg.options

            Item {
                id: seg
                required property var modelData
                readonly property bool on: modelData.value === sg.value
                implicitWidth: segText.implicitWidth + 20
                implicitHeight: sg.height - 6
                onOnChanged: {
                    if (on)
                        sg.selected = seg;
                    else if (sg.selected === seg)
                        sg.selected = null;
                }
                Component.onCompleted: if (on) sg.selected = seg
                Component.onDestruction: if (sg.selected === seg) sg.selected = null

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSm
                    color: segMouse.containsMouse && !seg.on ? Theme.hoverBg : "transparent"
                }

                Text {
                    id: segText
                    anchors.centerIn: parent
                    text: seg.modelData.label
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: seg.on ? Theme.accentFg : Theme.fg
                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                }

                MouseArea {
                    id: segMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sg.picked(seg.modelData.value)
                }
            }
        }
    }
}
