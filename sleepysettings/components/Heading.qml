import QtQuick
import QtQuick.Layouts
import qs

// Section heading inside a settings tab.
Text {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter
    Layout.topMargin: 8
    font.family: Theme.font
    font.pixelSize: Theme.fontSize - 1
    font.bold: true
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1
    color: Theme.fgMuted
}
