import QtQuick
import Quickshell.Io
import qs
import qs.components

// Download and upload rate of the connected interface, from /proc/net/dev counters. It samples every
// 2 s only while `active` (bind it to the dropdown being open) and shows "–" until two samples exist.
Item {
    id: root
    property bool active: false
    property string iface: ""        // preferred interface; empty or missing falls back to the first with traffic

    property real down: -1           // bytes per second, -1 = not known yet
    property real up: -1
    property string lastIface: ""
    property real lastRx: -1
    property real lastTx: -1
    property real lastTime: 0

    implicitWidth: line.implicitWidth
    implicitHeight: line.implicitHeight

    Row {
        id: line
        spacing: 4

        Glyph {
            cp: 0xF01DA
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Theme.iconNudge
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.rate(root.down)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            color: Theme.fg
        }

        // gap between the download and upload halves
        Item {
            width: 8
            height: 1
        }

        Glyph {
            cp: 0xF0552
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Theme.iconNudge
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.rate(root.up)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            color: Theme.fg
        }
    }

    // one decimal below 10, whole numbers above, so the text stays short
    function rate(bps) {
        if (bps < 0)
            return "–";
        const units = ["B/s", "kB/s", "MB/s", "GB/s"];
        let v = bps;
        let i = 0;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return (i > 0 && v < 10 ? v.toFixed(1) : Math.round(v)) + " " + units[i];
    }

    // loopback and container bridges would otherwise win the fallback
    function pick(stats) {
        if (iface !== "" && stats[iface])
            return iface;
        for (const name in stats) {
            if (/^(lo|docker|veth|virbr|br-)/.test(name))
                continue;
            if (stats[name][0] + stats[name][1] > 0)
                return name;
        }
        return "";
    }

    function reset() {
        down = -1;
        up = -1;
        lastIface = "";
        lastRx = -1;
        lastTx = -1;
    }

    // columns after "name:" are rx bytes, 7 more rx counters, then tx bytes
    function ingest(raw) {
        if (!active)    // a sample that finishes after the dropdown closed would poison the next first one
            return;
        const stats = {};
        for (const line of raw.split("\n")) {
            const m = line.match(/^\s*([^:\s]+):\s*(.*)$/);
            if (!m)
                continue;
            const f = m[2].split(/\s+/);
            if (f.length >= 9)
                stats[m[1]] = [Number(f[0]), Number(f[8])];
        }
        const name = pick(stats);
        if (name === "") {
            reset();
            return;
        }
        const now = Date.now();
        const rx = stats[name][0];
        const tx = stats[name][1];
        // another interface or a counter that went backwards starts over instead of showing nonsense
        if (name === lastIface && lastRx >= 0 && rx >= lastRx && tx >= lastTx && now > lastTime) {
            const secs = (now - lastTime) / 1000;
            down = (rx - lastRx) / secs;
            up = (tx - lastTx) / secs;
        } else {
            down = -1;
            up = -1;
        }
        lastIface = name;
        lastRx = rx;
        lastTx = tx;
        lastTime = now;
    }

    onActiveChanged: {
        if (!active)
            reset();
    }

    Process {
        id: sample
        command: ["cat", "/proc/net/dev"]
        stdout: StdioCollector {
            onStreamFinished: root.ingest(text)
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: sample.running = true
    }
}
