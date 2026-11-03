import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components

// A shell command the user has to run by hand (the monitor setup guide), in a muted box with a Copy button
// The command is plain text: it wraps, it is never run from here.
Rectangle {
    id: cl
    property string command: ""
    property bool copied: false
    Layout.fillWidth: true
    implicitHeight: Math.max(34, txt.implicitHeight + 16)
    radius: Theme.radiusSm
    color: Theme.tileBg

    function copy() {
        Quickshell.clipboardText = cl.command;
        cl.copied = true;
        back.restart();
    }

    Timer {
        id: back
        interval: 1400
        onTriggered: cl.copied = false
    }

    Text {
        id: txt
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - btn.width - 22
        text: cl.command
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
        color: Theme.fg
    }

    BarButton {
        id: btn
        objectName: "copyButton"
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        glued: false
        glyph: 0xF018F
        text: cl.copied ? "Copied" : "Copy"
        onClicked: cl.copy()
    }
}
