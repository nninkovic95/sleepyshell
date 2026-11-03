import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// Settings tab "Apps": which programs open what, and which apps start on
// which workspace. The default applications (browser, file manager, ...) are the desktop's, kept in mimeapps.list and
// read and written by services/DefaultApps.qml (a draft there until Apply); the terminal and the workspace apps are
// Settings keys (defaultTerminal, workspaceApps). A note shows when the keybinds in the Hyprland config open other
// programs than these; after an Apply it can ask to change the matching entries of programs.lua (the only Hyprland file it writes, with a backup).
TabPage {
    id: tab
    key: "apps"
    label: "Apps"
    tags: "workspace workspaces"
    icon: 0xF056E
    group: "apps"
    // the defaults are a draft of their own, next to the Settings keys
    dirty: tab.changes > 0 || DefaultApps.dirty
    busy: DefaultApps.applying
    note: "Apply saves to " + Settings.tilde(Settings.path) + " and sets the default apps with xdg-mime"
    files: [Settings.tilde(Settings.path), Settings.tilde(DefaultApps.mimeappsPath)]
    onApplying: {
        // the keybinds follow the programs picked here (programs.lua, after a question): what this Apply changes, as program names
        const wanted = {};
        if (Settings.changed(["defaultTerminal"]))
            wanted.terminal = Settings.get("defaultTerminal");
        for (const [k, id] of [["browser", "browser"], ["editor", "editor"], ["fileManager", "files"]])
            if (DefaultApps.staged.hasOwnProperty(id))
                wanted[k] = DefaultApps.programOf(DefaultApps.staged[id]);
        DefaultApps.apply();
        DefaultApps.planPrograms(wanted);
    }
    Connections {
        target: DefaultApps
        function onProgramsAsk(plan) {
            tab.confirm?.askLine("Change programs.lua to match?", "Your Hyprland keybinds open other programs than the ones you just chose. These lines of " + plan.file.split("/").pop() + " would change (a backup is kept: " + plan.file.split("/").pop() + ".bak-<date-time>).", plan.shown, () => DefaultApps.writePrograms(), "Change");
        }
    }
    onDiscarding: DefaultApps.discard()
    onVisibleChanged: if (visible)
        DefaultApps.ensure()
    Component.onCompleted: DefaultApps.ensure()

    // ---- the workspace list (staged as one JSON text) ------------------------------------------

    readonly property var entries: WorkspaceApps.parse(Settings.get("workspaceApps"))
    function save(list) {
        Settings.stage("workspaceApps", WorkspaceApps.serialise(list));
    }
    function edit(i, field, value) {
        const l = tab.entries.map(e => Object.assign({}, e));
        l[i][field] = value;
        if (field === "kind")
            l[i].value = "";
        tab.save(l);
    }
    function remove(i) {
        tab.save(tab.entries.filter((e, j) => j !== i));
    }
    function add() {
        const last = tab.entries.length > 0 ? tab.entries[tab.entries.length - 1].workspace : 1;
        tab.save(tab.entries.concat([WorkspaceApps.blank(last)]));
    }

    // ---- the apps the Hyprland config already places on workspaces (read only) --------

    // "workspace 1", "the magic workspace", "workspace music" for a Hyprland workspace text
    function wsText(w) {
        const s = String(w).replace(/\s+silent$/, "").trim();
        if (s === "special" || s === "special:magic")
            return "the magic workspace";
        if (s.startsWith("special:"))
            return "special workspace " + s.slice(8);
        return "workspace " + s.replace(/^name:/, "");
    }
    // the program an entry of this tab starts
    function entryProgram(e) {
        if (e.kind === "command")
            return String(e.value).trim().split(/\s+/)[0].replace(/^.*\//, "");
        return DefaultApps.programOf(e.value);
    }
    // the config's own placements, one row per app and workspace (an exec line and a window rule for the same app are one row)
    readonly property var hyprApps: {
        const out = [];
        for (const a of DefaultApps.hyprWorkspaceApps) {
            const ws = tab.wsText(a.workspace);
            const at = a.file.split("/").pop() + ", line " + a.line;
            const same = out.find(o => o.app === a.app && o.ws === ws);
            if (same)
                same.where.push(at);
            else
                out.push({ app: a.app, ws: ws, where: [at], file: a.file });
        }
        return out;
    }
    // entries here that the config already starts: they would run twice
    readonly property string twiceNote: {
        const dup = [];
        for (const e of tab.entries) {
            const p = tab.entryProgram(e).toLowerCase();
            const h = tab.hyprApps.find(a => p !== "" && a.app.toLowerCase() === p);
            if (h && !dup.includes(h.app))
                dup.push(h.app + " (" + h.where[0] + ")");
        }
        return dup.length > 0 ? "Your Hyprland config already starts " + dup.join(", ") + "; adding it here starts a second copy." : "";
    }

    // every installed application, with its icon, for the app pickers
    readonly property var appOptions: {
        const out = [];
        for (const e of DesktopEntries.applications.values)
            if (!e.noDisplay)
                out.push({
                    value: e.id,
                    label: e.name,
                    icon: DefaultApps.iconFor(e.icon)
                });
        out.sort((a, b) => a.label.localeCompare(b.label));
        return out;
    }

    // the page scrolls and the lists show every row (as the Keybinds tab does)
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 268

        Flickable {
            id: flick
            anchors.fill: parent
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onMovingChanged: if (moving && tab.tooltip)
                tab.tooltip.dismiss()

            ColumnLayout {
                id: col
                width: flick.width - (flick.contentHeight > flick.height ? 10 : 0)
                spacing: 8

                Section {
                    title: "Default apps"
                    requires: ["xdg-mime"]

                    SettingRow {
                        label: "Terminal"
                        key: "defaultTerminal"
                        info: "The terminal the shell opens for updates, the network settings and the calendar's agenda. It is only used by this shell; other programs choose their own."
                        tags: "terminal emulator kitty foot alacritty wezterm ghostty konsole console shell"
                        format: v => String(v)
                        extraSearch: DefaultApps.terminals.map(t => t.label).join(" ")

                        AppCombo {
                            picker: tab.picker
                            options: DefaultApps.terminalOptions(Settings.get("defaultTerminal"))
                            value: Settings.get("defaultTerminal")
                            emptyText: "No terminal found"
                            onPicked: v => Settings.stage("defaultTerminal", v)
                        }
                    }

                    Repeater {
                        model: DefaultApps.categories

                        SettingRow {
                            id: appRow
                            required property var modelData
                            readonly property bool changed: DefaultApps.staged.hasOwnProperty(modelData.id)
                            label: modelData.label
                            info: modelData.id === "browser" ? "Opens web links and HTML files. Also set as the system's default browser." : modelData.id === "files" ? "Shows folders, for example when a button says Show in folder." : modelData.id === "mail" ? "Opens email links. A web choice (Gmail, Outlook, Proton Mail) starts a new message on that site in your web browser." : "Opens these files when you open them without choosing a program."
                            tags: "default application xdg mime " + modelData.id + " " + modelData.candidates.map(a => a.name).join(" ")
                            hint: changed ? "Changes when you press Apply." : ""

                            AppCombo {
                                picker: tab.picker
                                options: DefaultApps.options(appRow.modelData.id)
                                value: DefaultApps.chosenId(appRow.modelData.id)
                                onPicked: v => DefaultApps.stage(appRow.modelData.id, v)
                            }
                        }
                    }

                    // the Hyprland config's keybinds open other programs than the ones above
                    RowLayout {
                        objectName: "bindNote"
                        visible: DefaultApps.bindNote !== ""
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: DefaultApps.bindNote + "."
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            color: Theme.fgMuted
                        }
                        BarButton {
                            text: "Open programs.lua"
                            glued: false
                            bg: Theme.tileBg
                            enabled: DefaultApps.programsFile !== ""
                            onClicked: DefaultApps.openProgramsFile()
                        }
                    }

                    SmallText {
                        visible: DefaultApps.error !== ""
                        color: Theme.urgentFg
                        text: DefaultApps.error
                    }
                }

                Section {
                    title: "Apps on workspaces"

                    headerItems: InfoTip {
                        Layout.alignment: Qt.AlignVCenter
                        tooltip: tab.tooltip
                        text: "Starts an app on a workspace without switching to it, once you log in or the first time you open an empty workspace. Skip if running avoids a second copy. Run now starts it at once."
                    }

                    // what the Hyprland config already starts on a workspace, read only with a way to its file
                    Repeater {
                        model: tab.hyprApps

                        RowLayout {
                            objectName: "hyprApp"
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: parent.parent.modelData.app + " on " + parent.parent.modelData.ws
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.fg
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: "From your Hyprland config: " + parent.parent.modelData.where.join(", ")
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 1
                                    color: Theme.fgMuted
                                }
                            }
                            BarButton {
                                text: "Open file"
                                glued: false
                                bg: Theme.tileBg
                                onClicked: DefaultApps.openInEditor(parent.modelData.file)
                            }
                        }
                    }

                    Repeater {
                        model: tab.entries

                        WorkspaceAppRow {
                            required property var modelData
                            required property int index
                            entry: modelData
                            picker: tab.picker
                            apps: tab.appOptions
                            query: tab.query
                            onEdited: (field, value) => tab.edit(index, field, value)
                            onRemoved: tab.remove(index)
                            onRunNow: WorkspaceApps.runNow(modelData)
                        }
                    }

                    SmallText {
                        visible: tab.entries.length === 0 && tab.hyprApps.length === 0
                        text: "No apps are set to start on a workspace yet."
                    }

                    SmallText {
                        objectName: "twiceNote"
                        visible: tab.twiceNote !== ""
                        color: Theme.urgentFg
                        text: tab.twiceNote
                    }

                    BarButton {
                        objectName: "addWorkspaceApp"
                        text: "Add an app"
                        glued: false
                        bg: Theme.hoverBg
                        onClicked: tab.add()
                    }
                }

                AdvancedSection {
                    SettingRow {
                        label: "Rules in Hyprland"
                        info: "Workspace rules found in your Hyprland config. They are shown here for reference and are edited in the file."
                        tags: "workspace rules hyprland config read only"

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            SmallText {
                                visible: DefaultApps.workspaceRules.length === 0
                                text: "No workspace rules found."
                            }
                            Repeater {
                                model: DefaultApps.workspaceRules

                                Text {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelData.raw
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 1
                                    color: Theme.fg
                                }
                            }
                        }
                    }
                }
            }
        }

        // scroll position, shown only when the page is taller than the view
        Rectangle {
            visible: flick.contentHeight > flick.height
            anchors.right: flick.right
            y: flick.visibleArea.yPosition * flick.height
            width: 3
            height: Math.max(20, flick.visibleArea.heightRatio * flick.height)
            radius: width / 2
            color: Theme.trackBg
        }
    }
}
