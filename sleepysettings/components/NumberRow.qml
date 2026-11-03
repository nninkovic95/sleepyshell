import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// A Settings number (staged until Apply) on the shared slider, or in a spin field (SpinField:
// - and + buttons and a typed number) when the key's schema entry says `spin: true`. The range
// and step come from the same entry (step 1 for whole numbers); `suffix` is the unit shown.
SettingRow {
    id: nr
    property string suffix: ""
    // the slider's own wish for width (200); a PairRow of two sliders asks for less so they fit side by side (the Display tab's night light)
    property int sliderWidth: 200
    readonly property var spec: Settings.schema[nr.key] ?? {}
    readonly property real min: nr.spec.min ?? 0
    readonly property real max: nr.spec.max ?? 1
    readonly property real step: nr.spec.step ?? 1
    readonly property real value: Settings.get(nr.key)
    readonly property bool spin: nr.spec.spin === true
    format: v => (nr.step >= 1 ? v : Number(v).toFixed(2)) + nr.suffix

    SpinField {
        visible: nr.spin
        Layout.fillWidth: true
        value: nr.value
        min: nr.min
        max: nr.max
        step: nr.step
        suffix: nr.suffix
        onMoved: v => Settings.stage(nr.key, v)
    }

    VSlider {
        visible: !nr.spin
        Layout.fillWidth: true
        implicitWidth: nr.sliderWidth
        value: (nr.value - nr.min) / (nr.max - nr.min)
        // one wheel notch = one step: the default 5 % of a range under 10 rounded back to the same value (review 3, F14)
        wheelStep: nr.step / (nr.max - nr.min)
        // the value is written right of the track by the slider itself
        text: nr.format(nr.value)
        textWidth: 64
        // a typed number (the unit is optional) is clamped to the range; the snapping to the step is below, as for the track
        parseTyped: t => {
            const n = Number(t.replace(nr.suffix.trim(), "").trim());
            return t === "" || isNaN(n) ? NaN : (Math.max(nr.min, Math.min(nr.max, n)) - nr.min) / (nr.max - nr.min);
        }
        onMoved: v => {
            const raw = nr.min + v * (nr.max - nr.min);
            const snapped = Math.round(raw / nr.step) * nr.step;
            Settings.stage(nr.key, nr.step >= 1 ? Math.round(snapped) : Number(snapped.toFixed(2)));
        }
    }
}
