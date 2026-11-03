import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// Settings tab: what this machine is, read-only. It runs
// scripts/sysinfo.py, which prints one JSON object (OS, kernel, CPU, GPU, memory, disks,
// displays, versions) in about 0.1 s, each time the tab is shown and on Refresh. It has no
// group, stages nothing and never goes dirty, so the Apply bar stays away on this tab. The rows
// are ReadoutRows, so the sidebar search finds both labels and values. Copy puts the same
// text on the clipboard.
// Reset is at the bottom of the Config tab: this tab is read-only information.
TabPage {
    id: tab
    key: "system"
    label: "System"
    icon: 0xF02FD

    // the parsed script output, null until the first read finishes
    property var info: null
    property bool failed: false
    readonly property bool shown: tab.visible

    onShownChanged: if (tab.shown)
        tab.refresh()

    function refresh() {
        if (!reader.running)
            reader.running = true;
    }

    // 1 byte -> "1 B", then KiB, MiB, GiB, TiB with one decimal
    function bytes(n) {
        const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
        let v = Number(n) || 0;
        let u = 0;
        while (v >= 1024 && u < units.length - 1) {
            v /= 1024;
            u++;
        }
        return u === 0 ? v + " B" : v.toFixed(1) + " " + units[u];
    }

    // seconds -> "5 h 21 min", "2 d 3 h 4 min", "12 min"
    function span(s) {
        const m = Math.floor((Number(s) || 0) / 60);
        const d = Math.floor(m / 1440);
        const h = Math.floor((m % 1440) / 60);
        const mi = m % 60;
        const out = [];
        if (d > 0)
            out.push(d + " d");
        if (d > 0 || h > 0)
            out.push(h + " h");
        out.push(mi + " min");
        return out.join(" ");
    }

    function usage(have, total) {
        return tab.bytes(have) + " / " + tab.bytes(total);
    }

    function frac(have, total) {
        return total > 0 ? have / total : 0;
    }

    // the missing field's row says so instead of showing nothing
    function val(v) {
        return v === undefined || v === null || v === "" ? "Unknown" : String(v);
    }

    // sections of rows { label, value, fraction } built from the script's JSON
    readonly property var sections: {
        const i = tab.info;
        if (!i)
            return [];
        const cpu = i.cpu ?? {};
        const mem = i.memory ?? {};
        const gpus = i.gpus ?? [];
        const disks = i.disks ?? [];
        const displays = i.displays ?? [];
        // without lspci the script can only print the cards' PCI ids; say so beside them (not greyed: it works)
        const gpuNote = Deps.has("lspci") ? "" : "  ·  PCI id (lspci is not installed)";
        const numbered = (name, list, map) => list.length === 0 ? [
            {
                label: name,
                value: "None found",
                fraction: -1
            }
        ] : list.map((x, n) => ({
                    label: list.length > 1 ? name + " " + (n + 1) : name,
                    value: map(x),
                    fraction: -1
                }));
        const swap = mem.swapTotal > 0 ? {
            label: "Swap",
            value: tab.usage(mem.swapUsed, mem.swapTotal),
            fraction: tab.frac(mem.swapUsed, mem.swapTotal)
        } : {
            label: "Swap",
            value: "None",
            fraction: -1
        };
        // three cards (the software rows joined the operating system); the Reset actions are
        // the Advanced fold below. "Machine" is the board and vendor from DMI, not the host name.
        // The displays sit in Hardware after the GPU, the last card is only the storage.
        return [
            {
                title: "System",
                rows: [
                    { label: "OS", value: tab.val(i.os), fraction: -1 },
                    { label: "Machine", value: tab.val(i.host), fraction: -1 },
                    { label: "Kernel", value: tab.val(i.kernel), fraction: -1 },
                    { label: "Uptime", value: i.uptime === undefined ? "Unknown" : tab.span(i.uptime), fraction: -1 },
                    { label: "Hyprland", value: tab.val(i.hyprland), fraction: -1 },
                    { label: "Quickshell", value: tab.val(i.quickshell), fraction: -1 },
                    { label: "Login shell", value: tab.val(i.shell), fraction: -1 }
                ]
            },
            {
                title: "Hardware",
                rows: [
                    { label: "CPU", value: tab.val(cpu.model), fraction: -1 },
                    { label: "CPU threads", value: tab.val(cpu.threads), fraction: -1 },
                    { label: "CPU max clock", value: tab.val(cpu.maxClock), fraction: -1 }
                ].concat(numbered("GPU", gpus, g => g + gpuNote)).concat(numbered("Display", displays, d => d)).concat([
                    {
                        label: "Memory",
                        value: tab.usage(mem.used, mem.total),
                        fraction: tab.frac(mem.used, mem.total)
                    },
                    swap
                ])
            },
            {
                title: "Storage",
                rows: disks.length === 0 ? [
                    { label: "Disks", value: "None found", fraction: -1 }
                ] : disks.map(d => ({
                            label: d.mount,
                            value: d.fs + "  ·  " + tab.usage(d.used, d.total),
                            fraction: tab.frac(d.used, d.total)
                        }))
            }
        ];
    }

    // the same, as plain text for the clipboard
    readonly property string plainText: tab.sections.map(s => s.title + "\n" + s.rows.map(r => "  " + r.label + ": " + r.value).join("\n")).join("\n\n")

    Process {
        id: reader
        command: ["python3", Quickshell.shellPath("scripts/sysinfo.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    tab.info = JSON.parse(text);
                    tab.failed = false;
                } catch (e) {
                    tab.failed = true;
                }
            }
        }
        onExited: code => {
            if (code !== 0)
                tab.failed = true;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        SmallText {
            Layout.alignment: Qt.AlignVCenter
            text: tab.failed ? "Could not read the system information." : tab.info ? "" : "Reading…"
            color: tab.failed ? Theme.urgentFg : Theme.fgMuted
        }

        Item {
            Layout.fillWidth: true
        }

        BarButton {
            text: "Copy as text"
            glyph: 0xF018F
            glyphFirst: true
            glued: false
            bg: Theme.tileBg
            enabled: tab.info !== null
            opacity: enabled ? 1 : 0.5
            onClicked: Quickshell.clipboardText = tab.plainText
        }

        BarButton {
            text: "Refresh"
            glyph: 0xF0450
            glyphFirst: true
            glued: false
            bg: Theme.tileBg
            opacity: reader.running ? 0.5 : 1
            onClicked: tab.refresh()
        }
    }

    // fixed height, it scrolls (the window is as tall as the tallest page, like the Display tab)
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 268

        Flickable {
            id: flick
            anchors.fill: parent
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // a tip belongs to what is under the pointer; it does not follow the content out of sight
            onMovingChanged: if (moving && tab.tooltip) tab.tooltip.dismiss()

            ColumnLayout {
                id: col
                // room for the scroll mark only when the page scrolls, so the cards line up with the other tabs'
                width: flick.width - (flick.contentHeight > flick.height ? 10 : 0)
                spacing: 8

                Repeater {
                    model: tab.sections

                    Section {
                        id: sec
                        required property var modelData
                        title: sec.modelData.title

                        Repeater {
                            model: sec.modelData.rows

                            ReadoutRow {
                                required property var modelData
                                label: modelData.label
                                value: modelData.value
                                fraction: modelData.fraction
                            }
                        }
                    }
                }
            }
        }

        // scroll position, shown only when the page is taller than the view
        Rectangle {
            visible: flick.contentHeight > flick.height
            anchors.right: flick.right
            y: flick.visibleArea.yPosition * flick.height
            width: 3
            height: Math.max(20, flick.visibleArea.heightRatio * flick.height)
            radius: width / 2
            color: Theme.trackBg
        }
    }
}
