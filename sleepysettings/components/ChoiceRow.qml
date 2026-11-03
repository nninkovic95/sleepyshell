import QtQuick
import qs.services

// A Settings value picked from a few choices shown side by side (Segmented).
// options: [{value, label}].
// `custom`: a spec (CustomEntry.qml) adds a last "Custom…" choice that opens an input under the row for a value
// of your own; the value is a normal value of the key, so the row reads and resets like any other. null: presets only.
SettingRow {
    id: cr
    property var options: []
    // ---- BEGIN toml custom ----
    property var custom: null
    // Custom… was picked and the input stays open (also while the typed value happens to equal a preset)
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
    format: v => (cr.options.find(o => o.value === v) ?? {
            label: String(v)
        }).label

    Segmented {
        value: cr.customOn ? cr.customMark : Settings.get(cr.key)
        options: cr.shown
        onPicked: v => cr.pick(v)
    }
}
