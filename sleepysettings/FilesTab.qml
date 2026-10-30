import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// Settings tab "Config" (the key is "files", the file is FilesTab.qml): every file
// Sleepysettings writes or reads. The paths are settings, each with a way to select a file and an arrow to reset. A status line
// on top, then one line per file in three groups by purpose (FileRow). The status line says "Everything is set up." or lists what needs
// attention, each with its fix; a file that is fine shows nothing but its name, its file name and the icons. The rare actions (change the
// location, back to the usual place) are in each row's "..." menu. The wallpaper folder is the Theme tab's key, edited here too.
TabPage {
    id: tab
    key: "files"
    label: "Config"
    icon: 0xF107C
    group: "files"
    // the wallpaper folder is the Theme tab's key, edited here too
    extraKeys: ["wallpaperDir"]

    // Reset (at the bottom of this tab): puts one tab's settings, or every tab's, back to their defaults. It only stages them like a revert arrow does, behind a
    // ConfirmDialog: the tabs show the arrows and the unapplied mark and nothing is written until Apply. Keybinds and Display keep their own drafts
    // and are not touched. After a reset the window jumps to the first tab that now has changes, since the Apply bar acts on the open tab.
    // the tabs Reset can reset (Sleepysettings passes the ones that stage Settings keys) and the
    // one picked in the Reset card
    property var resettable: []
    property string resetPick: "bar"
    readonly property var resetPage: tab.resettable.find(p => p.key === tab.resetPick) ?? null
    // asks the window to open this tab
    signal resetDone(string key)

    function askResetTab() {
        const p = tab.resetPage;
        if (!p || !tab.confirm)
            return;
        tab.confirm.ask("Reset the " + p.label + " tab?", "Puts the settings on this tab back to their defaults. Nothing is saved until you press Apply, and Discard undoes it.", () => {
            Settings.stageDefaults(p.keys);
            tab.resetDone(p.key);
        }, null, null, "Reset", "", "Cancel");
    }

    function askResetAll() {
        if (!tab.confirm)
            return;
        tab.confirm.ask("Reset all settings?", "Puts every setting on every tab back to its default, except Keybinds and Display, which keep their own drafts. Nothing is saved until you press Apply on each tab, and Discard undoes it.", () => {
            const keys = [];
            for (const p of tab.resettable)
                for (const k of p.keys)
                    if (!keys.includes(k))
                        keys.push(k);
            Settings.stageDefaults(keys);
            const first = tab.resettable.find(p => p.changes > 0);
            if (first)
                tab.resetDone(first.key);
        }, null, null, "Reset all", "", "Cancel");
    }

    // every row, in the order of the groups below; the status line works from this list
    readonly property var allRows: [rSettings, rMain, rKeys, rMonitors, rIdle, rColors, rWall]
    readonly property var problems: tab.allRows.filter(r => r.bad)

    // the row a file id points at (the other tabs' "Configure in Config")
    function target(id) {
        const m = { settings: rSettings, hypridle: rIdle, monitors: rMonitors, custombinds: rKeys, colors: rColors, wallpaper: rWall, keybinds: rKeys, extrakeybinds: rKeys };
        return m[id] ?? null;
    }

    // "Configure in Config": light the row up for a moment
    property var flashing: null
    function reveal(id) {
        const c = tab.target(id);
        if (!c)
            return;
        if (tab.flashing)
            tab.flashing.flash = false;
        tab.flashing = c;
        c.flash = true;
        flashOff.restart();
    }
    Timer {
        id: flashOff
        interval: 3500
        onTriggered: {
            if (tab.flashing)
                tab.flashing.flash = false;
            tab.flashing = null;
        }
    }

    // ---- the status line ----
    Rectangle {
        id: status
        objectName: "configStatus"
        Layout.fillWidth: true
        implicitHeight: statusCol.implicitHeight + 20
        radius: Theme.radiusLg
        color: Theme.container
        border.width: tab.problems.length > 0 ? 1 : 0
        border.color: Qt.alpha(Theme.urgentFg, 0.4)

        ColumnLayout {
            id: statusCol
            x: 14
            y: 10
            width: parent.width - 28
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Glyph {
                    cp: tab.problems.length > 0 ? 0xF0026 : 0xF05E0
                    color: tab.problems.length > 0 ? Theme.urgentFg : Theme.primary
                }

                Text {
                    objectName: "statusText"
                    Layout.fillWidth: true
                    text: tab.problems.length === 0 ? "Everything is set up." : tab.problems.length === 1 ? "1 thing needs attention" : tab.problems.length + " things need attention"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.Medium
                    color: Theme.fg
                }
            }

            Repeater {
                model: tab.problems

                ColumnLayout {
                    id: pl
                    required property var modelData
                    objectName: "statusProblem"
                    property bool copied: false
                    property string lastCopied: ""
                    Layout.fillWidth: true
                    Layout.leftMargin: 26
                    spacing: 4

                    Timer {
                        id: plCopied
                        interval: 1400
                        onTriggered: pl.copied = false
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            objectName: "statusLine"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            textFormat: Text.StyledText
                            text: pl.modelData.short
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            color: Theme.fg
                        }

                        BarButton {
                            objectName: "bannerFix"
                            visible: pl.modelData.fix !== ""
                            text: pl.modelData.fix
                            glyph: pl.modelData.fix === "Create" ? 0xF0257 : pl.modelData.fix === "Set up" ? 0xF0493 : pl.modelData.fix === "Open" ? 0xF11E7 : pl.modelData.fix === "Shuffle colours" ? 0xF03D8 : 0xF0DCF
                            glyphFirst: true
                            glued: false
                            bg: Theme.hoverBg
                            onClicked: pl.modelData.doFix()
                        }
                    }

                    // a command to install a program, or the line to add to hyprland.lua: monospace, a click copies it (never run)
                    Rectangle {
                        id: lineBox
                        objectName: "statusLineBox"
                        visible: pl.modelData.lineText !== ""
                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.radiusSm
                        color: lineMouse.containsMouse ? Theme.hoverBg : Theme.tileBg

                        Text {
                            objectName: "statusCommand"
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideMiddle
                            textFormat: Text.PlainText
                            text: pl.copied ? "Copied" : pl.modelData.lineText
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            color: pl.copied ? Theme.primary : Theme.fg
                        }

                        MouseArea {
                            id: lineMouse
                            objectName: "statusLineArea"
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.clipboardText = pl.modelData.lineText;
                                pl.lastCopied = pl.modelData.lineText;
                                pl.copied = true;
                                plCopied.restart();
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- by purpose ----
    Section {
        title: "Sleepyshell"

        FileRow {
            id: rSettings
            fileId: "settings"
            label: "Settings"
            path: Settings.path
            purpose: "Everything you set in Sleepysettings, in a plain text file you can edit by hand. This file can't be moved."
        }
    }

    Section {
        title: "Hyprland"

        FileRow {
            id: rMain
            label: "Main config"
            path: Keybinds.mainPath
            purpose: "Hyprland's main settings file, which loads the others. Sleepysettings only reads it."
        }
        FileRow {
            id: rKeys
            fileId: "custombinds"
            listCard: true
            label: "Keybinds"
            key: "pathCustombinds"
            own: true
            canCreate: true
            filters: ["*.lua"]
            purpose: "The keybinds of your Hyprland setup. The ones you add in the Keybinds tab are saved in the file marked \u201cadded here\u201d."
        }
        FileRow {
            id: rMonitors
            fileId: "monitors"
            label: "Monitors"
            key: "pathMonitors"
            canCreate: true
            filters: ["*.lua"]
            purpose: "Where your screen settings are saved. You normally don't need to change this."
        }
        FileRow {
            id: rIdle
            fileId: "hypridle"
            label: "Idle"
            key: "pathHypridle"
            canCreate: true
            filters: ["*.conf"]
            purpose: "Where the idle timers are saved. You normally don't need to change this."
        }
    }

    Section {
        title: "Theme"

        FileRow {
            id: rColors
            fileId: "colors"
            label: "Colours"
            key: "pathColors"
            filters: ["*.json"]
            purpose: "The colours of your theme, read by the shell. You normally don't need to change this."
        }
        FileRow {
            id: rWall
            fileId: "wallpaper"
            label: "Wallpapers"
            key: "wallpaperDir"
            isDir: true
            purpose: "The folder the wallpaper picker offers pictures from (the Theme tab has the same setting)."
        }
    }

    // how the window behaves (it belongs with the settings, behind Apply)
    Section {
        title: "Window"

        SwitchRow {
            label: "Show unavailable tabs"
            key: "showUnavailableTabs"
            info: "Shows tabs that need something missing, greyed out, instead of hiding them."
            tags: "tabs hidden greyed sidebar power"
        }
    }

    // Reset: staged, behind a dialog; nothing is written before Apply
    Section {
        title: "Reset"

        SettingRow {
            label: "Reset one tab…"
            info: "Puts the settings of the chosen tab back to their defaults. They are only staged: the tab shows the revert arrows and nothing is written until you press Apply there."
            tags: "defaults restore"

            Combo {
                picker: tab.picker
                value: tab.resetPick
                options: tab.resettable.map(p => ({
                            value: p.key,
                            label: p.label
                        }))
                onPicked: v => tab.resetPick = v
            }

            BarButton {
                text: "Reset…"
                glued: false
                bg: Theme.tileBg
                onClicked: tab.askResetTab()
            }
        }
        SettingRow {
            label: "Reset all settings…"
            info: "Stages the defaults of every tab except <b>Keybinds</b> and <b>Display</b>, which keep their own drafts and are not touched. Nothing is written until you press Apply on each tab."
            warn: true
            tags: "defaults restore everything"

            BarButton {
                text: "Reset all…"
                glued: false
                bg: Theme.tileBg
                onClicked: tab.askResetAll()
            }
        }
    }

    // optional programs that are missing: a muted note, never a warning (khal, lspci), with the command to copy
    Repeater {
        model: FileChecks.notes

        RowLayout {
            id: note
            required property var modelData
            objectName: "optionalNote"
            Layout.fillWidth: true
            spacing: 8
            property bool copied: false
            property string lastCopied: ""

            Timer {
                id: noteCopied
                interval: 1400
                onTriggered: note.copied = false
            }

            SmallText {
                objectName: "optionalNoteText"
                text: note.modelData.text
                textFormat: Text.StyledText
            }

            BarButton {
                objectName: "optionalCopy"
                visible: note.modelData.line !== ""
                text: note.copied ? "Copied" : note.modelData.line
                glued: false
                bg: Theme.tileBg
                onClicked: {
                    Quickshell.clipboardText = note.modelData.line;
                    note.lastCopied = note.modelData.line;
                    note.copied = true;
                    noteCopied.restart();
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
