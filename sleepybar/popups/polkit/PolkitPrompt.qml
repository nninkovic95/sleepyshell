import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import qs
import qs.components

// The session's polkit agent: the password prompt an app gets when it needs admin rights
// (pkexec, a disk mount, a package tool), drawn in the bar's style. Only one agent can register per
// session, so hyprpolkitagent.service must not run. One full-screen overlay on the focused
// monitor: the wallpaper is dimmed and blurred (namespace sleepyshell-polkit, matched by the sleepyshell
// blur rule), the card takes the keyboard. Enter submits, Escape cancels.
Scope {
    id: root

    PolkitAgent {
        id: agent
    }

    readonly property var flow: agent.flow
    readonly property bool shown: agent.isActive && flow !== null
    property bool shake: false

    Connections {
        target: root.flow
        function onAuthenticationFailed() {
            root.shake = true;
        }
    }

    PanelWindow {
        id: win
        visible: root.shown
        screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0]
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "sleepyshell-polkit"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                field.text = "";
                field.forceActiveFocus();
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.surface, 0.45)
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: shakeX
            width: 440
            height: col.implicitHeight + 40
            radius: Theme.radiusXl
            color: Qt.alpha(Theme.containerHighest, 0.8)
            border.width: 1
            border.color: Theme.trackBg

            property real shakeX: 0
            SequentialAnimation {
                running: root.shake
                onFinished: root.shake = false
                NumberAnimation { target: card; property: "shakeX"; to: -10; duration: 50 }
                NumberAnimation { target: card; property: "shakeX"; to: 10; duration: 70 }
                NumberAnimation { target: card; property: "shakeX"; to: -6; duration: 60 }
                NumberAnimation { target: card; property: "shakeX"; to: 0; duration: 50 }
            }

            ColumnLayout {
                id: col
                x: 20
                y: 20
                width: card.width - 40
                spacing: 12

                RowLayout {
                    spacing: 10

                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: height / 2
                        color: Theme.accent

                        Glyph {
                            anchors.centerIn: parent
                            cp: 0xF033E
                            font.pixelSize: 18
                            color: Theme.accentFg
                        }
                    }

                    ColumnLayout {
                        spacing: 0

                        Text {
                            text: "Authentication required"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize + 2
                            font.weight: Font.Medium
                            color: Theme.fg
                        }

                        Text {
                            visible: text !== ""
                            text: root.flow ? root.flow.actionId : ""
                            textFormat: Text.PlainText
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                            color: Theme.fgMuted
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.flow ? root.flow.message : ""
                    // a password prompt must show the message as written, never as markup (review 4)
                    textFormat: Text.PlainText
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    color: Theme.fg
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Theme.radiusMd
                    color: Theme.tileBg
                    border.width: field.activeFocus ? 1 : 0
                    border.color: Theme.primary

                    TextInput {
                        id: field
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        enabled: root.flow !== null && root.flow.isResponseRequired
                        // disabled until PAM asks and while it checks; a disabled item drops its
                        // focus and does not get it back on its own, which left Enter and Escape
                        // dead after a wrong password until the field was clicked (review 3, F3)
                        onEnabledChanged: {
                            if (enabled && root.shown)
                                forceActiveFocus();
                        }
                        echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                        passwordCharacter: String.fromCodePoint(0x2022)
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 1
                        color: Theme.fg
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentFg
                        onAccepted: submitBtn.clicked(Qt.LeftButton)
                        Keys.onEscapePressed: cancelBtn.clicked(Qt.LeftButton)
                    }

                    Text {
                        anchors.fill: field
                        verticalAlignment: Text.AlignVCenter
                        visible: field.text === ""
                        text: root.flow && root.flow.isResponseRequired ? (root.flow.inputPrompt.replace(/:\s*$/, "") || "Password") : "Checking…"
                        textFormat: Text.PlainText
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        color: Theme.fgMuted
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText   // the helper's text, never markup
                    text: root.flow ? root.flow.supplementaryMessage : ""
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: root.flow && root.flow.supplementaryIsError ? Theme.urgentFg : Theme.fgMuted
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Item {
                        Layout.fillWidth: true
                    }

                    BarButton {
                        id: cancelBtn
                        text: "Cancel"
                        glued: false
                        bg: Theme.tileBg
                        onClicked: if (root.flow) root.flow.cancelAuthenticationRequest()
                    }

                    BarButton {
                        id: submitBtn
                        text: "Authenticate"
                        glued: false
                        bg: Theme.accent
                        fg: Theme.accentFg
                        onClicked: {
                            if (root.flow && root.flow.isResponseRequired) {
                                root.flow.submit(field.text);
                                field.text = "";
                            }
                        }
                    }
                }
            }
        }
    }
}
