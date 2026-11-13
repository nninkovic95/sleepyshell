import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// Settings tab: notifications. Popups under the bar, do not disturb, the bell's list. Staged like
// every tab; the bell's switch and the control-centre tile still flip do not disturb at once.
TabPage {
    id: tab
    key: "notifications"
    label: "Notifications"
    icon: 0xF009C
    group: "notifications"

    // the newest picture in ~/Pictures/Screenshots (where Hyprshot saves), else the Hyprland
    // wallpaper that ships with it; the test below sends it so the large preview shows
    FolderListModel {
        id: shots
        folder: "file://" + Quickshell.env("HOME") + "/Pictures/Screenshots"
        showDirs: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        sortField: FolderListModel.Time
        sortReversed: false
    }

    function shotImage() {
        return shots.count > 0 ? shots.get(0, "filePath") : "/usr/share/hypr/wall0.png";
    }

    // the urgent apps as stored (desktop entry names), and every installed app not yet among them for
    // the "Add an app" list
    readonly property var urgentList: String(Settings.get("urgentApps")).split(",").map(a => a.trim()).filter(a => a !== "")
    function setUrgent(list) {
        Settings.stage("urgentApps", list.join(", "));
    }
    readonly property var appChoices: {
        const have = tab.urgentList.map(a => a.toLowerCase());
        const out = [];
        for (const e of DesktopEntries.applications.values)
            if (!e.noDisplay && !have.includes(e.id.toLowerCase()))
                out.push({
                    value: e.id,
                    label: e.name,
                    icon: DefaultApps.iconFor(e.icon)
                });
        out.sort((a, b) => a.label.localeCompare(b.label));
        return out;
    }
    // an app's name and icon for its chip; a name typed by hand that is no installed app shows as typed.
    // Looked up in the list rather than with byId: the list fills a moment after start, and a binding
    // over the list is evaluated again when it does (one over byId kept showing the bare id)
    function appInfo(id) {
        const e = DesktopEntries.applications.values.find(x => x.id === id);
        return e ? {
            label: e.name,
            icon: DefaultApps.iconFor(e.icon)
        } : {
            label: id,
            icon: "glyph:"
        };
    }

    // one Section for what is used every day: do not disturb first, the test last
    // (it acts at once, so it must not be in the Advanced fold, which is the last Section)
    Section {
        title: "Notifications"

        SwitchRow {
            label: "Do not disturb"
            key: "dnd"
            info: "No popups while it is on; critical ones still show. The bell's switch and the control-centre tile turn it on and off at once, without Apply."
            tags: "dnd quiet mute toast"
        }
        // the position's options are short ("At the top", not "At the top of the stack") so the choice fits half a card
        ChoiceRow {
            label: "New popup position"
            key: "toastStack"
            info: "Where a new notification popup goes in the stack under the bar: at the top, pushing the others down, or at the bottom, under the others."
            tags: "popup toast"
            options: [["top", "At the top"], ["bottom", "At the bottom"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
        }
        SwitchRow {
            label: "Show screenshot preview"
            key: "shotPreview"
            info: "A screenshot's notification (Hyprshot, or a file in a Screenshots folder) shows the picture under its text. Clicking the notification opens it either way."
            tags: "hyprshot image picture"
        }
        // a button that sends a test notification
        SettingRow {
            label: "Send a test"
            requires: ["notify-send"]
            info: "Sends a notification through notify-send (Screenshot: with the newest picture of ~/Pictures/Screenshots, so the preview shows). The popup settings preview while this window is open, so the test shows the staged ones."
            tags: "test notification toast"

            BarButton {
                text: "Normal"
                glyph: 0xF009A
                glyphFirst: true
                glued: false
                bg: Theme.tileBg
                onClicked: Quickshell.execDetached(["notify-send", "-a", "Sleepysettings", "Test notification", "Sent from the bar's settings window."])
            }

            // critical counts as urgent: the look, staying until dismissed and the sound
            BarButton {
                text: "Urgent"
                glyph: 0xF009E
                glyphFirst: true
                glued: false
                bg: Theme.tileBg
                onClicked: Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Sleepysettings", "Urgent test", "Stays until dismissed and plays the sound."])
            }

            // a test with a picture, as Hyprshot sends, for the large preview
            BarButton {
                text: "Screenshot"
                glyph: 0xF02E9
                glyphFirst: true
                glued: false
                bg: Theme.tileBg
                onClicked: Quickshell.execDetached(["notify-send", "-a", "Hyprshot", "-i", tab.shotImage(), "Screenshot test", "Sent from the settings window."])
            }
        }
    }

    // what makes a notification urgent, how it looks and how it rings
    Section {
        title: "Urgent"

        // one chip per chosen app, then a list of the installed apps to add one from
        SettingRow {
            label: "Urgent apps"
            key: "urgentApps"
            info: "Notifications from these apps pop up even with do not disturb on, stay until you close them, look different and play the sound. Critical notifications from any app always do. A web browser does not say which website sent a notification, so every site you allowed to send notifications in that browser counts."
            tags: "urgent important browser librewolf firefox chrome dnd sound"
            format: v => String(v).trim() === "" ? "none" : String(v)

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: tab.urgentList

                    Rectangle {
                        id: chip
                        objectName: "urgentAppChip"
                        required property string modelData
                        readonly property var app: tab.appInfo(modelData)
                        implicitWidth: chipRow.implicitWidth + 16
                        implicitHeight: 30
                        radius: Theme.radiusSm
                        color: Theme.tileBg

                        RowLayout {
                            id: chipRow
                            anchors.verticalCenter: parent.verticalCenter
                            x: 8
                            spacing: 6

                            Image {
                                visible: chip.app.icon !== "glyph:"
                                source: visible ? chip.app.icon : ""
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                sourceSize: Qt.size(36, 36)
                                fillMode: Image.PreserveAspectFit
                            }

                            Text {
                                text: chip.app.label
                                textFormat: Text.PlainText
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                                color: Theme.fg
                            }

                            BarButton {
                                objectName: "urgentAppRemove"
                                glyph: 0xF0156
                                glued: false
                                hpad: 4
                                implicitHeight: 22
                                fg: Theme.fgMuted
                                hoverFg: Theme.fg
                                onClicked: tab.setUrgent(tab.urgentList.filter(a => a !== chip.modelData))
                            }
                        }
                    }
                }

                AppCombo {
                    objectName: "urgentAppAdd"
                    width: 230
                    picker: tab.picker
                    options: tab.appChoices
                    value: null
                    unsetText: "Add an app…"
                    emptyText: "No installed apps"
                    onPicked: v => tab.setUrgent(tab.urgentList.concat([v]))
                }
            }
        }
        // presets only; a look of your own is written in sleepysettings.toml and shows here as "Custom",
        // a label rather than a choice (picking a preset replaces it, the reset arrow brings it back)
        ComboRow {
            id: lookRow
            readonly property string value: Settings.get("urgentLook")
            readonly property bool own: !lookRow.options.some(p => p.value === lookRow.value)
            label: "Urgent look"
            key: "urgentLook"
            picker: tab.picker
            info: "How an urgent notification stands out from the others. Send an Urgent test above to see it; the bar shows your choice before you apply it. A look of your own can be written in sleepysettings.toml as parts: tint and a number up to 100 (how red the card is), edge and a number of pixels up to 12 (0 hides it), and chip (the Urgent label), for example \"tint 30, edge 6, chip\". It then shows here as Custom."
            tags: "urgent look style colour color red label chip edge custom"
            options: [["full", "Red card and label"], ["tint", "Red card"], ["chip", "Label only"], ["edge", "Edge only"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
            otherLabel: "Custom"
            hint: lookRow.own ? "Custom: " + lookRow.value + ", set in sleepysettings.toml" : ""
        }
        SwitchRow {
            label: "Play a sound"
            key: "urgentSound"
            requires: ["pw-play"]
            info: "Plays the sound below when an urgent notification arrives, also with do not disturb on."
            tags: "urgent sound chime audio ring"
        }
        FieldRow {
            label: "Sound file"
            key: "urgentSoundFile"
            requires: ["pw-play"]
            enabled: Settings.get("urgentSound")
            info: "The sound an urgent notification plays: an audio file such as .oga, .ogg or .wav. ~ is your home."
            tags: "urgent sound chime audio ring file"
            // what Settings.expand turns into a whole path: ~ only as the home folder itself
            validate: t => /^(~(\/|$)|\/)/.test(t.trim()) ? "" : "Give the whole path, starting with / or ~/"

            BarButton {
                objectName: "urgentPlay"
                text: "Play"
                glyph: 0xF040A
                glyphFirst: true
                glued: false
                bg: Theme.tileBg
                // the bar plays it: it already knows the main output (Audio.sink), which this window
                // would first have to connect to the audio server for; only without the bar does the
                // window play it itself, and its first chime then may not find the main output yet
                onClicked: Settings.linked ? Settings.link.chime() : Chime.play()
            }
        }
        NumberRow {
            label: "Sound volume"
            key: "urgentSoundVolume"
            requires: ["pw-play"]
            enabled: Settings.get("urgentSound")
            suffix: " %"
            info: "How loud the urgent sound plays, compared with your main output's volume (the volume keys and the audio button): 100 % is the same, 110 % a little louder. It plays on whichever output is in use and goes up and down with it. Try it with Play."
            tags: "urgent sound chime audio ring volume loud quiet"
        }
    }

    AdvancedSection {
        NumberRow {
            label: "Max popups on screen"
            key: "toastMax"
            tags: "popup toast"
        }
        NumberRow {
            label: "Screenshot preview height"
            key: "shotPreviewMax"
            enabled: Settings.get("shotPreview")
            suffix: " px"
            info: "The tallest the screenshot preview gets; it is never wider than the card. Used while the preview is on."
            tags: "hyprshot image picture"
        }
        ChoiceRow {
            label: "Notification list order"
            key: "notifOrder"
            info: "The order of the notifications in the bell's dropdown on the right island."
            tags: "bell history"
            options: [["newest", "Newest first"], ["oldest", "Oldest first"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
