import QtQuick
import QtQuick.Layouts
import qs

// Muted, wrapping hint text under a control or at the bottom of a tab.
Text {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    font.family: Theme.font
    font.pixelSize: Theme.fontSize - 2
    color: Theme.fgMuted
}
