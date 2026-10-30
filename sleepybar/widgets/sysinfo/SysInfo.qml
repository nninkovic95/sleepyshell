import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.components
import qs.sleepybar.components

// CPU and memory percentages from /proc, sampled every 2 s (ironbar sys_info replacement).
// With hoverPanel on, hovering them opens a detail panel (SysInfoPanel) under the island. Off:
// the readout sits beside the clock and the opened centre island shows that panel
// (no hover action); `qs -c sleepyshell ipc call sleepybar toggle sysinfo` still opens it.
RowLayout {
    id: root
    required property var bar
    property bool hoverPanel: false
    property int cpu: 0
    property int mem: 0
    property real prevIdle: 0
    property real prevTotal: 0
    spacing: Theme.gap
    // fill the island row's height, so the hover area is the whole button band and not just the text
    Layout.fillHeight: true

    function parse(out) {
        const lines = out.trim().split("\n");
        const f = lines[0].trim().split(/\s+/).slice(1).map(Number);
        const idle = f[3] + f[4];
        const total = f.reduce((a, b) => a + b, 0);
        const dTotal = total - prevTotal;
        const dIdle = idle - prevIdle;
        if (prevTotal > 0 && dTotal > 0)
            cpu = Math.round(100 * (1 - dIdle / dTotal));
        prevTotal = total;
        prevIdle = idle;

        let memTotal = 0, memAvail = 0;
        for (const line of lines.slice(1)) {
            const m = line.match(/^(\w+):\s+(\d+)/);
            if (!m)
                continue;
            if (m[1] === "MemTotal")
                memTotal = Number(m[2]);
            else if (m[1] === "MemAvailable")
                memAvail = Number(m[2]);
        }
        if (memTotal > 0)
            mem = Math.round(100 * (memTotal - memAvail) / memTotal);
    }

    Process {
        id: sampler
        command: ["sh", "-c", "head -n1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: sampler.running = true
    }

    // each figure keeps the width of "100%", so the island does not jitter when a digit comes or goes
    // (the glyph has its own fixed cell, so only the figure is measured)
    TextMetrics {
        id: widest
        font.family: Theme.font
        font.pixelSize: Theme.barFontSize
        text: "100%"
    }

    // figure first, then the glyph
    Row {
        spacing: 4
        Layout.preferredWidth: Math.ceil(widest.width) + spacing + Math.max(Theme.iconCell, Theme.barIconSize + 4)

        Text {
            width: Math.ceil(widest.width)
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: root.cpu + "%"
            font.family: Theme.font
            font.pixelSize: Theme.barFontSize
            color: Theme.fg
        }

        Glyph {
            cp: 0xF035B // nf-md-memory (draws a processor chip)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Theme.iconNudge
            font.pixelSize: Theme.barIconSize
        }
    }

    Row {
        spacing: 4
        Layout.preferredWidth: Math.ceil(widest.width) + spacing + Math.max(Theme.iconCell, Theme.barIconSize + 4)

        Text {
            width: Math.ceil(widest.width)
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: root.mem + "%"
            font.family: Theme.font
            font.pixelSize: Theme.barFontSize
            color: Theme.fg
        }

        Glyph {
            cp: 0xF061A // nf-md-chip (draws a memory stick)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Theme.iconNudge
            font.pixelSize: Theme.barIconSize
        }
    }

    // Hover opens the panel; leaving both the figures and the panel closes it after a moment, so
    // the pointer can cross the gap between the island and the panel. (The panel sits below the
    // bar, so it never opens under the pointer.)
    HoverHandler {
        id: figuresHover
        onHoveredChanged: {
            if (hovered) {
                leaveTimer.stop();
                if (root.hoverPanel)
                    pop.open = true;
            } else {
                leaveTimer.restart();
            }
        }
    }

    Timer {
        id: leaveTimer
        interval: 350
        onTriggered: {
            if (!figuresHover.hovered && !pop.hovered)
                pop.open = false;
        }
    }

    Connections {
        target: pop

        function onHoveredChanged() {
            if (pop.hovered)
                leaveTimer.stop();
            else
                leaveTimer.restart();
        }
    }

    IslandDropdown {
        id: pop
        hover: true
        name: "sysinfo"
        fixedWidth: 300
        anchorItem: root
        bar: root.bar

        SysInfoPanel {
            active: pop.open
            cpu: root.cpu
        }
    }
}
