import QtQuick
import QtQuick.Shapes
import qs
import qs.components
import qs.services

// One big button of the session menu. Two layers on purpose: this outer Item owns the entrance (fade, scale,
// rise, the shake of a refused tap) and the inner `bg` surface owns the hover Lift, because Lift
// binds the scale of the item it sits in and the two would fight over one property. The Lift
// (scale, tilt, shadow) is on the background surface only: the disc, icon, label and key cap are
// siblings drawn above it at whole-pixel positions and scale 1, so they stay sharp while hovered
// (they were blurry when the whole lifted card scaled).
//
// All five cards share one calm surface at
// rest and danger shows only as state. One disc per card carries the icon; on the destructive
// cards the disc's own rim is the hold ring, and it fills red while held. Hover or keyboard
// selection gives the Lift and an accent outline (the same on every card, so the default Lock
// selection is not a different kind of button); the "hold" caption shows only on a selected
// destructive card.
//
// A danger button (log out, reboot, shut down) is run by holding it, not by a click: while
// `pressing` the ring fills over holdMs and `confirmed()` fires when it is full.
// Releasing early drains the ring again; SessionMenu then shows the hint line. Non-danger buttons
// never fill a ring, SessionMenu runs them on the click or key press.
Item {
    id: btn

    required property var modelData
    required property int index
    // selected (hover or keyboard) and whether the selection came from the keyboard: a keyboard
    // selection lifts the card as a hovered one does
    property bool active: false
    property bool keyboard: false
    // follows the menu being open; drives the staggered entrance and the quick exit
    property bool shown: false
    // set by the menu while the pointer or a key holds a danger button down
    property bool pressing: false
    property real hold: 0
    readonly property int holdMs: 600
    readonly property bool danger: modelData.danger === true
    // the state colour of the icon and captions: urgent for the destructive cards, accent otherwise
    readonly property color tone: danger ? Theme.urgentFg : Theme.accentFg
    // the state fill of the disc, and the hold ring (a stronger red than the icon tone)
    readonly property color discTint: danger ? Qt.alpha(Theme.urgent, 0.55) : Qt.alpha(Theme.accent, 0.8)
    readonly property color ringFill: Qt.tint(Theme.urgentFg, Qt.alpha(Theme.urgent, 0.7))
    property real reveal: 0

    readonly property int discSize: 88
    readonly property int rim: 3

    signal down      // mouse button pressed on it
    signal up        // mouse button released, or the press was cancelled
    signal clicked
    signal hovered   // the pointer entered or moved over it: the menu selects it
    signal confirmed // the hold ring filled

    // the refused tap: a short sideways shake
    function nudge() {
        shake.restart();
    }

    // content height plus the padding above the disc and below the key cap
    implicitHeight: 24 + discSize + content.spacing + Math.ceil(label.height) + content.spacing + 22 + 24

    opacity: Math.min(1, reveal * 1.6)
    // only the entrance scales this item (exactly 1 once it has landed); a held card is not
    // shrunk any more, since that scaled the icon and label
    scale: 0.8 + 0.2 * reveal
    transform: [
        Translate {
            y: Math.round((1 - btn.reveal) * 28)
            x: Math.round(btn.shakeX)
        }
    ]
    property real shakeX: 0

    onShownChanged: {
        if (shown) {
            outAnim.stop();
            inAnim.restart();
        } else {
            inAnim.stop();
            outAnim.restart();
            pressing = false;
            hold = 0;
        }
    }

    // stagger: 50 ms per button after a short lead-in, a little overshoot on landing
    SequentialAnimation {
        id: inAnim
        PauseAnimation {
            duration: 70 + btn.index * 50
        }
        NumberAnimation {
            target: btn
            property: "reveal"
            to: 1
            duration: 420
            easing.type: Easing.OutBack
            easing.overshoot: 1.3
        }
    }
    NumberAnimation {
        id: outAnim
        target: btn
        property: "reveal"
        to: 0
        duration: 140
        easing.type: Easing.InCubic
    }

    SequentialAnimation {
        id: shake
        NumberAnimation {
            target: btn
            property: "shakeX"
            to: -8
            duration: 45
        }
        NumberAnimation {
            target: btn
            property: "shakeX"
            to: 8
            duration: 70
        }
        NumberAnimation {
            target: btn
            property: "shakeX"
            to: -5
            duration: 60
        }
        NumberAnimation {
            target: btn
            property: "shakeX"
            to: 0
            duration: 50
        }
    }

    NumberAnimation {
        id: fill
        target: btn
        property: "hold"
        from: 0
        to: 1
        duration: btn.holdMs
        onFinished: if (btn.pressing)
            btn.confirmed()
    }
    NumberAnimation {
        id: drain
        target: btn
        property: "hold"
        to: 0
        duration: 200
        easing.type: Easing.OutCubic
    }
    onPressingChanged: {
        if (!danger)
            return;
        if (pressing) {
            drain.stop();
            fill.restart();
        } else if (hold < 1) {
            fill.stop();
            drain.restart();
        }
    }

    // a keyboard selection has no pointer to lean toward: lift flat
    onActiveChanged: {
        if (active && keyboard && !mouse.containsMouse) {
            lift.nx = 0;
            lift.ny = 0;
        }
    }

    Item {
        id: face
        anchors.fill: parent

        // the card surface: the only thing the Lift scales and tilts
        Rectangle {
            id: bg
            anchors.fill: parent
            radius: Theme.nested(Theme.radiusXxl, 12)
            // one calm surface at rest, the same on all five cards
            color: btn.active ? Theme.hoverBg : Theme.tileBg
            border.width: 1
            border.color: btn.active ? "transparent" : Theme.tileBg
            Behavior on color {
                ColorAnimation {
                    duration: 140
                }
            }

            // hover or a keyboard selection raises the surface. Settings > cardHover (tilt or
            // lift) is handled inside Lift.
            Lift {
                id: lift
                radius: bg.radius
                tilt: true
                pointer: mouse
                level: mouse.containsMouse || (btn.active && btn.keyboard) ? 1 : 0
            }

            // the hold also floods the surface a little in the state colour, so it reads from
            // across the room
            Rectangle {
                anchors.fill: parent
                radius: bg.radius
                color: btn.tone
                opacity: btn.hold * 0.1
            }

            // selection: an accent outline, the same on every card
            Rectangle {
                anchors.fill: parent
                radius: bg.radius
                color: "transparent"
                border.width: 2
                border.color: Theme.primary
                opacity: btn.active ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                    }
                }
            }
        }

        // every position below is a whole pixel (Math.round, no anchors.centerIn on fractional
        // sizes): a half-pixel offset blurs glyphs and labels. The only scale left at rest is exactly 1, and nothing here is a layer.
        Column {
            id: content
            width: face.width
            y: 24
            z: 2
            spacing: 14

            // the one disc: icon on it, and on a destructive card its rim is the hold ring
            Item {
                width: btn.discSize
                height: btn.discSize
                x: Math.round((parent.width - width) / 2)

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: btn.active ? btn.discTint : Theme.tileBg
                    border.width: btn.rim
                    border.color: btn.active ? Qt.alpha(btn.tone, 0.35) : Theme.tileBg
                    Behavior on color {
                        ColorAnimation {
                            duration: 140
                        }
                    }
                    Behavior on border.color {
                        ColorAnimation {
                            duration: 140
                        }
                    }
                }

                // the arc grows clockwise from the top over the rim; the multisampled layer exists
                // only while the ring is not empty, so nothing is a texture at rest
                Shape {
                    anchors.fill: parent
                    visible: btn.danger && btn.hold > 0.001
                    layer.enabled: visible
                    layer.samples: 4

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: btn.ringFill
                        strokeWidth: btn.rim
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: btn.discSize / 2
                            centerY: btn.discSize / 2
                            radiusX: (btn.discSize - btn.rim) / 2
                            radiusY: (btn.discSize - btn.rim) / 2
                            startAngle: -90
                            sweepAngle: 359.9 * btn.hold
                        }
                    }
                }

                Text {
                    x: Math.round((parent.width - width) / 2)
                    y: Math.round((parent.height - height) / 2)
                    text: String.fromCodePoint(btn.modelData.icon)
                    font.family: Theme.iconFont
                    font.pixelSize: 40
                    color: btn.active ? btn.tone : Theme.fg
                    Behavior on color {
                        ColorAnimation {
                            duration: 140
                        }
                    }
                }
            }

            Text {
                id: label
                x: Math.round((parent.width - width) / 2)
                text: btn.modelData.label
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 3
                font.weight: Font.Medium
                color: Theme.fg
            }

            // the key that runs it, as a small key cap; "hold" beside it only on a selected
            // destructive card, so the caption does not push the cap off the centre
            Item {
                width: parent.width
                height: 22

                Rectangle {
                    id: cap
                    x: Math.round((parent.width - width) / 2)
                    width: 24
                    height: 22
                    radius: Theme.radiusXs
                    color: Theme.tileBg
                    border.width: 1
                    border.color: btn.active ? Qt.alpha(btn.tone, 0.45) : Theme.trackBg

                    Text {
                        x: Math.round((parent.width - width) / 2)
                        y: Math.round((parent.height - height) / 2)
                        text: btn.modelData.key.toUpperCase()
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                        color: btn.active ? btn.tone : Theme.fgMuted
                    }
                }

                Text {
                    x: cap.x + cap.width + 8
                    y: Math.round((parent.height - height) / 2)
                    text: "hold"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: btn.tone
                    opacity: btn.danger && btn.active ? 0.85 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 140
                        }
                    }
                }
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: btn.hovered()
            onPositionChanged: btn.hovered()
            onPressed: btn.down()
            onReleased: btn.up()
            onCanceled: btn.up()
            onClicked: btn.clicked()
        }
    }
}
