import QtQuick
import qs
import qs.components

// On/off switch, "Island tab" look: a rounded-rectangle track with a
// rounded-square tab that slides. Off: muted track and an empty tab. On: the track fills with the
// theme accent and the tab shows a check mark. The parent flips it in onClicked.
// Same size as the old round-knob switch (38 x 22), so rows do not jump. The track is not a pill:
// its corners are the radiusSm token and the
// tab's are nested(radiusSm, inset), so the two are concentric and the whole switch follows the
// Sharp / Standard / Rounded preset; both are clamped so a rounder preset cannot turn them into a
// pill. The hover lift sits in a background holder, so the check mark stays sharp (CLAUDE.md,
// Hover); the tab is a sibling at scale 1.
Item {
    id: tg
    property bool checked: false
    signal clicked()
    implicitWidth: 38
    implicitHeight: 22
    // above its neighbours while lifted, so the shadow is not covered
    z: surface.z

    readonly property int inset: 3
    readonly property int tabSize: height - 2 * inset
    readonly property real trackRadius: Math.min(Theme.radiusSm, height / 2)
    // true while the tab shows the check mark (read by the tests)
    readonly property bool checkShown: check.opacity > 0.5
    readonly property real knobX: knob.x
    readonly property real tabRadius: knob.radius

    Item {
        anchors.fill: parent

        Rectangle {
            id: surface
            anchors.fill: parent
            radius: tg.trackRadius
            color: tg.checked ? Theme.accent : Theme.trackBg
            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }

            Lift {
                radius: surface.radius
                level: tgMouse.containsMouse && tg.enabled ? 1 : 0
            }
        }
    }

    Rectangle {
        id: knob
        width: tg.tabSize
        height: tg.tabSize
        radius: Math.min(Theme.nested(tg.trackRadius, tg.inset), height / 2)
        y: tg.inset
        x: tg.checked ? tg.width - width - tg.inset : tg.inset
        color: tg.checked ? Theme.accentFg : Theme.fg
        Behavior on x {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        // md-check, drawn in the track's colour so it reads as cut out of the tab
        Text {
            id: check
            anchors.centerIn: parent
            text: String.fromCodePoint(0xF012C)
            font.family: Theme.iconFont
            font.pixelSize: knob.height - 4
            color: Theme.accent
            opacity: tg.checked ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }
    }

    MouseArea {
        id: tgMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: tg.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: tg.clicked()
    }
}
