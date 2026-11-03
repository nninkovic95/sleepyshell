import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services
import qs.sleepysettings.components
import "../services/KeyNames.js" as KeyNames

// The Keybinds window: every Hyprland keybind, read-only, grouped as on the settings window's Keybinds
// tab (Keybinds.groupNames) and searchable. Each bind says what it is for (Keybinds.explain: your own
// description from the Keybinds tab, a plain name, the app it opens, or the comment above it in the config),
// with what it runs in a muted line under it. A cheat sheet to keep beside the work, not an editor: binds are
// added and removed on the Keybinds tab of Sleepysettings.
//
// The list is Keybinds.all: what scripts/hyprconf.py finds in every file Hyprland loads (HyprConfig), with
// each bind's readable action; the binds added in Sleepysettings (sleepybinds.lua) are in it too. Hyprland
// reloading its config does not refresh an open window; reopen it.
//
// Keys: typing goes to the search field (focused on open); Escape clears the search, then closes.
FloatingWindow {
    id: win

    // the float rule in the Hyprland config matches this title (class org.quickshell)
    title: "Keybinds"
    color: Theme.surface
    // room for every bind of a usual config without scrolling (three columns of groups)
    implicitWidth: 1560
    implicitHeight: 940
    minimumSize: Qt.size(560, 400)

    readonly property int pad: 16
    // binds matching the search: every word must be in the keys or the action
    readonly property var shown: {
        const words = search.text.toLowerCase().split(/\s+/).filter(w => w !== "");
        return Keybinds.all.filter(b => {
            // the keys as written and as words, so "mute" and "XF86AudioMute" both find the bind
            const hay = (b.combo + " " + KeyNames.combo(b.combo) + " " + Keybinds.explain(b) + " " + b.action).toLowerCase();
            return words.every(w => hay.includes(w));
        });
    }
    // the groups that have matches
    readonly property var groups: Keybinds.groupNames.map(g => ({
                name: g,
                binds: win.shown.filter(b => b.group === g)
            })).filter(g => g.binds.length > 0)
    // Balanced columns: as many as fit at 380 px or more, each group put into the column that is shortest so
    // far (a card's height counted from its binds). Cards flowing in rows left a hole under every short card
    // beside a tall one, so a window of binds needed scrolling.
    readonly property int cols: Math.max(1, Math.floor((flick.width + 12) / (380 + 12)))
    readonly property var columns: {
        const out = [];
        for (let i = 0; i < win.cols; i++)
            out.push({
                h: 0,
                groups: []
            });
        for (const g of win.groups) {
            const c = out.reduce((a, b) => b.h < a.h ? b : a);
            c.groups.push(g);
            c.h += g.binds.length * 2 + 3;
        }
        return out.map(c => c.groups).filter(c => c.length > 0);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: win.pad
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Glyph {
                cp: 0xF030C   // keyboard
                font.pixelSize: Theme.iconSize + 6
                color: Theme.primary
            }
            Text {
                text: "Keybinds"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 6
                font.bold: true
                color: Theme.fg
            }
            Text {
                Layout.fillWidth: true
                text: win.shown.length + (win.shown.length === 1 ? " bind" : " binds")
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: Theme.fgMuted
            }
            SearchBox {
                id: search
                Layout.preferredWidth: 320
                placeholder: "Search keybinds"
                focusedPlaceholder: "Search keybinds"
                noMatch: search.text !== "" && win.shown.length === 0
            }
        }

        Text {
            visible: win.groups.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 24
            horizontalAlignment: Text.AlignHCenter
            text: Keybinds.all.length === 0 ? "No keybinds found in the Hyprland config." : "No keybind matches the search."
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            color: Theme.fgMuted
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: masonry.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: masonry
                spacing: 12

                Repeater {
                    model: win.columns

                    Column {
                        id: column
                        required property var modelData
                        width: Math.floor((flick.width - (win.cols - 1) * masonry.spacing) / win.cols)
                        spacing: 12

                        Repeater {
                            model: column.modelData

                            // one group: a card with its title and its binds
                            Rectangle {
                                id: card
                                required property var modelData
                                width: column.width
                                height: col.implicitHeight + 20
                                radius: Theme.radiusMd
                                color: Theme.tileBg

                                ColumnLayout {
                                    id: col
                                    x: 10
                                    y: 10
                                    width: parent.width - 20
                                    spacing: 4

                                    Text {
                                        Layout.bottomMargin: 4
                                        text: card.modelData.name
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize
                                        font.bold: true
                                        color: Theme.primary
                                    }

                                    Repeater {
                                        model: card.modelData.binds

                                        RowLayout {
                                            id: bindRow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 10

                                            // the key chips, a fixed column so the actions line up
                                            Row {
                                                Layout.preferredWidth: 150
                                                Layout.alignment: Qt.AlignTop
                                                spacing: 3

                                                Repeater {
                                                    model: bindRow.modelData.keys

                                                    Rectangle {
                                                        required property string modelData
                                                        implicitWidth: chipText.implicitWidth + 10
                                                        implicitHeight: 20
                                                        radius: Theme.radiusXs
                                                        color: Theme.trackBg

                                                        Text {
                                                            id: chipText
                                                            anchors.centerIn: parent
                                                            text: KeyNames.key(parent.modelData)
                                                            textFormat: Text.PlainText
                                                            font.family: Theme.font
                                                            font.pixelSize: Theme.fontSize - 2
                                                            color: Theme.fg
                                                        }
                                                    }
                                                }
                                            }

                                            // what the bind is for, and under it what it runs when that says
                                            // something else (Keybinds.explain picks the words)
                                            ColumnLayout {
                                                readonly property string title: Keybinds.explain(bindRow.modelData)
                                                Layout.fillWidth: true
                                                spacing: 0

                                                Text {
                                                    Layout.fillWidth: true
                                                    wrapMode: Text.Wrap
                                                    text: parent.title
                                                    textFormat: Text.PlainText
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontSize
                                                    color: Theme.fg
                                                }
                                                Text {
                                                    visible: parent.title !== bindRow.modelData.action
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideMiddle
                                                    text: bindRow.modelData.action.replace(/^Run /, "")
                                                    textFormat: Text.PlainText
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontSize - 3
                                                    color: Theme.fgMuted
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Escape: clear the search first, then close (the process ends with the window, sleepykeys.qml)
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (search.text !== "")
                search.text = "";
            else
                win.visible = false;
        }
    }

    Component.onCompleted: search.input.forceActiveFocus()
}
