import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// One file (or folder, or the keybind files) of the Config tab, one line: the
// name, the file name alone (the whole path and what the file is for are in the tooltip), small icon buttons to open it in the editor and
// show it in the file manager, and a "..." menu for the rare things (Change location, back to the usual place, the keybind files). A file that
// is fine shows nothing more. One with a problem gets a coloured badge (Not found, Not loaded, Read-only, Has an error) and its fix beside it:
// Create, Set up, Change... or Open. The tab's status line at the top lists the same problems with the same fixes (FilesTab).
// With a `key` the path is a setting: the row shows the staged one, Change location... opens the window's themed file browser
// (FolderBrowser), Back to the usual place stages the default, and Apply saves it; the consumers read the applied path. A file that
// Sleepysettings may create (`canCreate`) can be named new in the browser, which makes it at once. A fixed file (sleepysettings.toml, hyprland.lua)
// has no location to change.
// `listCard` is the keybinds row: under its line one sub-line for each file the keybinds were found in, laid out like the other rows (the file
// name in their file-name column, how many keybinds and a tag, the editor and folder icons in their icon column; the path in the tip, a click
// copies it) and "+ Add file..", directly under them, for a file Hyprland reads in an unusual way (keybindExtraFiles, with a remove button each).
Item {
    id: row
    objectName: "fileRow"
    // FileChecks id ("" for none)
    property string fileId: ""
    property string label: ""
    // what it is for, plain words, for the tooltip
    property string purpose: ""
    property string key: ""
    property string path: ""
    property bool isDir: false
    property bool canCreate: false
    property var filters: []
    property bool listCard: false
    // Sleepysettings makes this file itself when it first writes it: a path that is not there is not an error
    property bool own: false
    // lit up for a moment: "Configure in Config" points here
    property bool flash: false

    readonly property var page: {
        let p = row.parent;
        while (p && p.isTabPage !== true)
            p = p.parent;
        return p ?? null;
    }
    readonly property var tooltip: row.page ? row.page.tooltip : null
    readonly property var folders: row.page ? row.page.folders : null
    readonly property var picker: row.page ? row.page.picker : null
    readonly property string query: row.page ? row.page.query : ""

    readonly property string value: row.key !== "" ? String(Settings.get(row.key)) : row.path
    readonly property string full: Settings.expand(row.value)
    readonly property string fileName: row.full.slice(row.full.lastIndexOf("/") + 1)
    readonly property bool staged: row.key !== "" && Settings.pending.hasOwnProperty(row.key)
    readonly property string defaultPath: row.key !== "" && Settings.schema[row.key] ? Settings.tilde(String(Settings.schema[row.key].def)) : ""
    readonly property bool custom: row.key !== "" && Settings.get(row.key) !== Settings.schema[row.key].def
    // the file check of this file (FileChecks), and whether it is about the path in force (a path staged here is checked after Apply)
    readonly property var problem: row.fileId !== "" && !row.listCard ? FileChecks.problem(row.fileId) : (row.listCard ? FileChecks.problem("custombinds") : null)
    readonly property bool applied: row.fileId === "" ? true : row.listCard ? Settings.expand(String(Settings.get("pathCustombinds"))) === FileChecks.pathOf("custombinds") : row.full === FileChecks.pathOf(row.fileId)
    readonly property var st: row.listCard ? FileChecks.info(Settings.expand(String(Settings.get("pathCustombinds")))) : FileChecks.info(row.full)
    readonly property bool gone: row.st !== null && !row.st.exists
    readonly property string checkId: row.listCard ? "custombinds" : row.fileId
    readonly property bool canMake: row.fix === "Create"
    readonly property bool notLoaded: row.applied && row.problem !== null && row.problem.kind === "notLoaded"

    // the badge: what is wrong (nothing for a file that is fine)
    readonly property string badge: {
        if (row.applied && row.problem !== null) {
            const k = row.problem.kind;
            return k === "needs" ? "Not installed" : k === "missing" || k === "noCreate" ? "Not found" : k === "notLoaded" || k === "noConfig" ? "Not loaded" : k === "notWritable" ? "Read-only" : k === "damaged" ? "Has an error" : "";
        }
        // a path staged here but not applied yet, or Hyprland's main config: only "not found" can be said
        return row.gone && !row.own && !row.applied || (row.gone && row.fileId === "") ? "Not found" : "";
    }
    readonly property bool bad: row.badge !== ""
    // what a program problem tells to copy, or the require line of a file Hyprland does not load (shown under the sentence in the status line)
    readonly property string lineText: row.bad && row.problem !== null && row.applied ? row.problem.requireLine : ""
    // a short plain sentence for the status line
    // (it names the file, says what it is for and what the fix does: FileChecks writes it, with <b> around the file name)
    readonly property string short: row.bad && row.problem !== null && row.applied ? row.problem.text : ""
    // the fix: the button beside the badge ("" for none)
    readonly property string fix: {
        if (!row.bad)
            return "";
        if (row.applied && row.problem !== null) {
            const a = row.problem.action;
            return a === "create" ? "Create" : a === "setup" ? "Set up" : a === "openSettings" ? "Open" : a === "shuffle" ? "Shuffle colours" : a === "configure" && row.key !== "" ? "Change…" : "";
        }
        return row.key !== "" ? "Change…" : "";
    }
    function doFix() {
        if (row.fix === "Change…")
            row.select();
        else if (row.fix !== "" && row.problem !== null)
            FileChecks.act(row.problem);
    }

    // the tooltip: what it is for, then the whole path on a muted line
    readonly property string tipText: row.purpose + "<br><font color='" + Theme.fgMuted + "'>" + (row.listCard ? row.listFiles.map(p => Settings.tilde(p) + " · " + row.countText(p)).join("<br>") : Settings.tilde(row.full)).replace(/</g, "&lt;") + "</font>"

    readonly property string searchText: Settings.norm(row.label + " " + row.purpose + " " + row.value + " " + row.badge + " " + row.fileName)
    readonly property bool searchHit: row.query === "" || Settings.searchMatch(row.searchText, row.query)

    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 10
    opacity: row.searchHit ? 1 : 0.3
    Behavior on opacity {
        NumberAnimation {
            duration: 120
        }
    }

    // lit up for a moment (Configure in Config)
    Rectangle {
        x: -8
        y: 0
        width: row.width + 16
        height: row.height
        radius: Theme.radiusMd
        color: Qt.alpha(Theme.accent, 0.28)
        opacity: row.flash ? 1 : 0
        visible: opacity > 0
        z: -1
        Behavior on opacity {
            NumberAnimation {
                duration: 350
            }
        }
    }

    // what the browser (Change location...) chose, as the setting's value (~ for home), staged like any change; the tests call this
    function choose(p) {
        Settings.stage(row.key, Settings.tilde(p));
    }

    function select() {
        if (row.key === "" || !row.folders)
            return;
        const start = row.isDir ? row.full : row.full.replace(/\/[^\/]*$/, "") || "/";
        const dflt = String(Settings.schema[row.key].def);
        const opts = { title: "Choose: " + row.label, filters: row.filters, newFile: row.canCreate, fileName: dflt.slice(dflt.lastIndexOf("/") + 1) };
        if (row.isDir)
            row.folders.open(start, p => row.choose(p));
        else
            row.folders.openFile(start, p => row.choose(p), opts);
    }

    // ---- the keybinds row: files with keybinds, and the extra ones ----
    readonly property var extraList: {
        return Settings.asList(Settings.get("keybindExtraFiles"));
    }
    readonly property var listFiles: {
        if (!row.listCard)
            return [];
        const out = HyprConfig.ok ? HyprConfig.bindFiles.slice() : Keybinds.bindFiles.slice();
        if (HyprConfig.ok && Keybinds.customPath !== "" && !out.includes(Keybinds.customPath) && HyprConfig.isLoaded(Keybinds.customPath))
            out.push(Keybinds.customPath);
        for (const p of row.extraList.map(x => Settings.expand(x)))
            if (!out.includes(p))
                out.push(p);
        return out;
    }
    function countIn(path) {
        return (HyprConfig.ok ? HyprConfig.binds : Keybinds.binds).filter(b => b.file === path).length;
    }
    function countText(path) {
        const n = row.countIn(path);
        const tag = path === Keybinds.customPath ? " · added here" : row.extraList.map(x => Settings.expand(x)).includes(path) ? " · extra" : "";
        return (n === 1 ? "1 keybind" : n + " keybinds") + tag;
    }
    function addExtra(path) {
        const p = Settings.tilde(path);
        if (row.extraList.includes(p))
            return false;
        Settings.stage("keybindExtraFiles", row.extraList.concat([p]));
        return true;
    }
    function removeExtra(i) {
        Settings.stage("keybindExtraFiles", row.extraList.filter((x, j) => j !== i));
    }
    function pickExtra() {
        if (!row.folders)
            return;
        row.folders.openFile(HyprConfig.dir, p => row.addExtra(p), { title: "Choose: Extra keybind file", filters: ["*.lua", "*.conf"] });
    }

    // ---- the "..." menu: drawn by the window's Picker, so it can reach past the tab ----
    // options: Change location..., Back to the usual place, Open hyprland.lua (a file Hyprland does not load)
    readonly property var menuOptions: {
        const o = [];
        if (row.key !== "")
            o.push({ value: "change", label: "Change location…" });
        if (row.key !== "" && row.custom)
            o.push({ value: "reset", label: "Back to the usual place" });
        if (row.notLoaded)
            o.push({ value: "hypr", label: "Open " + (HyprConfig.format === "conf" ? "hyprland.conf" : "hyprland.lua") });
        if (row.listCard && row.extraList.length > 0 && Settings.pending.hasOwnProperty("keybindExtraFiles"))
            o.push({ value: "extrareset", label: "Undo the added files" });
        return o;
    }
    function menuPicked(v) {
        if (v === "change")
            row.select();
        else if (v === "reset")
            Settings.stage(row.key, Settings.schema[row.key].def);
        else if (v === "hypr")
            FileChecks.act({ action: "openHypr", id: row.checkId });
        else if (v === "extrareset")
            Settings.stage("keybindExtraFiles", []);
    }

    ColumnLayout {
        id: body
        x: 0
        y: 5
        width: parent.width
        spacing: 2

        // the line: name, file name, badge, fix, icons
        RowLayout {
            id: line
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 8

            Rectangle {
                objectName: "rowStaged"
                visible: row.staged
                implicitWidth: 6
                implicitHeight: 6
                radius: 3
                color: Theme.accent
            }

            // the name and the file name: hovering them says what the file is for and where it is
            Item {
                id: info
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                Layout.minimumWidth: 60

                Text {
                    id: nameText
                    objectName: "rowLabel"
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 160)
                    elide: Text.ElideRight
                    text: row.label
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    color: Theme.fg
                }

                Text {
                    objectName: "rowFile"
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(nameText.width + 12, 168)
                    width: Math.max(0, parent.width - x)
                    elide: Text.ElideMiddle
                    visible: !row.listCard
                    text: row.fileName
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.weight: Font.Medium
                    color: row.gone ? Theme.fgMuted : Theme.fg
                }

                HoverHandler {
                    onHoveredChanged: {
                        if (!row.tooltip)
                            return;
                        if (hovered)
                            row.tooltip.show(info, row.tipText, false);
                        else
                            row.tooltip.hide(info);
                    }
                }
            }

            Rectangle {
                id: badgeBox
                objectName: "rowBadge"
                visible: row.bad
                implicitWidth: badgeText.implicitWidth + 14
                implicitHeight: 20
                radius: Theme.radiusXs
                color: Qt.alpha(Theme.urgentFg, 0.16)

                // the whole sentence: which file, what it is for, what the button does
                HoverHandler {
                    onHoveredChanged: {
                        if (!row.tooltip || row.short === "")
                            return;
                        if (hovered)
                            row.tooltip.show(badgeBox, row.short, true);
                        else
                            row.tooltip.hide(badgeBox);
                    }
                }

                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: row.badge
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                    font.weight: Font.Medium
                    color: Theme.urgentFg
                }
            }

            BarButton {
                objectName: "rowFix"
                visible: row.fix !== ""
                text: row.fix
                glyph: row.fix === "Create" ? 0xF0257 : row.fix === "Set up" ? 0xF0493 : row.fix === "Open" ? 0xF11E7 : row.fix === "Shuffle colours" ? 0xF03D8 : 0xF0DCF
                glyphFirst: true
                glued: false
                bg: Theme.hoverBg
                onClicked: row.doFix()
            }

            // Open in the editor, Show in the file manager; the keybinds row has them on each of its files instead
            BarButton {
                id: openBtn
                objectName: "openFile"
                visible: !row.listCard && !row.isDir
                glyph: 0xF11E7
                glued: false
                hpad: 5
                enabled: Deps.has(Keybinds.editorProgram) && !row.gone
                opacity: enabled ? 1 : 0.4
                onClicked: if (enabled)
                    Keybinds.openFile(row.full)
                onHoveredChanged: {
                    if (!row.tooltip)
                        return;
                    if (hovered)
                        row.tooltip.show(openBtn, row.gone ? "Not found" : enabled ? "Open in the editor" : Deps.needs([Keybinds.editorProgram]), false);
                    else
                        row.tooltip.hide(openBtn);
                }
            }

            BarButton {
                id: showBtn
                objectName: "revealFile"
                visible: !row.listCard
                glyph: 0xF0DCF
                glued: false
                hpad: 5
                enabled: Deps.has(Keybinds.openerProgram)
                opacity: enabled ? 1 : 0.4
                onClicked: if (enabled)
                    row.isDir ? Keybinds.revealDir(row.full) : Keybinds.revealFile(row.full)
                onHoveredChanged: {
                    if (!row.tooltip)
                        return;
                    if (hovered)
                        row.tooltip.show(showBtn, enabled ? "Show in the file manager" : Deps.needs([Keybinds.openerProgram]), false);
                    else
                        row.tooltip.hide(showBtn);
                }
            }

            // the rare things; its room is kept on every row so the icons line up
            Item {
                id: menuHost
                implicitWidth: menuBtn.implicitWidth
                implicitHeight: menuBtn.implicitHeight
                // what the window's Picker needs of its target
                property var options: row.menuOptions
                property var value: ""
                property real menuWidth: 200
                property bool menuAlignRight: true
                signal picked(var v)
                onPicked: v => row.menuPicked(v)

                BarButton {
                    id: menuBtn
                    objectName: "rowMenu"
                    anchors.fill: parent
                    glyph: 0xF01D8
                    glued: false
                    hpad: 5
                    enabled: row.menuOptions.length > 0
                    opacity: enabled ? 1 : 0.3
                    onClicked: if (enabled && row.picker)
                        row.picker.show(menuHost)
                    onHoveredChanged: {
                        if (!row.tooltip)
                            return;
                        if (hovered && enabled)
                            row.tooltip.show(menuBtn, "More: " + row.menuOptions.map(o => o.label).join(", "), false);
                        else
                            row.tooltip.hide(menuBtn);
                    }
                }
            }
        }

        // the keybind files, laid out like the other rows: the file name in the rows' file-name column, how many keybinds,
        // the editor and folder icons in the rows' icon column; the whole path is in the name's tip and a click on the name copies it. An added
        // file (keybindExtraFiles) has its remove button where the other rows have "...". "+ Add file..." follows directly under them.
        ColumnLayout {
            id: subLines
            objectName: "rowFiles"
            visible: row.listCard
            Layout.fillWidth: true
            spacing: 2
            // where the other rows' file names start
            readonly property real fileX: info.x + Math.max(nameText.width + 12, 168)

            Repeater {
                model: row.listFiles

                RowLayout {
                    id: sub
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: subLines.fileX
                    Layout.preferredHeight: 26
                    spacing: 8
                    readonly property var fst: FileChecks.info(modelData)
                    readonly property bool extra: row.extraList.map(x => Settings.expand(x)).includes(modelData)

                    Item {
                        id: subName
                        objectName: "keybindFile"
                        readonly property string path: Settings.tilde(sub.modelData)
                        readonly property bool missing: sub.fst !== null && !sub.fst.exists
                        // what the last click copied (the tests read it; the clipboard itself is the compositor's)
                        property string lastCopied: ""
                        Layout.preferredWidth: Math.min(subNameText.implicitWidth, 260)
                        Layout.preferredHeight: 26

                        Text {
                            id: subNameText
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            elide: Text.ElideMiddle
                            text: sub.modelData.slice(sub.modelData.lastIndexOf("/") + 1)
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            font.weight: Font.Medium
                            color: subName.missing ? Theme.fgMuted : Theme.fg
                        }

                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                            onHoveredChanged: {
                                if (!row.tooltip)
                                    return;
                                if (hovered)
                                    // the same path a click copies, written out
                                    row.tooltip.show(subName, sub.modelData.replace(/</g, "&lt;") + "<br><font color='" + Theme.fgMuted + "'>Click to copy the path</font>", false);
                                else
                                    row.tooltip.hide(subName);
                            }
                        }

                        TapHandler {
                            onTapped: {
                                Quickshell.clipboardText = sub.modelData;
                                subName.lastCopied = sub.modelData;
                                if (row.tooltip)
                                    row.tooltip.show(subName, "Copied", false);
                            }
                        }
                    }

                    Text {
                        objectName: "keybindCount"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: (subName.missing ? "Not found · " : "") + row.countText(sub.modelData)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.fgMuted
                    }

                    BarButton {
                        id: subOpen
                        objectName: "keybindOpen"
                        glyph: 0xF11E7
                        glued: false
                        hpad: 5
                        enabled: Deps.has(Keybinds.editorProgram) && !subName.missing
                        opacity: enabled ? 1 : 0.4
                        onClicked: if (enabled)
                            Keybinds.openFile(sub.modelData)
                        onHoveredChanged: {
                            if (!row.tooltip)
                                return;
                            if (hovered)
                                row.tooltip.show(subOpen, subName.missing ? "Not found" : enabled ? "Open in the editor" : Deps.needs([Keybinds.editorProgram]), false);
                            else
                                row.tooltip.hide(subOpen);
                        }
                    }

                    BarButton {
                        id: subShow
                        objectName: "keybindReveal"
                        glyph: 0xF0DCF
                        glued: false
                        hpad: 5
                        enabled: Deps.has(Keybinds.openerProgram)
                        opacity: enabled ? 1 : 0.4
                        onClicked: if (enabled)
                            Keybinds.revealFile(sub.modelData)
                        onHoveredChanged: {
                            if (!row.tooltip)
                                return;
                            if (hovered)
                                row.tooltip.show(subShow, enabled ? "Show in the file manager" : Deps.needs([Keybinds.openerProgram]), false);
                            else
                                row.tooltip.hide(subShow);
                        }
                    }

                    // the "..." column: the remove button of an added file, else empty room so the icons line up
                    Item {
                        implicitWidth: menuHost.implicitWidth
                        implicitHeight: menuHost.implicitHeight

                        BarButton {
                            id: removeBtn
                            objectName: "extraRemove"
                            anchors.fill: parent
                            visible: sub.extra
                            glyph: 0xF0156
                            hpad: 5
                            glued: false
                            fg: Theme.fgMuted
                            hoverFg: Theme.fg
                            onClicked: row.removeExtra(row.extraList.map(x => Settings.expand(x)).indexOf(sub.modelData))
                            onHoveredChanged: {
                                if (!row.tooltip)
                                    return;
                                if (hovered)
                                    row.tooltip.show(removeBtn, "Remove from the list (the file stays)", false);
                                else
                                    row.tooltip.hide(removeBtn);
                            }
                        }
                    }
                }
            }

            SmallText {
                visible: row.listFiles.length === 0
                Layout.leftMargin: subLines.fileX
                text: HyprConfig.ok ? "No keybinds found in your Hyprland files." : "Your Hyprland files could not be read yet."
            }

            BarButton {
                objectName: "extraAdd"
                Layout.leftMargin: subLines.fileX - 8
                text: "Add file…"
                glyph: 0xF0415
                glyphFirst: true
                glued: false
                bg: Theme.tileBg
                onClicked: row.pickExtra()
            }
        }
    }
}
