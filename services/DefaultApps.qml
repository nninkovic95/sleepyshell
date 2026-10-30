pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The programs the shell opens things with (Apps tab): the desktop's
// default applications, which live in the XDG database (mimeapps.list, read with `xdg-mime query default`) and are
// written back with `xdg-mime default`; and the terminal, which has no XDG entry and is the `defaultTerminal` setting.
// Every launch of a terminal, an editor, a folder or a link in the shell goes through the four commands below
// (terminalCommand, editorCommand, openUrl, revealDir), so changing a default changes the whole shell.
//
// Where the data comes from: scripts/defaultapps.py scan reads the current defaults and the installed applications
// that handle each category (Quickshell 0.3.2's DesktopEntry has no MimeType property, so the candidates come from
// the mimeinfo.cache files); DesktopEntries supplies the terminal emulators (Categories=TerminalEmulator) and the
// launch command of an entry. The defaults are a draft here (`staged`) until Apply, like the Settings keys.
// scripts/hyprconf.py programs reads the program names of the Hyprland config (programs.lua), to tell when its
// keybinds open different programs (the tab shows a note and a button that opens the file). After an Apply the tab may also ask to change those
// entries (planPrograms / writePrograms below: hyprconf.py set-programs, after a question that shows the exact lines).
//
// Test hook: with the environment variable SLEEPYSHELL_APPS_LOG set to a file, run() appends what it would have
// started to that file instead of starting it (the Apps tests; nothing in the shell sets it).
Singleton {
    id: root

    readonly property string logPath: Quickshell.env("SLEEPYSHELL_APPS_LOG") ?? ""

    // ---- the one place an outside program starts from this file -----------------------------------

    function run(argv) {
        if (root.logPath !== "")
            Quickshell.execDetached(["sh", "-c", 'printf "RUN %s\\n" "$1" >> "$2"', "sh", JSON.stringify(argv), root.logPath]);
        else
            Quickshell.execDetached(argv);
    }

    // ---- terminal -----------------------------------------------------------------------------

    // the terminal emulator's program name, "kitty" by default (applied value: a launch must not follow a draft)
    readonly property string terminal: Settings.defaultTerminal

    // installed terminal emulators: {value: program name, label, icon}; the chosen one is listed even if no entry says so
    readonly property var terminals: {
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (!(e.categories ?? []).includes("TerminalEmulator") || !e.command || e.command.length === 0)
                continue;
            const v = root.baseName(e.command[0]);
            if (!out.some(o => o.value === v))
                out.push({
                    value: v,
                    label: e.name,
                    icon: root.iconFor(e.icon)
                });
        }
        out.sort((a, b) => a.label.localeCompare(b.label));
        return out;
    }
    function terminalOptions(chosen) {
        const list = root.terminals.slice();
        if (chosen !== "" && !list.some(o => o.value === chosen))
            list.unshift({
                value: chosen,
                label: chosen,
                icon: root.iconFor("utilities-terminal")
            });
        return list;
    }

    // `argv` run inside the terminal, as the argument list that starts it. opts: {cls: window class / app id,
    // title: window title} where the terminal has such options. Each terminal takes these differently.
    function terminalCommand(argv, opts) {
        return root.terminalWith(root.terminal, argv, opts);
    }
    function terminalWith(term, argv, opts) {
        const cls = opts?.cls ?? "";
        const title = opts?.title ?? "";
        const a = [term];
        switch (term) {
        case "foot":
            if (cls) a.push("--app-id", cls);
            if (title) a.push("--title", title);
            break;
        case "alacritty":
            if (cls) a.push("--class", cls);
            if (title) a.push("--title", title);
            a.push("-e");
            break;
        case "wezterm":
            a.push("start");
            if (cls) a.push("--class", cls);
            a.push("--");
            break;
        case "ghostty":
            if (cls) a.push("--class=" + cls);
            if (title) a.push("--title=" + title);
            a.push("-e");
            break;
        case "konsole":
            if (title) a.push("-p", "tabtitle=" + title);
            a.push("-e");
            break;
        case "gnome-terminal":
            if (cls) a.push("--class=" + cls);
            if (title) a.push("--title=" + title);
            a.push("--");
            break;
        case "xterm":
            if (cls) a.push("-class", cls);
            if (title) a.push("-T", title);
            a.push("-e");
            break;
        default: // kitty, and the unknown: `-e` is the most common spelling
            if (term === "kitty") {
                if (cls) a.push("--class", cls);
                if (title) a.push("--title", title);
            }
            a.push("-e");
        }
        return a.concat(argv);
    }
    // a shell command line in the terminal (the keybinds' "Run in terminal")
    function terminalShell(cmd, opts) {
        return root.terminalCommand(["sh", "-c", cmd], opts);
    }
    function runInTerminal(argv, opts) {
        root.run(root.terminalCommand(argv, opts));
    }

    // ---- editor, folders, links ---------------------------------------------------------------

    // the text editor's command for a file; the desktop's opener while no editor is set
    function editorCommand(path) {
        const argv = root.execArgv(root.currentId("editor"));
        if (argv.length === 0)
            return ["xdg-open", path];
        const cmd = argv.concat([path]);
        return root.needsTerminal(root.currentId("editor")) ? root.terminalCommand(cmd) : cmd;
    }
    function openInEditor(path) {
        root.run(root.editorCommand(path.replace(/^~(?=\/|$)/, Quickshell.env("HOME"))));
    }
    // the editor's program (Deps probes it: a button that opens a file is greyed while it is missing)
    readonly property string editorProgram: {
        const a = root.execArgv(root.currentId("editor"));
        return a.length > 0 ? (root.needsTerminal(root.currentId("editor")) ? root.terminal : root.baseName(a[0])) : "xdg-open";
    }
    onEditorProgramChanged: Deps.want(root.editorProgram)
    Component.onCompleted: Deps.want(root.editorProgram)
    // folders and links go to the desktop's opener, which follows the defaults written here
    readonly property string openerProgram: "xdg-open"
    function openUrl(url) {
        root.run(["xdg-open", url]);
    }
    function revealDir(dir) {
        root.run(["xdg-open", dir]);
    }

    // ---- the default applications --------------------------------------------------------------

    // [{id, label, probe, types, current, candidates: [{id, name, icon, exec, terminal}]}] from the last scan
    property var categories: []
    property string mimeappsPath: Quickshell.env("HOME") + "/.config/mimeapps.list"
    property bool hasSettings: false
    property bool scanned: false
    // category id -> desktop id picked and not applied
    property var staged: ({})
    readonly property bool dirty: Object.keys(root.staged).length > 0
    property bool applying: false
    property string error: ""

    function category(id) {
        return root.categories.find(c => c.id === id) ?? null;
    }
    // the applied default of a category, "" when none
    function currentId(id) {
        return root.category(id)?.current ?? "";
    }
    // what the tab shows: the draft, else the applied one
    function chosenId(id) {
        return root.staged.hasOwnProperty(id) ? root.staged[id] : root.currentId(id);
    }
    function stage(id, desktopId) {
        const s = Object.assign({}, root.staged);
        if (desktopId === root.currentId(id))
            delete s[id];
        else
            s[id] = desktopId;
        root.staged = s;
    }
    function discard() {
        root.staged = {};
    }
    // dropdown options of a category, each with its icon; the current default first if the scan did not list it
    function options(id) {
        const c = root.category(id);
        if (!c)
            return [];
        return c.candidates.map(a => ({
                    value: a.id,
                    label: a.name,
                    icon: root.iconFor(a.icon)
                }));
    }

    function apply() {
        const pairs = Object.keys(root.staged).map(k => k + "=" + root.staged[k]);
        if (pairs.length === 0)
            return;
        root.applying = true;
        root.error = "";
        applyProc.command = ["python3", Quickshell.shellPath("scripts/defaultapps.py"), "apply"].concat(pairs);
        applyProc.running = true;
    }

    function refresh() {
        scanProc.running = false;
        scanProc.running = true;
        programsProc.running = false;
        programsProc.running = true;
    }

    // the first scan, asked for by what needs the data (the Apps tab, Keybinds in the settings window); the shell
    // itself never needs it (its launches are the terminal setting and xdg-open), so it never scans
    property bool requested: false
    function ensure() {
        if (root.requested)
            return;
        root.requested = true;
        Deps.want("xdg-mime");
        Deps.want("xdg-settings");
        root.refresh();
    }

    Process {
        id: scanProc
        command: ["python3", Quickshell.shellPath("scripts/defaultapps.py"), "scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.categories = d.categories;
                    root.mimeappsPath = d.mimeapps;
                    root.hasSettings = d.hasSettings;
                    root.scanned = true;
                } catch (e) {
                    root.error = "Could not read the default applications.";
                }
            }
        }
    }

    Process {
        id: applyProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.error = d.errors.join(" ");
                } catch (e) {
                    root.error = "Could not set the default applications.";
                }
            }
        }
        onExited: {
            root.applying = false;
            root.staged = {};
            root.refresh();
        }
    }

    // ---- desktop entries -----------------------------------------------------------------------

    function baseName(p) {
        return String(p).replace(/^.*\//, "");
    }

    // an icon name (or absolute path) as an Image source; "glyph:" when the icon theme has neither the icon nor the
    // generic application icon, so the pickers draw a themed glyph instead of Qt's magenta "missing" square
    function iconFor(name) {
        if (name && name.startsWith("/"))
            return "file://" + name;
        return Quickshell.iconPath(name || "application-x-executable", true) || Quickshell.iconPath("application-x-executable", true) || "glyph:";
    }

    // the Exec line of a .desktop file as an argument list, field codes (%u, %F ...) dropped
    function splitExec(line) {
        const out = [];
        let cur = "", quote = "", has = false;
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (quote) {
                if (c === "\\" && i + 1 < line.length)
                    cur += line[++i];
                else if (c === quote)
                    quote = "";
                else
                    cur += c;
            } else if (c === '"' || c === "'") {
                quote = c;
                has = true;
            } else if (/\s/.test(c)) {
                if (has || cur !== "")
                    out.push(cur);
                cur = "";
                has = false;
            } else
                cur += c;
        }
        if (has || cur !== "")
            out.push(cur);
        return out.filter(x => !/^%[a-zA-Z%]$/.test(x)).map(x => x.replace(/%%/g, "%"));
    }

    // the launch command of an application by desktop id ("codium.desktop"); [] when unknown
    function execArgv(desktopId) {
        if (!desktopId)
            return [];
        const plain = desktopId.replace(/\.desktop$/, "");
        const e = DesktopEntries.byId(plain);
        if (e && e.command && e.command.length > 0)
            return Array.from(e.command).filter(x => !/^%[a-zA-Z%]$/.test(x));
        for (const c of root.categories) {
            const a = c.candidates.find(x => x.id === desktopId);
            if (a)
                return root.splitExec(a.exec);
        }
        return [];
    }
    function needsTerminal(desktopId) {
        const e = DesktopEntries.byId(String(desktopId).replace(/\.desktop$/, ""));
        if (e)
            return e.runInTerminal;
        for (const c of root.categories) {
            const a = c.candidates.find(x => x.id === desktopId);
            if (a)
                return a.terminal;
        }
        return false;
    }
    // an application's program name, the word a keybind would use
    function programOf(desktopId) {
        const a = root.execArgv(desktopId);
        return a.length > 0 ? root.baseName(a[0]) : "";
    }

    // ---- the Hyprland config's programs (read only) ---------------------------------------------

    // {terminal, browser, editor ...} from programs.lua, and the file
    property var bindPrograms: ({})
    property string programsFile: ""
    // the workspace rules of the Hyprland config, [{file, line, workspace, rules, raw}], shown read only
    property var workspaceRules: []
    // the apps the Hyprland config itself starts on a workspace (exec lines with a workspace, window rules with one),
    // [{kind: "exec" | "rule", app, workspace, file, line, raw}], shown read only on the Apps tab
    property var hyprWorkspaceApps: []

    // "Your keybinds open kitty, not foot", or "" when the keybinds and the defaults agree
    readonly property string bindNote: {
        const checks = [["terminal", root.terminal], ["browser", root.programOf(root.currentId("browser"))], ["editor", root.programOf(root.currentId("editor"))]];
        const parts = [];
        for (const [k, def] of checks) {
            const bound = root.baseName((root.bindPrograms[k] ?? "").trim().split(/\s+/)[0]);
            if (bound !== "" && def !== "" && bound !== def)
                parts.push(bound + ", not " + def);
        }
        return parts.length > 0 ? "Your keybinds open " + parts.join("; ") : "";
    }

    Process {
        id: programsProc
        command: ["python3", Quickshell.shellPath("scripts/hyprconf.py"), "programs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.bindPrograms = d.values ?? {};
                    root.programsFile = d.file ?? "";
                    root.workspaceRules = d.workspaceRules ?? [];
                    root.hyprWorkspaceApps = d.workspaceApps ?? [];
                } catch (e) {
                    root.bindPrograms = {};
                }
            }
        }
    }

    function openProgramsFile() {
        if (root.programsFile !== "")
            root.openInEditor(root.programsFile);
    }

    // ---- programs.lua follows the defaults ---------------------------------------
    // After an Apply of the Apps tab the entries terminal, browser, editor and fileManager of programs.lua that already exist are set to the programs
    // just chosen, so the keybinds open them. Only after a question that shows the exact changed lines (the tab's ConfirmDialog); scripts/hyprconf.py
    // set-programs keeps a backup, writes atomically, reads the values back and puts the file back when they do not match. Never adds or removes an entry.
    readonly property string hyprconf: Quickshell.shellPath("scripts/hyprconf.py")
    readonly property var hyprRootArgs: []
    // {key: program} the last plan was made for, and the dry run's answer
    property var programsWanted: ({})
    property var programsPlan: ({})
    property bool programsWriting: false
    // the tab shows the question when the plan has lines to change
    signal programsAsk(var plan)

    // wanted: { terminal, browser, editor, fileManager } -> a program name; only the entries whose keybind program differs are planned
    function planPrograms(wanted) {
        const want = {};
        for (const k of Object.keys(wanted)) {
            const v = String(wanted[k] ?? "").trim();
            if (v === "" || !root.bindPrograms.hasOwnProperty(k))
                continue;
            if (root.baseName(String(root.bindPrograms[k]).trim().split(/\s+/)[0]) !== v)
                want[k] = v;
        }
        root.programsWanted = want;
        if (Object.keys(want).length === 0 || root.programsFile === "")
            return;
        planProc.command = ["python3", root.hyprconf, "set-programs", "--dry-run"].concat(root.hyprRootArgs, Object.keys(want).map(k => k + "=" + want[k]));
        planProc.running = true;
    }

    // after the question was answered with Update
    function writePrograms() {
        if (root.programsWriting || Object.keys(root.programsWanted).length === 0)
            return;
        root.programsWriting = true;
        writeProc.command = ["python3", root.hyprconf, "set-programs"].concat(root.hyprRootArgs, Object.keys(root.programsWanted).map(k => k + "=" + root.programsWanted[k]));
        writeProc.running = true;
    }

    Process {
        id: planProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.programsPlan = d;
                    if (d.ok && d.changes.length > 0)
                        root.programsAsk(d);
                } catch (e) {
                    root.programsPlan = {};
                }
            }
        }
    }

    Process {
        id: writeProc
        stdout: StdioCollector {
            id: writeOut
        }
        onExited: {
            root.programsWriting = false;
            try {
                const d = JSON.parse(writeOut.text);
                root.error = d.ok ? "" : d.message;
            } catch (e) {
                root.error = "Could not change programs.lua.";
            }
            programsProc.running = false;
            programsProc.running = true;
        }
    }
}
