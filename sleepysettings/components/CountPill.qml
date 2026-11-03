import QtQuick
import qs

// The "unapplied changes" marker (not an alarm, so not the red "!" that looked like
// the teal info tips): a small rounded pill in the accent colour with the number of unapplied changes
// (a dot for a tab with its own draft, which has no count). Used by the sidebar entries and the leave
// dialog. `on` is for a pill on the accent itself (the open tab's sidebar entry), where it turns light.
Rectangle {
    id: pill
    property int count: 0
    property bool on: false
    readonly property string label: pill.count > 0 ? String(pill.count) : "•"
    implicitWidth: Math.max(height, markText.implicitWidth + 10)
    implicitHeight: 18
    radius: Theme.radiusXs
    color: pill.on ? Qt.alpha(Theme.accentFg, 0.22) : Qt.alpha(Theme.primary, 0.2)

    Text {
        id: markText
        anchors.centerIn: parent
        text: pill.label
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
        font.weight: Font.Medium
        color: pill.on ? Theme.accentFg : Theme.primary
    }
}
