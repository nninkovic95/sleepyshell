import QtQuick
import qs.services

// A text Settings value, staged on every keystroke (staging is free until Apply). Staging only on
// Enter or focus out lost the text when Apply was clicked straight away: the Apply button takes
// no focus, so nothing was staged and Apply stayed dimmed (review 3, F2).
// `validate` (optional) returns "" or why the text is refused; refused text is not staged, its
// reason replaces the hint, and leaving the field puts the stored value back.
// Extra children (the Theme tab's Browse… button) go after the field.
SettingRow {
    id: fr
    property var validate: null
    error: fr.validate ? fr.validate(box.text) : ""
    format: v => v

    function take() {
        if (fr.error === "")
            Settings.stage(fr.key, box.text);
        else
            Settings.drop([fr.key]);
    }

    TextBox {
        id: box
        onEdited: fr.take()
        onFinished: fr.take()
    }

    // a Binding, not text: binding: typing would break a plain binding, and Defaults must still reach it.
    // Paused while the field has focus, so dropping a refused value does not overwrite the typing;
    // RestoreNone, or pausing would put back the text from before the first binding ("").
    Binding {
        target: box
        property: "text"
        value: Settings.get(fr.key)
        when: !box.input.activeFocus
        restoreMode: Binding.RestoreNone
    }
}
