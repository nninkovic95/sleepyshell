import QtQuick
import qs.services
import qs.components

// A boolean Settings value: label and a Toggle.
SettingRow {
    id: sr
    format: v => v ? "on" : "off"

    Toggle {
        checked: Settings.get(sr.key)
        onClicked: Settings.stage(sr.key, !Settings.get(sr.key))
    }
}
