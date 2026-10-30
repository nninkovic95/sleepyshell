import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// Inline password prompt under the row of a Wi-Fi network that needs one. WifiList owns the state:
// it opens this row for its `pending` network, makes the connect call and supplies the error text.
// The host window must hold keyboard focus meanwhile (WifiList.typing -> wantsKeyboard).
ColumnLayout {
    id: root
    property bool open: false
    property string name: ""
    property string error: ""
    property bool busy: false
    signal submitted(string psk)
    signal cancelled()

    visible: open
    spacing: 2

    function submit() {
        if (field.text !== "" && !busy)
            root.submitted(field.text);
    }

    // a fresh prompt each time: no leftover password from the last network
    onOpenChanged: {
        field.text = "";
        if (open)
            focusTimer.restart();
    }

    // Hyprland grants keyboard focus only after the surface asked for it (wantsKeyboard flips in
    // the same moment this row appears), so focusing at once would be too early
    Timer {
        id: focusTimer
        interval: 100
        onTriggered: field.forceActiveFocus()
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 36
        radius: Theme.radiusMd
        color: Theme.tileBg

        // the box is taller than the text: a click anywhere in it focuses the field
        TapHandler {
            onTapped: field.forceActiveFocus()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 4
            spacing: 6

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitWidth: 0

                TextInput {
                    id: field
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    clip: true
                    echoMode: TextInput.Password
                    passwordCharacter: String.fromCodePoint(0x2022)
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentFg
                    onAccepted: root.submit()
                    Keys.onEscapePressed: root.cancelled()
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    visible: field.text === ""
                    elide: Text.ElideRight
                    text: "Password for " + root.name
                    textFormat: Text.PlainText   // network name (review 4)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    color: Theme.fgMuted
                }
            }

            BarButton {
                Layout.alignment: Qt.AlignVCenter
                text: "Connect"
                glued: false
                bg: Theme.accent
                fg: root.busy ? Theme.fgMuted : Theme.accentFg
                hoverBg: Theme.primary
                hoverFg: Theme.surface
                onClicked: root.submit()
            }

            BarButton {
                Layout.alignment: Qt.AlignVCenter
                glyph: 0xF0156
                hpad: 6
                glued: false
                onClicked: root.cancelled()
            }
        }
    }

    Text {
        visible: root.error !== ""
        Layout.leftMargin: 8
        text: root.error
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
        color: Theme.urgentFg
    }
}
