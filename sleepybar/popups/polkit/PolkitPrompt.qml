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
    // PAM waits for the password; otherwise the helper is checking (or starting, or waiting for a fingerprint)
    readonly property bool asking: flow !== null && flow.isResponseRequired
    // a password was submitted and PAM has not asked again or finished: the check is running
    property bool checking: false
    onFlowChanged: checking = false
    onAskingChanged: if (asking) checking = false

    // A check that never ends (a PAM module that hangs) would hold the prompt, and the app behind it, for good: 30 s
    // after a submitted password the request is cancelled (the app is told it was not authorised) and a notification
    // says why. Only after a submit: a fingerprint reader waits for a finger without asking, for as long as the user
    // takes.
    Timer {
        interval: 30000
        running: root.shown && root.checking && !root.asking && !(root.flow?.isCompleted ?? true)
        onTriggered: {
            if (!root.flow)
                return;
            console.warn("polkit: the password check took longer than 30 s and was cancelled");
            root.flow.cancelAuthenticationRequest();
            Quickshell.execDetached(["notify-send", "-a", "Sleepy Shell", "Password check cancelled", "Checking the password took too long, so the request was cancelled. Try again."]);
        }
    }

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
            // the islands' fill and no outline, like every other panel of the shell
            color: Theme.popupBg

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
                        // read-only, not disabled, until PAM asks and while it checks: a disabled item drops its
                        // focus, which left Enter and Escape dead (Escape could not cancel a running check, and
                        // after a wrong password nothing worked until the field was clicked)
                        readOnly: !root.asking
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
                                root.checking = true;
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
