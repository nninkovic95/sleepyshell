// The test driver, added by inject.py inside the root object of a run copy's entry file; never part of the shell.
// It only reads: where items are and what they show. Clicks and keys come from outside, through the test compositor's
// virtual pointer and keyboard (wlinput.py), so they take the real input path. IPC target "sleepytest":
//   ping, windows, find <spec JSON>, texts <window index>, js <expression>,
//   recordStart <probe> <target> <property>, recordStop: a frame recorder (see recordStart below)
import QtQuick
import Quickshell
import Quickshell.Io
    IpcHandler {
        target: "sleepytest"
        function ping(): string {
            return "pong";
        }
        function windows(): string {
            return JSON.stringify(sleepytestDriver.scan().wins.map(w => w.info));
        }
        function find(spec: string): string {
            return JSON.stringify(sleepytestDriver.find(JSON.parse(spec)));
        }
        function texts(win: int): string {
            return JSON.stringify(sleepytestDriver.texts(win));
        }
        function js(code: string): string {
            return sleepytestDriver.run(code);
        }
        function recordStart(probe: string, target: string, prop: string): string {
            return sleepytestDriver.recordStart(probe, target, prop);
        }
        function recordStop(): string {
            return JSON.stringify(sleepytestDriver.recordStop());
        }
    }
    QtObject {
        id: sleepytestDriver
        function typeName(o) {
            return String(o).split("(")[0].replace(/_QMLTYPE_\d+$|_QML_\d+$/, "");
        }
        function isWindow(o) {
            return o && o.contentItem !== undefined && o.screen !== undefined && (o.exclusionMode !== undefined || o.title !== undefined || o.anchor !== undefined);
        }
        function kids(o) {
            const out = [];
            for (const p of ["contentItem", "children", "data", "instances", "item", "resources", "surface"]) {
                let v;
                try {
                    v = o[p];
                } catch (e) {
                    continue;
                }
                if (!v || typeof v !== "object")
                    continue;
                if (typeof v.length === "number") {
                    for (let i = 0; i < v.length; i++)
                        if (v[i] && typeof v[i] === "object")
                            out.push(v[i]);
                } else {
                    out.push(v);
                }
            }
            return out;
        }
        function winInfo(w, index) {
            const kind = typeName(w).includes("SessionLockSurface") ? "lock" : w.exclusionMode !== undefined ? "panel" : w.title !== undefined ? "floating" : "popup";
            const info = { index: index, kind: kind, type: typeName(w), visible: !!w.visible, width: w.width, height: w.height, title: w.title ?? "" };
            if (kind === "lock") {
                info.x = 0;  // a lock surface covers its whole output; the test compositor has one, at 0,0
                info.y = 0;
            }
            if (kind === "panel" && w.screen) {
                const sw = w.screen.width, sh = w.screen.height, a = w.anchors, m = w.margins;
                info.x = a.left && !a.right ? m.left : a.right && !a.left ? sw - w.width - m.right : (sw - w.width) / 2 + (m.left - m.right) / 2;
                info.y = a.top && !a.bottom ? m.top : a.bottom && !a.top ? sh - w.height - m.bottom : (sh - w.height) / 2 + (m.top - m.bottom) / 2;
                info.screen = w.screen.name;
            }
            return info;
        }
        // every window that exists (each registers itself in the run copy, prepare.py) and every item in it
        function scan() {
            const wins = [], items = [];
            const walk = (it, win, depth) => {
                if (!it || depth > 300)
                    return;
                items.push({ obj: it, win: win });
                const c = it.children;
                if (c)
                    for (let i = 0; i < c.length; i++)
                        walk(c[i], win, depth + 1);
            };
            const list = SleepytestRegistry.wins;
            for (let i = 0; i < list.length; i++) {
                const w = list[i];
                if (!w || !w.contentItem)
                    continue;
                const win = { obj: w, info: winInfo(w, wins.length) };
                wins.push(win);
                const c = w.contentItem.children;
                for (let k = 0; k < c.length; k++)
                    walk(c[k], win, 0);
            }
            return { wins: wins, items: items };
        }
        function opacityOf(it) {
            let o = 1;
            for (let p = it; p; p = p.parent)
                o *= p.opacity;
            return o;
        }
        function describe(e) {
            const it = e.obj, w = e.win;
            const p = it.mapToItem(null, 0, 0);
            const text = typeof it.text === "string" ? it.text : "";
            const inside = p.x + it.width > 0 && p.y + it.height > 0 && p.x < w.obj.width && p.y < w.obj.height;
            const r = {
                type: typeName(it), objectName: it.objectName || "", text: text,
                x: p.x, y: p.y, w: it.width, h: it.height, win: w.info.index, winKind: w.info.kind, winTitle: w.info.title,
                winX: w.info.x, winY: w.info.y,
                visible: !!(it.visible && w.obj.visible && inside && it.width > 0 && it.height > 0 && opacityOf(it) > 0.01),
                enabled: !!it.enabled
            };
            for (const k of ["checked", "on", "value", "currentIndex", "placeholderText", "readOnly", "activeFocus"])
                if (it[k] !== undefined && typeof it[k] !== "object" && typeof it[k] !== "function")
                    r[k] = it[k];
            return r;
        }
        // spec: { text, contains, objectName, type, props: { name: value }, inside: { another spec }, win, title (of the window), all } ; only visible items unless all is true
        function matches(e, spec) {
            const it = e.obj;
            if (spec.objectName !== undefined && it.objectName !== spec.objectName)
                return false;
            if (spec.type !== undefined && typeName(it) !== spec.type)
                return false;
            if (spec.text !== undefined && it.text !== spec.text)
                return false;
            if (spec.contains !== undefined && !(typeof it.text === "string" && it.text.includes(spec.contains)))
                return false;
            if (spec.props !== undefined && Object.keys(spec.props).some(k => it[k] !== spec.props[k]))
                return false;
            return true;
        }
        function find(spec) {
            const s = scan(), out = [];
            // inside: only items under one that matches this spec (a row's own switch, a dialog's own buttons)
            const outer = spec.inside ? s.items.filter(e => matches(e, spec.inside)).map(e => e.obj) : null;
            for (const e of s.items) {
                const it = e.obj;
                if (outer) {
                    let p = it.parent;
                    while (p && !outer.includes(p))
                        p = p.parent;
                    if (!p)
                        continue;
                }
                if (spec.objectName !== undefined && it.objectName !== spec.objectName)
                    continue;
                if (spec.type !== undefined && typeName(it) !== spec.type)
                    continue;
                if (spec.text !== undefined && it.text !== spec.text)
                    continue;
                if (spec.contains !== undefined && !(typeof it.text === "string" && it.text.includes(spec.contains)))
                    continue;
                if (spec.win !== undefined && e.win.info.index !== spec.win)
                    continue;
                if (spec.title !== undefined && e.win.info.title !== spec.title)
                    continue;
                if (spec.props !== undefined && Object.keys(spec.props).some(k => it[k] !== spec.props[k]))
                    continue;
                const d = describe(e);
                if (!spec.all && !d.visible)
                    continue;
                out.push(d);
            }
            return out;
        }
        // the visible text of one window in reading order (top to bottom, then left to right)
        function texts(win) {
            return find({ win: win }).filter(d => d.text !== "").sort((a, b) => Math.round(a.y) - Math.round(b.y) || a.x - b.x).map(d => d.text);
        }
        function run(code) {
            try {
                const v = eval(code);
                return JSON.stringify(v === undefined ? null : v);
            } catch (e) {
                return JSON.stringify({ error: String(e) });
            }
        }

        // Frame recorder, read-only. Every frame (a FrameAnimation) the expression `probe` is evaluated and kept as
        // [frame number, changes so far, value]; "changes" counts the change signals of `prop` on the object `target`
        // (an expression). A test can then prove that no frame was skipped and that every change was seen by its own
        // frame, so a recording never passes by missing the frame that would have failed it.
        property var recFrames: null
        property var recWatch: null
        property var recProbe: null
        property var recLog: []
        property int recChanges: 0
        function recordStart(probe, target, prop) {
            recordStop();
            try {
                recProbe = eval("(function () { return (" + probe + "); })");
                const obj = eval("(" + target + ")");
                const handler = "on" + prop.charAt(0).toUpperCase() + prop.slice(1) + "Changed";
                recChanges = 0;
                recLog = [];
                recWatch = Qt.createQmlObject("import QtQuick; Connections { property var drv: null; function " + handler + "() { drv.recChanges++; } }", sleepytestDriver, "sleepytestRecWatch");
                recWatch.drv = sleepytestDriver;
                recWatch.target = obj;
                recFrames = Qt.createQmlObject("import QtQuick; FrameAnimation { property var drv: null; running: true; onTriggered: drv.recTick(currentFrame) }", sleepytestDriver, "sleepytestRecFrames");
                recFrames.drv = sleepytestDriver;
                return "ok";
            } catch (e) {
                recordStop();
                return "error: " + e;
            }
        }
        function recTick(frame) {
            let v;
            try {
                v = recProbe();
            } catch (e) {
                v = { error: String(e) };
            }
            recLog.push([frame, recChanges, v]);
        }
        function recordStop() {
            if (recFrames) {
                recFrames.running = false;
                recFrames.destroy();
                recFrames = null;
            }
            if (recWatch) {
                recWatch.destroy();
                recWatch = null;
            }
            const out = recLog;
            recLog = [];
            return out;
        }
    }
