import QtQuick
import QtQuick.Layouts
import qs
import qs.services

// The input under a row that offers "Custom…" (ChoiceRow and ComboRow with a `custom` spec). The row's key holds
// the custom value like any other value: this only edits it. The text is checked as it is typed; a valid text is staged (Apply saves
// it), a refused one shows why and stages nothing. Under the field: a warning where the spec has one, a live preview where it has
// one (the clock formats), and the value in use.
// spec: { placeholder, parse(text) -> {ok, value, error}, toText(value), seed(presetValue) (the text offered when Custom… is picked
//         over a preset), describe(value) -> text, warn, preview(text, now) -> text, suggest(text) -> [names] (the clock font's list) }
ColumnLayout {
    id: ce
    objectName: "customEntry"
    required property var row
    readonly property var spec: row.custom ?? ({})
    property string error: ""
    readonly property alias box: box
    readonly property var value: Settings.get(row.key)
    property date now: new Date()
    Layout.fillWidth: true
    spacing: 4

    // Custom… was picked: over a preset the field starts from that preset's nearest custom value, and has the focus
    function open() {
        ce.error = "";
        if (row.isPreset)
            box.text = ce.spec.seed ? ce.spec.seed(ce.value) : "";
        box.input.forceActiveFocus();
        box.input.selectAll();
    }

    function take() {
        if (box.text.trim() === "") {
            ce.error = "";
            return;
        }
        const r = ce.spec.parse(box.text);
        if (r.ok) {
            ce.error = "";
            Settings.stage(row.key, r.value);
        } else {
            ce.error = r.error;
        }
    }

    function pickSuggestion(name) {
        box.text = name;
        ce.take();
    }

    TextBox {
        id: box
        objectName: "customField"
        placeholder: ce.spec.placeholder ?? ""
        onEdited: ce.take()
        onFinished: ce.take()
    }

    // the stored custom value follows into the field unless it is being typed in (as FieldRow); a refused text goes back to it on leaving
    Binding {
        target: box
        property: "text"
        value: ce.spec.toText ? ce.spec.toText(ce.value) : String(ce.value)
        when: !box.input.activeFocus && !ce.row.isPreset
        restoreMode: Binding.RestoreNone
    }

    // the clock font: installed families that match what is typed
    Flow {
        objectName: "customSuggestions"
        visible: ce.spec.suggest !== undefined && repeater.count > 0
        Layout.fillWidth: true
        spacing: 4

        Repeater {
            id: repeater
            model: ce.spec.suggest ? ce.spec.suggest(box.text) : []

            Rectangle {
                id: chip
                required property string modelData
                height: 24
                width: chipText.implicitWidth + 16
                radius: Theme.radiusSm
                color: chipMouse.containsMouse ? Theme.hoverBg : Theme.tileBg

                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: chip.modelData
                    font.family: chip.modelData
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.fg
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ce.pickSuggestion(chip.modelData)
                }
            }
        }
    }

    SmallText {
        objectName: "customWarn"
        visible: (ce.spec.warn ?? "") !== ""
        text: ce.spec.warn ?? ""
        color: Theme.urgentFg
    }
    SmallText {
        objectName: "customError"
        visible: ce.error !== ""
        text: ce.error
        color: Theme.urgentFg
    }
    SmallText {
        objectName: "customPreview"
        visible: ce.spec.preview !== undefined && text !== ""
        text: ce.spec.preview ? ce.spec.preview(box.text, ce.now) : ""
    }
    SmallText {
        objectName: "customApplied"
        text: "Using: " + (ce.spec.describe ? ce.spec.describe(ce.value) : String(ce.value))
    }

    // the clock's seconds: the preview ticks while it is shown
    Timer {
        interval: 1000
        repeat: true
        running: ce.visible && ce.spec.preview !== undefined
        onTriggered: ce.now = new Date()
    }
}
