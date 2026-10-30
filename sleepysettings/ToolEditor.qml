import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// The dialog behind the control centre tools grid's "+ Add tool" tile and every tool's pencil, to edit a tool or add other apps or commands. Fill the window with it; openAdd() and openEdit(name) show it, Save stages the result through
// Settings (customTools, toolOverrides), so nothing is written before Apply, like every other change.
//
// A tool of the user's own has a label, an icon and an action: App (a desktop entry, picked from the installed applications with
// their icons), Command (a shell command, optionally run in the terminal) or Link (opened with the desktop's opener). A built-in tool keeps
// its action: only its label and icon can change, and Save stores them as an override that the tile's revert arrow takes back.
// The icon is picked by name from the Material Design set of the shell's icon font (data/icons.json, made by scripts/gen_icons.py).
// Same look as the other dialogs (ConfirmDialog): the dimmed window, a Section-card surface, the Apply bar's button styles.
Item {
    id: dlg
    // the window's Tooltip
    property var tooltip: null

    visible: false
    z: 30

    // ---- what is being edited ----
    property string toolId: ""
    // a built-in tool: label and icon only
    property bool builtin: false
    property bool adding: true
    property string label: ""
    property int icon: 0xF04CE
    property string kind: "app"
    // what each kind keeps apart, so switching the kind back and forth loses nothing; `value` is the one of the kind shown
    property string appId: ""
    property string textValue: ""
    readonly property string value: dlg.kind === "app" ? dlg.appId : dlg.textValue
    property bool terminal: false
    // the built-in's own label and icon, for the hint and the reset links
    readonly property string ownLabel: dlg.builtin ? (Settings.toolLabels[dlg.toolId] ?? dlg.toolId) : ""
    readonly property int ownIcon: dlg.builtin ? (Settings.toolIcons[dlg.toolId] ?? 0) : 0
    // the icon page instead of the form
    property bool picking: false
    property string iconQuery: ""
    property string appQuery: ""

    readonly property bool canSave: dlg.label.trim() !== "" && (dlg.builtin || dlg.value.trim() !== "")
    // why Save is not possible, for a hint under the buttons
    readonly property string saveHint: dlg.label.trim() === "" ? "Give the tool a label." : !dlg.builtin && dlg.value.trim() === "" ? (dlg.kind === "app" ? "Pick an application." : dlg.kind === "command" ? "Type the command to run." : "Type the address to open.") : ""

    function openAdd() {
        dlg.toolId = Settings.newToolId();
        dlg.builtin = false;
        dlg.adding = true;
        dlg.label = "";
        dlg.icon = 0xF04CE;
        dlg.kind = "app";
        dlg.appId = "";
        dlg.textValue = "";
        dlg.terminal = false;
        dlg.begin();
    }

    function openEdit(name) {
        const c = Settings.customTool(name, true);
        dlg.toolId = name;
        dlg.adding = false;
        dlg.builtin = c === null;
        dlg.label = Settings.toolLabel(name, true);
        dlg.icon = Settings.toolIcon(name, true);
        dlg.kind = c ? c.kind : "app";
        dlg.appId = c && c.kind === "app" ? String(c.value) : "";
        dlg.textValue = c && c.kind !== "app" ? String(c.value) : "";
        dlg.terminal = c ? c.terminal === true : false;
        dlg.begin();
    }

    function begin() {
        dlg.picking = false;
        dlg.iconQuery = "";
        dlg.appQuery = "";
        labelBox.text = dlg.label;
        iconBox.text = "";
        appBox.text = "";
        valueBox.text = dlg.textValue;
        dlg.visible = true;
        labelBox.input.forceActiveFocus();
    }

    function close() {
        dlg.visible = false;
    }

    function save() {
        if (!dlg.canSave)
            return false;
        if (dlg.builtin)
            Settings.stageToolOverride(dlg.toolId, dlg.label, dlg.icon);
        else
            Settings.stageCustomTool({ id: dlg.toolId, label: dlg.label.trim(), icon: dlg.icon, kind: dlg.kind, value: dlg.value.trim(), terminal: dlg.kind === "command" && dlg.terminal });
        dlg.close();
        return true;
    }

    // back to the tool's own label and icon (a built-in)
    function useOwn() {
        dlg.label = dlg.ownLabel;
        labelBox.text = dlg.ownLabel;
        dlg.icon = dlg.ownIcon;
    }

    function pickKind(k) {
        dlg.kind = k;
    }

    // ---- the icon names (data/icons.json: [[codepoint, "name"], ...]) ----
    property var icons: []
    property bool iconsWanted: false
    FileView {
        path: dlg.iconsWanted ? Quickshell.shellPath("data/icons.json") : ""
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                dlg.icons = JSON.parse(text());
            } catch (e) {
                console.warn("tool editor: data/icons.json is not readable", e);
            }
        }
    }
    onPickingChanged: if (dlg.picking)
        dlg.iconsWanted = true

    readonly property var iconWords: Settings.norm(dlg.iconQuery).split(" ").filter(w => w !== "")
    readonly property var iconHits: dlg.icons.filter(e => dlg.iconWords.every(w => e[1].includes(w)))
    readonly property int iconMax: 420
    function iconName(cp) {
        const e = dlg.icons.find(x => x[0] === cp);
        return e ? e[1].replace(/_/g, " ") : "";
    }

    // ---- the applications ----
    readonly property var appWords: Settings.norm(dlg.appQuery).split(" ").filter(w => w !== "")
    readonly property var apps: {
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay)
                continue;
            out.push(e);
        }
        out.sort((a, b) => a.name.localeCompare(b.name));
        return out;
    }
    readonly property var appHits: dlg.apps.filter(e => {
        const t = Settings.norm(e.name + " " + e.id + " " + (e.genericName ?? "") + " " + (e.keywords ?? []).join(" "));
        return dlg.appWords.every(w => t.includes(w));
    })
    readonly property var chosenApp: dlg.kind === "app" && dlg.value !== "" ? DesktopEntries.byId(dlg.value) : null

    // dims the window and closes on a click outside the card
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.surface, 0.7)

        MouseArea {
            anchors.fill: parent
            onClicked: dlg.close()
        }
    }

    Rectangle {
        id: card
        objectName: "toolCard"
        anchors.centerIn: parent
        width: Math.min(560, dlg.width - 40)
        height: Math.min(dlg.height - 40, content.implicitHeight + 36)
        radius: Theme.radiusLg
        color: Theme.container

        // a click inside the card must not close it
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: content
            x: 18
            y: 18
            width: parent.width - 36
            spacing: 10

            // ---- title ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    objectName: "toolTitle"
                    Layout.fillWidth: true
                    text: dlg.picking ? "Choose an icon" : dlg.adding ? "Add a tool" : dlg.builtin ? "Change " + dlg.ownLabel : "Edit " + dlg.label
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                    font.weight: Font.Medium
                    color: Theme.fg
                }
            }

            // ---- the icon page ----
            ColumnLayout {
                visible: dlg.picking
                Layout.fillWidth: true
                spacing: 8

                TextBox {
                    id: iconBox
                    objectName: "toolIconSearch"
                    placeholder: "Search icons by name, e.g. camera, music, web"
                    onEdited: dlg.iconQuery = text
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 252

                    GridView {
                        id: iconGrid
                        objectName: "toolIconGrid"
                        anchors.fill: parent
                        clip: true
                        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 44)))
                        cellHeight: 44
                        boundsBehavior: Flickable.StopAtBounds
                        model: dlg.iconHits.length > dlg.iconMax ? dlg.iconHits.slice(0, dlg.iconMax) : dlg.iconHits
                        onMovingChanged: if (moving && dlg.tooltip)
                            dlg.tooltip.dismiss()

                        delegate: Item {
                            id: cell
                            required property var modelData
                            width: iconGrid.cellWidth
                            height: iconGrid.cellHeight
                            readonly property bool on: modelData[0] === dlg.icon

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - 4
                                height: parent.height - 4
                                radius: Theme.radiusSm
                                color: cell.on ? Qt.alpha(Theme.primary, 0.28) : cellMouse.containsMouse ? Theme.hoverBg : "transparent"
                            }

                            Glyph {
                                anchors.centerIn: parent
                                cp: cell.modelData[0]
                                font.pixelSize: Theme.iconSize + 6
                                color: Theme.fg
                            }

                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    dlg.icon = cell.modelData[0];
                                    dlg.picking = false;
                                    if (dlg.tooltip)
                                        dlg.tooltip.dismiss();
                                }
                                onContainsMouseChanged: {
                                    if (!dlg.tooltip)
                                        return;
                                    if (containsMouse)
                                        dlg.tooltip.show(cell, cell.modelData[1].replace(/_/g, " "), false);
                                    else
                                        dlg.tooltip.hide(cell);
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: dlg.icons.length > 0 && dlg.iconHits.length === 0
                        text: "No icon matches"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        color: Theme.fgMuted
                    }
                }

                SmallText {
                    objectName: "toolIconCount"
                    text: dlg.icons.length === 0 ? "Loading the icon names..." : dlg.iconHits.length > dlg.iconMax ? "Showing the first " + dlg.iconMax + " of " + dlg.iconHits.length + " icons: type to narrow them down." : dlg.iconHits.length + " icons"
                }

                RowLayout {
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    }

                    BarButton {
                        objectName: "toolIconBack"
                        text: "Back"
                        glued: false
                        hpad: 14
                        bg: Qt.alpha(Theme.fg, 0.09)
                        onClicked: dlg.picking = false
                    }
                }
            }

            // ---- the form ----
            ColumnLayout {
                visible: !dlg.picking
                Layout.fillWidth: true
                spacing: 10

                // label and icon on one line
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    BarButton {
                        id: iconBtn
                        objectName: "toolIconBtn"
                        glyph: dlg.icon
                        glyphSize: Theme.iconSize + 6
                        glued: false
                        hpad: 10
                        bg: Theme.tileBg
                        onClicked: dlg.picking = true
                        onHoveredChanged: {
                            if (!dlg.tooltip)
                                return;
                            if (hovered)
                                dlg.tooltip.show(iconBtn, "Choose the icon" + (dlg.iconName(dlg.icon) !== "" ? " (now: " + dlg.iconName(dlg.icon) + ")" : ""), false);
                            else
                                dlg.tooltip.hide(iconBtn);
                        }
                    }

                    TextBox {
                        id: labelBox
                        objectName: "toolLabel"
                        placeholder: "Label, e.g. Terminal"
                        onEdited: dlg.label = text
                        onAccepted: dlg.save()
                    }

                    // a built-in tool: back to its own label and icon
                    BarButton {
                        objectName: "toolUseOwn"
                        visible: dlg.builtin && (dlg.label !== dlg.ownLabel || dlg.icon !== dlg.ownIcon)
                        glyph: 0xF054C
                        glued: false
                        hpad: 4
                        fg: Theme.fgMuted
                        hoverFg: Theme.fg
                        onClicked: dlg.useOwn()
                    }
                }

                SmallText {
                    visible: dlg.builtin
                    text: "You can change this tool's name and icon. What it does stays the same."
                }

                // what the tool does
                ColumnLayout {
                    visible: !dlg.builtin
                    Layout.fillWidth: true
                    spacing: 8

                    Segmented {
                        objectName: "toolKind"
                        value: dlg.kind
                        options: [{ value: "app", label: "App" }, { value: "command", label: "Command" }, { value: "link", label: "Link" }]
                        onPicked: v => dlg.pickKind(v)
                    }

                    // App: the installed applications, with their icons
                    ColumnLayout {
                        visible: dlg.kind === "app"
                        Layout.fillWidth: true
                        spacing: 6

                        TextBox {
                            id: appBox
                            objectName: "toolAppSearch"
                            placeholder: "Search applications"
                            onEdited: dlg.appQuery = text
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 168

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radiusSm
                                color: Theme.tileBg
                            }

                            ListView {
                                id: appList
                                objectName: "toolAppList"
                                anchors.fill: parent
                                anchors.margins: 4
                                clip: true
                                spacing: 2
                                boundsBehavior: Flickable.StopAtBounds
                                model: dlg.appHits
                                onMovingChanged: if (moving && dlg.tooltip)
                                    dlg.tooltip.dismiss()

                                delegate: Item {
                                    id: appRow
                                    required property var modelData
                                    readonly property bool on: modelData.id === dlg.value
                                    width: appList.width
                                    height: 30

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.radiusSm
                                        color: appRow.on ? Qt.alpha(Theme.primary, 0.22) : appMouse.containsMouse ? Theme.hoverBg : "transparent"
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        // an icon the theme does not have must not draw Qt's magenta checkerboard: a glyph instead
                                        Item {
                                            implicitWidth: 20
                                            implicitHeight: 20

                                            IconImage {
                                                id: appIcon
                                                anchors.fill: parent
                                                visible: source !== ""
                                                implicitSize: 20
                                                source: Quickshell.iconPath(appRow.modelData.icon, true) || Quickshell.iconPath("application-x-executable", true)
                                            }

                                            Glyph {
                                                anchors.centerIn: parent
                                                visible: !appIcon.visible
                                                cp: 0xF08C6
                                                color: Theme.fgMuted
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: appRow.modelData.name
                                            textFormat: Text.PlainText
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize
                                            color: Theme.fg
                                        }

                                        Text {
                                            text: appRow.modelData.id
                                            textFormat: Text.PlainText
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: 180
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize - 3
                                            color: Theme.fgMuted
                                        }
                                    }

                                    MouseArea {
                                        id: appMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            dlg.appId = appRow.modelData.id;
                                            // an empty label takes the application's name
                                            if (dlg.label.trim() === "") {
                                                dlg.label = appRow.modelData.name;
                                                labelBox.text = dlg.label;
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: dlg.appHits.length === 0
                                text: "No application matches"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                                color: Theme.fgMuted
                            }
                        }

                        SmallText {
                            objectName: "toolAppChosen"
                            text: dlg.value === "" ? "No application chosen." : dlg.chosenApp ? "Runs " + dlg.chosenApp.name + "." : "This application is not installed, so the tool will be greyed out."
                            color: dlg.value !== "" && !dlg.chosenApp ? Theme.urgentFg : Theme.fgMuted
                        }
                    }

                    // Command / Link: one text field
                    ColumnLayout {
                        visible: dlg.kind !== "app"
                        Layout.fillWidth: true
                        spacing: 6

                        TextBox {
                            id: valueBox
                            objectName: "toolValue"
                            placeholder: dlg.kind === "command" ? "Command, e.g. btop" : "Address, e.g. https://example.org"
                            onEdited: dlg.textValue = text
                            onAccepted: dlg.save()
                        }

                        RowLayout {
                            visible: dlg.kind === "command"
                            Layout.fillWidth: true
                            spacing: 8

                            Toggle {
                                objectName: "toolTerminal"
                                checked: dlg.terminal
                                onClicked: dlg.terminal = !dlg.terminal
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Run in terminal"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                                color: Theme.fg
                            }
                        }

                        SmallText {
                            text: dlg.kind === "command" ? "The tool is greyed out if the program is not installed. \u201cRun in terminal\u201d opens it in a terminal window." : "Opens the address in your default browser."
                        }
                    }
                }

                // buttons
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 8

                    SmallText {
                        objectName: "toolSaveHint"
                        Layout.fillWidth: true
                        visible: !dlg.canSave
                        text: dlg.saveHint
                    }

                    Item {
                        Layout.fillWidth: true
                        visible: dlg.canSave
                    }

                    BarButton {
                        objectName: "toolCancel"
                        text: "Cancel"
                        glued: false
                        hpad: 14
                        onClicked: dlg.close()
                    }

                    BarButton {
                        objectName: "toolSave"
                        text: dlg.adding ? "Add" : "Save"
                        glued: false
                        hpad: 18
                        bg: Theme.accent
                        fg: Theme.accentFg
                        enabled: dlg.canSave
                        opacity: enabled ? 1 : 0.4
                        onClicked: dlg.save()
                    }
                }
            }
        }
    }
}
