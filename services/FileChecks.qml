pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// What state is every file Sleepysettings reads or writes in, and what does that break (grey out the rows,
// sections and tabs a missing, read-only or never-loaded file would make useless, and say exactly why and what to do). Used by the
// settings window only. Each file has an id:
//
//   settings     sleepysettings.toml (Settings.path): the window's banner (a damaged or read-only file); no greying
//   hypridle     the hypridle.conf the Idle tab writes (scripts/idle.py): a missing file is fine (it is created), a missing folder
//                or a read-only file greys the Idle tab; hypridle reads the file itself, Hyprland does not load it
//   monitors     the monitors file the Display tab reads and writes; Hyprland must load it
//   custombinds  the file the Keybinds tab adds binds to; Hyprland must load it
//   colors       colors.json (matugen writes it, the shell reads it): missing means no theme has run yet (offer a first run)
//   wallpaper    the wallpaper folder: missing greys the Theme tab's wallpaper buttons
//
// `problem(id)` is null when the file is fine, else
//   { id, kind, grey, text, tip, requireLine, wiki, action, actionText, path }
//   kind     "missing" | "noCreate" | "notWritable" | "notLoaded" | "noConfig" | "damaged"
//   grey     the rows that depend on it grey out (a missing colors.json only offers its fix)
//   text     what is wrong and what to do, in plain words, two short sentences at most, no path in it
//   tip      the detail for the "!" next to it: the exact path, why, what the button does
//   requireLine  the line to add to hyprland.lua ("" when none); it is shown on a row of its own, and a click copies it
//   action   the button that matches the fix: "create" | "openHypr" (hyprland.lua in the editor) | "configure" (the Config tab) |
//            "openSettings" | "shuffle" (the first theme run); `actionText` is its label
//   wiki     a HyprWiki key for a second button on a read-only Hyprland file ("" for none)
// The existence and permissions come from scripts/filecheck.py (one run for all paths); whether Hyprland loads a file comes from
// HyprConfig (scripts/hyprconf.py). Until the first answers arrive nothing is reported, so nothing flashes grey.
// `create(id)` makes what is missing, the folder first: the monitors file with the current layout (Displays), the folder of hypridle.conf,
// the wallpaper folder (empty). Sleepysettings' own files (sleepybinds.lua) are never reported missing: they are made, with
// their header, by the first write (`withDir` makes the folder first), and "not loaded" is reported for them only while something that needs
// them is on (Num Lock at login, keybinds added). hyprland.lua is edited only by `setUp`, after the window asked.
Singleton {
    id: root

    // "Configure in Config": the window opens the Config tab, opens Advanced if needed and highlights the row of this file id
    signal configureRequested(string id)
    // the Theme tab's first theme run (the notice's button): the tab runs scripts/theme.py
    signal themeRunRequested()
    // "Set up" on a file Hyprland does not load: the window asks first (a dialog with the line), then calls setUp(id)
    signal setupRequested(var problem)

    readonly property var ids: ["settings", "hypridle", "monitors", "custombinds", "colors", "wallpaper"]

    readonly property var labels: ({
            settings: "Settings file",
            hypridle: "Idle config",
            monitors: "Monitors config",
            custombinds: "Custom keybinds file",
            colors: "Theme colours file",
            wallpaper: "Wallpaper folder"
        })
    // the files Hyprland has to load itself to honour what Sleepysettings writes into them
    readonly property var hyprLoads: ({ monitors: true, custombinds: true })
    // the module name hyprland.lua requires (by the file's place under the Hyprland folder), for the require line
    readonly property var wikiKeys: ({
            monitors: "monitors",
            custombinds: "binds",
            hypridle: "hypridle"
        })

    // the applied path of each file (what the consumers use) ...
    function pathOf(id) {
        switch (id) {
        case "settings":
            return Settings.path;
        case "hypridle":
            return Settings.pathHypridle;
        case "monitors":
            return Settings.pathMonitors;
        case "custombinds":
            return Settings.pathCustombinds;
        case "colors":
            return Settings.pathColors;
        case "wallpaper":
            return Settings.expand(Settings.wallpaperDir);
        }
        return "";
    }

    // ... and the staged one, which the Config tab shows beside the row while it differs
    function stagedPathOf(id) {
        const k = { hypridle: "pathHypridle", monitors: "pathMonitors", custombinds: "pathCustombinds", colors: "pathColors", wallpaper: "wallpaperDir" }[id];
        return k ? Settings.expand(String(Settings.get(k))) : root.pathOf(id);
    }

    // every path to ask about: the applied and staged path of each id, and the extra keybind files
    readonly property var paths: {
        const out = [];
        for (const id of root.ids) {
            for (const p of [root.pathOf(id), root.stagedPathOf(id)])
                if (p !== "" && !out.includes(p))
                    out.push(p);
        }
        for (const p of Settings.keybindExtraFiles.concat(Settings.asList(Settings.get("keybindExtraFiles")).map(x => Settings.expand(x))))
            if (!out.includes(p))
                out.push(p);
        for (const p of HyprConfig.files.map(f => f.path))
            if (!out.includes(p))
                out.push(p);
        return out;
    }

    // path -> filecheck.py's answer
    property var results: ({})
    property bool ready: false
    property bool again: false
    onPathsChanged: Qt.callLater(root.refresh)

    function refresh() {
        if (!Deps.has("python3"))
            return;
        if (check.running) {
            root.again = true;
            return;
        }
        check.command = ["python3", Quickshell.shellPath("scripts/filecheck.py")].concat(root.paths);
        check.running = true;
    }

    function info(path) {
        return root.results[path] ?? null;
    }

    Process {
        id: check
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const next = {};
                    for (const r of JSON.parse(text))
                        next[r.path] = r;
                    root.results = next;
                    root.ready = true;
                } catch (e) {
                    console.warn("filecheck: unreadable answer", e);
                }
            }
        }
        onExited: {
            if (root.again) {
                root.again = false;
                root.refresh();
            }
        }
    }

    // Hyprland's own answer changes who loads what; a refresh of the stat answers also follows a saved file
    Connections {
        target: HyprConfig
        function onGenerationChanged() {
            root.refresh();
        }
    }

    Component.onCompleted: Qt.callLater(root.refresh)

    // ---- the require line that makes Hyprland load a file ----
    function dirOf(p) {
        const i = p.lastIndexOf("/");
        return i <= 0 ? "/" : p.slice(0, i);
    }

    // require("modules.monitors") for a file under the Hyprland folder; the absolute path (without .lua) otherwise
    function requireLine(path) {
        const dir = HyprConfig.dir + "/";
        if (HyprConfig.format === "conf")
            return "source = " + Settings.tilde(path);
        const mod = path.startsWith(dir) ? path.slice(dir.length).replace(/\.lua$/, "").replace(/\//g, ".") : path.replace(/\.lua$/, "");
        return 'require("' + mod + '")';
    }

    // ---- the verdict for one file ----
    // the detail behind a notice's "!": a sentence or two in plain words, then the path on a muted line of its own
    function tipOf(sentences, path) {
        return sentences + "<br><font color='" + Theme.fgMuted + "'>" + String(path).replace(/</g, "&lt;") + "</font>";
    }

    function make(id, kind, grey, text, tip, extra) {
        return Object.assign({ id: id, kind: kind, grey: grey, text: text, tip: tip, path: root.pathOf(id), requireLine: "", wiki: "", action: "", actionText: "" }, extra ?? {});
    }

    // what each file is, in plain words: its name for a sentence, what it stores, and what stops working without it (every message names the file, says what it is for and what the button does)
    readonly property var about: ({
            settings: { name: "Settings file", stores: "everything you set in Sleepysettings", off: "your settings can't be saved" },
            hypridle: { name: "Idle settings file", stores: "the idle timers", off: "idle times can't be saved" },
            monitors: { name: "Monitors file", stores: "your screen settings", off: "screen settings can't be saved" },
            custombinds: { name: "Custom keybinds file", stores: "the keybinds you add", off: "keybinds you add can't be saved" },
            colors: { name: "Theme colours file", stores: "your theme colours", off: "" },
            wallpaper: { name: "Wallpaper folder", stores: "your wallpapers", off: "wallpapers can't be offered" }
        })
    // the programs behind each file (a missing path might also mean a missing dependency): checked through Deps first, and
    // a missing one is reported INSTEAD of the file's own problem, with the command that installs it (shown, never run). What stops working
    // without each program is `effects`.
    readonly property var programsFor: ({ hypridle: ["hypridle"], monitors: ["hyprctl"], custombinds: ["hyprctl"], colors: ["matugen"], wallpaper: ["awww"] })
    readonly property var effects: ({ hypridle: "idle times have no effect", hyprctl: "Hyprland can't be asked about your screens", matugen: "theme colours can't be made", awww: "wallpapers can't be set", python3: "the theme and idle scripts can't run", magick: "theme colours can't be made" })
    // optional programs: a muted note, never a warning (khal: the Calendar tool; lspci: GPU names in the System tab)
    readonly property var optionalPrograms: [{ prog: "khal", off: "the Calendar tool is left out of the control centre" }, { prog: "lspci", off: "graphics cards show as PCI numbers in the System tab" }]
    readonly property var notes: root.optionalPrograms.filter(o => !Deps.has(o.prog)).map(o => {
        const i = Deps.install(o.prog);
        return { prog: o.prog, text: "Optional: <b>" + o.prog + "</b> isn't installed, so " + o.off + ". " + i.text, line: i.line };
    })

    // what does not work while Hyprland does not load the file
    readonly property var unloaded: ({ monitors: "your screen settings won't apply", custombinds: "keybinds you add won't work" })

    function base(path) {
        return path.slice(path.lastIndexOf("/") + 1);
    }

    function b(s) {
        return "<b>" + String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b>";
    }

    function problem(id) {
        const path = root.pathOf(id);
        const r = root.info(path);
        const ab = root.about[id];
        const shown = Settings.tilde(path);
        const wiki = root.wikiKeys[id] ?? "";
        const file = root.b(root.base(path));
        const who = ab ? ab.name + " (" + file + ")" : file;
        // a program behind the file is missing: that comes first (Until Deps has answered every program counts as present)
        const prog = (root.programsFor[id] ?? []).find(x => !Deps.has(x)) ?? (id === "colors" && r && !r.exists ? ["python3", "magick"].find(x => !Deps.has(x)) : undefined);
        if (prog !== undefined) {
            const i = Deps.install(prog);
            return root.make(id, "needs", true, root.b(prog) + " isn't installed, so " + (root.effects[prog] ?? "this can't work") + ". " + (i.line !== "" ? i.text.replace(/\.$/, ":") : i.text),
                root.tipOf("Sleepysettings needs the " + root.b(prog) + " program for this. It never installs anything itself: copy the command and run it in a terminal.", shown), { requireLine: i.line, prog: prog });
        }
        if (id === "settings") {
            if (Settings.broken) {
                // the failing line is named and quoted; the last good settings stay in use, not the defaults (toml job)
                const copy = Settings.brokenCopy !== "" ? root.base(Settings.brokenCopy) : "sleepysettings.toml.broken";
                const at = Settings.brokenLine > 0 ? " on line " + Settings.brokenLine + (Settings.brokenLineText.trim() !== "" ? " (" + root.b(Settings.brokenLineText.trim()) + ")" : "") : "";
                return root.make(id, "damaged", false, "The " + ab.name.toLowerCase() + " (" + file + ") has a mistake" + at + ", so your last working settings are used. Open it to fix the mistake (a copy was kept as " + root.b(copy) + ").",
                    root.tipOf("Sleepysettings can't read the file you saved your settings in" + (Settings.brokenWhy !== "" ? ": " + String(Settings.brokenWhy).replace(/&/g, "&amp;").replace(/</g, "&lt;") : "") + ". It keeps using your last working settings and leaves the file alone until you fix it.", shown),
                    { action: "openSettings", actionText: "Open settings file" });
            }
            if (Settings.saveError !== "" || (r && r.exists && !r.writable) || (r && !r.exists && !r.creatable))
                return root.make(id, "notWritable", false, "The " + ab.name.toLowerCase() + " (" + file + ") can't be changed, so " + ab.off + ". Check its permissions.",
                    root.tipOf("Your settings still work while this window is open, but they are not kept. Make the file or its folder writable.", shown), { action: "openSettings", actionText: "Open settings file" });
            // a value typed by hand that is the wrong kind (a word for a number) is ignored; the next Apply writes the default over it,
            // so it is said here (review)
            if (Settings.badKeys.length > 0)
                return root.make(id, "ignored", false, "Some values in " + file + " aren't the right kind, so their defaults are used: " + Settings.badKeys.map(k => root.b(k)).join(", ") + ". Fix them in the file; the next Apply writes the defaults over them.",
                    root.tipOf("A number setting needs a number, a switch true or false, and text goes in quotes.", shown), { action: "openSettings", actionText: "Open settings file" });
            return null;
        }
        if (!r)
            return null;
        if (id === "wallpaper") {
            if (!r.exists || !r.isdir) {
                const can = r.parentExists ? r.creatable : r.dirCreatable;
                return can ? root.make(id, "missing", true, who + " is missing. It holds " + ab.stores + ". Create makes it.", root.tipOf("The wallpaper picker looks here for pictures. Create makes an empty folder; put pictures in it, or choose another folder in Config.", shown), { action: "create", actionText: "Create" })
                           : root.make(id, "noCreate", true, who + " is missing and can't be made there, so " + ab.off + ". Change… picks another folder.", root.tipOf("The folder doesn't exist and can't be made here.", shown), { action: "configure", actionText: "Change…" });
            }
            if (!r.readable)
                return root.make(id, "notWritable", true, who + " can't be read, so " + ab.off + ". Change… picks another folder.", root.tipOf("This folder can't be opened.", shown), { action: "configure", actionText: "Change…" });
            return null;
        }
        if (id === "colors") {
            if (!r.exists)
                return root.make(id, "missing", false, "No theme colours yet: the " + ab.name.toLowerCase() + " (" + file + ") is missing. Shuffle colours makes them.", root.tipOf("Until a theme has been made the shell uses its built-in colours. Shuffle colours makes one from your wallpaper.", shown), { action: "shuffle", actionText: "Shuffle colours" });
            return null;
        }
        // Sleepysettings' own file (sleepybinds.lua) is made by Sleepysettings itself when it first writes it, so it is never "missing" and has no
        // Create; hypridle.conf is made by idle.py on Apply, only its folder is checked
        const own = id === "custombinds";
        const ownMissing = !r.exists && own && (r.parentExists ? r.creatable : r.dirCreatable);
        if (!r.exists && id === "hypridle" && r.parentExists)
            return null;
        // the file is not there
        if (!r.exists && !ownMissing) {
            const can = r.parentExists ? r.creatable : r.dirCreatable;
            if (id === "hypridle" && can)
                return root.make(id, "missing", true, "The folder of the " + ab.name.toLowerCase() + " (" + file + ") is missing. Create makes it.", root.tipOf("The idle timers are saved in a file in this folder. Create makes the folder; Apply in the Idle tab writes the file.", shown), { action: "create", actionText: "Create", wiki: wiki });
            if (!can)
                return root.make(id, "noCreate", true, who + " is missing and can't be made there, so " + ab.off + ". Change… picks another file.", root.tipOf("The file doesn't exist and its folder can't be written.", shown), { action: "configure", actionText: "Change…", wiki: wiki });
            // the monitors file is yours: without it the Display tab has nothing to work on
            return root.make(id, "missing", true, who + " is missing. It stores " + ab.stores + ". Create makes it.",
                root.tipOf("Create makes " + (r.parentExists ? "the file" : "the folder and the file") + ", with " + ab.stores + " as they are now.", shown), { action: "create", actionText: "Create", wiki: wiki });
        }
        if (r.exists && !r.writable)
            return root.make(id, "notWritable", true, file + " can't be changed, so " + ab.off + ". Change… picks another file.", root.tipOf("Sleepysettings can't save changes to it. Check its permissions, or pick another file.", shown),
                { action: "configure", actionText: "Change…", wiki: wiki });
        // Hyprland must load it
        if (root.hyprLoads[id] && HyprConfig.ready) {
            const main = HyprConfig.format === "conf" ? "hyprland.conf" : "hyprland.lua";
            if (!HyprConfig.ok && HyprConfig.error.startsWith("no hyprland"))
                return root.make(id, "noConfig", true, "Hyprland's main config (" + root.b(main) + ") wasn't found, so " + root.unloaded[id] + ". Create it and add this line:", root.tipOf("Hyprland only reads files that its main config file lists. Make that file, then add the line.", shown),
                    { requireLine: root.requireLine(path), wiki: "lua" });
            // an own file matters only while something that needs it exists: keybinds added here
            const needed = id === "custombinds" ? Keybinds.custom.length > 0 : true;
            if (HyprConfig.ok && !HyprConfig.isLoaded(path) && needed)
                return root.make(id, "notLoaded", !own, "Hyprland doesn't load " + file + " yet, so " + root.unloaded[id] + ". Set up adds it.",
                    root.tipOf("Hyprland only reads the files its main config lists. Set up adds the line " + root.requireLine(path) + " to " + root.b(main) + " after you confirm, and keeps a backup. You can add it yourself instead.", shown),
                    { requireLine: root.requireLine(path), action: "setup", actionText: "Set up" });
        }
        return null;
    }

    // what a notice's button does
    function act(p) {
        switch (p.action) {
        case "create":
            root.create(p.id);
            break;
        case "setup":
            root.setupRequested(p);
            break;
        case "openHypr":
            Keybinds.openFile(HyprConfig.main !== "" ? HyprConfig.main : Keybinds.mainPath);
            break;
        case "configure":
            root.configureRequested(p.id);
            break;
        case "openSettings":
            Keybinds.openFile(Settings.path);
            break;
        case "shuffle":
            root.themeRunRequested();
            break;
        }
    }

    // "" or the first greying problem's title with its text: what a greyed row says (the long form is in FileNotice)
    function needs(idList) {
        for (const id of (idList ?? [])) {
            const p = root.problem(id);
            if (p && p.grey)
                return p.text;
        }
        return "";
    }

    // the problems among these ids, in order
    function problems(idList) {
        return (idList ?? []).map(id => root.problem(id)).filter(p => p !== null);
    }

    // the short red line under a file row of the Config tab ("" for none): the notice's sentence
    function line(id) {
        const p = root.problem(id);
        if (!p || p.kind === "damaged" || p.kind === "missing")
            return "";
        return p.kind === "notLoaded" || p.kind === "noConfig" ? "Hyprland doesn't load this file yet." : p.text;
    }

    // ---- "Set up": have hyprconf.py add the line that makes Hyprland load a file (after the window asked) ----
    // the last result: { id, ok, text }; a success shows for a few seconds, a failure stays under the notice of that file
    property var setupNote: ({ id: "", ok: true, text: "" })
    property string setupBusy: ""

    function setUp(id) {
        const p = root.pathOf(id);
        if (p === "" || root.setupBusy !== "")
            return;
        root.setupBusy = id;
        setup.command = ["python3", HyprConfig.script, "add-require", p, "--root", HyprConfig.dir];
        setup.running = true;
    }

    function gotSetup(text) {
        let r = null;
        try {
            r = JSON.parse(text);
        } catch (e) {
            r = null;
        }
        const id = root.setupBusy;
        root.setupBusy = "";
        root.setupNote = r && r.ok ? { id: id, ok: true, text: r.changed ? "Done. Hyprland now loads this file." : "Hyprland already loads this file." }
                                   : { id: id, ok: false, text: "That didn't work. " + (r && r.message ? r.message : "hyprconf.py gave no answer.") };
        noteTimer.restart();
        HyprConfig.refresh();
        recheck.restart();
    }

    Timer {
        id: noteTimer
        interval: 7000
        onTriggered: if (root.setupNote.ok)
            root.setupNote = { id: "", ok: true, text: "" }
    }

    Process {
        id: setup
        stdout: StdioCollector {
            onStreamFinished: root.gotSetup(text)
        }
    }

    // ---- creating a missing file (the notice's and the Config row's Create) ----
    // the folder first (`mkdir -p`, an argument array), then the content by whoever owns the file
    property string creating: ""

    function canCreate(id) {
        const p = root.problem(id);
        return p !== null && p.action === "create";
    }

    function create(id) {
        const p = root.pathOf(id);
        if (p === "" || root.creating !== "")
            return;
        root.creating = id;
        mkdir.command = ["mkdir", "-p", id === "wallpaper" ? p : root.dirOf(p)];
        mkdir.running = true;
    }

    function made(id) {
        switch (id) {
        case "custombinds":
            Keybinds.createCustomFile();
            break;
        case "monitors":
            Displays.createFile();
            break;
        }
        root.finishCreate();
    }

    function finishCreate() {
        root.creating = "";
        HyprConfig.refresh();
        Qt.callLater(root.refresh);
        // the file was written a moment ago: ask again after it is on disk
        recheck.restart();
    }

    Timer {
        id: recheck
        interval: 400
        onTriggered: root.refresh()
    }

    Process {
        id: mkdir
        onExited: code => {
            if (code === 0)
                root.made(root.creating);
            else
                root.creating = "";
        }
    }

    // make the folder of `path` first when it is not there, then run fn (an own file's first write: sleepybinds.lua)
    property var afterDir: null
    function withDir(path, fn) {
        const r = root.info(path);
        if (r && !r.parentExists) {
            root.afterDir = fn;
            dirMake.command = ["mkdir", "-p", root.dirOf(path)];
            dirMake.running = true;
        } else {
            fn();
        }
    }

    Process {
        id: dirMake
        onExited: code => {
            const f = root.afterDir;
            root.afterDir = null;
            if (code === 0 && f)
                f();
            root.refresh();
        }
    }
}
