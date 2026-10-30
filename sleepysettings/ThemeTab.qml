import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services
import "Customs.js" as Customs
import qs.sleepysettings.components

// One "Theme" list. The first entry, Sleepytheme, makes its colours from the wallpaper (matugen, a new
// palette for each wallpaper) and shows the "Wallpaper style" picker; a community theme (themes/*.toml, listed by theme.py --list-presets) keeps
// its own colours and shows a "Variant" picker with the author's variants. Under Colours and Palette come Appearance (icon theme,
// interface font, matched folder colours: applied through scripts/appearance.py) and the wallpaper changer's settings (services/WallpaperTimer.qml).
// Settings tab: the matugen palette. The scheme, mode, contrast and cool-hue switch are stored in
// sleepysettings.toml and read by scripts/theme.py, which picks a seed colour from the
// wallpaper and runs matugen; matugen then rewrites the templates of every themed app (bar,
// Hyprland borders, kitty, walker, starship, GTK 3 and 4). Nothing changes until a button below runs
// it: the settings are a draft until Apply, which saves them and generates a theme from the
// current wallpaper. The wallpaper folder lives here too; a change to the folder alone
// is saved without running matugen.
TabPage {
    id: tab
    key: "theme"
    label: "Theme"
    icon: 0xF0E0C
    group: "theme"
    // "Match folder colours to the theme" and "Change wallpaper automatically" are the names chosen for two switches
    labelMax: 300
    busy: tab.running
    // Apply writes sleepysettings.toml and then runs theme.py, which has matugen rewrite the themed apps (or renders a community theme), and
    // appearance.py for the icons, the font and GNOME's light or dark preference
    afterNote: {
        const parts = [];
        if (tab.runsTheme)
            parts.push(tab.community ? "theme.py (renders the theme's colours)" : "theme.py (matugen rewrites the themed apps)");
        if (tab.appearanceDirty)
            parts.push("appearance.py (sets the icons, font and light or dark)");
        return parts.length > 0 ? "then runs " + parts.join(" and ") : "";
    }
    dirtyText: {
        if (tab.paletteDirty)
            return tab.community ? "Apply saves these and applies the theme's colours" : "Apply saves these and makes a theme from the current wallpaper";
        if (tab.appearanceDirty)
            return "Apply saves these and sets the icons and font";
        return tab.changes === 1 && Settings.changed(["wallpaperDir"]) ? "Apply saves the wallpaper folder" : "Apply saves the wallpaper settings";
    }
    note: "Apply saves; changing the theme, wallpaper style, mode or contrast also regenerates the theme"
    // the Apply bar lists what else Apply writes (the folder overlay)
    files: {
        const f = [Settings.tilde(Settings.path)];
        if (Settings.changed(["iconTheme", "folderColours"]) && Settings.get("folderColours"))
            f.push("~/.local/share/icons/Sleepytheme-Folders/index.theme");
        return f;
    }

    // theme.py is Python 3 with ImageMagick and matugen, and sets the wallpaper through awww; without
    // them the Sleepytheme rows and the wallpaper buttons are greyed out and Apply only saves. A community theme needs only Python.
    readonly property var themeRequires: ["python3", "magick", "matugen", "awww"]
    readonly property bool canRun: Deps.available(tab.themeRequires)
    readonly property bool canRunPreset: Deps.available(["python3"])
    // what the shown (staged) theme is
    readonly property string preset: Settings.get("themePreset")
    readonly property bool community: tab.preset !== ""
    readonly property string family: Appearance.split(tab.preset).family
    // the keys whose change regenerates the colours; the wallpaper folder and the changer's settings only save
    readonly property var paletteKeys: ["themePreset", "themeScheme", "themeMode", "themeContrast", "themeCoolHues", "folderColours"]
    // the keys appearance.py applies; a change of Light or dark (or of the theme, whose variant has a mode) also sets GNOME's color-scheme ("colorScheme")
    readonly property var appearanceKeys: ["iconTheme", "folderColours", "gtkFont", "gtkFontSize"]
    readonly property var schemeKeys: ["themeMode", "themePreset"]
    readonly property bool paletteDirty: Settings.changed(tab.paletteKeys)
    readonly property bool appearanceDirty: Settings.changed(tab.appearanceKeys) || Settings.changed(tab.schemeKeys)
    // Apply would run theme.py: a community theme needs only Python
    readonly property bool runsTheme: tab.paletteDirty && (tab.community ? tab.canRunPreset : tab.canRun)
    property bool running: false
    property string current: ""     // wallpaper awww shows, "" when unknown
    property bool applyAfterQuery: false
    property bool themeAfterApp: false
    property bool appRunning: false
    property var appKeys: []
    property string appMode: ""

    // run `theme` (a path keeps the wallpaper, none picks a random one); kitty reloads kitty.conf by
    // itself when matugen rewrites it (auto_reload_config, kitty 0.47+), so no signal is sent
    function run(path) {
        if (!tab.canRun)
            return;
        tab.launch(path ? [path] : []);
    }

    // a community theme: its colours are rendered again, the wallpaper stays
    function runPreset(spec) {
        if (!tab.canRunPreset)
            return;
        tab.launch(["--preset", spec]);
    }

    function launch(args) {
        running = true;
        runner.command = [Quickshell.shellPath("scripts/theme.py")].concat(args);
        runner.running = true;
    }

    // Before the group is committed (TabPage.apply): wait for Settings.committed, which says the
    // palette keys are in sleepysettings.toml (the bar writes it; `theme` reads the file), then ask awww
    // for the wallpaper again before running, since the picker, Shuffle and the SUPER+SHIFT+W bind
    // change the wallpaper without this tab noticing, so a path read earlier put the old wallpaper
    // back (review 3, F4). The query's stream handler runs `theme` with the fresh answer ("" when
    // awww shows none: theme then picks a random one). No word from the bar within three seconds
    // (it went away mid-apply): run anyway. The icons, font and colour scheme go first (appearance.py reads the
    // saved file too), a community theme runs `theme.py --preset` and leaves the wallpaper alone.
    property bool awaitingCommit: false

    onApplying: {
        const app = tab.appearanceKeys.filter(k => Settings.pending.hasOwnProperty(k));
        if (Settings.changed(tab.schemeKeys)) {
            app.push("colorScheme");
            tab.appMode = tab.effMode;
        }
        tab.autoIcon = "";
        if (!tab.runsTheme && app.length === 0)
            return;
        tab.appKeys = app;
        tab.themeAfterApp = tab.runsTheme;
        tab.running = true;
        tab.awaitingCommit = true;
        ackWait.restart();
    }

    onDiscarding: tab.autoIcon = ""

    function afterCommit() {
        tab.awaitingCommit = false;
        ackWait.stop();
        if (tab.appKeys.length > 0) {
            tab.appRunning = true;
            Appearance.apply(tab.appKeys, tab.appMode);
        } else {
            tab.startTheme();
        }
    }

    function startTheme() {
        if (!tab.themeAfterApp) {
            tab.running = false;
            return;
        }
        tab.themeAfterApp = false;
        if (Settings.themePreset !== "") {
            tab.runPreset(Settings.themePreset);
        } else {
            tab.applyAfterQuery = true;
            query.running = true;
        }
    }

    Connections {
        target: Appearance
        function onApplied(ok) {
            if (!tab.appRunning)
                return;
            tab.appRunning = false;
            tab.appKeys = [];
            tab.startTheme();
        }
    }

    Connections {
        target: Settings
        function onCommitted(keys) {
            if (tab.awaitingCommit && keys.some(k => tab.paletteKeys.includes(k) || tab.appKeys.includes(k)))
                tab.afterCommit();
        }
    }

    Timer {
        id: ackWait
        interval: 3000
        onTriggered: {
            if (!tab.awaitingCommit)
                return;
            console.warn("theme: no word from the bar that the palette settings were saved, running theme anyway");
            tab.afterCommit();
        }
    }

    Process {
        id: runner
        onExited: {
            tab.running = false;
            query.running = true;
            // the first run makes colors.json (FileChecks offers it while the file is missing)
            FileChecks.refresh();
        }
    }

    // the notice of a missing colors.json: "Run the theme now". A new palette on the wallpaper that is showing,
    // or a random wallpaper when awww shows none; a community theme is rendered again instead
    Connections {
        target: FileChecks
        function onThemeRunRequested() {
            if (tab.running)
                return;
            if (Settings.themePreset !== "")
                tab.runPreset(Settings.themePreset);
            else
                tab.run(tab.current !== "" ? "--palette" : "");
        }
    }

    // lines look like ": DP-1: 2560x1440, scale: 1, currently displaying: image: /path/file.png"
    Process {
        id: query
        command: ["sh", "-c", "awww query 2>/dev/null || swww query 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/image: (.+)$/m);
                tab.current = m ? m[1].trim() : "";
                if (tab.applyAfterQuery) {
                    tab.applyAfterQuery = false;
                    tab.run(tab.current);
                }
            }
        }
    }

    // what the tab is showing (the wallpaper awww has); asked once Deps has looked for awww
    function ask() {
        if (Deps.has("awww") && Deps.ready)
            query.running = true;
    }

    Component.onCompleted: {
        tab.ask();
        Appearance.ensure();
    }

    Connections {
        target: Deps
        function onReadyChanged() {
            tab.ask();
        }
    }

    // ---- the theme list and the light/dark follow -------------------------------------------------------------------------------

    // a theme's colour strip: five roles of a variant, as hex
    function stripOf(v) {
        return v ? ["surface", "surface_container", "primary", "secondary", "tertiary", "error"].map(k => v.colors[k]).filter(c => c) : [];
    }

    // Sleepytheme first, then the community themes under their own heading (Matugen's styles are never in this list: they are the
    // "Wallpaper style" row of Sleepytheme)
    readonly property var themeOptions: {
        const mode = Settings.get("themeMode");
        const own = [Theme.surface, Theme.container, Theme.accent, Theme.primary, Theme.fg].map(c => String(Qt.rgba(c.r, c.g, c.b, 1)));
        const out = [
            {
                value: "",
                label: "Sleepytheme",
                hint: "from your wallpaper",
                strip: own
            }
        ];
        if (Appearance.presets.length > 0)
            out.push({
                header: true,
                label: "Community themes"
            });
        for (const p of Appearance.presets) {
            const v = p.variants.find(x => x.mode === mode) ?? p.variants[0];
            out.push({
                value: p.id,
                label: p.name,
                hint: p.variants.length > 1 ? p.variants.length + " variants" : "",
                strip: tab.stripOf(v)
            });
        }
        return out;
    }

    // the author's variants of the shown theme; the value is the whole setting, "family:variant"
    readonly property var variantOptions: {
        const p = Appearance.presetOf(tab.family);
        return p ? p.variants.map(v => ({
                    value: p.id + ":" + v.id,
                    label: Appearance.titleCase(v.id),
                    hint: v.mode,
                    strip: tab.stripOf(v)
                })) : [];
    }
    // a hand-edited "family" without a variant shows the one it would open with
    readonly property string variantValue: tab.preset.indexOf(":") >= 0 ? tab.preset : tab.family + ":" + Appearance.defaultVariant(tab.family, Settings.get("themeMode"))

    function pickFamily(fam) {
        if (fam === "") {
            Settings.stage("themePreset", "");
            return;
        }
        // keep the variant when the family is the same, else the one in the shown mode
        Settings.stage("themePreset", fam + ":" + Appearance.defaultVariant(fam, Settings.get("themeMode")));
    }

    // dark or light as the colours are: the variant's mode for a community theme, else the Light or dark row
    readonly property string effMode: {
        if (tab.community) {
            const v = Appearance.variantOf(tab.variantValue);
            if (v)
                return v.mode;
        }
        return Settings.get("themeMode");
    }

    // Light or dark follows the icon theme: when the mode changes, the icon theme's -Dark or -Light sibling is staged, if the
    // theme has one installed. `autoIcon` is what was staged this way and `iconOrigin` the choice before it, so going back restores it;
    // a pick by hand forgets both.
    property string autoIcon: ""
    property string iconOrigin: ""
    property string seenMode: ""
    readonly property bool listsReady: Appearance.presetsLoaded && Appearance.iconsLoaded && Appearance.stateLoaded
    onListsReadyChanged: if (tab.listsReady)
        tab.seenMode = tab.effMode
    onEffModeChanged: {
        if (!tab.listsReady || tab.effMode === tab.seenMode)
            return;
        tab.seenMode = tab.effMode;
        // after this binding has settled: staging the icon theme changes what effMode reads
        const m = tab.effMode;
        Qt.callLater(() => tab.followIcons(m));
    }

    function followIcons(mode) {
        const now = Settings.get("iconTheme");
        // what the choice was before this function staged anything
        const origin = tab.autoIcon !== "" && now === tab.autoIcon ? tab.iconOrigin : now;
        const base = origin !== "" ? origin : Appearance.state.iconBase ?? "";
        if (base === "")
            return;
        const sib = Appearance.sibling(base, mode);
        if (sib !== base) {
            tab.iconOrigin = origin;
            tab.autoIcon = sib;
            Settings.stage("iconTheme", sib);
        } else if (tab.autoIcon !== "") {
            Settings.stage("iconTheme", origin);
            tab.autoIcon = "";
        }
    }

    // ---- previews and hints of the Appearance section ----------------------------------------------------------------------

    readonly property string iconShown: Settings.get("iconTheme") || Appearance.state.iconBase || ""
    readonly property string fontShown: Settings.get("gtkFont") || Appearance.state.font || ""
    readonly property var iconInfo: Appearance.iconOf(tab.iconShown)

    // the lists: a theme's small samples ride on its option (the picker draws up to six, the closed picker four)
    readonly property var iconOptions: Appearance.icons.map(i => ({
                value: i.id,
                label: i.name,
                images: i.samples.filter(x => x.path !== "").map(x => Appearance.mark(x.path)),
                imageSize: 16
            }))
    readonly property var fontOptions: Appearance.fonts.map(f => ({
                value: f,
                label: f,
                fontFamily: f
            }))
    readonly property string appearanceError: !Appearance.lastOk && Appearance.lastResult !== "" ? Appearance.lastResult : ""

    // the switch's "!" tip: what it does, and the same icons without and with the matched colours (the pictures sit in the tip's text)
    readonly property string folderTip: {
        const img = (p, n) => p ? "<img src=\"" + Appearance.mark(p) + "\" width=\"" + n + "\" height=\"" + n + "\"> " : "";
        let t = "Draws the folder icons in the theme's colour, on top of the chosen icon theme (a small icon theme of its own, <b>Sleepytheme-Folders</b>, that falls back to the chosen one for everything else). Off by default.";
        const without = tab.iconInfo ? tab.iconInfo.folders.filter(x => x.path !== "").map(x => img(x.path, 24)).join("") : "";
        const withs = ["folder", "user-home", "folder-download", "folder-documents", "folder-music"].map(n => img(Appearance.folderPreview[n], 24)).join("");
        if (without !== "" || withs !== "")
            t += "<br><br>Without: " + without + "<br>With: " + withs;
        return t;
    }

    // the colours the matched folder icons would have: the shown community theme's primary, else the colours in use
    readonly property var folderColours: {
        if (tab.community) {
            const v = Appearance.variantOf(tab.variantValue);
            if (v && v.colors.primary && v.colors.on_primary)
                return [v.colors.primary, v.colors.on_primary];
        }
        const f = c => String(Qt.rgba(c.r, c.g, c.b, 1));
        return [f(Theme.primary), f(Theme.surface)];
    }
    onFolderColoursChanged: previewDelay.restart()
    Timer {
        id: previewDelay
        interval: 150
        onTriggered: Appearance.previewFolders(tab.folderColours[0], tab.folderColours[1])
    }
    readonly property bool foldersReady: Appearance.folders.configured === true

    Connections {
        target: Appearance
        function onFoldersLoadedChanged() {
            previewDelay.restart();
        }
    }

    // ---- sections --------------------------------------------------------------------------------------------------------

    Section {
        title: "Colours"
        // colors.json missing: no theme has run yet, offer the first run (FileChecks)
        fileIds: ["colors"]

        // the theme: Sleepytheme or a community theme; matugen's styles are the Wallpaper style row below
        SettingRow {
            objectName: "themeRow"
            label: "Theme"
            key: "themePreset"
            requires: ["python3"]
            info: "<b>Sleepytheme</b> makes its colours from your wallpaper, a new set for each wallpaper. A community theme keeps its own colours when the wallpaper changes."
            tags: "preset palette community theme colour color family sleepytheme"
            extraSearch: tab.themeOptions.map(o => o.label).join(" ")
            format: v => v === "" ? "Sleepytheme" : (Appearance.presetOf(Appearance.split(v).family)?.name ?? v)

            Combo {
                objectName: "themeCombo"
                picker: tab.picker
                value: tab.family
                options: tab.themeOptions
                onPicked: v => tab.pickFamily(v)
            }
        }

        // a community theme's own variants (Mocha, Latte, ...): only the author's
        SettingRow {
            objectName: "variantRow"
            visible: tab.community
            label: "Variant"
            requires: ["python3"]
            info: "The versions the theme's author made, for example a dark and a light one."
            tags: "variant dark light mocha latte"
            extraSearch: tab.variantOptions.map(o => o.label).join(" ")

            Combo {
                objectName: "variantCombo"
                picker: tab.picker
                value: tab.variantValue
                options: tab.variantOptions
                onPicked: v => Settings.stage("themePreset", v)
            }
        }

        ComboRow {
            visible: !tab.community
            label: "Wallpaper style"
            key: "themeScheme"
            requires: tab.themeRequires
            picker: tab.picker
            info: "How matugen builds the colours from the wallpaper's colour. <b>Vibrant</b> is bold, <b>Tonal spot</b> is calm, <b>Expressive</b> and <b>Fruit salad</b> shift the hues, <b>Fidelity</b> and <b>Content</b> stay close to the wallpaper, <b>Neutral</b> and <b>Monochrome</b> are near grey."
            tags: "scheme matugen colour color style palette colour scheme"
            // the third field is the short hint the picker shows beside the name
            options: [["scheme-vibrant", "Vibrant", "bold"], ["scheme-tonal-spot", "Tonal spot", "calm"], ["scheme-expressive", "Expressive", "shifted hues"], ["scheme-fidelity", "Fidelity", "true to wallpaper"], ["scheme-content", "Content", "true to wallpaper"], ["scheme-fruit-salad", "Fruit salad", "shifted hues"], ["scheme-rainbow", "Rainbow", "many hues"], ["scheme-neutral", "Neutral", "near grey"], ["scheme-monochrome", "Monochrome", "grey"]].map(p => ({
                        value: p[0],
                        label: p[1],
                        hint: p[2]
                    }))
        }
        ChoiceRow {
            visible: !tab.community
            label: "Light or dark"
            key: "themeMode"
            requires: tab.themeRequires
            info: "Dark or light colours for every themed app. The bar's frosted islands are tuned for dark. The icon theme follows when it has a dark and a light version."
            tags: "dark light"
            options: [["dark", "Dark"], ["light", "Light"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
        }
        ChoiceRow {
            visible: !tab.community
            label: "Text contrast"
            key: "themeContrast"
            requires: tab.themeRequires
            info: "Distance between text and background colours. 0 is matugen's standard; raise it if text is hard to read, lower it for a softer look."
            options: [[-0.5, "Low"], [0, "Standard"], [0.5, "High"], [1, "Max"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
            // ---- BEGIN toml custom ----: any contrast matugen takes, -1 to 1
            custom: ({
                    placeholder: "A number from -1 (softest) to 1 (strongest), such as 0.25",
                    toText: v => String(v),
                    seed: v => String(v),
                    parse: t => Customs.number(t, -1, 1),
                    describe: v => "contrast " + v + " (-1 softest, 0 standard, 1 strongest)"
                })
            // ---- END toml custom ----
        }
    }

    // the theme's colours: one tile per role pair, the name and hex inside it in its on-colour, then the surfaces as
    // a second row of tiles (a ramp of touching segments was tried and read as one dark strip). A click copies the hex. They read the live Theme tokens, so a matugen run recolours them.
    Section {
        title: "Palette"

        // a new palette on the current wallpaper, at once and not staged, like the control centre's button; matugen's own, so only
        // while Sleepytheme is the theme in use (a community theme has no wallpaper palette to shuffle)
        headerItems: BarButton {
            id: shuffleBtn
            objectName: "shufflePalette"
            visible: Settings.themePreset === ""
            Layout.topMargin: 8
            text: tab.running ? "Shuffling…" : "Shuffle colours"
            glyph: 0xF03D8
            glyphFirst: true
            glued: false
            bg: Theme.tileBg
            enabled: tab.canRun && !tab.running
            opacity: tab.canRun ? (tab.running ? 0.6 : 1) : 0.4
            onClicked: if (enabled) tab.run("--palette")
            onHoveredChanged: {
                if (!tab.tooltip)
                    return;
                if (hovered)
                    tab.tooltip.show(shuffleBtn, "A new set of colours from the current wallpaper, at once: nothing is staged and Apply is not needed.", false);
                else
                    tab.tooltip.hide(shuffleBtn);
            }
        }

        // four across, two by two when the page is narrow
        GridLayout {
            id: tiles
            Layout.fillWidth: true
            columns: tab.width < 640 ? 2 : 4
            columnSpacing: 8
            rowSpacing: 8
            uniformCellWidths: true

            ColourTile { Layout.fillWidth: true; role: "Accent"; shade: Theme.accent; matching: Theme.accentFg }
            ColourTile { Layout.fillWidth: true; role: "Primary"; shade: Theme.primary }
            ColourTile { Layout.fillWidth: true; role: "Text"; shade: Theme.fg }
            ColourTile { Layout.fillWidth: true; role: "Alert"; shade: Theme.urgent; matching: Theme.urgentFg }
        }

        // the surfaces, in a second row of the same tiles (the text on them is the normal text colour)
        GridLayout {
            id: surfaces
            Layout.fillWidth: true
            columns: tab.width < 640 ? 2 : 4
            columnSpacing: 8
            rowSpacing: 8
            uniformCellWidths: true

            ColourTile { Layout.fillWidth: true; role: "Surface"; shade: Theme.surface; matching: Theme.fg }
            ColourTile { Layout.fillWidth: true; role: "Container"; shade: Theme.container; matching: Theme.fg }
            ColourTile { Layout.fillWidth: true; role: "Container high"; shade: Theme.containerHigh; matching: Theme.fg }
            ColourTile { Layout.fillWidth: true; role: "Container highest"; shade: Theme.containerHighest; matching: Theme.fg }
        }
    }

    // icons, interface font and the folder colours: the desktop's own settings (gsettings), set on Apply by
    // scripts/appearance.py; only installed themes and fonts are offered. One compact row each: the samples live in the pickers' lists, a few tiny ones in the closed picker,
    // and the matched-folders comparison in the switch's "!" tip. Staged like the rest.
    Section {
        title: "Appearance"
        objectName: "appearanceSection"

        SmallText {
            objectName: "appearanceError"
            visible: tab.appearanceError !== ""
            text: "Could not set everything: " + tab.appearanceError
            color: Theme.urgentFg
        }

        SettingRow {
            objectName: "iconThemeRow"
            label: "Icon theme"
            key: "iconTheme"
            enabled: Appearance.hasGsettings
            hint: Appearance.hasGsettings ? "" : "Needs gsettings (not installed)"
            info: "The icons of the file manager, dialogs and apps. When you switch between Dark and Light, a theme with a dark and a light version follows (for example Papirus-Dark and Papirus-Light)."
            tags: "icons icon theme papirus"
            format: v => v === "" ? "as it is now" : v
            extraSearch: Appearance.icons.map(i => i.name).join(" ")

            Combo {
                objectName: "iconCombo"
                picker: tab.picker
                value: tab.iconShown
                options: tab.iconOptions
                onPicked: v => {
                    tab.autoIcon = "";
                    Settings.stage("iconTheme", v);
                }
            }
        }

        SwitchRow {
            objectName: "folderColoursRow"
            label: "Match folder colours to the theme"
            key: "folderColours"
            enabled: Appearance.hasGsettings
            info: tab.folderTip
            tags: "folder icons colour color match accent papirus"

            // matugen has to know the folder icons before it can draw them: asked first, with the exact lines (a backup is kept)
            below: RowLayout {
                objectName: "folderSetup"
                visible: Settings.get("folderColours") && Appearance.foldersLoaded && !tab.foldersReady
                Layout.fillWidth: true
                spacing: 8

                SmallText {
                    Layout.fillWidth: true
                    text: "matugen does not draw the folder icons yet. Set up adds them to its config."
                }

                BarButton {
                    objectName: "folderSetupButton"
                    text: "Set up…"
                    glued: false
                    bg: Theme.tileBg
                    enabled: !Appearance.settingUp
                    onClicked: tab.confirm?.askLine("Add the folder icons to the matugen config?", "Adds " + (Appearance.folders.count ?? 0) + " entries for the folder icons. A backup is kept (" + Appearance.folders.config?.split("/").pop() + ".bak-<date-time>).", Appearance.folders.sample ?? "", () => Appearance.setUpFolders(), "Add")
                }
            }
        }

        // the interface font: family and size in one row; every family is drawn in its own face in the list
        SettingRow {
            objectName: "fontRow"
            label: "Interface font"
            key: "gtkFont"
            enabled: Appearance.hasGsettings
            hint: Appearance.hasGsettings ? "" : "Needs gsettings (not installed)"
            info: "The font of GTK apps and dialogs, and its size in points. The bar has its own font settings on the Bar tab."
            tags: "font typeface text gtk interface size"
            format: v => v === "" ? "as it is now" : v

            Combo {
                objectName: "fontCombo"
                picker: tab.picker
                value: tab.fontShown
                options: tab.fontOptions
                onPicked: v => Settings.stage("gtkFont", v)
            }

            SpinField {
                objectName: "fontSize"
                Layout.fillWidth: false
                value: Settings.get("gtkFontSize")
                min: Settings.schema.gtkFontSize.min
                max: Settings.schema.gtkFontSize.max
                step: Settings.schema.gtkFontSize.step
                suffix: " pt"
                onMoved: v => Settings.stage("gtkFontSize", v)
            }
        }
    }

    Section {
        title: "Wallpaper"
        // the wallpaper folder is missing or unreadable: the buttons grey out under a notice (FileChecks)
        fileIds: ["wallpaper"]

        SettingRow {
            label: "Change wallpaper"
            info: "Both regenerate the theme from the new wallpaper, with the applied settings (a community theme keeps its colours). <b>Choose wallpaper</b> opens the bar's wallpaper grid; a chosen wallpaper is themed with these settings too, and so is SUPER + SHIFT + W."
            tags: "random shuffle picker pick new wallpaper"
            requires: tab.themeRequires
            // the wallpaper awww shows now, as a small caption under the buttons (the row "Current wallpaper" went in the declutter pass)
            hint: tab.current.replace(Quickshell.env("HOME"), "~")

            // the two buttons share the row and wrap onto a second line when it is narrow, so neither label is ever cut
            Flow {
                Layout.fillWidth: true
                spacing: 6

                BarButton {
                    objectName: "randomWallpaper"
                    text: "Random wallpaper"
                    glyph: 0xF049D
                    glyphFirst: true
                    glued: false
                    bg: Theme.tileBg
                    onClicked: if (!tab.running) tab.run("")
                }

                BarButton {
                    objectName: "chooseWallpaper"
                    text: "Choose wallpaper"
                    glyph: 0xF02E9
                    glyphFirst: true
                    glued: false
                    bg: Theme.tileBg
                    onClicked: Settings.toggleOnBar("wallpaper")
                }
            }
        }

        // the automatic changer (off by default): the shell's timer runs theme.py like the Random wallpaper button
        SwitchRow {
            objectName: "autoRow"
            label: "Change wallpaper automatically"
            key: "wallpaperAuto"
            requires: ["python3", "awww"]
            info: "Picks a new wallpaper now and then, never the one on screen, and themes it like the Random wallpaper button. It waits while the screen is dimmed or locked."
            tags: "automatic auto timer change slideshow rotate wallpaper interval"
        }
        ComboRow {
            objectName: "everyRow"
            visible: Settings.get("wallpaperAuto")
            label: "Change every"
            key: "wallpaperEvery"
            picker: tab.picker
            requires: ["python3", "awww"]
            info: "How long a wallpaper stays. Custom takes any number of minutes from 5 to 1440 (24 hours)."
            tags: "interval minutes hours timer custom"
            options: [["5", "5 minutes"], ["10", "10 minutes"], ["15", "15 minutes"], ["30", "30 minutes"], ["60", "1 hour"], ["120", "2 hours"], ["180", "3 hours"], ["360", "6 hours"], ["720", "12 hours"], ["1440", "24 hours"], ["custom", "Custom"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
        }
        NumberRow {
            objectName: "customRow"
            visible: Settings.get("wallpaperAuto") && Settings.get("wallpaperEvery") === "custom"
            label: "Custom interval"
            key: "wallpaperCustomMin"
            suffix: " min"
            requires: ["python3", "awww"]
            info: "Minutes between wallpapers, 5 to 1440."
            tags: "interval minutes custom"
        }
        ChoiceRow {
            objectName: "orderRow"
            visible: Settings.get("wallpaperAuto")
            label: "Order"
            key: "wallpaperOrder"
            requires: ["python3", "awww"]
            info: "<b>Random</b> picks any other picture. <b>In order</b> goes through the wallpaper folder by file name and starts over at the end."
            tags: "random order name sequence"
            options: [["random", "Random"], ["name", "In order"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
        }
        SwitchRow {
            objectName: "loginRow"
            visible: Settings.get("wallpaperAuto")
            label: "Also on login"
            key: "wallpaperOnLogin"
            requires: ["python3", "awww"]
            info: "Also changes the wallpaper once, a few seconds after the shell starts."
            tags: "login start startup boot"
        }
    }

    AdvancedSection {
        SwitchRow {
            label: "Cool colours only"
            key: "themeCoolHues"
            requires: tab.themeRequires
            visible: !tab.community
            info: "On: a warm colour picked from the wallpaper is folded into blues, cyans and violets. Off: the palette follows the wallpaper's own colour."
            tags: "blue warm colour color cool hues"
        }
        // the folder the wallpaper grid and "Random wallpaper" read; typed, or chosen with Browse
        FieldRow {
            label: "Wallpaper folder"
            key: "wallpaperDir"
            info: "The folder the wallpaper grid and Random wallpaper read. ~ is your home; it is read when the picker opens."
            tags: "wallpaper directory"

            BarButton {
                text: "Browse…"
                glyph: 0xF024B
                glyphFirst: true
                glued: false
                bg: Theme.tileBg
                onClicked: {
                    const home = Quickshell.env("HOME");
                    const start = Settings.get("wallpaperDir").replace(/^~(?=\/|$)/, home);
                    tab.folders?.open(start, p => Settings.stage("wallpaperDir", p.startsWith(home) ? "~" + p.slice(home.length) : p));
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
