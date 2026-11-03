import QtQuick
import qs

// One Nerd Font icon in a fixed, centred cell. Its family and size come from Theme (iconFont,
// iconSize), separate from the text font, so every icon on the bar has the same optical size and
// the same slot width. Set cp (a codepoint) for one icon, or text for several at once.
Text {
    property int cp: 0
    text: cp ? String.fromCodePoint(cp) : ""
    width: Math.max(Theme.iconCell, contentWidth)
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    font.family: Theme.iconFont
    font.pixelSize: Theme.iconSize
    color: Theme.fg
}
