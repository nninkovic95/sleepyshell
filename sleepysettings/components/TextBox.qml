import QtQuick
import QtQuick.Layouts
import qs

// One-line text field in the settings style. `text` is what is typed; set it from outside with
// a Binding when it must follow a stored value. `edited` fires on every keystroke, `finished` on
// Enter or focus loss. Escape drops focus; the window's Escape shortcut is claimed first through
// shortcutOverride so the first Escape only leaves the field and the second one closes.
Rectangle {
    id: tb
    property alias text: field.text
    property alias input: field
    property string placeholder: ""
    signal accepted()
    signal finished()
    signal edited()
    // Escape in the field (before it drops the focus), for a field that cancels something with it (the file browser's new folder)
    signal escaped()
    Layout.fillWidth: true
    implicitHeight: 30
    radius: Theme.radiusSm
    color: field.activeFocus ? Theme.hoverBg : Theme.tileBg

    TextInput {
        id: field
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.accentFg
        onAccepted: tb.accepted()
        onEditingFinished: tb.finished()
        onTextEdited: tb.edited()
        Keys.onShortcutOverride: event => {
            if (event.key === Qt.Key_Escape)
                event.accepted = true;
        }
        Keys.onEscapePressed: {
            tb.escaped();
            focus = false;
        }
    }

    Text {
        anchors.fill: field
        verticalAlignment: Text.AlignVCenter
        visible: field.text === ""
        elide: Text.ElideRight
        text: tb.placeholder
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fgMuted
    }
}
