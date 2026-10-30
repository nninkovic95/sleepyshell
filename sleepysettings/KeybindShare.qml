import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// The Keybinds tab's "Share keybinds" card: Export writes the binds added in Sleepysettings (or every bind Hyprland loads)
// to a Lua file picked in the window's browser; Import reads a Lua file of hl.bind lines or a .conf file, shows what it would do
// (new / already there / conflict, with a choice per conflict) and writes NOTHING until "Add to the list". Add only stages the binds, like
// a bind added by hand; Apply writes sleepybinds.lua (after a backup). Everything that is not a command keybind is listed as not imported
// with its line and why, and is never copied or run (services/Keybinds.qml, scripts/hyprconf.py parse-binds).
ColumnLayout {
    id: share
    // the window's file browser and tooltip (the tab passes them in)
    property var folders: null
    property var tooltip: null
    readonly property var plan: Keybinds.importPlan
    readonly property var counts: Keybinds.importPlan ? Keybinds.planCounts() : null
    spacing: 8
    Layout.fillWidth: true
    // the rows "already there" are folded away unless there are only a few (a long default list would bury the news)
    property bool showSame: false
    onPlanChanged: showSame = plan !== null && plan.items.length <= 8

    // ---- export ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            text: "Export"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            color: Theme.fg
            Layout.preferredWidth: 60
        }

        Segmented {
            objectName: "exportMode"
            options: [{ value: false, label: "My keybinds" }, { value: true, label: "All keybinds" }]
            value: Keybinds.exportAll
            onPicked: v => Keybinds.exportAll = v
        }

        BarButton {
            objectName: "exportButton"
            text: "Export…"
            glued: false
            bg: Theme.hoverBg
            onClicked: Keybinds.chooseExport(share.folders)
        }

        InfoTip {
            tooltip: share.tooltip
            text: "Saves a small Lua file you can read, share or keep as a backup. “My keybinds” are the ones added in this tab; “All keybinds” lists every keybind your Hyprland files define (the ones that do not run a command are comments)."
        }

        Item {
            Layout.fillWidth: true
        }
    }

    SmallText {
        objectName: "exportMessage"
        visible: Keybinds.exportMessage !== ""
        color: Keybinds.exportFailed ? Theme.urgentFg : Theme.fgMuted
        text: Keybinds.exportMessage
    }

    // ---- import ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            text: "Import"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            color: Theme.fg
            Layout.preferredWidth: 60
        }

        BarButton {
            objectName: "importButton"
            text: Keybinds.importBusy ? "Reading…" : "Import…"
            glued: false
            bg: Theme.hoverBg
            onClicked: Keybinds.chooseImport(share.folders)
        }

        BarButton {
            objectName: "importDefaultsButton"
            text: "Hyprland defaults"
            glued: false
            bg: Theme.hoverBg
            onClicked: Keybinds.importDefaultBinds()
        }

        InfoTip {
            tooltip: share.tooltip
            text: "Import… reads a .lua file of hl.bind lines or a Hyprland .conf file and shows what it would add. Nothing is written until you press Add and then Apply. Only command keybinds and a few window and workspace actions are imported; the file is checked, never run. Hyprland defaults are the keybinds of Hyprland’s own example config (v0.56.2), with its terminal, file manager and launcher replaced by yours from programs.lua."
        }

        Item {
            Layout.fillWidth: true
        }
    }

    SmallText {
        objectName: "importError"
        visible: Keybinds.importError !== ""
        color: Theme.urgentFg
        text: Keybinds.importError
    }

    SmallText {
        objectName: "importMessage"
        visible: Keybinds.importMessage !== ""
        text: Keybinds.importMessage
    }

    // ---- the preview ----
    ColumnLayout {
        objectName: "importPreview"
        visible: share.plan !== null
        Layout.fillWidth: true
        spacing: 6

        Text {
            Layout.fillWidth: true
            elide: Text.ElideMiddle
            text: share.plan ? (share.plan.defaults ? "From the Hyprland defaults (Hyprland 0.56.2 example config)" : "From " + Settings.tilde(share.plan.path)) : ""
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            font.weight: Font.Medium
            color: Theme.fg
        }

        SmallText {
            objectName: "importSummary"
            text: {
                const c = share.counts;
                if (!c)
                    return "";
                const parts = [];
                parts.push(c.new + " new");
                if (c.same + c.repeat > 0)
                    parts.push((c.same + c.repeat) + " already there");
                if (c.conflict > 0)
                    parts.push(c.conflict + (c.conflict === 1 ? " conflict" : " conflicts"));
                if (c.errors > 0)
                    parts.push(c.errors + (c.errors === 1 ? " line" : " lines") + " not imported");
                return parts.join(" · ") + (share.plan && share.plan.ignored > 0 ? " · " + share.plan.ignored + " other lines skipped (not keybinds)" : "");
            }
        }

        SmallText {
            objectName: "importVars"
            visible: share.plan && share.plan.defaults && Object.keys(Keybinds.importVars).length > 0
            text: "Filled in from your programs.lua: " + Object.keys(Keybinds.importVars).map(k => k + " = " + Keybinds.importVars[k]).join(", ")
        }

        SmallText {
            objectName: "importEmpty"
            visible: share.plan && share.plan.items.length === 0
            text: "There are no keybinds in this file that can be imported."
        }

        BarButton {
            objectName: "importShowSame"
            visible: share.counts !== null && share.counts.same + share.counts.repeat > 0
            text: share.showSame ? "Hide the ones already there" : "Show the " + (share.counts ? share.counts.same + share.counts.repeat : 0) + " already there"
            glued: false
            onClicked: share.showSame = !share.showSame
        }

        Repeater {
            model: share.plan ? share.plan.items : []

            ColumnLayout {
                id: item
                required property var modelData
                required property int index
                objectName: "importItem"
                visible: (item.modelData.status !== "same" && item.modelData.status !== "repeat") || share.showSame
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        objectName: "importStatus"
                        Layout.preferredWidth: 96
                        text: item.modelData.status === "new" ? "New" : item.modelData.status === "conflict" ? "Conflict" : "Already there"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                        font.weight: Font.Medium
                        color: item.modelData.status === "new" ? Theme.primary : item.modelData.status === "conflict" ? Theme.urgentFg : Theme.fgMuted
                    }

                    Rectangle {
                        implicitWidth: comboText.implicitWidth + 12
                        implicitHeight: 22
                        radius: Theme.radiusXs
                        color: Theme.trackBg

                        Text {
                            id: comboText
                            anchors.centerIn: parent
                            text: item.modelData.combo
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                            color: Theme.fg
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: item.modelData.action
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.fg
                    }

                    Segmented {
                        objectName: "conflictChoice"
                        visible: item.modelData.status === "conflict" && !item.modelData.builtin
                        options: [{ value: "mine", label: "Keep mine" }, { value: "theirs", label: "Take imported" }]
                        value: item.modelData.choice
                        onPicked: v => Keybinds.chooseConflict(item.index, v)
                    }
                }

                SmallText {
                    Layout.leftMargin: 104
                    visible: item.modelData.note !== "" || item.modelData.builtin
                    text: item.modelData.builtin ? item.modelData.note + ". It is changed in its own file, so the imported one is not added." : item.modelData.note
                }
            }
        }

        // lines that were not imported, with the reason (the first few)
        Text {
            visible: share.plan && share.plan.errors.length > 0
            Layout.topMargin: 4
            text: "Not imported"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            font.weight: Font.Medium
            color: Theme.fg
        }

        Repeater {
            model: share.plan ? share.plan.errors.slice(0, 8) : []

            ColumnLayout {
                id: err
                required property var modelData
                objectName: "importErrorLine"
                Layout.fillWidth: true
                spacing: 0

                SmallText {
                    color: Theme.urgentFg
                    text: "Line " + err.modelData.line + ": " + err.modelData.reason
                }

                SmallText {
                    visible: err.modelData.raw !== ""
                    Layout.leftMargin: 8
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: err.modelData.raw
                }
            }
        }

        SmallText {
            visible: share.plan && share.plan.errors.length > 8
            text: share.plan ? "and " + (share.plan.errors.length - 8) + " more lines" : ""
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            BarButton {
                objectName: "importAdd"
                visible: share.counts !== null
                enabled: share.counts !== null && share.counts.add > 0
                opacity: enabled ? 1 : 0.5
                text: share.counts ? "Add " + share.counts.add + (share.counts.add === 1 ? " keybind" : " keybinds") + " to the list" : "Add"
                glued: false
                bg: Theme.hoverBg
                onClicked: if (enabled) Keybinds.confirmImport()
            }

            BarButton {
                objectName: "importCancel"
                text: "Cancel"
                glued: false
                onClicked: Keybinds.cancelImport()
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
