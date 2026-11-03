pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Screen brightness of a laptop panel). Reads /sys/class/backlight/<device>/
// brightness and max_brightness, writes through logind's Session.SetBrightness, which lets the
// active session set a backlight without root (no brightnessctl, no udev rule). `available` is
// false on this desktop (no backlight), and the slider and the Power tab's Screen row stay hidden.
// `simulate` replaces the sysfs reading for tests: { device: "name", max: n, value: n }.
// sysfs does not notify on a change made by someone else (a brightness key handled by the firmware),
// so the value is read again every few seconds while a backlight exists.
//
// External monitors over DDC/CI, through scripts/ddc.py: `list` once at start and on every
// screen change, `get` on demand (the control centre opening calls readDdc), `set` throttled per bus: one
// write in flight, the latest value wins, 150 ms between writes (DDC is slow, about a second per write).
// Per output the level is 0..100 (ddcLevel, -1 until read); `rows` is what the control centre draws: the
// laptop backlight (when present) and one entry per DDC monitor, with `ok`/`reason` for the greyed ones.
// `ddcCommand` is the command prefix that is run with list/get/set appended; tests point it at a fake
// script, so nothing real is written.
Singleton {
    id: root

    property var simulate: null
    readonly property var sim: root.simulate

    // the panel's name under /sys/class/backlight ("" for none)
    property string realDevice: ""
    property int realMax: 0
    property int realRaw: 0
    readonly property string device: root.sim ? (root.sim.device ?? "") : root.realDevice
    readonly property int max: root.sim ? (root.sim.max ?? 0) : root.realMax
    readonly property int raw: root.sim ? (root.sim.value ?? 0) : root.realRaw
    readonly property bool available: root.device !== "" && root.max > 0
    // 0..1
    readonly property real level: root.max > 0 ? Math.max(0, Math.min(1, root.raw / root.max)) : 0
    // never below 2 % of the range: at 0 many panels are fully dark and there is no way back to see the slider
    readonly property int floorRaw: Math.max(1, Math.ceil(root.max * 0.02))

    // set the brightness (0..1) of the panel
    function set(level) {
        // the write is a busctl call to logind; without busctl nothing is changed or shown as changed
        if (!root.available || !Deps.has("busctl"))
            return;
        const v = Math.max(root.floorRaw, Math.min(root.max, Math.round(level * root.max)));
        if (root.sim)
            root.simulate = Object.assign({}, root.sim, { value: v });
        else
            root.realRaw = v;
        root.queued = v;
        if (writeGap.running)
            root.waiting = true;
        else
            root.flush();
    }

    // writes go out at most every 60 ms, the last value always: a slider drag makes dozens of them
    property int queued: -1
    property bool waiting: false

    function flush() {
        root.waiting = false;
        root.write("backlight", root.device, root.queued);
        writeGap.restart();
    }

    // the backlight write; DDC outputs have their own queue (workers below)
    function write(kind, id, value) {
        if (kind === "backlight")
            Quickshell.execDetached(["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", id, String(value)]);
    }

    Timer {
        id: writeGap
        interval: 60
        onTriggered: if (root.waiting)
            root.flush()
    }

    // ---- external monitors over DDC/CI ----
    property var ddcCommand: ["python3", Quickshell.shellPath("scripts/ddc.py")]
    // pause between two writes to one bus
    property int ddcSpacing: 150
    readonly property string ddcCode: "0x10"
    readonly property bool ddcUsable: Deps.has("python3")

    // [{ output: "DP-1", bus: 5, model: "...", access: true, pct: -1..100, max: 100, error: "" }]
    property var ddc: []
    // the buses that get a worker (a write queue each), changed only when the set changes
    property var ddcBuses: []
    property var workers: ({})

    function refreshDdc() {
        if (root.ddcUsable && !lister.running)
            lister.running = true;
    }

    function gotList(text) {
        let l = [];
        try {
            l = JSON.parse(text);
        } catch (e) {
            l = [];
        }
        if (!Array.isArray(l))
            l = [];
        const old = root.ddc;
        const next = l.filter(m => m && typeof m.output === "string" && Number.isInteger(m.bus)).map(m => {
            const o = old.find(x => x.output === m.output && x.bus === m.bus);
            return {
                output: m.output,
                bus: m.bus,
                model: m.model ?? "",
                access: m.access === true,
                pct: o ? o.pct : -1,
                max: o ? o.max : 100,
                error: ""
            };
        });
        if (JSON.stringify(next) !== JSON.stringify(old))
            root.ddc = next;
        const buses = next.filter(m => m.access).map(m => m.bus);
        if (JSON.stringify(buses) !== JSON.stringify(root.ddcBuses))
            root.ddcBuses = buses;
    }

    // change fields of one monitor's entry (a new array, so bindings update)
    function patchDdc(bus, fields) {
        root.ddc = root.ddc.map(m => m.bus === bus ? Object.assign({}, m, fields) : m);
    }

    // read every reachable monitor's level, now (the control centre opened)
    function readDdc() {
        for (const b of root.ddcBuses)
            root.workers[b]?.read();
    }

    // 0..100, -1 while unknown
    function ddcLevel(output) {
        return root.ddc.find(m => m.output === output)?.pct ?? -1;
    }

    function setDdc(output, pct) {
        const m = root.ddc.find(x => x.output === output);
        if (!m || !m.access || !root.ddcUsable)
            return;
        const v = Math.max(0, Math.min(100, Math.round(pct)));
        root.patchDdc(m.bus, { pct: v });
        root.workers[m.bus]?.request(v);
    }

    // the label of a monitor: its EDID model, else the output name; the output is added when two share a model
    function ddcLabel(m) {
        const base = m.model !== "" ? m.model : m.output;
        return root.ddc.filter(x => (x.model !== "" ? x.model : x.output) === base).length > 1 ? base + " (" + m.output + ")" : base;
    }

    // what the control centre draws, in order: { kind, id, label, level 0..1 (-1 unknown), ok, reason }
    readonly property var rows: {
        const r = [];
        if (root.available) {
            const miss = Deps.needs(["busctl"]);
            r.push({ kind: "backlight", id: "backlight", label: "Laptop display", level: root.level, ok: miss === "", reason: miss });
        }
        for (const m of root.ddc) {
            let reason = "";
            if (!root.ddcUsable)
                reason = Deps.needs(["python3"]);
            else if (!m.access)
                reason = "No DDC access to the monitor";
            else if (m.error !== "")
                reason = m.error;
            r.push({ kind: "ddc", id: m.output, label: root.ddcLabel(m), level: m.pct < 0 ? -1 : m.pct / 100, ok: m.access && root.ddcUsable, reason: reason });
        }
        return r;
    }
    readonly property bool anyOutput: root.rows.length > 0

    // one slider of the control centre or the Power tab: the backlight or a DDC output
    function setOutput(kind, id, level) {
        if (kind === "backlight")
            root.set(level);
        else
            root.setDdc(id, level * 100);
    }

    Process {
        id: lister
        command: root.ddcCommand.concat(["list"])
        stdout: StdioCollector {
            onStreamFinished: root.gotList(text)
        }
    }

    // monitors come and go with the screens; a burst of events is one listing
    Connections {
        target: Quickshell
        function onScreensChanged() {
            relist.restart();
        }
    }
    Timer {
        id: relist
        interval: 600
        onTriggered: root.refreshDdc()
    }
    Component.onCompleted: root.refreshDdc()

    // one worker per reachable bus: its reads and its throttled writes
    Variants {
        model: root.ddcBuses

        QtObject {
            id: w
            required property int modelData
            readonly property int bus: w.modelData
            property int queued: -1
            property bool waiting: false

            // the monitor's own 0..max range (100 on nearly all)
            function maxOf() {
                return root.ddc.find(m => m.bus === w.bus)?.max ?? 100;
            }

            function busy() {
                return setter.running || gap.running || w.waiting;
            }

            function read() {
                if (!getter.running && !w.busy())
                    getter.running = true;
            }

            // a slider drag makes dozens of these: one write goes out, the rest collapse to the latest
            function request(pct) {
                w.queued = pct;
                if (setter.running || gap.running)
                    w.waiting = true;
                else
                    w.flush();
            }

            function flush() {
                w.waiting = false;
                setter.command = root.ddcCommand.concat(["set", String(w.bus), root.ddcCode, String(Math.round(w.queued / 100 * w.maxOf()))]);
                setter.running = true;
            }

            function gotLevel(text) {
                // a value still on its way out is newer than this reading
                if (w.busy())
                    return;
                let r = null;
                try {
                    r = JSON.parse(text);
                } catch (e) {
                    r = null;
                }
                if (r && typeof r.current === "number" && r.max > 0)
                    root.patchDdc(w.bus, { pct: Math.round(r.current / r.max * 100), max: r.max, error: "" });
                else
                    root.patchDdc(w.bus, { error: "The monitor does not answer" });
            }

            Component.onCompleted: root.workers[w.bus] = w
            Component.onDestruction: delete root.workers[w.bus]

            property Process getter: Process {
                command: root.ddcCommand.concat(["get", String(w.bus), root.ddcCode])
                stdout: StdioCollector {
                    onStreamFinished: w.gotLevel(text)
                }
            }
            property Process setter: Process {
                onExited: gap.restart()
            }
            property Timer gap: Timer {
                interval: root.ddcSpacing
                onTriggered: if (w.waiting)
                    w.flush()
            }
        }
    }

    // ---- reading sysfs ----
    Process {
        // one device name: type raw first, then platform, then firmware (the kernel's own order of
        // preference); an unknown type counts last
        command: ["sh", "-c", "for t in raw platform firmware ''; do for d in /sys/class/backlight/*; do [ -e \"$d/brightness\" ] || continue; if [ -z \"$t\" ] || [ \"$(cat \"$d/type\" 2>/dev/null)\" = \"$t\" ]; then basename \"$d\"; exit; fi; done; done"]
        running: true
        stdout: StdioCollector {
            // the best device by type (see the command)
            onStreamFinished: root.realDevice = text.trim().split("\n")[0]
        }
    }

    FileView {
        id: maxFile
        path: root.realDevice !== "" ? "/sys/class/backlight/" + root.realDevice + "/max_brightness" : ""
        printErrors: false
        onLoaded: root.realMax = parseInt(text()) || 0
    }

    FileView {
        id: curFile
        path: root.realDevice !== "" ? "/sys/class/backlight/" + root.realDevice + "/brightness" : ""
        printErrors: false
        onLoaded: {
            // a value we just wrote may not be applied yet; do not jump back to the old one
            if (!writeGap.running && !root.waiting)
                root.realRaw = parseInt(text()) || 0;
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.realDevice !== "" && !root.sim
        onTriggered: curFile.reload()
    }
}
