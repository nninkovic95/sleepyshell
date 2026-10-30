import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// Settings window: a normal toplevel window (not a bar layer surface), so Hyprland's window rules
// decide where it goes; the rule in windowrules.lua floats and centres it by class and title.
// It runs as its own Quickshell instance (sleepysettings.qml in the bar's folder,
// `qs -p ~/.config/quickshell/sleepyshell/sleepysettings.qml`), launched by the bar from the control centre's
// "Settings" entry or `qs -c sleepyshell ipc call sleepybar toggle settings`, and from the launcher through
// ~/.local/share/applications/sleepyshell-settings.desktop. BarLink carries the staged values, the
// commits and the bar's close request over a socket; the bar previews the draft while the
// window is up.
// Tabs in a sidebar on the left, one file each in this folder, each a TabPage that carries its
// own sidebar entry and Apply state; their settings sit on Section cards. Every tab edits a
// draft; the one Apply bar under the pages acts on the open tab and is only there while
// something is pending. Bar, Left island, Centre island, Right
// island, Notifications, Idle and Power stage Settings keys (Settings.groups; one tab per island); while the window is open the
// bar previews them at once, Apply has the bar write sleepysettings.toml, and closing the window puts
// the bar back to the stored values; a draft lives as long as the window (sleepysettings.qml ends the
// process once it is closed and no tab is at work). Theme runs matugen through scripts/theme.py,
// Idle rewrites hypridle.conf through scripts/idle.py,
// Display writes monitors.lua with a keep-or-revert countdown (Displays.qml), Keybinds
// lists binds.lua and manages sleepybinds.lua (Keybinds.qml), System shows the machine's
// hardware and versions read-only (scripts/sysinfo.py, no draft), and ends in the Reset section
// (a tab's keys, or every tab's, back to their defaults, staged like any change). A tab that cannot
// work here (Power without a battery or a backlight; a tab whose `requires` programs are missing,
// services/Deps.qml) is hidden from the sidebar unless "Show unavailable tabs" (a row of the Config tab, key showUnavailableTabs) is on,
// when it is listed greyed; the search still
// finds its rows and offers to show it. The bar can ask for a tab by name (SettingsServer.openTab). Leaving a tab or closing the window
// with unapplied changes asks first (ConfirmDialog), and the sidebar marks such a tab with a red
// "!". The search field over the sidebar (SearchBox) counts matching settings per tab, dims the
// rest and says "No matches" when no tab has any.
// Keys: Escape closes (dialog, picker, a search, then the window), Ctrl+S applies, Ctrl+Tab and
// Ctrl+Shift+Tab (or Ctrl+PgDown / PgUp) change tab, Ctrl+F searches; in the search field Escape
// clears it, Down or Enter open the first tab with matches.
// The controls are separate files: inline components added here failed to load
// ("X is not a type") under Quickshell 0.3.2.
FloatingWindow {
    id: root
    property bool open: false
    property string tab: "bar"
    // sidebar order
    readonly property var pages: [barTab, leftTab, centreTab, widgetsTab, appsTab, notificationsTab, themeTab, idleTab, powerTab, displayTab, keybindsTab, filesTab, systemTab]
    readonly property int tabIndex: Math.max(0, pages.findIndex(p => p.key === tab))
    readonly property var current: pages[tabIndex]
    // does the sidebar list this tab: always when it works here, the open one always, the rest only
    // with "Show unavailable tabs"
    function listed(p) {
        return !p.unavailable || Settings.showUnavailableTabs || p === root.current;
    }
    readonly property var listedPages: pages.filter(p => root.listed(p))
    // tabs the search finds something on but the sidebar hides
    readonly property var hiddenFound: root.query === "" ? [] : pages.filter(p => !root.listed(p) && p.hits > 0)
    // the sidebar search, as the pages match it
    readonly property string query: Settings.norm(searchBox.text)
    // a tab the search leaves undimmed: matching rows, or its own name
    function pageFound(p) {
        return root.query === "" || p.hits > 0 || Settings.searchMatch(Settings.norm(p.label + " " + p.tags), root.query);
    }
    // the search finds nothing on any tab
    readonly property bool noMatches: root.query !== "" && !root.pages.some(p => root.pageFound(p))

    // Down or Enter in the search field: open the first tab the search finds, and hand the keys
    // back to the window (a second Escape then clears the search, a third closes)
    function jumpToFound() {
        const p = root.listedPages.find(x => root.pageFound(x));
        if (p && p !== root.current)
            root.leave(() => root.tab = p.key);
        keys.forceActiveFocus();
    }

    // While a query is typed the sidebar lists only the tabs it finds. If the open tab is not one
    // of them the window goes to the first that is, remembering where it came from; clearing the query puts the tab
    // back, unless the user chose another meanwhile. A tab with unapplied changes is never left on its own (that
    // would pop the leave dialog while typing).
    property string autoFrom: ""
    property string autoTo: ""
    // the tabs Ctrl+Tab cycles: the listed ones, and only the found ones while searching
    readonly property var navPages: root.listedPages.filter(p => root.query === "" || root.pageFound(p))
    function followSearch() {
        if (root.query === "" || root.noMatches || root.pageFound(root.current) || root.current.dirty || root.current.pending)
            return;
        const p = root.navPages[0];
        if (!p)
            return;
        if (root.autoFrom === "")
            root.autoFrom = root.tab;
        root.autoTo = p.key;
        root.tab = p.key;
    }
    onQueryChanged: {
        if (root.query === "") {
            const back = root.autoFrom;
            const mine = root.autoTo === root.tab;
            root.autoFrom = "";
            root.autoTo = "";
            if (back !== "" && mine)
                root.leave(() => root.tab = back);
        } else {
            Qt.callLater(root.followSearch);
        }
    }
    // the sidebar entry of the open tab, under the sliding highlight; it slides only once a tab
    // has been changed, not into place on the first opening
    property Item currentEntry: null
    property bool slidePill: false
    onTabChanged: {
        slidePill = true;
        tooltip.dismiss();
        // the Keybinds tab lists what the config holds now: ask again whenever it opens; the file checks follow
        if (tab === "keybinds" || tab === "files") {
            HyprConfig.refresh();
            FileChecks.refresh();
        }
    }

    // "Set up" (FileNotice / FileActions) on a file Hyprland does not load: ask first, with the exact line; hyprconf.py add-require writes it
    // and keeps a backup of hyprland.lua
    Connections {
        target: FileChecks
        function onSetupRequested(p) {
            confirm.askLine("Add this line to " + (HyprConfig.format === "conf" ? "hyprland.conf" : "hyprland.lua") + "?", "A backup is kept (" + (HyprConfig.format === "conf" ? "hyprland.conf" : "hyprland.lua") + ".bak-<date-time>).", p.requireLine, () => FileChecks.setUp(p.id), "Add line");
        }
    }

    // "Configure in Config" (FileNotice / FileActions): the Config tab, the file's row lit up (Advanced opened if the row is in it)
    Connections {
        target: FileChecks
        function onConfigureRequested(id) {
            root.leave(() => {
                root.tab = "files";
                filesTab.reveal(id);
            });
        }
    }
    readonly property int pad: 18
    readonly property int sideW: 170
    readonly property int pageW: 560

    // run `next` now, or after asking when the open tab has unapplied changes (every tab's
    // changes wait for its Apply). While a keep-or-revert countdown runs
    // (Display, review 3, F5) it asks Keep or Revert, since the change would otherwise revert
    // unseen; Apply from the dialog on such a tab stays there, where the countdown shows.
    function leave(next) {
        picker.hide();
        const p = current;
        if (p.pending) {
            confirm.ask(p.label + " change not kept", "The new settings revert by themselves unless they are kept.", () => {
                p.keep();
                next();
            }, () => {
                p.revert();
                next();
            }, null, "Keep", "Revert");
        } else if (p.dirty) {
            confirm.ask(p.label + " changes not applied", "You changed settings on this tab but have not applied them.", p.applyStays ? () => p.apply() : () => {
                p.apply();
                next();
            }, () => {
                p.discard();
                next();
            }, null, null, null, null, { count: p.changes, files: p.files });
        } else {
            next();
        }
    }

    // the tab `delta` places along the sidebar (the listed ones), through leave()
    function step(delta) {
        const l = root.navPages.length > 0 ? root.navPages : root.listedPages;
        const i = Math.max(0, l.indexOf(root.current));
        const k = l[(i + delta + l.length) % l.length].key;
        leave(() => root.tab = k);
    }

    function applyCurrent() {
        if (current.dirty && !current.busy && !current.pending)
            current.apply();
    }

    // the app is called Sleepysettings; the Hyprland float rule matches this title
    title: "Sleepysettings"
    visible: open
    color: Theme.surface
    // fixed width: a long text in a page (a monitor's maker name) would otherwise widen the
    // layout's implicit width past the content
    // opens wider than its smallest size; resizable either way, the page and the long lists
    // (keybinds, display) take the extra room
    readonly property int openPageW: 820
    implicitWidth: sideW + openPageW + pad * 3
    // the Apply bar comes and goes; the window keeps the height it has with
    // the bar up, and the pages take the room while it is away
    readonly property real fullPageH: page.implicitHeight + applyBar.collapsed
    implicitHeight: fullPageH + pad * 2
    minimumSize: Qt.size(sideW + pageW + pad * 3, fullPageH + pad * 2)

    // the bar previews the staged settings only while this window is visible
    Binding {
        target: Settings
        property: "previewing"
        value: root.visible
    }

    // the socket to the bar (services/SettingsServer.qml)
    BarLink {
        window: root
    }

    // closed by the compositor (kill-active bind, window close): keep `open` in step. Closing
    // ends the live preview (the bar goes back to the stored values); in sleepysettings.qml it also
    // ends the process, so a draft lives as long as the window (the sandbox only hides it).
    onVisibleChanged: {
        if (!visible && open)
            open = false;
        if (!visible) {
            tooltip.dismiss();
            confirm.visible = false;
            toolDialog.close();
            folders.close();
            picker.hide();
        }
        if (visible) {
            Displays.refresh();
            Keybinds.refresh();
            HyprConfig.refresh();
            FileChecks.refresh();
            keys.forceActiveFocus();
        }
    }

    // Window shortcuts, not Keys handlers on a focused item: once a text field or the key
    // capture had taken focus and dropped it again, nothing was focused and a Keys handler never
    // fired (review 3, F13). A focused field claims Escape first through shortcutOverride, so its
    // first Escape only leaves the field. The others do nothing while a dialog or overlay is up.
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        readonly property bool free: !confirm.visible && !folders.visible && !picker.target && !toolDialog.visible

        Shortcut {
            sequence: "Escape"
            onActivated: {
                tooltip.dismiss();
                if (confirm.visible)
                    confirm.visible = false;
                else if (toolDialog.visible && toolDialog.picking)
                    toolDialog.picking = false;
                else if (toolDialog.visible)
                    toolDialog.close();
                else if (folders.visible)
                    folders.cancelOrClose();
                else if (picker.target)
                    picker.hide();
                else if (searchBox.text !== "")
                    searchBox.clear();
                else
                    root.leave(() => root.open = false);
            }
        }

        Shortcut {
            sequence: "Ctrl+S"
            enabled: keys.free
            onActivated: root.applyCurrent()
        }

        Shortcut {
            sequences: ["Ctrl+Tab", "Ctrl+PgDown"]
            enabled: keys.free
            onActivated: root.step(1)
        }

        // Qt reports Ctrl+Shift+Tab as Backtab on some setups; when both sequences match one press
        // it signals activatedAmbiguously instead, so either way the press steps once
        Shortcut {
            sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab", "Ctrl+PgUp"]
            enabled: keys.free
            onActivated: root.step(-1)
            onActivatedAmbiguously: root.step(-1)
        }

        Shortcut {
            sequence: "Ctrl+F"
            enabled: keys.free
            onActivated: searchBox.focusAll()
        }
    }

    // A click anywhere in the window that is not in a text field ends the editing:
    // the field loses focus, which commits what
    // was typed (the same check as Enter) and hides the caret. One handler for the whole window, not
    // one per field. The handler is passive: it ends the editing and lets the press go on to the control
    // under the pointer, which still gets its click. A click in a field (another one, or the same one
    // to move the caret) leaves the focus where the click puts it.
    function tappedAt(x, y) {
        const f = keys.Window.activeFocusItem;
        if (f && f !== keys && f.cursorPosition !== undefined) {
            // the field's own box (its parent: the TextBox rectangle) counts as inside
            const box = f.parent ?? f;
            const p = box.mapFromItem(null, x, y);
            if (box.contains(p) || f.contains(f.mapFromItem(null, x, y)))
                return;
        }
        if (f && f !== keys)
            keys.forceActiveFocus();
    }

    // On top of everything, so it sees every press first, and ignores it (accepted = false) so the press
    // goes on to the item below. A TapHandler on the window did not see presses that a control's MouseArea
    // took (a click on a Segmented left the caret in the field). Presses only: no wheel
    // handler, no hover, so scrolling and hover lifts are not affected.
    MouseArea {
        id: outsideTap
        anchors.fill: parent
        z: 1000
        onPressed: mouse => {
            const p = outsideTap.mapToItem(null, mouse.x, mouse.y);
            root.tappedAt(p.x, p.y);
            mouse.accepted = false;
        }
    }

    // ---- sidebar ----------------------------------------------------------------------------

    Rectangle {
        id: side
        x: 0
        y: 0
        width: root.sideW + root.pad
        height: parent.height
        color: Theme.container

        // the open tab's highlight, sliding between entries
        Rectangle {
            visible: root.currentEntry !== null
            x: entries.x
            y: root.currentEntry ? entries.y + root.currentEntry.y : 0
            width: entries.width
            height: root.currentEntry ? root.currentEntry.height : 0
            radius: Theme.radiusMd
            color: Theme.accent
            Behavior on y {
                enabled: root.slidePill
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
        }

        ColumnLayout {
            id: entries
            x: root.pad / 2
            y: root.pad
            width: side.width - root.pad
            spacing: 4

            Text {
                Layout.leftMargin: 10
                Layout.bottomMargin: 8
                id: appName
                objectName: "appName"
                text: "Sleepysettings"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 2
                font.weight: Font.Medium
                color: Theme.fg

                // how to close it, now that the title row has no ×
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered)
                            tooltip.show(appName, "<b>Esc</b> closes this window (when no field is being edited). It asks first if something is not applied.", false);
                        else
                            tooltip.hide(appName);
                    }
                }
            }

            // search: every tab counts its matching settings, the open one dims the rest
            SearchBox {
                id: searchBox
                Layout.bottomMargin: 8
                noMatch: root.noMatches
                onJump: root.jumpToFound()
            }

            Repeater {
                model: root.pages

                Item {
                    id: tabBtn
                    required property var modelData
                    readonly property bool on: root.current === modelData
                    // while searching: matching rows, or the tab's own name
                    readonly property bool found: root.pageFound(modelData)
                    // listed, and found while a query is typed; the row folds out and in
                    readonly property bool shown: root.listed(modelData) && (root.query === "" || found)
                    // out of the layout once folded away; the model stays the one list so the delegates
                    // (and the sliding highlight that follows one) are never rebuilt
                    visible: implicitHeight > 0.5
                    clip: true
                    Layout.fillWidth: true
                    implicitHeight: shown ? 36 : 0
                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                    property real radius: Theme.radiusMd
                    // above its neighbours while lifted, so the shadow is not covered
                    z: surface.z
                    // dimmed while the search skips it, and for a tab that cannot work here (Power on a desktop, programs missing)
                    opacity: (found ? 1 : 0.4) * (modelData.unavailable ? 0.5 : 1) * (shown ? 1 : 0)
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 140
                        }
                    }
                    onOnChanged: if (on) root.currentEntry = tabBtn
                    Component.onCompleted: if (on) root.currentEntry = tabBtn

                    // only the background lifts; the glyph and label stay at scale 1 and sharp
                    // The holder keeps the lifted surface (z 1) from covering them.
                    Item {
                        anchors.fill: parent

                        Rectangle {
                            id: surface
                            anchors.fill: parent
                            radius: tabBtn.radius
                            color: !tabBtn.on && tabMouse.containsMouse ? Theme.hoverBg : "transparent"

                            Lift {
                                radius: tabBtn.radius
                                level: tabMouse.containsMouse ? 1 : 0
                            }
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Glyph {
                            id: tabGlyph
                            anchors.verticalCenter: parent.verticalCenter
                            cp: tabBtn.modelData.icon
                            color: tabBtn.on ? Theme.accentFg : Theme.fg
                        }

                        // a label too long for the entry is cut with an ellipsis before the marks at the right (never touches the edge)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, Math.min(implicitWidth, tabBtn.width - 20 - tabGlyph.width - 8 - (tabMarks.width > 0 ? tabMarks.width + 6 : 0)))
                            elide: Text.ElideRight
                            text: tabBtn.modelData.label
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            font.weight: tabBtn.on ? Font.Medium : Font.Normal
                            color: tabBtn.on ? Theme.accentFg : Theme.fg
                        }
                    }

                    Row {
                        id: tabMarks
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        // matches while searching
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.query !== "" && tabBtn.modelData.hits > 0
                            text: tabBtn.modelData.hits
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                            color: tabBtn.on ? Theme.accentFg : Theme.primary
                        }

                        // unapplied changes on this tab (not an alarm, so no red "!" that looks
                        // like the teal info tips): a small accent pill with how many; a tab with its own draft
                        // (Display, Keybinds) has no count and shows a dot. On the open tab, whose entry is itself
                        // the accent, it is a light pill so it stays readable.
                        CountPill {
                            objectName: "tabMark"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: tabBtn.modelData.dirty
                            count: tabBtn.modelData.changes
                            on: tabBtn.on
                        }
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const k = tabBtn.modelData.key;
                            if (k !== root.tab)
                                root.leave(() => root.tab = k);
                        }
                    }
                }
            }

            // the search finds rows on tabs the sidebar hides: offer to list them
            ColumnLayout {
                id: hiddenOffer
                objectName: "hiddenOffer"
                visible: root.hiddenFound.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.leftMargin: 10
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Also in " + root.hiddenFound.map(p => p.label + " (" + p.hits + ")").join(", ") + ", which " + (root.hiddenFound.length === 1 ? "is" : "are") + " unavailable here"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                    color: Theme.fgMuted
                }

                BarButton {
                    objectName: "hiddenOfferButton"
                    text: root.hiddenFound.length === 1 ? "Show tab" : "Show tabs"
                    glued: false
                    bg: Theme.tileBg
                    onClicked: Settings.setNow("showUnavailableTabs", true)
                }
            }

            // the search finds nothing on any tab
            RowLayout {
                visible: root.noMatches
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.leftMargin: 10
                spacing: 8

                Glyph {
                    cp: 0xF0349
                    color: Theme.fgMuted
                }

                Text {
                    Layout.fillWidth: true
                    text: "No settings match"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    color: Theme.fgMuted
                }
            }
        }
    }

    // while the window is not linked to the bar (the bar is not running, or its socket is not up yet), a quiet line above the switch says
    // what that means; BarLink retries every 2 s, so it goes by itself once the bar answers
    Text {
        objectName: "linkNote"
        visible: !Settings.linked
        x: root.pad / 2 + 10
        y: openToml.y - height - 6
        width: side.width - root.pad - 20
        wrapMode: Text.WordWrap
        text: "Bar not running: changes show after Apply, no live preview"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
        color: Theme.fgMuted
    }

    // ---- BEGIN toml: sidebar footer ----
    // "Open sleepysettings.toml": the settings file in the chosen editor (Apps tab, DefaultApps.openInEditor). The shell and the
    // window both watch the file, so a hand edit is picked up, and a draft in this window is kept.
    Item {
        id: openToml
        objectName: "openToml"
        readonly property bool ready: Deps.has(DefaultApps.editorProgram)
        // the label (the tests read it): generic, the file's name is in the tip, on two lines where one does not fit the sidebar (the
        // longer label "Open sleepysettings.toml" ran past the sidebar's edge)
        readonly property string label: "Open in text editor"
        x: root.pad / 2
        y: parent.height - height - root.pad
        width: side.width - root.pad
        height: tomlText.implicitHeight + 14
        opacity: ready ? 1 : 0.4
        z: tomlFace.z

        Item {
            anchors.fill: parent

            Rectangle {
                id: tomlFace
                anchors.fill: parent
                radius: Theme.radiusMd
                color: tomlArea.containsMouse && openToml.ready ? Theme.hoverBg : "transparent"

                Lift {
                    radius: tomlFace.radius
                    level: tomlArea.containsMouse && openToml.ready ? 1 : 0
                }
            }
        }

        Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Glyph {
                id: tomlGlyph
                cp: 0xF11E7
                color: Theme.fgMuted
            }

            Text {
                id: tomlText
                anchors.verticalCenter: parent.verticalCenter
                width: openToml.width - 10 - tomlGlyph.width - 8 - 4
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: openToml.label
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                color: Theme.fg
            }
        }

        MouseArea {
            id: tomlArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: openToml.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (openToml.ready) DefaultApps.openInEditor(Settings.path)
            onContainsMouseChanged: {
                if (containsMouse)
                    tooltip.show(openToml, "Opens your settings file in your text editor. Changes you save there show up here and on the bar.<br><font color='" + Theme.fgMuted + "'>" + Settings.tilde(Settings.path) + "</font>", false);
                else
                    tooltip.hide(openToml);
            }
        }
    }
    // ---- END toml ----

    // ---- page -------------------------------------------------------------------------------

    ColumnLayout {
        id: page
        x: side.width + root.pad
        y: root.pad
        width: Math.max(root.pageW, root.width - side.width - root.pad * 2)
        height: Math.max(implicitHeight, root.height - root.pad * 2)
        spacing: 10

        // page title row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Glyph {
                cp: root.current.icon
                color: Theme.primary
            }

            Text {
                Layout.fillWidth: true
                text: root.current.label
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 2
                font.weight: Font.Medium
                color: Theme.fg
            }

            // the result of "Set up", for a few seconds (a failure stays under the notice of its file)
            Text {
                objectName: "setupDone"
                visible: FileChecks.setupNote.text !== "" && FileChecks.setupNote.ok
                text: FileChecks.setupNote.text
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                color: Theme.primary
            }

            // no close button here: Escape closes the window (when no field or dialog has it), the
            // control centre's Settings entry toggles it, and the compositor can close it; each asks first when a tab
            // has unapplied changes (leave())
        }

        // a damaged or read-only settings file: the banner says so; the window works from the defaults and never
        // overwrites the file (Settings.broken)
        FileNotice {
            id: settingsNotice
            ids: ["settings"]
            tooltip: tooltip
        }

        // pages; held at the tallest page's height so the window keeps one size (the stack alone
        // follows the current page, and Hyprland then moved the resized window). A new page fades
        // and slides in.
        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Math.max(...root.pages.map(p => p.implicitHeight))
            currentIndex: root.tabIndex
            transform: Translate {
                id: slide
            }
            onCurrentIndexChanged: enter.restart()

            ParallelAnimation {
                id: enter
                NumberAnimation {
                    target: stack
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 180
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: slide
                    property: "y"
                    from: 8
                    to: 0
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            BarTab {
                id: barTab
                tooltip: tooltip
                query: root.query
            }
            LeftTab {
                id: leftTab
                query: root.query
            }
            CentreTab {
                id: centreTab
                picker: picker
                toolDialog: toolDialog
                tooltip: tooltip
                query: root.query
            }
            WidgetsTab {
                id: widgetsTab
                tooltip: tooltip
                query: root.query
            }
            AppsTab {
                id: appsTab
                picker: picker
                tooltip: tooltip
                // after an Apply, the question whether programs.lua should follow the new default apps
                confirm: confirm
                query: root.query
            }
            NotificationsTab {
                id: notificationsTab
                tooltip: tooltip
                query: root.query
            }
            ThemeTab {
                id: themeTab
                picker: picker
                tooltip: tooltip
                folders: folders
                // "Set up" of the folder icons asks first
                confirm: confirm
                query: root.query
            }
            IdleTab {
                id: idleTab
                tooltip: tooltip
                query: root.query
            }
            PowerTab {
                id: powerTab
                tooltip: tooltip
                query: root.query
            }
            DisplayTab {
                id: displayTab
                picker: picker
                tooltip: tooltip
                query: root.query
            }
            KeybindsTab {
                id: keybindsTab
                tooltip: tooltip
                folders: folders   // Share keybinds: the save and open browser
                query: root.query
            }
            FilesTab {
                id: filesTab
                tooltip: tooltip
                picker: picker
                folders: folders
                confirm: confirm
                query: root.query
                // the tabs Reset can reset: the ones that stage Settings keys (Display and Keybinds keep their own drafts)
                resettable: root.pages.filter(p => p.group !== "")
                onResetDone: key => root.leave(() => root.tab = key)
            }
            SystemTab {
                id: systemTab
                picker: picker
                tooltip: tooltip
                query: root.query
            }
        }

        ApplyBar {
            id: applyBar
            tooltip: tooltip
            gap: page.spacing
            shown: root.pages.some(p => p.dirty || p.busy || p.pending)
            dirty: root.current.dirty
            busy: root.current.busy
            pending: root.current.pending
            idleText: root.current.note !== "" ? "No changes  ·  " + root.current.note : "No changes"
            dirtyText: root.current.dirtyText
            pendingText: root.current.pendingText
            files: root.current.files
            afterNote: root.current.afterNote
            onApply: root.current.apply()
            onDiscard: root.current.discard()
            onKeep: root.current.keep()
            onRevert: root.current.revert()
        }
    }

    Picker {
        id: picker
        anchors.fill: parent
    }

    Tooltip {
        id: tooltip
        anchors.fill: parent
    }

    FolderBrowser {
        id: folders
        anchors.fill: parent
        tip: tooltip
    }

    // adds and edits the control centre's tools (the Centre island tab)
    ToolEditor {
        id: toolDialog
        anchors.fill: parent
        tooltip: tooltip
    }

    // a tip never stays under a dialog, a picker or the folder browser, or after the window was hidden or lost the focus
    Connections {
        target: confirm
        function onVisibleChanged() {
            tooltip.dismiss();
        }
    }
    Connections {
        target: picker
        function onTargetChanged() {
            tooltip.dismiss();
        }
    }
    Connections {
        target: folders
        function onVisibleChanged() {
            tooltip.dismiss();
        }
    }
    Connections {
        target: toolDialog
        function onVisibleChanged() {
            tooltip.dismiss();
        }
    }
    Connections {
        target: root.contentItem.Window.window
        ignoreUnknownSignals: true
        function onActiveChanged() {
            if (!root.contentItem.Window.window.active)
                tooltip.dismiss();
        }
    }

    ConfirmDialog {
        id: confirm
        tooltip: tooltip
        anchors.fill: parent
    }
}
