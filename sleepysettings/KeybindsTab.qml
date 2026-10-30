import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// Settings tab: the binds added here (the sleepybinds file, removable) with a form to add one (key combination plus
// a command), and every bind of every file Hyprland loads (read-only, searchable; HyprConfig runs scripts/hyprconf.py, which follows
// hyprland.lua's require lines). A bind shows its file on hover and "Open" jumps to it. Added and removed binds
// are a draft in Keybinds.qml until Apply. The "Share keybinds" card exports them to a file and imports a file as a preview (KeybindShare.qml). The list refreshes when the tab opens, when a file changes and when Hyprland reloads.
TabPage {
    id: tab
    key: "keybinds"
    label: "Keybinds"
    icon: 0xF097B
    dirty: Keybinds.dirty
    busy: Keybinds.busy
    note: "Apply writes the custom keybinds file; the other files are edited by hand"
    files: [Settings.tilde(Keybinds.customPath)]
    // the sidebar search also filters the list, and counts the binds it finds
    hits: tab.query === "" ? 0 : tab.matching(tab.query).length + tab.countHits(tab)
    onApplying: Keybinds.apply()
    onDiscarding: Keybinds.discard()

    property string error: ""

    function matching(q) {
        return Keybinds.all.filter(b => Settings.searchMatch(Settings.norm(b.combo + " " + b.action + " " + b.note), q));
    }

    // the binds this tab added (sleepybinds.lua), and the read-only ones of binds.lua; the sidebar search filters both
    function matchingIn(list, q) {
        return list.filter(b => Settings.searchMatch(Settings.norm(b.combo + " " + b.action + " " + b.note), q));
    }
    readonly property var yours: tab.query === "" ? Keybinds.custom : tab.matchingIn(Keybinds.custom, tab.query)
    // the groups the user folded (name -> true); a search unfolds them, so a hit is never hidden
    property var folded: ({})
    function toggleGroup(g) {
        const f = Object.assign({}, tab.folded);
        f[g] = !f[g];
        tab.folded = f;
    }
    // the built-in binds as a list with a header line before each group's binds (the sidebar search or the tab's own box filters them)
    readonly property string builtInQuery: Settings.norm(search.text) || tab.query
    readonly property var builtInMatches: tab.builtInQuery === "" ? Keybinds.binds : tab.matchingIn(Keybinds.binds, tab.builtInQuery)
    readonly property var builtIn: {
        const out = [];
        for (const g of Keybinds.groupNames) {
            const items = tab.builtInMatches.filter(b => b.group === g);
            if (items.length === 0)
                continue;
            const open = tab.builtInQuery !== "" || tab.folded[g] !== true;
            out.push({ header: true, group: g, count: items.length, open: open });
            if (open)
                for (const b of items)
                    out.push(b);
        }
        return out;
    }

    // what you add first, the built-in list after it, the
    // rare rows in Advanced
    // the page scrolls and the lists show every row (no inner scroll area cut to a few rows)
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
            onMovingChanged: if (moving && tab.tooltip) tab.tooltip.dismiss()

            ColumnLayout {
                id: col
                width: flick.width - (flick.contentHeight > flick.height ? 10 : 0)
                spacing: 8

                Section {
                    title: "Your keybinds"
                    // greyed out with a notice while Hyprland does not load the file, or it is missing or read-only (FileChecks)
                    fileIds: ["custombinds"]
                    // one short line and a link, not the whole notice: the fix (Set up, the keybind files, the location) is in the Config tab
                    briefNotice: true

                    // one card row: the add form, its hint and its error line (the card draws a hairline between rows)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        // the add form: the combination, the command, the button and a "?" tip with the details
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            KeyCapture {
                                id: capture
                                onComboChanged: tab.error = combo !== "" && Keybinds.conflict(combo) ? combo + " is already bound: " + Keybinds.conflict(combo).action : ""
                            }

                            TextBox {
                                id: command
                                placeholder: "Command, e.g. kitty -e btop"
                                onAccepted: addBtn.clicked(Qt.LeftButton)
                            }

                            BarButton {
                                id: addBtn
                                text: "Add keybind"
                                glued: false
                                bg: Theme.hoverBg
                                onClicked: {
                                    tab.error = Keybinds.add(capture.combo, command.text);
                                    if (tab.error === "") {
                                        capture.combo = "";
                                        command.text = "";
                                    }
                                }
                            }

                            InfoTip {
                                tooltip: tab.tooltip
                                text: "Added keybinds run a command. They start working a moment after you Apply. The keybinds below are changed in their own files."
                            }
                        }

                        // the hint is muted, an error is urgent: two lines, so they never share a colour
                        SmallText {
                            objectName: "keybindHint"
                            text: "Click the first field, press the keys, then type the command."
                        }

                        SmallText {
                            objectName: "keybindError"
                            // without the discovery (hyprconf.py could not run) the old test stands in for the file notice
                            visible: tab.error !== "" || (!Keybinds.customEnabled && !Keybinds.discovered)
                            color: Theme.urgentFg
                            text: tab.error !== "" ? tab.error : "Hyprland doesn't load this file yet, so keybinds you add here won't work."
                        }
                    }

                    KeybindList {
                        objectName: "yourList"
                        tooltip: tab.tooltip
                        visible: tab.yours.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: contentHeight
                interactive: false
                        model: tab.yours
                    }

                    SmallText {
                        objectName: "emptyHint"
                        visible: Keybinds.custom.length === 0
                        text: "No keybinds added here yet."
                    }
                }

                // export and import of keybinds: nothing is written before Add and Apply
                Section {
                    title: "Share keybinds"

                    KeybindShare {
                        objectName: "share"
                        folders: tab.folders
                        tooltip: tab.tooltip
                    }
                }

                Section {
                    title: "Built-in keybinds"
                    // where the built-in list reads from
                    titleTip: "These come from your Hyprland files. The list updates by itself when you change them."

                    headerItems: TextBox {
                        id: search
                        Layout.fillWidth: false
                        Layout.preferredWidth: 240
                        Layout.topMargin: 4
                        placeholder: tab.query !== "" ? "Showing keybinds matching \"" + tab.query + "\"" : "Search keybinds"
                    }

                    SmallText {
                        objectName: "discoverNote"
                        visible: !Keybinds.discovered || Keybinds.unreadableCount > 0
                        color: Keybinds.discovered ? Theme.fgMuted : Theme.urgentFg
                        text: !Keybinds.discovered ? "Your Hyprland files could not be read, so only the main keybinds file is shown." : Keybinds.unreadableCount + (Keybinds.unreadableCount === 1 ? " keybind" : " keybinds") + " in your files use special code and can't be shown here."
                    }

                    KeybindList {
                        objectName: "builtinList"
                        tooltip: tab.tooltip
                        Layout.fillWidth: true
                        Layout.preferredHeight: contentHeight
                interactive: false
                        model: tab.builtIn
                        onGroupToggled: g => tab.toggleGroup(g)
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
