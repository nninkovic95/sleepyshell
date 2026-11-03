import QtQuick
import qs.services

// A Settings value picked from a list (Combo, drawn by the window's Picker, passed in as picker).
// options: [{value, label}]. `custom`: a spec (CustomEntry.qml) adds a last "Custom…" entry to the list that opens an input under the
// row for a value of your own; null: presets only.
SettingRow {
    id: cr
    property var options: []
    // ---- BEGIN toml custom ----
    property var custom: null
    property bool editing: false
    readonly property var current: Settings.get(cr.key)
    readonly property bool isPreset: cr.options.some(o => o.value === cr.current)
    readonly property bool customOn: cr.custom !== null && (cr.editing || !cr.isPreset)
    readonly property string customMark: "__custom__"
    readonly property var shown: cr.custom !== null ? cr.options.concat([{ value: cr.customMark, label: "Custom…" }]) : cr.options
    onCurrentChanged: {
        if (cr.isPreset && cr.editing && !customEntry.box.input.activeFocus)
            cr.editing = false;
    }
    function pick(v) {
        if (v === cr.customMark) {
            cr.editing = true;
            customEntry.open();
        } else {
            cr.editing = false;
            Settings.stage(cr.key, v);
        }
    }
    below: CustomEntry {
        id: customEntry
        row: cr
        visible: cr.customOn
    }
    // ---- END toml custom ----
    extraSearch: cr.shown.map(o => o.label + " " + (o.hint ?? "")).join(" ")
    property var picker: null
    format: v => (cr.options.find(o => o.value === v) ?? {
            label: String(v)
        }).label

    Combo {
        picker: cr.picker
        value: cr.customOn ? cr.customMark : Settings.get(cr.key)
        options: cr.shown
        onPicked: v => cr.pick(v)
    }
}
