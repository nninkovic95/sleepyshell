import QtQuick
import QtQuick.Layouts
import qs

// Records a key combination in Hyprland's form ("SUPER + SHIFT + P"). Click it, then press the
// combination; Escape with no modifier cancels. Key names follow xkb keysyms for the US layout
// (input.lua: kb_layout "us"), so SHIFT + 1 records as "SHIFT + 1", not "!". A combination that
// Hyprland already binds is taken by Hyprland and never reaches this field.
Rectangle {
    id: kc
    property string combo: ""
    // Qt drops active focus when the window loses focus and hands it back on return, so the
    // field re-armed itself after alt-tab; leaving the window now ends the capture for good
    readonly property bool listening: activeFocus && Window.active
    Window.onActiveChanged: {
        if (!Window.active)
            kc.focus = false;
    }
    Layout.preferredWidth: 190
    implicitHeight: 30
    radius: Theme.radiusSm
    color: listening ? Theme.hoverBg : Theme.tileBg
    border.width: listening ? 1 : 0
    border.color: Theme.primary
    activeFocusOnTab: true

    function keyName(e) {
        const k = e.key;
        if (k >= Qt.Key_A && k <= Qt.Key_Z)
            return String.fromCharCode(k);
        if (k >= Qt.Key_0 && k <= Qt.Key_9)
            return String.fromCharCode(k);
        if (k >= Qt.Key_F1 && k <= Qt.Key_F24)
            return "F" + (k - Qt.Key_F1 + 1);
        const shifted = {
            [Qt.Key_Exclam]: "1",
            [Qt.Key_At]: "2",
            [Qt.Key_NumberSign]: "3",
            [Qt.Key_Dollar]: "4",
            [Qt.Key_Percent]: "5",
            [Qt.Key_AsciiCircum]: "6",
            [Qt.Key_Ampersand]: "7",
            [Qt.Key_Asterisk]: "8",
            [Qt.Key_ParenLeft]: "9",
            [Qt.Key_ParenRight]: "0",
            [Qt.Key_Underscore]: "minus",
            [Qt.Key_Plus]: "equal",
            [Qt.Key_BraceLeft]: "bracketleft",
            [Qt.Key_BraceRight]: "bracketright",
            [Qt.Key_Colon]: "semicolon",
            [Qt.Key_QuoteDbl]: "apostrophe",
            [Qt.Key_Less]: "comma",
            [Qt.Key_Greater]: "period",
            [Qt.Key_Question]: "slash",
            [Qt.Key_Bar]: "backslash",
            [Qt.Key_AsciiTilde]: "grave"
        };
        const named = {
            [Qt.Key_Return]: "Return",
            [Qt.Key_Enter]: "KP_Enter",
            [Qt.Key_Escape]: "Escape",
            [Qt.Key_Space]: "space",
            [Qt.Key_Tab]: "Tab",
            [Qt.Key_Backtab]: "Tab",
            [Qt.Key_Backspace]: "BackSpace",
            [Qt.Key_Delete]: "Delete",
            [Qt.Key_Insert]: "Insert",
            [Qt.Key_Home]: "Home",
            [Qt.Key_End]: "End",
            [Qt.Key_PageUp]: "Page_Up",
            [Qt.Key_PageDown]: "Page_Down",
            [Qt.Key_Left]: "left",
            [Qt.Key_Right]: "right",
            [Qt.Key_Up]: "up",
            [Qt.Key_Down]: "down",
            [Qt.Key_Print]: "Print",
            [Qt.Key_Comma]: "comma",
            [Qt.Key_Period]: "period",
            [Qt.Key_Slash]: "slash",
            [Qt.Key_Minus]: "minus",
            [Qt.Key_Equal]: "equal",
            [Qt.Key_BracketLeft]: "bracketleft",
            [Qt.Key_BracketRight]: "bracketright",
            [Qt.Key_Semicolon]: "semicolon",
            [Qt.Key_Apostrophe]: "apostrophe",
            [Qt.Key_Backslash]: "backslash",
            [Qt.Key_QuoteLeft]: "grave"
        };
        return shifted[k] ?? named[k] ?? "";
    }

    function mods(m) {
        const out = [];
        if (m & Qt.MetaModifier)
            out.push("SUPER");
        if (m & Qt.ControlModifier)
            out.push("CTRL");
        if (m & Qt.AltModifier)
            out.push("ALT");
        if (m & Qt.ShiftModifier)
            out.push("SHIFT");
        return out;
    }

    // every key is ours while listening, including Escape, which is otherwise the window's shortcut
    Keys.onShortcutOverride: e => e.accepted = true
    Keys.onPressed: e => {
        e.accepted = true;
        const ms = mods(e.modifiers);
        if (e.key === Qt.Key_Escape && ms.length === 0) {
            kc.focus = false;
            return;
        }
        const name = keyName(e);
        if (name === "")
            return;     // a modifier on its own, or a key with no keysym mapping here
        kc.combo = ms.concat([name]).join(" + ");
        kc.focus = false;
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: kc.forceActiveFocus()
    }

    Text {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: kc.listening ? "Press keys…" : kc.combo !== "" ? kc.combo : "Click, then press keys"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: kc.combo !== "" && !kc.listening ? Theme.fg : Theme.fgMuted
    }
}
