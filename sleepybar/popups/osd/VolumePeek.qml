import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// The volume / microphone level row (or Caps Lock on/off) the clock island reveals under its
// title for a moment after a change (state in OsdState; shown through GrowingIsland.peek, which sizes it to the collapsed island).
Item {
    id: root
    implicitHeight: 18

    RowLayout {
        anchors.fill: parent
        spacing: 8

        Glyph {
            Layout.preferredWidth: 18
            cp: OsdState.glyph
            font.pixelSize: Theme.fontSize + 1
            color: OsdState.muted ? Theme.fgMuted : Theme.fg
        }

        Text {
            Layout.fillWidth: true
            visible: OsdState.capsLast
            text: CapsLock.on ? "Caps Lock on" : "Caps Lock off"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            color: Theme.fg
        }

        Rectangle {
            visible: !OsdState.capsLast
            Layout.fillWidth: true
            Layout.preferredHeight: 5
            radius: height / 2
            color: Theme.trackBg

            Rectangle {
                width: OsdState.level * parent.width
                height: parent.height
                radius: height / 2
                color: OsdState.muted ? Theme.fgMuted : Theme.primary
            }
        }

        Text {
            visible: !OsdState.capsLast
            Layout.preferredWidth: 34
            horizontalAlignment: Text.AlignRight
            text: Math.round(OsdState.level * 100) + "%"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            color: Theme.fg
        }
    }
}
