import QtQuick
import QtQuick.Layouts
import qs.services
import qs.sleepysettings.components

// Settings tab "Right island": which right-island widgets show and in what order, update checks.
// Notifications have their own tab (NotificationsTab.qml), and the wallpaper folder is in the Theme
// tab.
TabPage {
    id: tab
    key: "widgets"
    label: "Right island"
    icon: 0xF10AB
    group: "widgets"

    // one line per widget: grip (drag to reorder), name, shown
    Section {
        title: "Widgets"

        OrderList {
            orderKey: "rightOrder"
            hiddenKey: "rightHidden"
            labels: Settings.widgetLabels
            query: tab.query
            noun: "widget"
        }
        ChoiceRow {
            label: "Dropdown fit"
            key: "dropdownFit"
            info: "Extend: the island widens so a widget's dropdown hangs flush under it, as one shape. Float: the island stays as it is and the dropdown is a separate card under it."
            tags: "dropdown panel island extend float card shape"
            options: [["extend", "Extend"], ["float", "Float"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
        }
    }

    AdvancedSection {
        NumberRow {
            label: "Update check interval"
            key: "updateMinutes"
            requires: ["pacman", "paru", "fakeroot"]
            suffix: " min"
            info: "How often the Package updates widget looks for package updates."
            tags: "pacman packages updates check every"
        }
        NumberRow {
            label: "Island padding"
            key: "rightPadding"
            suffix: " px"
            info: "Space between the right island's edges and its widgets."
            tags: "padding space margin island edge"
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
