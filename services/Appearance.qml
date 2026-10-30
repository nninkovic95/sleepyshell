pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What the Theme tab needs to know and do outside settings.json: the community themes (`scripts/theme.py --list-presets`) and
// everything of the Appearance section (`scripts/appearance.py`: the icon and font lists with their previews, the state the desktop is in
// now, apply through gsettings, the folder icons' matugen set-up). The settings window only; every outside program is started by those
// two scripts, never here (one service per outside command). Lists are read once, when the Theme tab first shows (`ensure`), and again after an
// apply. A Process that answers nothing leaves the list empty and the rows say so.
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/appearance.py")
    readonly property string themeScript: Quickshell.shellPath("scripts/theme.py")

    property var presets: []
    property bool presetsLoaded: false
    property var state: ({})
    property bool stateLoaded: false
    property var icons: []
    property bool iconsLoaded: false
    property var fonts: []
    property bool fontsLoaded: false
    // the folder icons' templates: { templates, configured, missing, overlay, overlayBase, config }
    property var folders: ({})
    property bool foldersLoaded: false
    // five folder icons in the colours of the shown theme: { name: svg path }
    property var folderPreview: ({})
    // an apply or a set-up in progress, and what the last one said
    property bool applying: false
    property bool settingUp: false
    property string lastResult: ""
    property bool lastOk: true
    property int applies: 0
    property bool started: false

    // the programs the script found: gsettings (apply), fc-list (fonts); true until the first answer
    readonly property bool hasGsettings: root.state.available ? root.state.available.gsettings !== false : true
    readonly property bool hasFontList: root.state.available ? root.state.available.fontList !== false : true

    signal applied(bool ok)

    function ensure() {
        if (root.started)
            return;
        root.started = true;
        root.refresh();
    }

    function refresh() {
        presetsP.running = true;
        stateP.running = true;
        iconsP.running = true;
        fontsP.running = true;
        foldersP.running = true;
    }

    // ---- lookups the rows use ----

    function presetOf(family) {
        return root.presets.find(p => p.id === family) ?? null;
    }
    // "family:variant" -> { family, variant } (variant "" when only a family is given)
    function split(spec) {
        const i = String(spec).indexOf(":");
        return i < 0 ? { family: String(spec), variant: "" } : { family: spec.slice(0, i), variant: spec.slice(i + 1) };
    }
    function variantOf(spec) {
        const s = root.split(spec);
        const p = root.presetOf(s.family);
        return p ? (p.variants.find(v => v.id === s.variant) ?? null) : null;
    }
    // the variant a family opens with: the one in the shown mode, else its first
    function defaultVariant(family, mode) {
        const p = root.presetOf(family);
        if (!p || p.variants.length === 0)
            return "";
        return (p.variants.find(v => v.mode === mode) ?? p.variants[0]).id;
    }
    function titleCase(id) {
        return id.length === 0 ? id : id.charAt(0).toUpperCase() + id.slice(1);
    }
    function iconOf(id) {
        return root.icons.find(i => i.id === id) ?? null;
    }
    // the icon theme's light or dark sibling, or itself when there is none ("Papirus-Dark" and "Papirus-Light" of "Papirus"; "breeze" and
    // "breeze-dark"): only a theme that is installed is ever named
    function sibling(name, mode) {
        const ids = root.icons.map(i => i.id);
        const stem = name.replace(/-(dark|light)$/i, "");
        const want = mode === "dark" ? [stem + "-Dark", stem + "-dark"] : [stem + "-Light", stem + "-light", stem];
        return want.find(c => ids.includes(c)) ?? name;
    }
    function mark(file) {
        return file === "" ? "" : "file://" + file;
    }

    // ---- actions ----

    // set what changed: keys like ["iconTheme", "gtkFont"]; the values are read from settings.json by the script, so call it after the commit.
    // "colorScheme" sets GNOME's color-scheme to `mode` ("dark" or "light")
    function apply(keys, mode) {
        if (root.applying || keys.length === 0)
            return;
        root.applying = true;
        applyP.command = [root.script, "apply", keys.join(",")].concat(keys.includes("colorScheme") ? ["--color-scheme", mode ?? ""] : []);
        applyP.running = true;
    }

    // add the folder icons' [templates.*] lines to the matugen config (the window asked first)
    function setUpFolders() {
        if (root.settingUp)
            return;
        root.settingUp = true;
        setupP.command = [root.script, "folders-setup"];
        setupP.running = true;
    }

    function previewFolders(primary, onPrimary) {
        if (!/^#[0-9a-fA-F]{6}$/.test(primary) || !/^#[0-9a-fA-F]{6}$/.test(onPrimary))
            return;
        previewP.command = [root.script, "folders-preview", "--primary", primary, "--on", onPrimary];
        previewP.running = true;
    }

    function parse(text, fallback) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return fallback;
        }
    }

    Process {
        id: presetsP
        command: [root.themeScript, "--list-presets"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.presets = root.parse(text, []);
                root.presetsLoaded = true;
            }
        }
    }
    Process {
        id: stateP
        command: [root.script, "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.state = root.parse(text, {});
                root.stateLoaded = true;
            }
        }
    }
    Process {
        id: iconsP
        command: [root.script, "icons"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.icons = root.parse(text, { icons: [] }).icons ?? [];
                root.iconsLoaded = true;
            }
        }
    }
    Process {
        id: fontsP
        command: [root.script, "fonts"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.fonts = root.parse(text, { fonts: [] }).fonts ?? [];
                root.fontsLoaded = true;
            }
        }
    }
    Process {
        id: foldersP
        command: [root.script, "folders-state"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.folders = root.parse(text, {});
                root.foldersLoaded = true;
            }
        }
    }
    Process {
        id: previewP
        stdout: StdioCollector {
            onStreamFinished: root.folderPreview = root.parse(text, { icons: {} }).icons ?? {}
        }
    }
    Process {
        id: applyP
        stdout: StdioCollector {
            id: applyOut
        }
        onExited: {
            const r = root.parse(applyOut.text, { ok: false, errors: ["no answer from appearance.py"] });
            root.lastOk = r.ok === true;
            root.lastResult = (r.ok ? (r.did ?? []) : (r.errors ?? [])).join("; ");
            root.applying = false;
            root.applies++;
            // what the desktop uses now has changed: read it again
            stateP.running = true;
            foldersP.running = true;
            root.applied(root.lastOk);
        }
    }
    Process {
        id: setupP
        stdout: StdioCollector {
            id: setupOut
        }
        onExited: {
            const r = root.parse(setupOut.text, { ok: false });
            root.lastOk = r.ok === true;
            root.lastResult = r.ok ? (r.changed ? "added" : "already there") : (r.error ?? "failed");
            root.settingUp = false;
            foldersP.running = true;
        }
    }
}
