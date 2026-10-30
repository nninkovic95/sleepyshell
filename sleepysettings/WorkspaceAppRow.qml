import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// One entry of the Apps tab's "Apps on workspaces" list (services/WorkspaceApps.qml describes the fields): workspace,
// app or command, delay, when, window state, skip-if-running, enabled, Run now, delete. The tab stages edits through
// `edited(field, value)`; nothing here writes settings. The controls wrap onto more lines when the page is narrow.
Item {
    id: row
    required property var entry
    required property var picker
    required property var apps          // [{value, label, icon}] of the installed applications
    property string query: ""
    signal edited(string field, var value)
    signal removed()
    signal runNow()

    Layout.fillWidth: true
    implicitHeight: flow.implicitHeight + 8
    opacity: row.entry.enabled ? 1 : 0.55

    // found by the settings search
    readonly property string searchText: Settings.norm("apps on workspaces " + row.entry.value + " workspace " + row.entry.workspace)
    readonly property bool searchHit: row.query === "" || Settings.searchMatch(row.searchText, row.query)

    readonly property var workspaceOptions: {
        const o = [];
        for (let i = 1; i <= 10; i++)
            o.push({
                value: i,
                label: "Workspace " + i
            });
        o.push({
            value: "special",
            label: "Special workspace"
        });
        return o;
    }
    readonly property var kindOptions: [
        {
            value: "app",
            label: "App"
        },
        {
            value: "command",
            label: "Command"
        }
    ]

    Flow {
        id: flow
        x: 0
        y: 4
        width: row.width
        spacing: 8

        Combo {
            width: 175
            picker: row.picker
            options: row.workspaceOptions
            value: row.entry.workspace
            onPicked: v => row.edited("workspace", v)
        }
        Combo {
            width: 110
            picker: row.picker
            options: row.kindOptions
            value: row.entry.kind
            onPicked: v => row.edited("kind", v)
        }
        AppCombo {
            visible: row.entry.kind === "app"
            width: 230
            picker: row.picker
            options: row.apps
            value: row.entry.value
            emptyText: "No installed apps"
            unsetText: "Pick an app"
            onPicked: v => row.edited("value", v)
        }
        TextBox {
            id: cmd
            visible: row.entry.kind === "command"
            width: 230
            placeholder: "Command, e.g. steam -silent"
            onFinished: if (text !== row.entry.value)
                row.edited("value", text)
            // follows the stored text unless it is being typed in
            Binding {
                target: cmd
                property: "text"
                value: row.entry.value
                when: !cmd.input.activeFocus
                restoreMode: Binding.RestoreNone
            }
        }
        Combo {
            width: 150
            picker: row.picker
            options: WorkspaceApps.whenOptions
            value: row.entry.when
            onPicked: v => row.edited("when", v)
        }
        Combo {
            width: 110
            picker: row.picker
            options: WorkspaceApps.stateOptions
            value: row.entry.windowState
            onPicked: v => row.edited("windowState", v)
        }
        RowLayout {
            spacing: 6
            Text {
                text: "Delay"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                color: Theme.fgMuted
            }
            SpinField {
                value: row.entry.delay
                min: 0
                max: 60
                step: 1
                suffix: "s"
                onMoved: v => row.edited("delay", v)
            }
        }
        RowLayout {
            spacing: 6
            Toggle {
                checked: row.entry.skipIfRunning
                onClicked: row.edited("skipIfRunning", !row.entry.skipIfRunning)
            }
            Text {
                text: "Skip if running"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                color: Theme.fgMuted
            }
        }
        RowLayout {
            spacing: 6
            Toggle {
                checked: row.entry.enabled
                onClicked: row.edited("enabled", !row.entry.enabled)
            }
            Text {
                text: "On"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                color: Theme.fgMuted
            }
        }
        BarButton {
            text: "Run now"
            glued: false
            bg: Theme.tileBg
            enabled: row.entry.value.trim() !== ""
            opacity: enabled ? 1 : 0.5
            onClicked: row.runNow()
        }
        BarButton {
            glyph: 0xF0156
            glued: false
            bg: Theme.tileBg
            onClicked: row.removed()
        }
    }
}
