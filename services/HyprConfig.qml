pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// What the user's Hyprland config loads and binds, found by scripts/hyprconf.py `discover`: it starts at
// hyprland.lua (hyprland.conf when there is no Lua config), follows every require (source in .conf) and reads the binds, the
// workspace rules and the monitors out of all of those files without running Hyprland. Used by the settings window only: the
// Keybinds tab lists the binds, the Config tab lists the files they came from, and FileChecks asks which files Hyprland
// really loads (a file that is not on the list is never read by Hyprland, whatever it holds).
//
// `keybindExtraFiles` (Config tab > Advanced) are config files Hyprland loads some other way; each is run through the same script
// as if it were the main file, and its binds are added.
//
// Refreshes: at start, when the Keybinds tab opens (`refresh()`), when one of the files changes (a FileView per file, watching),
// and on Hyprland's own `configreloaded` event. All three go through one short timer, so a save that touches several files
// runs the script once. Without python3 or when the script fails, `ok` is false and the Keybinds tab falls back to parsing
// binds.lua itself (services/Keybinds.qml), and nothing is judged "not loaded".
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/hypr"
    readonly property string script: Quickshell.shellPath("scripts/hyprconf.py")

    // the last answer for the main config
    property bool ready: false
    property bool ok: false
    property string error: ""
    property string format: ""
    property string main: ""
    property var files: []
    property var mainBinds: []
    property var unreadable: []
    property var monitors: []
    // path -> the discover result of one extra keybind file
    property var extras: ({})
    // bumped on every new answer, so a binding can depend on "the list changed"
    property int generation: 0

    // the paths Hyprland loads (missing ones are on the list too: hyprland.lua asks for them, they are just not there)
    readonly property var loadedPaths: root.files.map(f => f.path)
    // all binds: the main config's, then each extra file's (a file the main config already loads is not read twice)
    readonly property var binds: {
        let out = root.mainBinds.slice();
        const seen = new Set(root.loadedPaths);
        for (const p of Settings.keybindExtraFiles) {
            const r = root.extras[p];
            if (!r || seen.has(p))
                continue;
            out = out.concat(r.binds ?? []);
        }
        return out;
    }
    // every file a bind was found in, in the order found
    readonly property var bindFiles: {
        const out = [];
        for (const b of root.binds)
            if (!out.includes(b.file))
                out.push(b.file);
        return out;
    }

    function isLoaded(path) {
        return root.loadedPaths.includes(path);
    }
    // a file the config asks for but that is not there
    function isMissing(path) {
        const f = root.files.find(x => x.path === path);
        return f ? f.missing === true : false;
    }

    function refresh() {
        refreshTimer.restart();
    }

    function runNow() {
        if (!Deps.has("python3")) {
            root.ok = false;
            root.error = "python3 is not installed";
            root.ready = true;
            return;
        }
        if (!mainProc.running)
            mainProc.running = true;
        else
            root.again = true;
        for (let i = 0; i < extraProcs.count; i++)
            extraProcs.objectAt(i).start();
    }

    // a refresh asked for while the script ran: run once more when it ends
    property bool again: false

    // the answer for the main config
    function take(text) {
        let d = null;
        try {
            d = JSON.parse(text);
        } catch (e) {
            d = null;
        }
        if (!d || d.error || !d.main) {
            root.ok = false;
            root.error = d && d.error ? d.error : "scripts/hyprconf.py gave no answer";
            root.files = [];
            root.mainBinds = [];
            root.unreadable = [];
            root.monitors = [];
            root.main = "";
            root.format = "";
        } else {
            root.ok = true;
            root.error = "";
            root.format = d.format;
            root.main = d.main;
            root.files = d.files;
            root.mainBinds = d.binds;
            root.unreadable = d.unreadable;
            root.monitors = d.monitors;
        }
        root.ready = true;
        root.generation++;
    }

    function takeExtra(path, text) {
        let d = null;
        try {
            d = JSON.parse(text);
        } catch (e) {
            d = null;
        }
        const next = Object.assign({}, root.extras);
        next[path] = d && !d.error ? d : { binds: [], files: [], error: d && d.error ? d.error : "no answer" };
        root.extras = next;
        root.generation++;
    }

    Timer {
        id: refreshTimer
        interval: 250
        onTriggered: root.runNow()
    }

    Component.onCompleted: root.runNow()

    Process {
        id: mainProc
        command: ["python3", root.script, "discover", "--root", root.dir]
        stdout: StdioCollector {
            onStreamFinished: root.take(text)
        }
        onExited: {
            if (root.again) {
                root.again = false;
                running = true;
            }
        }
    }

    // one run per extra file, as if it were the main config
    Instantiator {
        id: extraProcs
        model: Settings.keybindExtraFiles

        delegate: QtObject {
            id: probe
            required property string modelData
            function start() {
                if (!proc.running)
                    proc.running = true;
            }
            property Process proc: Process {
                command: ["python3", root.script, "discover", "--root", probe.modelData]
                stdout: StdioCollector {
                    onStreamFinished: root.takeExtra(probe.modelData, text)
                }
            }
            Component.onCompleted: probe.start()
        }
    }

    // a watch on each file the config loads: a save to any of them refreshes (hyprland.lua itself included)
    Instantiator {
        model: root.files.filter(f => !f.missing).map(f => f.path).concat(Settings.keybindExtraFiles)

        delegate: FileView {
            required property string modelData
            path: modelData
            watchChanges: true
            printErrors: false
            onFileChanged: root.refresh()
        }
    }

    // Hyprland reloaded its config (a save of any file it loads, or `hyprctl reload`)
    function onHyprEvent(name) {
        if (name === "configreloaded")
            root.refresh();
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            root.onHyprEvent(event.name);
        }
    }
}
