import QtQuick
import QtQuick.Layouts
import qs

// Muted, wrapping hint text under a control or at the bottom of a tab. Plain text by default: it often shows
// text from outside (an imported line, a file name), which must never be read as markup; a hint written with
// markup sets textFormat: Text.StyledText itself.
Text {
    Layout.fillWidth: true
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    font.family: Theme.font
    font.pixelSize: Theme.fontSize - 2
    color: Theme.fgMuted
}
