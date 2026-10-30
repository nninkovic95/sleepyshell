pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Display settings for the settings window's Display tab. Under the Lua config a monitor cannot
// be changed at run time (`hyprctl keyword monitor` fails), so
// this edits ~/.config/hypr/modules/monitors.lua, which Hyprland reloads on save. Only the
// hl.monitor({...}) block of each edited output is rewritten; comments, other blocks and keys
// the tab does not know (position, mirror, ...) stay as they were. After Apply the previous
// file is kept in memory and written back after 15 s unless Keep is pressed, so a mode the panel
// cannot show reverts by itself.
Singleton {
    id: root

    // the file the Config tab names (pathMonitors, applied); the usual place until it is changed
    readonly property string path: Settings.pathMonitors
    readonly property int revertSeconds: 15

    // connected outputs from hyprctl: {name, model, modes, running, scale}
    property var monitors: []
    property string fileText: ""
    // output name -> {mode, scale, transform, vrr, bitdepth, cm, sdrbrightness, sdrsaturation}, what the tab shows and edits
    //
    // HDR (the field names are from the Hyprland wiki's Monitors page, Fields table, and from
    // `hyprctl monitors -j` of Hyprland 0.56.2, which reports colorManagementPreset, sdrBrightness and sdrSaturation):
    //  - `cm` is the colour management preset, a string, default "srgb"; "hdr" is the HDR preset ("hdredid" uses the monitor's own EDID values;
    //    both count as on here). Off is written as "srgb".
    //  - `sdrbrightness` ("SDR brightness in HDR mode") is a float, default 1.0; the wiki says "Typical brightness value should be in the
    //    1.0 ... 2.0 range" and its example uses 1.2: that is the slider's range and the "around 1.2 to 1.5" of the tip.
    //  - `sdrsaturation` ("SDR saturation in HDR mode") is a float, default 1.0, no range given (its example uses 0.98): the slider is 0.5 to 1.5
    //    in steps of 0.05, an own choice that keeps 1.0 in the middle.
    //  - `bitdepth` 10 (8 or 10, default 8): the wiki's HDR examples set bitdepth = 10 with cm = "hdr"; it does not say it is required, so turning
    //    HDR on also sets the draft's 10-bit colour (the row shows it) and turning it off leaves 10-bit as it is.
    //  The switch is always in the Advanced fold but works only for an output whose EDID advertises HDR (scripts/edid.py hdr: the PQ bit of the
    //  CTA-861 HDR static metadata block); otherwise it is greyed and says why (hdrReason). It is staged like the resolution and goes through the same keep-or-revert countdown, because HDR can blank or wash out a screen.
    property var draft: ({})
    property bool pending: false
    property int countdown: 0
    property string backup: ""
    // output name -> { hdr, pq, hlg, maxNits } from the EDID (scripts/edid.py hdr), read when the monitors are
    property var hdr: ({})
    function hasHdr(name) {
        return root.hdr[name]?.hdr === true;
    }
    // why the HDR row is greyed: "" when the monitor advertises HDR
    function hdrReason(name) {
        const h = root.hdr[name];
        if (!h || h.error)
            return "Couldn't read this monitor's capabilities.";
        return h.hdr === true ? "" : "This monitor doesn't report HDR support.";
    }
    function hdrOn(d) {
        return d.cm === "hdr" || d.cm === "hdredid";
    }

    readonly property bool dirty: {
        fileText;
        for (const m of monitors) {
            const d = draft[m.name];
            if (d && JSON.stringify(d) !== JSON.stringify(configured(m.name)))
                return true;
        }
        return false;
    }

    // ---- reading ------------------------------------------------------------------------------

    function unquote(s) {
        return s.length >= 2 && s.startsWith('"') && s.endsWith('"') ? s.slice(1, -1) : s;
    }

    function num(s, def) {
        if (s === null || s === undefined)
            return def;
        if (s === "true")
            return 1;
        if (s === "false")
            return 0;
        const n = Number(s);
        return isNaN(n) ? def : n;
    }

    // every hl.monitor({...}) call: its span, output and [key, raw value] pairs; a block with a
    // nested table (reserved = {...}) is marked unsupported and left alone
    function blocks(text) {
        const re = /hl\.monitor\(\s*\{([\s\S]*?)\}\s*\)/g;
        const out = [];
        let m;
        while ((m = re.exec(text)) !== null) {
            // a commented-out call (`-- hl.monitor({ ... })`) is not a block: rewriting it left
            // the `-- ` on the first line only and broke the file (review 4). Skip it and resume
            // the scan on the next line, so a real block after it is still found.
            const lineStart = text.lastIndexOf("\n", m.index) + 1;
            if (text.slice(lineStart, m.index).includes("--")) {
                const eol = text.indexOf("\n", m.index);
                re.lastIndex = eol === -1 ? text.length : eol + 1;
                continue;
            }
            const body = m[1].split("\n").filter(l => !l.trim().startsWith("--")).join("\n");
            const keys = [];
            const kre = /(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|[^,\n}]+)/g;
            let k;
            while ((k = kre.exec(body)) !== null)
                keys.push([k[1], k[2].trim()]);
            const o = keys.find(p => p[0] === "output");
            out.push({
                start: m.index,
                end: m.index + m[0].length,
                output: o ? unquote(o[1]) : "",
                keys: keys,
                supported: !body.includes("{")
            });
        }
        return out;
    }

    // what the file says for an output, filled in from the running state where it says nothing
    function configured(name) {
        const mon = monitors.find(x => x.name === name);
        const b = blocks(fileText).find(x => x.output === name);
        const get = k => {
            const p = b ? b.keys.find(q => q[0] === k) : null;
            return p ? unquote(p[1]) : null;
        };
        return {
            mode: get("mode") ?? (mon ? mon.running : "preferred"),
            scale: num(get("scale"), mon ? mon.scale : 1),
            transform: num(get("transform"), 0),
            vrr: num(get("vrr"), 0),
            bitdepth: num(get("bitdepth"), 8),
            cm: get("cm") ?? "srgb",
            sdrbrightness: num(get("sdrbrightness"), 1),
            sdrsaturation: num(get("sdrsaturation"), 1)
        };
    }

    function editable(name) {
        const b = blocks(fileText).find(x => x.output === name);
        return !b || b.supported;
    }

    function resetDraft() {
        const d = {};
        for (const m of monitors)
            d[m.name] = configured(m.name);
        draft = d;
    }

    function setDraft(name, key, value) {
        const d = Object.assign({}, draft);
        d[name] = Object.assign({}, d[name]);
        d[name][key] = value;
        draft = d;
    }

    // several keys of one output at once
    function setDraftKeys(name, values) {
        const d = Object.assign({}, draft);
        d[name] = Object.assign({}, d[name], values);
        draft = d;
    }

    // the revert arrow of a row: these keys of this output go back to what the file says now
    function revertKeys(name, keys) {
        const c = configured(name);
        const v = {};
        for (const k of keys)
            v[k] = c[k];
        setDraftKeys(name, v);
    }

    // does the draft of this output differ from the file in one of these keys?
    function changed(name, keys) {
        const d = draft[name];
        if (!d)
            return false;
        const c = configured(name);
        return keys.some(k => d[k] !== c[k]);
    }

    // take the colour management key out of this monitor's block (the notice about an HDR line on a monitor that has none); written by Apply
    function removeCm(name) {
        setDraftKeys(name, { cm: "" });
    }

    // HDR on or off: on also asks for 10-bit colour (see the note on `draft`)
    function setHdr(name, on) {
        // a monitor that does not report HDR is never switched into it
        if (on && !hasHdr(name))
            return;
        setDraftKeys(name, on ? { cm: "hdr", bitdepth: 10 } : { cm: "srgb" });
    }

    function setMonitors(json) {
        let list;
        try {
            list = JSON.parse(json);
        } catch (e) {
            console.warn("Displays: hyprctl monitors: " + e);
            return;
        }
        const size = v => {
            const mm = v.match(/^(\d+)x(\d+)@([\d.]+)$/);
            return mm ? [Number(mm[1]) * Number(mm[2]), Number(mm[3])] : [0, 0];
        };
        // the test kit's virtual monitors ("sleepytest…") are left out of the Display tab
        monitors = list.filter(m => !String(m.name).startsWith("sleepytest")).map(m => {
            const modes = [];
            for (const s of m.availableModes ?? []) {
                const v = s.replace(/Hz$/, "");
                if (!modes.includes(v))
                    modes.push(v);
            }
            modes.sort((a, b) => {
                const ka = size(a), kb = size(b);
                return kb[0] - ka[0] || kb[1] - ka[1];
            });
            return {
                name: m.name,
                model: (m.model ?? "").trim(),
                modes: modes,
                running: m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2),
                scale: m.scale,
                vrrActive: m.vrr === true
            };
        });
        // a re-query (window reopened) or a file change must not drop an unapplied draft (review 3, F7)
        if (!pending && !dirty)
            resetDraft();
        root.readHdr();
    }

    // which of the outputs advertise HDR: read once for the names that are there now
    function readHdr() {
        const names = monitors.map(m => m.name).filter(n => /^[A-Za-z0-9._-]+$/.test(n));
        if (names.length === 0 || JSON.stringify(names) === root.hdrAsked)
            return;
        root.hdrAsked = JSON.stringify(names);
        edid.command = ["python3", root.edidScript, "hdr"].concat(root.edidArgs, names);
        edid.running = true;
    }
    property string hdrAsked: ""
    readonly property string edidScript: Quickshell.shellPath("scripts/edid.py")
    // the test kit points the script at fixture EDIDs
    readonly property var edidArgs: []

    // ---- writing ------------------------------------------------------------------------------

    function fmtScale(s) {
        return String(Number(Number(s).toFixed(2)));
    }

    // a plain Lua number for sdrbrightness and sdrsaturation (two decimals at most)
    function fmtNum(s) {
        return String(Number(Number(s).toFixed(2)));
    }

    // one hl.monitor block, keys in their old order, values from the draft; transform and
    // bitdepth are only written when they differ from Hyprland's default or were there already
    function blockText(name, keys, d) {
        const set = {
            output: '"' + name + '"',
            mode: '"' + d.mode + '"',
            scale: '"' + fmtScale(d.scale) + '"',
            vrr: String(d.vrr),
            transform: String(d.transform),
            bitdepth: String(d.bitdepth),
            cm: '"' + d.cm + '"',
            sdrbrightness: fmtNum(d.sdrbrightness),
            sdrsaturation: fmtNum(d.sdrsaturation)
        };
        const quiet = {
            transform: "0",
            bitdepth: "8",
            cm: '"srgb"',
            sdrbrightness: "1",
            sdrsaturation: "1"
        };
        const have = keys.map(p => p[0]);
        // an empty `cm` in the draft means "take the key out of the block" (the HDR notice's Remove it): only that key goes
        const pairs = keys.filter(p => !(p[0] === "cm" && d.cm === "")).map(p => [p[0], set[p[0]] ?? p[1]]);
        for (const k of ["output", "mode", "position", "scale", "vrr", "transform", "bitdepth", "cm", "sdrbrightness", "sdrsaturation"]) {
            if (have.includes(k) || (k === "cm" && d.cm === ""))
                continue;
            if (k === "position")
                pairs.push([k, '"auto"']);
            else if (quiet[k] !== set[k])
                pairs.push([k, set[k]]);
        }
        const w = Math.max(...pairs.map(p => p[0].length));
        return "hl.monitor({\n" + pairs.map(p => "    " + p[0].padEnd(w) + " = " + p[1] + ",").join("\n") + "\n})";
    }

    function compose() {
        let text = fileText;
        const bs = blocks(text);
        const edits = [];
        const appends = [];
        for (const m of monitors) {
            const d = draft[m.name];
            if (!d)
                continue;
            const b = bs.find(x => x.output === m.name);
            if (!b)
                appends.push(blockText(m.name, [], d));
            else if (b.supported)
                edits.push([b.start, b.end, blockText(m.name, b.keys, d)]);
        }
        edits.sort((a, b) => b[0] - a[0]);
        for (const e of edits)
            text = text.slice(0, e[0]) + e[2] + text.slice(e[1]);
        for (const a of appends)
            text = text.replace(/\s*$/, "") + "\n\n" + a + "\n";
        return text;
    }

    // a new monitors file (FileChecks "Create", the file is missing): a header and one block for each connected output as it is set now
    function createFile() {
        let text = "-- Monitors, written by Sleepysettings (Display tab). Hyprland loads this file with a require line in hyprland.lua.\n";
        for (const m of monitors)
            text += "\n" + blockText(m.name, [], configured(m.name)) + "\n";
        write(text);
    }

    function write(text) {
        file.setText(text);
        fileText = text;
        requery.restart();
    }

    function apply() {
        if (pending || !dirty)
            return;
        backup = fileText;
        write(compose());
        countdown = revertSeconds;
        pending = true;
        tick.restart();
    }

    function keep() {
        tick.stop();
        pending = false;
    }

    function revert() {
        tick.stop();
        pending = false;
        write(backup);
        resetDraft();
    }

    function refresh() {
        query.running = true;
        file.reload();
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        // in place, so Hyprland's watch on the file sees a plain modification
        atomicWrites: false
        onFileChanged: reload()
        onLoaded: {
            root.fileText = text();
            if (!root.pending && !root.dirty)
                root.resetDraft();
        }
    }

    Process {
        id: query
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.setMonitors(text)
        }
    }

    Process {
        id: edid
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.hdr = JSON.parse(text);
                } catch (e) {
                    root.hdr = {};
                }
            }
        }
    }

    Component.onCompleted: query.running = true

    // the running mode settles a moment after Hyprland reloads the file
    Timer {
        id: requery
        interval: 1500
        onTriggered: query.running = true
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0)
                root.revert();
        }
    }
}
