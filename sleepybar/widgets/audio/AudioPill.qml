import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services
import qs.sleepybar.components

// Speaker and microphone side by side. Each half: click opens the dropdown (output panel above
// input panel), right click mutes, scroll changes ±5 %. Middle click on the speaker: mixer.
// dropdown: false (it sits beside the clock): a click emits openRequested instead, and
// the control centre shows the audio panels; `qs -c sleepyshell ipc call sleepybar toggle audio` still opens it.
Item {
    id: root
    required property var bar
    property bool dropdown: true
    signal openRequested()

    function primary() {
        if (dropdown)
            pop.toggle();
        else
            openRequested();
    }
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.buttonHeight

    // one highlight for both halves: hovering either, or the open dropdown
    Highlight {
        anchors.fill: parent
        // no hover highlight beside the clock (dropdown false): a click there only opens the centre island
        color: (pop.open || (root.dropdown && (spk.hovered || mic.hovered))) ? Theme.hoverBg : "transparent"
    }

    // both halves keep the width of "100%" plus the glyph, so the pill (and the island) does not jitter per digit
    TextMetrics {
        id: widest
        font.family: Theme.font
        font.pixelSize: Theme.barFontSize
        text: "100%"
    }

    Row {
        id: row
        spacing: 0

        BarButton {
            id: spk
            hoverBg: "transparent"
            lift: false    // no lift on audio levels
            // beside the clock hovering opens the control centre already, so no hand there
            handCursor: root.dropdown
            glyph: Audio.sinkGlyph()
            text: Math.round(Audio.volume * 100) + "%"
            fg: Audio.muted ? Theme.fgMuted : Theme.fg
            hpad: 6
            minWidth: Math.ceil(widest.width) + 4 + Theme.iconCell + hpad * 2
            onClicked: button => {
                if (button === Qt.RightButton)
                    Audio.toggleMute();
                else if (button === Qt.MiddleButton)
                    Quickshell.execDetached(["pwvucontrol"]);
                else
                    root.primary();
            }
            onScrolled: d => Audio.step(d > 0 ? 0.05 : -0.05)
        }

        BarButton {
            id: mic
            hoverBg: "transparent"
            lift: false    // no lift on audio levels
            // beside the clock hovering opens the control centre already, so no hand there
            handCursor: root.dropdown
            glyph: Audio.micGlyph()
            text: Math.round(Audio.micVolume * 100) + "%"
            fg: Audio.micMuted ? Theme.fgMuted : Theme.fg
            hpad: 6
            minWidth: Math.ceil(widest.width) + 4 + Theme.iconCell + hpad * 2
            onClicked: button => {
                if (button === Qt.RightButton)
                    Audio.toggleMicMute();
                else
                    root.primary();
            }
            onScrolled: d => Audio.stepMic(d > 0 ? 0.05 : -0.05)
        }
    }

    IslandDropdown {
        id: pop
        name: "audio"
        fixedWidth: 340
        anchorItem: root
        bar: root.bar

        AudioPanel {
            input: false
            showMixer: false
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 4
            implicitHeight: 1
            color: Theme.containerHighest
        }

        AudioPanel {
            input: true
        }
    }
}
