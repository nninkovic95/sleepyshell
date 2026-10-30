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

            BarButton {
                text: "Critical"
                glyph: 0xF0026
                glyphFirst: true
                glued: false
                bg: Theme.tileBg
                onClicked: Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Sleepysettings", "Critical test", "Stays until dismissed."])
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
