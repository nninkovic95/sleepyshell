import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs
import qs.services

// What one screen shows while the session is locked (Sleepylock.qml puts it inside a WlSessionLockSurface):
// the blurred wallpaper of this output under a dimmed Theme.surface layer, the time and date, and a
// card with the password field. The compositor gives keyboard focus to one lock surface only, so the
// typed text lives in the shared context (Sleepylock.qml) and every screen mirrors it. The field is
// read-only, not disabled, while PAM checks: a disabled item would lose the focus.
Rectangle {
    id: root
    required property var context
    property string screenName: ""
    readonly property string wallpaper: context.wallpapers[screenName] ?? ""
    readonly property string user: Quickshell.env("USER")
    readonly property int blurRadius: 48   // MultiEffect blurMax: the pixel radius a blur of 1.0 reaches

    color: Theme.surface

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // The image is oversized by the blur radius so the blur's fade-out at the texture edge falls
    // off screen, and autoPaddingEnabled is off so the effect keeps the size of the image.
    Image {
        anchors.fill: parent
        anchors.margins: -root.blurRadius
        source: root.wallpaper === "" ? "" : "file://" + root.wallpaper.split("/").map(encodeURIComponent).join("/")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1.0
            blurMax: root.blurRadius
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        opacity: 0.55
    }

    MouseArea {
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
    }

    Connections {
        target: root.context
        function onCurrentTextChanged() {
            input.text = root.context.currentText;
        }
        // Sleepylock.qml clears unlockInProgress before it sets showFailure, so a failed check shakes
        function onShowFailureChanged() {
            if (root.context.showFailure && !root.context.unlockInProgress)
                shakeAnim.restart();
        }
    }

    Component.onCompleted: {
        input.text = context.currentText;
        input.forceActiveFocus();
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        // clock in the centre island's font (Settings.clockFont), the date in small caps under it
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            font.family: Settings.clockFont
            font.pixelSize: 96
            color: Theme.fg
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 40
            text: Qt.formatDateTime(clock.date, "dddd d MMMM")
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 2
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 3
            color: Theme.fgMuted
        }

        // user name above the field
        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 8
            spacing: 8

            Rectangle {
                width: 28
                height: 28
                radius: height / 2
                color: Theme.accent

                Text {
                    anchors.centerIn: parent
                    text: root.user.charAt(0).toUpperCase()
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                    color: Theme.accentFg
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.user
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 1
                font.weight: Font.Medium
                color: Theme.fg
            }
        }

        // The field: a frosted pill with a lock badge, the typed characters as dots that pop in,
        // and a round submit button. The real TextInput is invisible and only holds the text.
        Rectangle {
            id: pill
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 340
            implicitHeight: 52
            radius: height / 2
            readonly property bool failed: root.context.showFailure && !root.context.unlockInProgress
            color: Qt.alpha(Theme.containerHighest, 0.7)
            border.width: 2
            border.color: failed ? Theme.urgentFg : input.activeFocus ? Qt.alpha(Theme.primary, 0.7) : Theme.trackBg
            Behavior on border.color {
                ColorAnimation {
                    duration: 150
                }
            }
            // a Translate, not x: the layout owns this item's x and would undo the shake
            transform: Translate {
                id: shake
            }

            // four swings of 8 px at 40 ms each, then back to rest
            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: shake; property: "x"; to: 8; duration: 40 }
                NumberAnimation { target: shake; property: "x"; to: -8; duration: 40 }
                NumberAnimation { target: shake; property: "x"; to: 8; duration: 40 }
                NumberAnimation { target: shake; property: "x"; to: -8; duration: 40 }
                NumberAnimation { target: shake; property: "x"; to: 0; duration: 40 }
            }

            // lock badge
            Rectangle {
                id: badge
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                radius: height / 2
                color: pill.failed ? Theme.urgent : Theme.tileBg

                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(root.context.unlockInProgress ? 0xF0453 : 0xF033E)
                    font.family: Theme.iconFont
                    font.pixelSize: 18
                    color: pill.failed ? Theme.urgentFg : Theme.fg
                    RotationAnimation on rotation {
                        running: root.context.unlockInProgress
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        onStopped: parent.rotation = 0
                    }
                }
            }

            // submit
            Rectangle {
                id: go
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                radius: height / 2
                color: input.text !== "" ? Theme.accent : Theme.tileBg
                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF0054)
                    font.family: Theme.iconFont
                    font.pixelSize: 18
                    color: input.text !== "" ? Theme.accentFg : Theme.fgMuted
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.context.tryUnlock()
                }
            }

            // what is shown between the badge and the button
            Item {
                id: middle
                anchors.left: badge.right
                anchors.right: go.left
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                clip: true

                Text {
                    anchors.centerIn: parent
                    visible: input.text === ""
                    text: root.context.unlockInProgress ? "Checking…" : pill.failed ? "Wrong password" : "Password"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                    color: pill.failed ? Theme.urgentFg : Theme.fgMuted
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 7

                    Repeater {
                        // a ListModel kept in step with the text (at most 16 dots), so typing adds one
                        // delegate instead of rebuilding them all and every dot popping again
                        model: ListModel {
                            id: dots
                        }

                        Rectangle {
                            width: 10
                            height: 10
                            radius: height / 2
                            color: Theme.fg
                            scale: 0
                            Component.onCompleted: scale = 1
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 140
                                    easing.type: Easing.OutBack
                                }
                            }
                        }
                    }
                }

                TextInput {
                    id: input
                    anchors.fill: parent
                    opacity: 0
                    focus: true
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData
                    readOnly: root.context.unlockInProgress
                    onTextChanged: {
                        root.context.currentText = text;
                        const n = Math.min(text.length, 16);
                        while (dots.count < n)
                            dots.append({});
                        while (dots.count > n)
                            dots.remove(dots.count - 1);
                    }
                    onAccepted: root.context.tryUnlock()
                    // the first key after waking lifts the black sleep cover and still reaches the field
                    Keys.onPressed: event => {
                        root.context.wake("key");
                        event.accepted = false;
                    }
                    Keys.onEscapePressed: root.context.currentText = ""
                }
            }

            // In the gap under the field, so showing it does not shift the layout; it shakes with it.
            Text {
                visible: root.context.capsLock
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 10 }
                text: String.fromCodePoint(0xF0632) + "  Caps Lock is on"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: Theme.urgentFg
            }
        }
    }
}
