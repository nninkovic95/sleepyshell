import QtQuick
import QtQuick.Layouts
import qs

// A read-only SettingRow: the label, then a value as text, and optionally a thin usage bar
// (`fraction` 0 to 1; -1 for none). The value is part of the row's search text, so the settings
// search finds "btrfs" or "Hyprland" as well as the label. Used by the System tab; no key, so
// there is no reset button or unapplied mark.
SettingRow {
    id: ro
    property string value: ""
    property real fraction: -1
    // a low fraction is the bad end (a battery's charge), not a high one (a disk's use)
    property bool lowIsBad: false
    tags: ro.value

    Text {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: ro.value
        textFormat: Text.PlainText   // names come from the machine's firmware and EDID
        elide: Text.ElideRight
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fg
    }

    Rectangle {
        visible: ro.fraction >= 0
        Layout.preferredWidth: 140
        Layout.preferredHeight: 6
        Layout.alignment: Qt.AlignVCenter
        radius: height / 2
        color: Theme.trackBg

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, ro.fraction))
            height: parent.height
            radius: height / 2
            color: (ro.lowIsBad ? ro.fraction < 0.2 : ro.fraction > 0.9) ? Theme.urgentFg : Theme.primary
            Behavior on width {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
