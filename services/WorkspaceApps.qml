pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Apps that start on a workspace (Apps tab). The list is the `workspaceApps`
// setting (a JSON text, see parse()); entries are {id, workspace (1 to 10, or "special"), kind ("app": a desktop
// entry id, or "command": a shell command line), value, delay (0 to 60 s), when ("login" or "first-visit"),
// skipIfRunning, windowState ("normal", "float", "maximize", "fullscreen"), enabled}.
//
// The shell sets `autorun`; then (after a short pause for Hyprland) every enabled "login" entry starts once its delay
// has passed, and "first-visit" entries start the first time their workspace is focused while empty. This is the
// shell's job, not Hyprland's config: nothing here writes a Hyprland file. A window is placed with an exec rule,
// `hl.dsp.exec_cmd(cmd, { workspace = "3 silent", float = true })` dispatched through Hyprland (checked on Hyprland
// 0.56.2: the rule table takes workspace, float, maximize and fullscreen), so the window appears on its workspace
// without taking the focus and has its state from the first frame. Limit: the rule follows the process Hyprland
// starts; an app that hands the request to an instance that already runs (a browser) opens its window from that
// process, which the rule does not reach. skipIfRunning is on by default for that reason.
// What has run survives a hot reload (PersistentProperties), so a QML save does not start the apps again.
//
// Tests (never launch real apps): SLEEPYSHELL_APPS_LOG (see DefaultApps) turns every dispatch into a line in a
// file; `fakeClasses` replaces the window classes read from Hyprland and `emptyOverride` the "workspace is empty" check.
Singleton {
    id: root

    // true in the shell only: it starts the login entries and watches workspace changes
    property bool autorun: false

    // the special workspace's name: the user's binds use special:magic (SUPER+S moves a window there)
    readonly property string specialName: "special:magic"

    // test hooks (null: use Hyprland)
    property var fakeClasses: null
    property var emptyOverride: null

    // ---- the list -----------------------------------------------------------------------------

    readonly property var whenOptions: [
        {
            value: "login",
            label: "At login"
        },
        {
            value: "first-visit",
            label: "On first visit"
        }
    ]
    readonly property var stateOptions: [
        {
            value: "normal",
            label: "Normal"
        },
        {
            value: "float",
            label: "Floating"
        },
        {
            value: "maximize",
            label: "Maximised"
        },
        {
            value: "fullscreen",
            label: "Fullscreen"
        }
    ]

    function newId() {
        return "a" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36);
    }

    // one entry with every field in range; an unreadable one is dropped by parse()
    function normalise(e) {
        if (!e || typeof e !== "object")
            return null;
        const ws = e.workspace === "special" ? "special" : Math.max(1, Math.min(10, Math.round(Number(e.workspace)) || 1));
        const d = Math.max(0, Math.min(60, Math.round(Number(e.delay)) || 0));
        return {
            id: typeof e.id === "string" && e.id !== "" ? e.id : root.newId(),
            workspace: ws,
            kind: e.kind === "command" ? "command" : "app",
            value: typeof e.value === "string" ? e.value : "",
            delay: d,
            when: e.when === "first-visit" ? "first-visit" : "login",
            skipIfRunning: e.skipIfRunning !== false,
            windowState: ["float", "maximize", "fullscreen"].includes(e.windowState) ? e.windowState : "normal",
            enabled: e.enabled !== false
        };
    }
    function blank(ws) {
        return root.normalise({
            workspace: ws ?? 1,
            kind: "app",
            value: "",
            delay: 0,
            when: "login"
        });
    }
    function parse(text) {
        try {
            const a = JSON.parse(text);
            return Array.isArray(a) ? a.map(root.normalise).filter(e => e !== null) : [];
        } catch (err) {
            return [];
        }
    }
    function serialise(list) {
        return JSON.stringify(list.map(root.normalise));
    }

    // what the shell runs: the applied list
    readonly property var entries: root.parse(Settings.workspaceApps)

    // ---- what to start ------------------------------------------------------------------------

    function baseName(p) {
        return String(p).replace(/^.*\//, "");
    }

    // (an app entry that names nothing is not looked up: the heuristic lookup of "" finds some application)
    function entryFor(e) {
        if (e.kind !== "app" || e.value.trim() === "")
            return null;
        return DesktopEntries.byId(e.value.replace(/\.desktop$/, "")) ?? DesktopEntries.heuristicLookup(e.value);
    }

    // the command line, as a string for Hyprland's exec (it runs through a shell)
    function quote(a) {
        return /^[A-Za-z0-9_@%+=:,.\/-]+$/.test(a) ? a : "'" + String(a).replace(/'/g, "'\\''") + "'";
    }
    function commandLine(e) {
        if (e.kind === "command")
            return e.value.trim();
        const entry = root.entryFor(e);
        const id = e.value.replace(/\.desktop$/, "");
        let argv = entry && entry.command && entry.command.length > 0 ? Array.from(entry.command).filter(x => !/^%[a-zA-Z%]$/.test(x)) : (id !== "" ? [id] : []);
        if (entry && entry.runInTerminal)
            argv = DefaultApps.terminalCommand(argv);
        return argv.map(root.quote).join(" ");
    }

    function workspaceRule(e) {
        return (e.workspace === "special" ? root.specialName : String(e.workspace)) + " silent";
    }

    // a string as a Lua string literal
    function luaString(s) {
        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "\\r") + '"';
    }

    // the Hyprland dispatcher that starts the entry on its workspace
    function dispatchText(e) {
        const rules = ["workspace = " + root.luaString(root.workspaceRule(e))];
        if (e.windowState !== "normal")
            rules.push(e.windowState + " = true");
        return "hl.dsp.exec_cmd(" + root.luaString(root.commandLine(e)) + ", { " + rules.join(", ") + " })";
    }

    // the one place something starts from this file
    function dispatch(text) {
        if (DefaultApps.logPath !== "")
            Quickshell.execDetached(["sh", "-c", 'printf "DISPATCH %s\\n" "$1" >> "$2"', "sh", text, DefaultApps.logPath]);
        else
            Hyprland.dispatch(text);
    }
    function note(text) {
        if (DefaultApps.logPath !== "")
            Quickshell.execDetached(["sh", "-c", 'printf "NOTE %s\\n" "$1" >> "$2"', "sh", text, DefaultApps.logPath]);
    }

    // "Run now": start it at once, ignoring the delay and skipIfRunning
    function runNow(e) {
        if (root.commandLine(e) === "")
            return;
        root.dispatch(root.dispatchText(e));
    }

    // ---- is it running ------------------------------------------------------------------------

    // window classes an entry's window may have, lower case
    function entryClasses(e) {
        const out = [];
        const add = x => {
            const v = String(x ?? "").toLowerCase();
            if (v !== "" && !out.includes(v))
                out.push(v);
        };
        if (e.kind === "app") {
            const en = root.entryFor(e);
            add(e.value.replace(/\.desktop$/, ""));
            if (en) {
                add(en.id);
                add(en.startupClass);
                add(en.name);
                if (en.command && en.command.length > 0)
                    add(root.baseName(en.command[0]));
            }
        } else {
            const first = e.value.trim().split(/\s+/)[0];
            add(root.baseName(first));
        }
        return out;
    }
    function openClasses() {
        if (root.fakeClasses !== null)
            return root.fakeClasses.map(x => String(x).toLowerCase());
        return Hyprland.toplevels.values.map(t => String(t.lastIpcObject?.class ?? t.wayland?.appId ?? "").toLowerCase());
    }
    function isRunning(e) {
        const want = root.entryClasses(e);
        return root.openClasses().some(c => c !== "" && want.includes(c));
    }

    // ---- the schedule ---------------------------------------------------------------------------

    PersistentProperties {
        id: session
        reloadableId: "workspaceApps"
        // ids already started at login, ids whose first visit has been seen (comma separated)
        property string ranLogin: ""
        property string seen: ""
    }
    function has(list, id) {
        return list.split(",").includes(id);
    }
    function add(list, id) {
        return list === "" ? id : list + "," + id;
    }

    // entries waiting for their delay: {e, due (ms)}
    property var queue: []

    function schedule(e) {
        root.queue = root.queue.concat([
            {
                e: e,
                due: Date.now() + e.delay * 1000
            }
        ]);
    }

    function fire(e) {
        if (e.skipIfRunning && root.isRunning(e)) {
            root.note("skip " + e.id + " (already running)");
            return;
        }
        root.runNow(e);
    }

    Timer {
        interval: 250
        repeat: true
        running: root.queue.length > 0
        onTriggered: {
            const now = Date.now();
            const due = root.queue.filter(q => q.due <= now);
            if (due.length === 0)
                return;
            root.queue = root.queue.filter(q => q.due > now);
            for (const q of due)
                root.fire(q.e);
        }
    }

    // after the shell starts Hyprland needs a moment to tell about its windows; the login entries wait for it
    Timer {
        id: startPause
        interval: 1500
        onTriggered: root.start()
    }
    onAutorunChanged: if (root.autorun)
        startPause.restart()

    function start() {
        for (const e of root.entries) {
            if (!e.enabled || e.when !== "login" || root.has(session.ranLogin, e.id))
                continue;
            session.ranLogin = root.add(session.ranLogin, e.id);
            root.schedule(e);
        }
        // the workspace already in front counts as visited
        const w = Hyprland.focusedWorkspace;
        if (w)
            root.visit(root.keyOf(w.name));
    }

    // "3" for workspace 3, "special" for the special workspace, "" for anything else
    function keyOf(name) {
        if (/^\d+$/.test(name))
            return name;
        return name.startsWith("special:") ? "special" : "";
    }

    function workspaceEmpty(key) {
        if (root.emptyOverride !== null)
            return root.emptyOverride;
        const name = key === "special" ? root.specialName : key;
        const w = Hyprland.workspaces.values.find(x => x.name === name);
        return !w || (w.toplevels?.values?.length ?? 0) === 0;
    }

    // a workspace was focused; start its first-visit entries once, if it is empty
    function visit(key) {
        if (key === "")
            return;
        for (const e of root.entries) {
            if (!e.enabled || e.when !== "first-visit" || String(e.workspace) !== key || root.has(session.seen, e.id))
                continue;
            session.seen = root.add(session.seen, e.id);
            if (root.workspaceEmpty(key))
                root.schedule(e);
            else
                root.note("visit " + key + ": " + e.id + " not started (workspace not empty)");
        }
    }

    Connections {
        target: Hyprland
        enabled: root.autorun
        function onRawEvent(ev) {
            // workspacev2: "3,3"; activespecialv2: "-98,special:magic,DP-1" (an empty name: it closed)
            if (ev.name === "workspacev2")
                root.visit(root.keyOf(ev.data.split(",").slice(1).join(",")));
            else if (ev.name === "activespecialv2") {
                const parts = ev.data.split(",");
                if (parts.length > 1 && parts[1] !== "")
                    root.visit(root.keyOf(parts[1]));
            }
        }
    }
}
