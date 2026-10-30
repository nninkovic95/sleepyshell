pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Keybinds for the settings window's Keybinds tab. `hyprctl binds -j` only reports "__lua" for Lua binds (checked under the Lua
// config: just __lua and an index, no action text), so the list is read from the config files themselves. That is every file Hyprland loads: HyprConfig runs scripts/hyprconf.py, which starts at hyprland.lua, follows each
// require and reads the hl.bind calls of all of them, with the variables, app.* from programs.lua and numeric loops resolved. Each
// bind carries its file and line; the tab shows the file on hover and opens it. The old parser below (binds.lua only) stays as the
// fallback for when hyprconf.py cannot run (no python3, no hyprland.lua). Binds added in the tab go to the sleepybinds file (Config
// tab), edited in place by this file (a removed bind's line is deleted, an added one appended, everything else in the file is left
// alone); it counts as "added here" and is not listed again among the built-in ones. Hyprland reloads it on save, if it loads it.
Singleton {
    id: root

    readonly property string dir: HyprConfig.dir
    // the Hyprland config that requires the modules (read only here: the Config tab shows it)
    readonly property string mainPath: HyprConfig.main !== "" ? HyprConfig.main : dir + "/hyprland.lua"
    // the file the Config tab names (pathCustombinds, applied); whether Hyprland loads it is FileChecks' question
    readonly property string customPath: Settings.pathCustombinds
    readonly property string defaultCustomPath: dir + "/modules/sleepybinds.lua"
    // the fallback's binds file, when hyprconf.py gave no answer
    readonly property string fallbackBindsPath: dir + "/modules/binds.lua"

    property string bindsText: ""
    property string programsText: ""
    property string customText: ""
    property string mainText: ""

    // hyprland.lua loads the custombinds file (the discovery says so; without it, the old test: the require line for modules/sleepybinds.lua)
    readonly property bool customRequired: HyprConfig.ok ? HyprConfig.isLoaded(customPath) : /^\s*require\(\s*["']modules\.sleepybinds["']\s*\)/m.test(mainText)
    // the binds written to customPath load (without the discovery: and customPath is the file the line names)
    readonly property bool customEnabled: HyprConfig.ok ? customRequired : customRequired && customPath === defaultCustomPath
    readonly property var app: parseAssignments(programsText, /(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"/g)
    readonly property var vars: {
        const v = parseAssignments(bindsText, /local\s+(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"/g);
        // the workspace loop in binds.lua: `for i = 1, 10 do local key = i % 10`
        v.key = "1…0";
        v.i = "1…10";
        return v;
    }
    // [{combo, keys, action, run, group, flags, note, custom, index, file, line}]: the built-in binds, from every file Hyprland loads
    // (HyprConfig), without the sleepybinds file's, which are the "added here" ones below; from binds.lua alone when the discovery failed
    readonly property bool discovered: HyprConfig.ok
    readonly property var binds: HyprConfig.ok ? fromDiscover(HyprConfig.binds.filter(b => b.file !== customPath)) : parse(bindsText, false).map(b => Object.assign(b, { file: fallbackBindsPath, line: 0 }))
    // every file a built-in bind was found in (the Config tab's "Keybind files"), in the order found
    readonly property var bindFiles: {
        const out = [];
        for (const b of binds)
            if (!out.includes(b.file))
                out.push(b.file);
        return out;
    }
    // what the discovery could not turn into a bind (a Lua function as the action, an unknown dispatcher), for a hint
    readonly property int unreadableCount: HyprConfig.ok ? HyprConfig.unreadable.length : 0
    readonly property var fileCustom: parse(customText, true)
    // added and removed binds wait here until Apply (null: nothing staged)
    property var staged: null
    readonly property bool dirty: staged !== null
    readonly property var custom: staged === null ? fileCustom : staged.map((b, i) => ({
                combo: b.combo,
                keys: b.combo.split("+").map(x => x.trim()).filter(x => x !== ""),
                action: b.src ? (fileCustom.find(f => f.src === b.src)?.action ?? "Run " + b.run) : (b.action ?? "Run " + b.run),
                run: b.run,
                group: groupOf(b.combo, b.src ? "Run " + b.run : (b.action ?? "Run " + b.run), b.run),
                flags: b.src ? (fileCustom.find(f => f.src === b.src)?.flags ?? []) : (b.flags ?? []),
                note: "",
                custom: true,
                index: i,
                src: b.src ?? "",
                lua: b.lua ?? "",
                file: customPath,
                line: fileCustom.find(f => f.src === b.src)?.line ?? 0
            }))
    readonly property var all: binds.concat(custom)

    // ---- the discovery's binds (scripts/hyprconf.py) ------------------------------------------

    // hyprconf.py binds -> the tab's shape. A bind a numeric loop made (workspaces 1 to 10) is one row: its keys "1…0" and its
    // action with the number range ("Go to workspace 1…10"), as the old parser showed it.
    function fromDiscover(list) {
        const rows = [];
        const loops = new Map();
        for (const b of list) {
            if (b.from_loop) {
                const k = b.file + ":" + b.line;
                if (loops.has(k)) {
                    loops.get(k).push(b);
                    continue;
                }
                loops.set(k, [b]);
                rows.push({ loop: loops.get(k) });
            } else {
                rows.push({ one: b });
            }
        }
        return rows.map((r, i) => {
            let b, key, action;
            if (r.one) {
                b = r.one;
                key = b.key;
                action = b.action;
            } else {
                b = r.loop[0];
                const z = r.loop[r.loop.length - 1];
                key = r.loop.length > 1 && z.key !== b.key ? b.key + "…" + z.key : b.key;
                const ta = b.action.split(" "), tz = z.action.split(" ");
                action = ta.map((t, j) => tz[j] !== undefined && tz[j] !== t ? t + "…" + tz[j] : t).join(" ");
            }
            const keys = b.mods.concat([key]);
            const combo = keys.join(" + ");
            const run = action.startsWith("Run ") ? action.slice(4) : "";
            // a trailing comment on the bind's line, when it has one
            const note = (String(b.raw ?? "").match(/\)\s+--\s+([^"'()]+)$/) ?? ["", ""])[1].trim();
            return {
                combo: combo,
                keys: keys,
                action: action,
                run: run,
                group: groupOf(combo, action, run),
                flags: (b.flags ?? []).filter(f => ["locked", "repeating", "mouse", "release"].includes(f)),
                note: note,
                custom: false,
                index: i,
                src: "",
                file: b.file,
                line: b.line
            };
        });
    }

    // ---- parsing ------------------------------------------------------------------------------

    function parseAssignments(text, re) {
        const out = {};
        let m;
        re.lastIndex = 0;
        while ((m = re.exec(text)) !== null)
            out[m[1]] = m[2].replace(/\\(.)/g, "$1");
        return out;
    }

    // split s at sep where not inside a string, parentheses or braces
    function splitTop(s, sep) {
        const out = [];
        let depth = 0, quote = "", start = 0;
        for (let i = 0; i < s.length; i++) {
            const c = s[i];
            if (quote) {
                if (c === "\\")
                    i++;
                else if (c === quote)
                    quote = "";
                continue;
            }
            if (c === '"' || c === "'")
                quote = c;
            else if (c === "(" || c === "{")
                depth++;
            else if (c === ")" || c === "}")
                depth--;
            else if (depth === 0 && s.startsWith(sep, i)) {
                out.push(s.slice(start, i));
                start = i + sep.length;
                i += sep.length - 1;
            }
        }
        out.push(s.slice(start));
        return out.map(x => x.trim()).filter(x => x !== "");
    }

    function evalExpr(e) {
        return splitTop(e, "..").map(t => {
            if (/^(".*"|'.*')$/.test(t))
                return t.slice(1, -1).replace(/\\(.)/g, "$1");
            if (t in vars)
                return vars[t];
            const m = t.match(/^app\.(\w+)$/);
            if (m && m[1] in app)
                return app[m[1]];
            return t;
        }).join("");
    }

    function table(s) {
        const t = {};
        const body = s.trim().replace(/^\{/, "").replace(/\}$/, "");
        for (const part of splitTop(body, ",")) {
            const m = part.match(/^(\w+)\s*=\s*([\s\S]+)$/);
            if (m)
                t[m[1]] = m[2].trim();
        }
        return t;
    }

    function workspace(v) {
        const w = evalExpr(v);
        if (w === "e+1")
            return "next workspace";
        if (w === "e-1")
            return "previous workspace";
        if (w.startsWith("special:"))
            return "special workspace " + w.slice(8);
        return "workspace " + w;
    }

    // a readable action; run is the command for exec_cmd binds, "" otherwise
    function describe(a) {
        const m = a.match(/^hl\.dsp\.([\w.]+)\(([\s\S]*)\)$/);
        if (!m)
            return {
                action: a,
                run: ""
            };
        const fn = m[1], arg = m[2].trim();
        const t = arg.startsWith("{") ? table(arg) : {};
        let text;
        switch (fn) {
        case "exec_cmd":
            return {
                action: "Run " + evalExpr(arg),
                run: evalExpr(arg)
            };
        case "window.close":
            text = "Close window";
            break;
        case "window.float":
            text = "Toggle floating";
            break;
        case "window.pseudo":
            text = "Toggle pseudo-tiling";
            break;
        case "window.drag":
            text = "Drag window";
            break;
        case "window.resize":
            text = "Resize window";
            break;
        case "layout":
            text = "Layout: " + evalExpr(arg);
            break;
        case "focus":
            text = t.direction ? "Focus " + evalExpr(t.direction) : t.workspace ? "Go to " + workspace(t.workspace) : "Focus " + arg;
            break;
        case "window.move":
            text = t.workspace ? "Move window to " + workspace(t.workspace) : "Move window " + arg;
            break;
        case "workspace.toggle_special":
            text = "Toggle special workspace " + evalExpr(arg);
            break;
        case "event": {
            // sleepyshell's own events (shell.qml splits them): readable names for the ones the binds use
            const ev = evalExpr(arg);
            const names = {
                "sleepyshell:capslock": "Refresh the Caps Lock indicator",
                "sleepyshell:toggle:session": "Session menu"
            };
            text = names[ev] ?? (ev.startsWith("sleepyshell:toggle:") ? "Toggle the " + ev.slice(19) + " panel" : ev.startsWith("sleepyshell:") ? "Shell event " + ev.slice(12) : "Event " + ev);
            break;
        }
        default:
            text = fn.replace(/[._]/g, " ") + (arg ? " " + arg : "");
        }
        return {
            action: text,
            run: ""
        };
    }

    // the group a bind is listed under on the Keybinds tab: Workspaces, Windows, Media and system (media keys, Print, Caps Lock,
    // volume, lock, the session menu), Apps (everything else that runs a command), else Other
    readonly property var groupNames: ["Apps", "Windows", "Workspaces", "Media and system", "Other"]
    function groupOf(combo, action, run) {
        const key = combo.split("+").pop().trim();
        if (/^(XF86|Print|Caps_Lock)/i.test(key) || /wpctl|lock\.qml|lock-session|brightnessctl|playerctl/.test(run) || /^(Session menu|Refresh the Caps|Toggle the )/.test(action))
            return "Media and system";
        if (/workspace/i.test(action))
            return "Workspaces";
        if (/^(Focus|Close window|Toggle floating|Toggle pseudo|Drag window|Resize window|Layout:|Move window)/.test(action) || /^hyprctl/.test(run))
            return "Windows";
        if (action.startsWith("Run "))
            return "Apps";
        return "Other";
    }

    function parse(text, isCustom) {
        const out = [];
        const re = /hl\.bind\(/g;
        let m;
        while ((m = re.exec(text)) !== null) {
            const lineStart = text.lastIndexOf("\n", m.index) + 1;
            if (text.slice(lineStart, m.index).includes("--"))
                continue;
            // find the matching ")" outside strings
            let depth = 1, quote = "", i = re.lastIndex;
            for (; i < text.length && depth > 0; i++) {
                const c = text[i];
                if (quote) {
                    if (c === "\\")
                        i++;
                    else if (c === quote)
                        quote = "";
                } else if (c === '"' || c === "'")
                    quote = c;
                else if (c === "(")
                    depth++;
                else if (c === ")")
                    depth--;
            }
            const args = splitTop(text.slice(re.lastIndex, i - 1), ",");
            const lineEnd = text.indexOf("\n", i);
            const rest = text.slice(i, lineEnd < 0 ? text.length : lineEnd);
            const note = (rest.match(/--\s*(.*)$/) ?? ["", ""])[1].trim();
            if (args.length < 2)
                continue;
            const lineNo = text.slice(0, m.index).split("\n").length;
            const combo = evalExpr(args[0]);
            const d = describe(args[1]);
            const opts = args[2] ? table(args[2]) : {};
            const flags = ["locked", "repeating", "mouse", "release"].filter(f => opts[f] === "true");
            out.push({
                combo: combo,
                keys: combo.split("+").map(x => x.trim()).filter(x => x !== ""),
                action: d.action,
                run: d.run,
                group: groupOf(combo, d.action, d.run),
                flags: flags,
                note: note,
                custom: isCustom,
                file: isCustom ? customPath : fallbackBindsPath,
                line: lineNo,
                index: out.length,
                // the bind's own line(s) in the file, what writeCustom deletes when it is removed
                src: text.slice(lineStart, lineEnd < 0 ? text.length : lineEnd)
            });
            re.lastIndex = i;
        }
        return out;
    }

    // ---- conflicts ----------------------------------------------------------------------------

    // every concrete combo a bind covers, normalised ("1…0" covers the ten digits)
    function normalised(combo) {
        const parts = combo.split("+").map(x => x.trim().toUpperCase()).filter(x => x !== "");
        const alias = {
            CONTROL: "CTRL",
            MOD1: "ALT",
            MOD4: "SUPER",
            WIN: "SUPER"
        };
        const order = ["SUPER", "CTRL", "ALT", "SHIFT"];
        const mods = [];
        let key = "";
        for (const p of parts) {
            const q = alias[p] ?? p;
            if (order.includes(q))
                mods.push(q);
            else
                key = q;
        }
        mods.sort((a, b) => order.indexOf(a) - order.indexOf(b));
        const keys = key.includes("…") ? ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] : [key];
        return keys.map(k => mods.concat([k]).join(" + "));
    }

    function conflict(combo) {
        const want = normalised(combo)[0];
        return all.find(b => normalised(b.combo).includes(want)) ?? null;
    }

    // ---- writing custom binds ----------------------------------------------------------------

    function luaString(s) {
        return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
    }

    // Edit sleepybinds.lua in place: the line of every file bind missing from `list` is deleted,
    // binds without a source line (added in the tab) are appended, and the rest of the file is
    // left as it is. Regenerating the file turned hand-written non-exec binds into exec_cmd("")
    // and dropped their flags and comments (review 3, F6).
    function writeCustom(list) {
        const keep = list.map(b => b.src).filter(s => s);
        let text = customText;
        for (const b of fileCustom.slice().reverse()) {
            const k = keep.indexOf(b.src);
            if (k >= 0) {
                keep.splice(k, 1);
                continue;
            }
            const at = text.lastIndexOf(b.src);
            if (at < 0)
                continue;
            let end = at + b.src.length;
            if (text[end] === "\n")
                end++;
            text = text.slice(0, at) + text.slice(end);
        }
        const fresh = text.trim() === "";
        if (fresh)
            text = ["-- Keybinds added in Sleepysettings: managed by Sleepysettings (Keybinds tab), loaded by require(\"modules.sleepybinds\")",
                "-- in hyprland.lua. The tab deletes the line of a removed bind and appends added ones; the rest is left alone.", ""].join("\n");
        // an imported bind brings its canonical line (hyprconf.py parse-binds built it from the parsed values, with its options)
        const added = list.filter(b => !b.src).map(b => b.lua ? b.lua : "hl.bind(" + luaString(b.combo) + ", hl.dsp.exec_cmd(" + luaString(b.run) + "))");
        if (added.length > 0)
            text = text.replace(/\s*$/, "\n") + (fresh ? "\n" : "") + added.join("\n");
        text = text.replace(/\s*$/, "\n");
        customText = text;
        // the folder first when it is not there (the first write of the file)
        FileChecks.withDir(customPath, () => customFile.setText(text));
    }

    // a new custom keybinds file with nothing in it but its header (FileChecks "Create"; the file is missing, so the list is empty)
    function createCustomFile() {
        customText = "";
        writeCustom([]);
    }

    // returns "" on success or the reason it was refused
    function add(combo, command) {
        if (combo === "" || command.trim() === "")
            return "Press a key combination and type a command.";
        if (normalised(combo)[0].split(" + ").length < 2 && !/^(F\d+|Print|XF86\w+)$/i.test(combo))
            return "Use at least one modifier (SUPER, CTRL, ALT or SHIFT).";
        const c = conflict(combo);
        if (c)
            return combo + " is already bound: " + c.action;
        settle(current().concat([{
                    combo: combo,
                    run: command.trim()
                }]));
        return "";
    }

    function remove(index) {
        settle(current().filter((b, i) => i !== index));
    }

    // stage `list`, or nothing when it is the file's binds unchanged: removing a pending add left
    // an empty staged list behind, so the tab stayed dirty with nothing to apply (review 3, F45).
    // A bind added in the tab has no source line, so re-adding a removed file bind still differs.
    function settle(list) {
        const same = list.length === fileCustom.length && list.every((b, i) => b.src !== "" && b.src === fileCustom[i].src);
        staged = same ? null : list;
    }

    // the custom binds as plain {combo, run, src}, staged or from the file (src "" for one added in the tab)
    function current() {
        return custom.map(b => ({
                    combo: b.combo,
                    run: b.run,
                    src: b.src ?? "",
                    lua: b.lua ?? "",
                    flags: b.flags ?? [],
                    action: b.action
                }));
    }

    // Apply: an import copies sleepybinds.lua to sleepybinds.lua.bak-YYYYMMDD-HHMMSS first (when the file has content), then writes
    function apply() {
        if (staged === null)
            return;
        const list = staged;
        if (importStaged && customText.trim() !== "") {
            // the draft stays until the copy is made: a failed backup writes nothing and loses nothing
            backup.run(() => {
                writeCustom(list);
                staged = null;
                importStaged = false;
            });
        } else {
            staged = null;
            importStaged = false;
            writeCustom(list);
        }
    }

    function discard() {
        staged = null;
        importStaged = false;
    }


    // ======== Export and import (Keybinds tab > Share keybinds) ========================================================
    // Export writes a small Lua file of hl.bind lines (a header comment, one bind per line, the form of sleepybinds.lua) to a file the
    // user picked in the window's FolderBrowser: "my" binds (the ones of sleepybinds.lua) or "all" (every bind of every file Hyprland
    // loads, for sharing or a backup; a bind that does not run a command is a comment line there). Import reads a file with
    // `hyprconf.py parse-binds` (read-only, the file is never run: only hl.bind lines that run a command, or a .conf's bind = lines),
    // sorts each bind into new / already there / conflict, and shows that as a preview. Nothing is written by the preview. "Add" puts the
    // chosen binds into the staged list (the same draft as a bind added by hand), and Apply writes sleepybinds.lua, after a backup.
    property bool exportAll: false
    property string exportMessage: ""
    property bool exportFailed: false
    property string exportPath: ""
    // the import: the file asked for, the plan built from it (null: no preview), a failure line, the line after "Add"
    property string importPath: ""
    // "defaults": the Hyprland example's binds shipped in data/hyprland-default-binds.lua, their @terminal@-style variables filled from programs.lua
    property bool importDefaults: false
    property var importPlan: null
    property string importError: ""
    property string importMessage: ""
    property bool importStaged: false
    readonly property bool importBusy: parseProc.running
    // the backup copy of an import's Apply is running (the tab reports it as busy)
    readonly property bool busy: backup.proc.running

    function stamp() {
        return Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss");
    }

    function flagsOf(b) {
        return (b.flags ?? []).filter(f => ["locked", "repeating", "release"].includes(f));
    }

    // one command bind in the form of sleepybinds.lua
    function luaLine(combo, run, flags) {
        const f = (flags ?? []).filter(x => ["locked", "repeating", "release"].includes(x));
        return "hl.bind(" + luaString(combo) + ", hl.dsp.exec_cmd(" + luaString(run) + ")" + (f.length > 0 ? ", { " + f.map(x => x + " = true").join(", ") + " }" : "") + ")";
    }

    function exportHeader(everything, count) {
        return ["-- sleepyshell keybinds export (" + (everything ? "all keybinds, for sharing or a backup" : "keybinds added in Sleepysettings") + ")",
            "-- exported " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm") + ", " + count + (count === 1 ? " keybind" : " keybinds"),
            "-- Import it in Sleepysettings > Keybinds > Import. Only hl.bind lines that run a command are imported; they are checked, never run.",
            ""];
    }

    // the text of an export: "my" binds as sleepybinds.lua holds them (the line of a file bind, a fresh line for one still unapplied), or
    // "all": every row grouped by file, command binds as importable lines and the rest as comments
    function exportText(everything) {
        const lines = [];
        let count = 0;
        if (!everything) {
            for (const b of custom) {
                if (b.src && /^\s*hl\.bind\(/.test(b.src)) {
                    lines.push(b.src.trim());
                    count++;
                } else if (b.lua || b.run !== "") {
                    lines.push(b.lua ? b.lua : luaLine(b.combo, b.run, b.flags));
                    count++;
                } else {
                    lines.push("-- not a command keybind, not exported: " + b.combo + " (" + b.action + ")");
                }
            }
        } else {
            const files = [];
            for (const b of root.all) {
                let g = files.find(x => x.file === b.file);
                if (!g) {
                    g = { file: b.file, rows: [] };
                    files.push(g);
                }
                g.rows.push(b);
            }
            for (const g of files) {
                lines.push("-- " + Settings.tilde(g.file));
                for (const b of g.rows) {
                    if (b.run !== "" && !b.combo.includes("…")) {
                        lines.push(luaLine(b.combo, b.run, b.flags));
                        count++;
                    } else {
                        lines.push("-- " + b.combo + "  " + b.action);
                    }
                }
                lines.push("");
            }
        }
        return exportHeader(everything, count).concat(lines).join("\n").replace(/\s*$/, "\n");
    }

    // write an export to `path` (the browser's choice); the result is a line for the tab
    function exportTo(path) {
        exportPath = path;
        exportMessage = "";
        exportFailed = false;
        const text = exportText(exportAll);
        exportFile.path = path;
        exportFile.setText(text);
    }

    // ask the window's browser (save mode: a file name, existing or new) and export there
    function chooseExport(folders) {
        if (!folders)
            return;
        folders.openFile(Quickshell.env("HOME"), p => root.exportTo(p), { title: "Save keybinds as", filters: ["*.lua"], newFile: true, fileName: exportAll ? "all-keybinds.lua" : "my-keybinds.lua" });
    }

    function chooseImport(folders) {
        if (!folders)
            return;
        folders.openFile(Quickshell.env("HOME"), p => root.importFrom(p), { title: "Choose: keybinds to import", filters: ["*.lua", "*.conf"] });
    }

    function importDefaultBinds() {
        importDefaults = true;
        importStart(Quickshell.shellPath("data/hyprland-default-binds.lua"));
    }
    function importFrom(path) {
        importDefaults = false;
        importStart(path);
    }
    function importStart(path) {
        importPlan = null;
        importError = "";
        importMessage = "";
        if (!Deps.has("python3")) {
            importError = "Importing needs python3, which is not installed.";
            return;
        }
        importPath = path;
        parseProc.running = false;
        parseProc.running = true;
    }

    function takeImport(text) {
        let d = null;
        try {
            d = JSON.parse(text);
        } catch (e) {
            d = null;
        }
        if (!d) {
            importError = "The file could not be read.";
            return;
        }
        if (d.error) {
            importError = d.error;
            return;
        }
        importPlan = plan(d);
    }
    // the resolved variables of the defaults, for the preview line ("terminal = kitty, menu = walker")
    property var importVars: ({})

    // sort the parsed binds: new, same (the same keys run the same command already), conflict (the same keys, another action: a bind
    // of sleepybinds.lua can be replaced, a built-in one cannot, it is changed in its own file), repeated (the file binds the keys twice)
    function plan(d) {
        const items = [];
        const errors = d.errors.slice();
        importVars = d.variables ?? ({});
        const seen = new Map();
        for (const b of d.binds) {
            const k = normalised(b.combo)[0];
            if (seen.has(k)) {
                const first = seen.get(k);
                if (first.run === b.run && first.action === b.action)
                    items.push({ status: "repeat", line: b.line, combo: b.combo, run: b.run, action: b.action, flags: b.flags, lua: b.lua, note: "Repeated: line " + first.line + " binds the same keys to the same command." });
                else
                    errors.push({ line: b.line, raw: b.raw, reason: "These keys are already used by line " + first.line + " of this file, which is kept. Remove one of them in the file." });
                continue;
            }
            seen.set(k, b);
            const ex = conflict(b.combo);
            const it = { status: "new", line: b.line, combo: b.combo, run: b.run, action: b.action, flags: b.flags, lua: b.lua, choice: "mine", builtin: false, existing: "", note: "" };
            if (ex) {
                it.existing = ex.action;
                it.builtin = !ex.custom;
                it.existingFile = ex.file;
                if (ex.run === b.run && (b.run !== "" || sameAction(ex.action, b.action))) {
                    it.status = "same";
                    it.note = (b.run !== "" ? "Already bound to the same command" : "Already bound to the same action") + (ex.custom ? "" : " in " + fileName(ex.file)) + ".";
                } else {
                    it.status = "conflict";
                    it.note = (ex.custom ? "Yours: " : "Built-in" + (ex.file ? " (" + fileName(ex.file) + ")" : "") + ": ") + ex.action;
                }
            }
            items.push(it);
        }
        errors.sort((a, b) => a.line - b.line);
        return { path: importPath, defaults: importDefaults, format: d.format, items: items, errors: errors, ignored: d.ignored ?? 0 };
    }

    function fileName(path) {
        return String(path).replace(/^.*\//, "");
    }

    // the same action text; a built-in loop row says "Workspace 1…10", which covers "Workspace 4"
    function sameAction(have, want) {
        if (have === want)
            return true;
        if (!have.includes("…"))
            return false;
        const ranges = (have.match(/\d+…\d+/g) ?? []).map(r => r.split("…").map(Number));
        const re = new RegExp("^" + have.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\d+…\d+/g, "(\\d+)") + "$");
        const m = re.exec(want);
        return m !== null && ranges.every((r, i) => Number(m[i + 1]) >= r[0] && Number(m[i + 1]) <= r[1]);
    }

    function chooseConflict(i, choice) {
        if (!importPlan || !importPlan.items[i] || importPlan.items[i].status !== "conflict" || importPlan.items[i].builtin)
            return;
        const next = Object.assign({}, importPlan);
        next.items = importPlan.items.map((it, j) => j === i ? Object.assign({}, it, { choice: choice }) : it);
        importPlan = next;
    }
    function setAllConflicts(choice) {
        if (!importPlan)
            return;
        const next = Object.assign({}, importPlan);
        next.items = importPlan.items.map(it => it.status === "conflict" && !it.builtin ? Object.assign({}, it, { choice: choice }) : it);
        importPlan = next;
    }

    function planCounts() {
        const c = { new: 0, same: 0, repeat: 0, conflict: 0, take: 0, builtin: 0, errors: 0 };
        if (!importPlan)
            return c;
        for (const it of importPlan.items) {
            c[it.status]++;
            if (it.status === "conflict" && it.builtin)
                c.builtin++;
            if (it.status === "conflict" && !it.builtin && it.choice === "theirs")
                c.take++;
        }
        c.errors = importPlan.errors.length;
        c.add = c.new + c.take;
        return c;
    }

    // Add: stage the new binds, and the imported ones chosen over a bind of sleepybinds.lua (that bind's line goes). Writes nothing.
    function confirmImport() {
        if (!importPlan)
            return 0;
        let list = current();
        let n = 0;
        for (const it of importPlan.items) {
            const imported = { combo: it.combo, run: it.run, src: "", lua: it.lua, flags: it.flags, action: it.action };
            if (it.status === "new") {
                list.push(imported);
                n++;
            } else if (it.status === "conflict" && !it.builtin && it.choice === "theirs") {
                const want = normalised(it.combo)[0];
                list = list.filter(b => normalised(b.combo)[0] !== want);
                list.push(imported);
                n++;
            }
        }
        importPlan = null;
        if (n === 0) {
            importMessage = "Nothing to add.";
            return 0;
        }
        settle(list);
        importStaged = staged !== null;
        importMessage = n + (n === 1 ? " keybind" : " keybinds") + " added to the list below. Apply saves them.";
        return n;
    }

    function cancelImport() {
        importPlan = null;
        importError = "";
        importMessage = "";
    }

    Process {
        id: parseProc
        command: ["python3", HyprConfig.script, "parse-binds", root.importPath].concat(root.importDefaults ? ["--resolve", HyprConfig.dir] : [])
        stdout: StdioCollector {
            onStreamFinished: root.takeImport(text)
        }
    }

    FileView {
        id: exportFile
        atomicWrites: false
        printErrors: false
        onSaved: {
            root.exportFailed = false;
            root.exportMessage = "Saved to " + Settings.tilde(root.exportPath) + ".";
        }
        onSaveFailed: error => {
            root.exportFailed = true;
            root.exportMessage = "The file could not be written: " + Settings.tilde(root.exportPath) + ".";
        }
    }

    // sleepybinds.lua.bak-<stamp> before an import is applied; fn runs when the copy is done (or could not be made: then it does not run)
    QtObject {
        id: backup
        property var then: null
        property string target: ""
        function run(fn) {
            then = fn;
            target = root.customPath + ".bak-" + root.stamp();
            proc.command = ["cp", "--", root.customPath, backup.target];
            proc.running = true;
        }
        property Process proc: Process {
            onExited: code => {
                const fn = backup.then;
                backup.then = null;
                if (code === 0 && fn)
                    fn();
                else
                    root.importMessage = "The backup of " + Settings.tilde(root.customPath) + " could not be made, so nothing was written.";
            }
        }
    }
    // ====================================================================================================================================

    // The editor and the file manager are the desktop's defaults, chosen in the Apps tab (services/DefaultApps.qml;
    // every launch goes through it).
    readonly property string editorProgram: DefaultApps.editorProgram
    readonly property string openerProgram: DefaultApps.openerProgram
    Component.onCompleted: DefaultApps.ensure()

    // open a file in the editor (the Keybinds tab, the System tab's Files, the Apply bar's file chips)
    function openFile(path) {
        if (!Deps.has(root.editorProgram))
            return;
        DefaultApps.openInEditor(path);
    }

    // show a file in the file manager: its folder goes to the desktop's opener, so the
    // system's handler for folders decides which file manager. `self`: the path is itself a folder (the
    // wallpaper folder) and is shown as it is, not its parent
    function reveal(path, self) {
        if (!Deps.has(root.openerProgram))
            return;
        const full = path.replace(/^~(?=\/|$)/, Quickshell.env("HOME"));
        const dir = self ? full : full.replace(/\/[^\/]*$/, "") || "/";
        DefaultApps.revealDir(dir);
    }
    function revealFile(path) {
        root.reveal(path, false);
    }
    function revealDir(path) {
        root.reveal(path, true);
    }

    // the first file the built-in binds came from (the old "Open binds.lua")
    function openBindsFile() {
        root.openFile(root.bindFiles.length > 0 ? root.bindFiles[0] : root.fallbackBindsPath);
    }

    function refresh() {
        HyprConfig.refresh();
        bindsFile.reload();
        programsFile.reload();
        customFile.reload();
        mainFile.reload();
    }

    // pathBinds (the old "Main keybinds" location) is gone: a stored file that the config does not load is carried
    // over into the extra keybind files, then the old key is cleared. Waits for the discovery, so the usual binds.lua is not "extra".
    function migrate() {
        // the custom keybinds file was called custombinds.lua before: a stored value that is the old usual place becomes the new one
        if (Settings.expand(String(Settings.stored("pathCustombinds"))) === Settings.expand("~/.config/hypr/modules/custombinds.lua"))
            Settings.setNow("pathCustombinds", Settings.schema.pathCustombinds.def);
        const legacy = Settings.legacyPathBinds;
        if (legacy === "" || !HyprConfig.ready || !HyprConfig.ok)
            return;
        const known = HyprConfig.loadedPaths.includes(legacy) || Settings.keybindExtraFiles.includes(legacy);
        if (!known)
            Settings.setNow("keybindExtraFiles", Settings.asList(Settings.stored("keybindExtraFiles")).concat([Settings.tilde(legacy)]));
        Settings.setNow("pathBinds", "");
    }

    Connections {
        target: HyprConfig
        function onGenerationChanged() {
            root.migrate();
        }
    }
    Connections {
        target: Settings
        function onLegacyPathBindsChanged() {
            // not inside the binding that changed: migrate writes the settings
            Qt.callLater(root.migrate);
        }
    }

    FileView {
        id: bindsFile
        path: root.fallbackBindsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.bindsText = text()
    }

    FileView {
        id: programsFile
        path: root.dir + "/modules/programs.lua"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.programsText = text()
    }

    FileView {
        id: customFile
        path: root.customPath
        watchChanges: true
        // in place, so Hyprland's watch on the file sees a plain modification
        atomicWrites: false
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.customText = text()
        // the file went away: nothing of it is left to edit in place (the next write starts it again, with its header)
        onLoadFailed: root.customText = ""
    }

    FileView {
        id: mainFile
        path: root.mainPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.mainText = text()
    }
}
