pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Monitor controls over DDC/CI for the Display tab: everything beyond brightness. The monitors, the
// brightness reading and its throttled writes are Brightness.qml's (`Brightness.ddc`, `Brightness.setDdc`,
// `Brightness.ddcCommand`); this file adds, per monitor, the capabilities (`ddc.py caps BUS`, read once and cached),
// the current values of contrast, input source, colour preset, red/green/blue gain, volume and mute, and their writes.
// Every command goes through ONE queue, one at a time with `Brightness.ddcSpacing` between them (DDC is slow and a
// bus handles one request at a time); a write that waits in the queue is replaced by a newer write of the same
// feature, so a slider drag makes one write per pause, the last value always. A job on a bus that
// Brightness's own worker is using waits for it.
//
// Only the codes in `allowed` can ever be written. Factory reset (0x04, 0x05, 0x08) and power mode (0xD6) are not
// in it, so no caller can send them (never expose them).
//
// What the setup guide needs is here too: `stateOf(monitor)` says why a monitor cannot be controlled ("nomodule":
// no /dev/i2c-N at all; "noaccess": the nodes exist but this user cannot open them; "off": it opens but the monitor
// does not answer, DDC/CI is off in its menu), and `ruleCommand()` builds the udev rule from the bus adapter's
// real name (`ddc.py probe` reads /sys/bus/i2c/devices/i2c-N/name).
Singleton {
    id: root

    // true while the Display tab is open: nothing talks to a monitor before that
    property bool active: false

    // the features that may be written, by VCP code; brightness (0x10) is written by Brightness
    // (the red, green and blue gains 0x16, 0x18 and 0x1A are not offered: the Custom colour preset uses the values saved in the monitor)
    readonly property var allowed: [0x12, 0x14, 0x60]
    // read once when the capabilities arrive
    readonly property var readCodes: [0x10, 0x12, 0x14, 0x60]

    // VCP 0x60 input source names (MCCS)
    readonly property var inputNames: ({
            1: "VGA 1", 2: "VGA 2", 3: "DVI 1", 4: "DVI 2", 5: "Composite 1", 6: "Composite 2", 7: "S-Video 1", 8: "S-Video 2",
            9: "Tuner 1", 10: "Tuner 2", 11: "Tuner 3", 12: "Component 1", 13: "Component 2", 14: "Component 3",
            15: "DisplayPort 1", 16: "DisplayPort 2", 17: "HDMI 1", 18: "HDMI 2"
        })
    // VCP 0x14 colour preset names, as the MCCS standard numbers them; a monitor offers some of these
    readonly property var presetNames: ({
            1: "sRGB", 2: "Native", 3: "4000 K", 4: "5000 K", 5: "6500 K", 6: "7500 K", 7: "8200 K", 8: "9300 K",
            9: "10000 K", 10: "11500 K", 11: "Custom 1", 12: "Custom 2", 13: "Custom 3"
        })
    function inputLabel(v) {
        return root.inputNames[v] ?? ("Input " + v);
    }
    // 11, 12 and 13 are the monitor's own custom colour slots (MCCS "User 1" to "User 3"); they use the red, green and blue values saved in the monitor, which
    // are set in its own menu. A monitor that lists only one of them shows it as "Custom (your own red, green, blue)", one that lists several as "Custom 1 (your own red,
    // green, blue)", "Custom 2", "Custom 3". `output` says which monitor's list to count.
    function presetLabel(v, output) {
        if (v >= 11 && v <= 13) {
            const slots = output ? root.allowedValues(output, 0x14).filter(x => x >= 11 && x <= 13).length : 0;
            if (slots === 1)
                return "Custom (your own red, green, blue)";
            return root.presetNames[v] + (v === 11 ? " (your own red, green, blue)" : "");
        }
        return root.presetNames[v] ?? ("Preset " + v);
    }

    // ---- state ----
    // what `ddc.py probe` said: known once it answered
    property var probeInfo: ({ known: false, devices: true, adapters: {} })
    // output -> { key, state: "loading" | "ok" | "off", features: { "code": [allowed values] } }
    property var mons: ({})
    // output -> { "code": { current, max } }
    property var vals: ({})
    // output -> { "code": { current, max } } as the monitor had it when the Display tab was opened (the first reading of each value since
    // then): the revert arrow of a DDC row goes back to it. Emptied when the tab closes.
    property var baseline: ({})
    function base(output, code) {
        return root.baseline[output]?.[String(code)] ?? null;
    }
    // a live value that differs from its baseline (a slider by at least 1 %, a choice at all)
    function changedFromBase(output, code) {
        const b = root.base(output, code);
        const v = root.val(output, code);
        if (!b || !v)
            return false;
        return root.allowedValues(output, code).length > 0 ? v.current !== b.current : Math.abs(v.current / v.max - b.current / b.max) >= 0.01;
    }
    // put a value back to its baseline: through the queue like any write (brightness: through Brightness)
    function revertToBase(output, code) {
        const b = root.base(output, code);
        if (!b)
            return;
        if (code === 0x10)
            Brightness.setDdc(output, b.current / b.max * 100);
        else
            root.setValue(output, code, b.current);
    }
    // a short log of what was sent, for the tests: "set 7 0x12 40"
    property var sent: []

    function mon(output) {
        return root.mons[output] ?? null;
    }

    // the monitor can be controlled, or why not
    function stateOf(m) {
        if (!Brightness.ddcUsable)
            return "loading";
        if (root.probeInfo.known && !root.probeInfo.devices)
            return "nomodule";
        if (!m.access)
            return root.probeInfo.known ? "noaccess" : "loading";
        return root.mons[m.output]?.state ?? "loading";
    }

    function has(output, code) {
        const mm = root.mons[output];
        return !!mm && mm.state === "ok" && String(code) in mm.features;
    }

    function allowedValues(output, code) {
        return root.mons[output]?.features[String(code)] ?? [];
    }

    function val(output, code) {
        return root.vals[output]?.[String(code)] ?? null;
    }

    // current / max, 0 until read
    function frac(output, code) {
        const v = root.val(output, code);
        return v && v.max > 0 ? Math.max(0, Math.min(1, v.current / v.max)) : 0;
    }

    function setVal(output, code, entry) {
        const all = Object.assign({}, root.vals);
        all[output] = Object.assign({}, all[output] ?? {});
        all[output][String(code)] = entry;
        root.vals = all;
    }

    function setMon(output, fields) {
        const all = Object.assign({}, root.mons);
        all[output] = Object.assign({}, all[output] ?? {}, fields);
        root.mons = all;
    }

    // ---- writing ----
    // Set a feature of a monitor. A slider passes 0..1 as `frac`; a choice passes the code's own value.
    function setValue(output, code, value) {
        if (!root.allowed.includes(code) || !root.has(output, code))
            return false;
        const m = Brightness.ddc.find(x => x.output === output);
        if (!m || !m.access)
            return false;
        const cur = root.val(output, code);
        const range = root.allowedValues(output, code);
        let v = Math.round(value);
        if (range.length > 0) {
            // a choice: only what the monitor listed
            if (!range.includes(v))
                return false;
        } else {
            v = Math.max(0, Math.min(cur ? cur.max : 100, v));
        }
        root.setVal(output, code, { current: v, max: cur ? cur.max : 100 });
        root.enqueue({ kind: "set", bus: m.bus, output: output, code: code, value: v });
        return true;
    }

    // a slider's 0..1
    function setFrac(output, code, f) {
        const cur = root.val(output, code);
        return root.setValue(output, code, Math.max(0, Math.min(1, f)) * (cur ? cur.max : 100));
    }

    // ---- the queue ----
    property var jobs: []
    property var current: null

    function enqueue(job) {
        if (job.kind === "set")
            root.jobs = root.jobs.filter(j => !(j.kind === "set" && j.bus === job.bus && j.code === job.code));
        root.jobs = root.jobs.concat([job]);
        root.pump();
    }

    function hex(code) {
        return "0x" + code.toString(16).toUpperCase().padStart(2, "0");
    }

    function pump() {
        if (root.current || runner.running || gap.running || root.jobs.length === 0)
            return;
        const j = root.jobs[0];
        // brightness has its own worker on the same bus; wait for it
        if (Brightness.workers[j.bus]?.busy()) {
            retry.restart();
            return;
        }
        root.jobs = root.jobs.slice(1);
        // the last guard: a write of a code that is not allowed never leaves
        if (j.kind === "set" && !root.allowed.includes(j.code)) {
            root.pump();
            return;
        }
        root.current = j;
        const c = Brightness.ddcCommand;
        let cmd;
        if (j.kind === "caps")
            cmd = c.concat(["caps", String(j.bus)]);
        else if (j.kind === "get")
            cmd = c.concat(["get", String(j.bus), root.hex(j.code)]);
        else
            cmd = c.concat(["set", String(j.bus), root.hex(j.code), String(j.value)]);
        if (j.kind === "set")
            root.sent = root.sent.concat(["set " + j.bus + " " + root.hex(j.code) + " " + j.value]);
        runner.command = cmd;
        runner.running = true;
        watchdog.restart();
    }

    function finished(text) {
        watchdog.stop();
        const j = root.current;
        if (!j)
            return;
        root.current = null;
        root.handle(j, text);
        gap.restart();
    }

    // consecutive failed reads and writes per monitor: two in a row mean DDC/CI was switched off in the monitor's menu
    // (one dropped message is normal on a slow bus and is not shown as a fault)
    property var fails: ({})
    function noteResult(output, good) {
        const n = good ? 0 : (root.fails[output] ?? 0) + 1;
        root.fails[output] = n;
        if (n >= 2 && root.mons[output]?.state === "ok") {
            root.jobs = root.jobs.filter(x => x.output !== output);
            root.setMon(output, { state: "off" });
        }
    }

    function handle(j, text) {
        let r = null;
        try {
            r = JSON.parse(text);
        } catch (e) {
            r = null;
        }
        if (j.kind !== "caps")
            root.noteResult(j.output, j.kind === "get" ? !!r && typeof r.current === "number" : !(r && r.error));
        if (j.kind === "caps") {
            if (root.mons[j.output]?.key !== j.key)
                return;
            if (!r || r.error || !r.features || Object.keys(r.features).length === 0) {
                root.setMon(j.output, { state: "off", features: {} });
                return;
            }
            root.setMon(j.output, { state: "ok", features: r.features });
            for (const code of root.readCodes)
                if (String(code) in r.features)
                    root.enqueue({ kind: "get", bus: j.bus, output: j.output, code: code });
        } else if (j.kind === "get") {
            if (!r || typeof r.current !== "number" || !(r.max > 0))
                return;
            root.setVal(j.output, j.code, { current: r.current, max: r.max });
            if (!root.base(j.output, j.code)) {
                const all = Object.assign({}, root.baseline);
                all[j.output] = Object.assign({}, all[j.output] ?? {});
                all[j.output][String(j.code)] = { current: r.current, max: r.max };
                root.baseline = all;
            }
            // the control centre's brightness reads this entry
            if (j.code === 0x10)
                Brightness.patchDdc(j.bus, { pct: Math.round(r.current / r.max * 100), max: r.max, error: "" });
        }
    }

    // read the capabilities of every reachable monitor not yet read (cached by output, bus and model)
    function ensure() {
        if (!root.active || !Brightness.ddcUsable)
            return;
        if (root.probeInfo.known && !root.probeInfo.devices)
            return;
        for (const m of Brightness.ddc) {
            if (!m.access)
                continue;
            const key = m.output + "|" + m.bus + "|" + m.model;
            if (root.mons[m.output]?.key === key)
                continue;
            root.setMon(m.output, { key: key, state: "loading", features: {} });
            root.enqueue({ kind: "caps", bus: m.bus, output: m.output, key: key });
        }
    }

    // "Check again" in the setup guide: read the bus list and the access again, and ask the monitors that gave no answer
    function checkAgain() {
        root.fails = {};
        const next = {};
        for (const k in root.mons)
            if (root.mons[k].state === "ok")
                next[k] = root.mons[k];
        root.mons = next;
        root.runProbe();
        Brightness.refreshDdc();
        settle.restart();
    }

    function runProbe() {
        if (Brightness.ddcUsable && !prober.running)
            prober.running = true;
    }

    function gotProbe(text) {
        let r = null;
        try {
            r = JSON.parse(text);
        } catch (e) {
            r = null;
        }
        if (!r || typeof r !== "object")
            return;
        root.probeInfo = { known: true, devices: r.devices === true, adapters: r.adapters ?? {} };
        root.ensure();
    }

    onActiveChanged: {
        // the baseline is what the monitors have now each time the tab opens (values read earlier stay in `vals`; nothing is read again)
        const snap = root.active ? JSON.parse(JSON.stringify(root.vals)) : ({});
        if (root.active)
            // brightness is written through Brightness, which keeps its own level (`vals` holds only what was read): the level it has now
            for (const m of Brightness.ddc) {
                const level = Brightness.ddcLevel(m.output);
                if (level >= 0) {
                    snap[m.output] = snap[m.output] ?? {};
                    snap[m.output]["16"] = { current: level, max: 100 };
                }
            }
        root.baseline = snap;
        if (root.active) {
            root.runProbe();
            Brightness.refreshDdc();
            root.ensure();
        }
    }

    Connections {
        target: Brightness
        function onDdcChanged() {
            root.ensure();
        }
    }

    // ---- the udev rule ----
    readonly property string rulePath: "/etc/udev/rules.d/60-sleepyshell-ddc.rules"

    function adapterOf(bus) {
        return root.probeInfo.adapters[String(bus)] ?? "";
    }

    // what ATTR{name}== should match for an adapter name: the whole family where the name ends in a bus number
    // ("AMDGPU DM i2c hw bus 1" -> "AMDGPU DM*"), else the exact name. "" for a name with characters that
    // do not belong in a rule (the pattern ends up inside a shell command, so nothing odd is passed on).
    function udevPattern(name) {
        if (!/^[A-Za-z0-9 ._:+-]+$/.test(name))
            return "";
        if (name.startsWith("AMDGPU DM"))
            return "AMDGPU DM*";
        const stem = name.replace(/\s*\d+$/, "");
        return stem !== name && stem !== "" ? stem + "*" : name;
    }

    function ruleLine(pattern) {
        return 'SUBSYSTEM=="i2c-dev", ATTR{name}=="' + pattern + '", TAG+="uaccess"';
    }

    // the patterns for these buses, without repeats
    function patternsFor(buses) {
        const out = [];
        for (const b of buses) {
            const p = root.udevPattern(root.adapterOf(b));
            if (p !== "" && !out.includes(p))
                out.push(p);
        }
        return out;
    }

    // the command that writes the rule file for these patterns ("" for none)
    function ruleCommand(patterns) {
        if (patterns.length === 0)
            return "";
        if (patterns.length === 1)
            return "echo '" + root.ruleLine(patterns[0]) + "' | sudo tee " + root.rulePath;
        return "printf '%s\\n' " + patterns.map(p => "'" + root.ruleLine(p) + "'").join(" ") + " | sudo tee " + root.rulePath;
    }

    Process {
        id: runner
        stdout: StdioCollector {
            onStreamFinished: root.finished(text)
        }
    }

    Process {
        id: prober
        command: Brightness.ddcCommand.concat(["probe"])
        stdout: StdioCollector {
            onStreamFinished: root.gotProbe(text)
        }
    }

    Timer {
        id: gap
        interval: Brightness.ddcSpacing
        onTriggered: root.pump()
    }
    Timer {
        id: retry
        interval: 100
        onTriggered: root.pump()
    }
    Timer {
        id: settle
        interval: 900
        onTriggered: root.ensure()
    }
    // a monitor that never answers must not hold the queue
    Timer {
        id: watchdog
        interval: 20000
        onTriggered: {
            runner.running = false;
            root.finished("");
        }
    }
}
