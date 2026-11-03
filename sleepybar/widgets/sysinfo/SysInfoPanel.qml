import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs

// Body of the CPU / memory hover panel (see SysInfo): usage with a thin track bar under it, load,
// memory, storage (the system disk, /), and the CPU, GPU
// and NVMe temperatures. One sh run every 2 s, and only while the
// panel is open (`active`); the CPU percentage comes from SysInfo's own sampler, which runs anyway.
ColumnLayout {
    id: root
    property bool active: false
    property int cpu: 0
    // sizes in kB as /proc/meminfo gives them; temps maps "<hwmon name> <label>" to °C
    property string loadAvg: ""
    property real memTotal: 0
    property real memUsed: 0
    property real diskTotal: 0
    property real diskUsed: 0
    property var temps: ({})
    // the NVMe drive rows; the control centre leaves them out so its left column ends with the
    // audio column
    property bool drives: true
    readonly property var nvmeKeys: Object.keys(temps).filter(k => k.startsWith("nvme Composite")).sort()
    spacing: 6
    Layout.fillWidth: true

    // Only the sensors named here are printed, and one that cannot be read just drops its line.
    // An NVMe hwmon number does not follow the nvme number (hwmon1 is nvme1, hwmon2 is nvme0 here),
    // so the device node is appended to the label.
    readonly property string script: [
        'exec 2>/dev/null; cat /proc/loadavg',
        'grep -E "^(MemTotal|MemAvailable):" /proc/meminfo',
        // the root filesystem in kB, printed like the meminfo lines so the same parser reads it
        'df -kP / | awk \'NR == 2 { print "DiskTotal: " $2; print "DiskUsed: " $3 }\'',
        'for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name); d=',
        '  case $n in nvme) d=" $(basename $(readlink -f $h/device))" ;; k10temp|amdgpu) ;; *) continue ;; esac',
        '  for f in $h/temp*_input; do echo "TEMP $n $(cat ${f%_input}_label)$d $(cat $f)"; done',
        'done'
    ].join("\n")

    // "" when the sensor is missing, which hides its row
    function deg(key, suffix) {
        const c = temps[key];
        return c === undefined ? "" : Math.round(c) + " °C" + suffix;
    }

    function parse(out) {
        const kb = {}, t = {};
        for (const line of out.split("\n")) {
            let m;
            if ((m = line.match(/^(\d+\.\d+ \d+\.\d+ \d+\.\d+) /)))
                loadAvg = m[1];
            else if ((m = line.match(/^(\w+):\s+(\d+)/)))
                kb[m[1]] = Number(m[2]);
            else if ((m = line.match(/^TEMP (\S+ .+) (-?\d+)$/)))
                t[m[1]] = Number(m[2]) / 1000;
        }
        memTotal = kb.MemTotal ?? 0;
        memUsed = memTotal - (kb.MemAvailable ?? 0);
        diskTotal = kb.DiskTotal ?? 0;
        diskUsed = kb.DiskUsed ?? 0;
        temps = t;
    }

    Process {
        id: sampler
        command: ["sh", "-c", root.script]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: sampler.running = true
    }

    component Cell: Text {
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fg
    }

    // one row: muted label, value, a right-aligned note, and an optional track bar underneath;
    // a row with no value and no note is hidden
    component Metric: ColumnLayout {
        id: m
        property string label
        property string value
        property string note
        property real frac: -1    // 0..1 draws the track under the row, below 0 draws none
        visible: value !== "" || note !== ""
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Cell { Layout.preferredWidth: 56; text: m.label; color: Theme.fgMuted }
            Cell { text: m.value }
            Cell { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: m.note; color: Theme.fgMuted }
        }

        // VSlider's track without the knob: this one is not interactive
        Rectangle {
            visible: m.frac >= 0
            Layout.fillWidth: true
            implicitHeight: 6
            radius: height / 2
            color: Theme.trackBg

            Rectangle {
                width: parent.width * Math.min(1, m.frac)
                height: parent.height
                radius: height / 2
                color: Theme.primary
            }
        }
    }

    // kB used of kB total shown in GiB with a percentage and the track; no total (df failed) hides the row
    component Meter: Metric {
        property real used: 0
        property real total: 0
        value: total > 0 ? (used / 1048576).toFixed(1) + " / " + (total / 1048576).toFixed(1) + " GiB" : ""
        note: total > 0 ? Math.round(100 * used / total) + "%" : ""
        frac: total > 0 ? used / total : -1
    }

    Metric {
        label: "CPU"
        value: root.cpu + "%"
        note: root.loadAvg !== "" ? "load " + root.loadAvg : ""
        frac: root.cpu / 100
    }

    Meter { label: "Memory"; used: root.memUsed; total: root.memTotal }
    Meter { label: "Storage"; used: root.diskUsed; total: root.diskTotal }

    Rectangle {
        Layout.fillWidth: true
        Layout.margins: 4
        implicitHeight: 1
        color: Theme.containerHighest
    }

    Cell { Layout.leftMargin: 4; text: "Temperatures"; font.bold: true }
    Metric { label: "CPU"; value: root.deg("k10temp Tctl", "") }
    Metric { label: "GPU"; value: root.deg("amdgpu edge", " edge"); note: root.deg("amdgpu junction", " junction") }

    // the count only changes when a drive appears; the key is looked up per index so a delegate
    // that outlives a shrinking list just goes blank
    Repeater {
        model: root.drives ? root.nvmeKeys.length : 0

        Metric {
            label: (root.nvmeKeys[index] ?? "").split(" ").pop()
            value: root.deg(root.nvmeKeys[index] ?? "", "")
        }
    }
}
