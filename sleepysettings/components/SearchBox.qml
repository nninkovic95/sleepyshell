import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// The search field over the settings sidebar: a magnifier
// inside the field, a placeholder that names the shortcut while idle, a clear button while text
// is present, an accent outline while focused (the urgent tone while `noMatch`), and these keys:
// Escape clears the text first and only then, on an empty field, drops focus (the window's own
// Escape then acts as before), Down and Enter fire `jump()` (the window goes to the first tab
// with matches). It only holds the text; the window and the tabs do the matching. Like TextBox,
// the focused field claims Escape through shortcutOverride so the window's shortcut does not
// close the window under it.
Rectangle {
    id: sb
    property alias text: field.text
    property alias input: field
    property string placeholder: "Search settings (Ctrl+F)"
    property string focusedPlaceholder: "Search settings"
    // the search finds nothing anywhere: the outline turns urgent
    property bool noMatch: false
    // found by the sandbox's test helper
    readonly property bool isSearchBox: true
    signal jump()

    function clear() {
        field.text = "";
    }

    // Ctrl+F: focus the field with its text selected, so typing replaces the last search
    function focusAll() {
        field.forceActiveFocus();
        field.selectAll();
    }

    Layout.fillWidth: true
    implicitHeight: 30
    radius: Theme.radiusSm
    color: field.activeFocus ? Theme.hoverBg : hover.hovered ? Qt.alpha(Theme.fg, 0.1) : Theme.tileBg
    border.width: field.activeFocus || sb.noMatch ? 1 : 0
    border.color: sb.noMatch ? Theme.urgentFg : Theme.primary
    Behavior on color {
        ColorAnimation {
            duration: 120
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.IBeamCursor
    }

    Glyph {
        id: lens
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        cp: 0xF0349
        color: field.activeFocus ? Theme.primary : Theme.fgMuted
    }

    TextInput {
        id: field
        anchors.left: lens.right
        anchors.leftMargin: 2
        anchors.right: clearBtn.visible ? clearBtn.left : parent.right
        anchors.rightMargin: clearBtn.visible ? 0 : 8
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.accentFg
        onAccepted: sb.jump()
        Keys.onShortcutOverride: event => {
            if (event.key === Qt.Key_Escape)
                event.accepted = true;
        }
        Keys.onEscapePressed: {
            if (text !== "")
                text = "";
            else
                focus = false;
        }
        Keys.onDownPressed: sb.jump()
    }

    Text {
        anchors.fill: field
        verticalAlignment: Text.AlignVCenter
        visible: field.text === ""
        elide: Text.ElideRight
        text: field.activeFocus ? sb.focusedPlaceholder : sb.placeholder
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fgMuted
    }

    BarButton {
        id: clearBtn
        visible: field.text !== ""
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        glyph: 0xF0156
        hpad: 4
        glued: false
        fg: Theme.fgMuted
        hoverFg: Theme.fg
        onClicked: {
            sb.clear();
            field.forceActiveFocus();
        }
    }
}
