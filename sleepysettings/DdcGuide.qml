import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// The setup guide of a monitor that cannot be controlled yet: the section is greyed and the guide explains why.
// kind: "nomodule" (no /dev/i2c-N: the kernel module is not loaded), "noaccess" (the nodes exist but this user cannot
// open them: a udev rule built from the bus adapter's real name), "off" (the monitor does not answer: DDC/CI is off in its
// own menu). Each command has its own Copy button; "Check again" reads the buses and the monitor again.
ColumnLayout {
    id: g
    property string kind: ""
    // the i2c buses of the monitors this guide is for (the udev rule matches their adapters)
    property var buses: []
    readonly property var patterns: MonitorCtl.patternsFor(g.buses)
    readonly property string ruleCmd: MonitorCtl.ruleCommand(g.patterns)
    readonly property string title: g.kind === "nomodule" ? "Monitor control needs the i2c-dev kernel module." : g.kind === "noaccess" ? "This user cannot reach the monitor's control channel." : "The monitor does not answer."
    readonly property string text: g.kind === "nomodule" ? "Run these two commands in a terminal, then press Check again." : g.kind === "noaccess" ? (g.ruleCmd !== "" ? "A small rule lets the person at the screen use it. Run these three commands in a terminal, then press Check again." : "The name of this monitor's connection could not be read, so no rule can be written here.") : "Turn on DDC/CI in the monitor's own menu (often under System, Setup or Other), then press Check again."

    Layout.fillWidth: true
    spacing: 6

    Text {
        objectName: "guideTitle"
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: g.title
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.bold: true
        color: Theme.fg
    }

    SmallText {
        objectName: "guideText"
        text: g.text
    }

    CommandLine {
        visible: g.kind === "nomodule"
        command: "sudo modprobe i2c-dev"
    }
    CommandLine {
        visible: g.kind === "nomodule"
        command: "echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf"
    }

    CommandLine {
        visible: g.kind === "noaccess" && g.ruleCmd !== ""
        command: g.ruleCmd
    }
    CommandLine {
        visible: g.kind === "noaccess" && g.ruleCmd !== ""
        command: "sudo udevadm control --reload"
    }
    CommandLine {
        visible: g.kind === "noaccess" && g.ruleCmd !== ""
        command: "sudo udevadm trigger --subsystem-match=i2c-dev"
    }

    RowLayout {
        Layout.fillWidth: true

        BarButton {
            objectName: "checkAgain"
            glued: false
            glyph: 0xF0450
            text: "Check again"
            bg: Theme.tileBg
            onClicked: MonitorCtl.checkAgain()
        }

        Item {
            Layout.fillWidth: true
        }
    }
}
