import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs
import qs.components
import qs.services
import qs.sleepybar.widgets.network
import qs.sleepybar.widgets.audio
import qs.sleepybar.widgets.power
import qs.sleepybar.widgets.sysinfo
import qs.sleepybar.components

// Control centre: the body of the centre island when it is open (islands/Sleepycentre.qml, a
// GrowingIsland). Three columns:
//   left    date, uptime, hardware (load, memory, swap, temperatures)
//   middle  quick-setting tiles (Wi-Fi, Bluetooth, do-not-disturb, keep awake, power profile, night
//           light), an expandable Wi-Fi or Bluetooth list, and the tools (theme, colour picker,
//           calendar, settings, the user's own)
//   right   audio output and input with device lists and the laptop's brightness
// The middle column hangs lower than the other two; the island reads the three columns
// (middleColumn, leftColumn, rightColumn) to draw that shape.
RowLayout {
    id: root

    // ---- API ----
    // the centre island this body opens in (its `open` state, its widgets beside the clock)
    required property var centre
    property date date
    readonly property Item leftColumn: hwCol
    readonly property Item middleColumn: quickCol
    readonly property Item rightColumn: audioCol
    // the Wi-Fi password field has the keyboard
    readonly property bool typing: wifiList.typing

    spacing: 0

    // ---- state ----
    // the open list under a tile: "wifi", "bt" or ""
    property string section: ""
    // the tiles by name (Settings.tileNames)
    readonly property var tileComponents: ({
            wifi: tileWifi,
            bluetooth: tileBluetooth,
            dnd: tileDnd,
            awake: tileAwake,
            profile: tileProfile,
            night: tileNight
        })
    // the tile rows, two names to a row, and which row holds the tile whose list is open (-1: none, or its tile is hidden)
    readonly property var tileRows: {
        const t = Settings.tiles, rows = [];
        for (let i = 0; i < t.length; i += 2)
            rows.push(t.slice(i, i + 2));
        return rows;
    }
    readonly property string sectionTile: root.section === "wifi" ? "wifi" : root.section === "bt" ? "bluetooth" : ""
    readonly property int listRow: root.sectionTile === "" ? -1 : root.tileRows.findIndex(r => r.includes(root.sectionTile))
    readonly property var rowsAbove: root.listRow < 0 ? [] : root.tileRows.slice(0, root.listRow + 1)
    readonly property var rowsBelow: root.listRow < 0 ? root.tileRows : root.tileRows.slice(root.listRow + 1)
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property int btConnected: adapter ? adapter.devices.values.filter(d => d.connected).length : 0

    Connections {
        target: root.centre

        function onOpenChanged() {
            if (root.centre.open)
                uptime.running = true;
            else
                root.section = "";
        }
    }

    // ---- actions ----
    function run(cmd) {
        root.centre.open = false;
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    // scripts/theme.py (wallpaper and palette), with its arguments
    function theme(args) {
        root.centre.open = false;
        Quickshell.execDetached([Quickshell.shellPath("scripts/theme.py")].concat(args));
    }

    function toggleSection(s) {
        section = section === s ? "" : s;
    }

    function profileName(p) {
        return p === PowerProfile.Performance ? "Performance" : p === PowerProfile.PowerSaver ? "Power saver" : "Balanced";
    }

    function profileGlyph(p) {
        return p === PowerProfile.Performance ? 0xF04C5 : p === PowerProfile.PowerSaver ? 0xF032A : 0xF0F85;
    }

    function cycleProfile() {
        const p = PowerProfiles.profile;
        if (p === PowerProfile.PowerSaver)
            PowerProfiles.profile = PowerProfile.Balanced;
        else if (p === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile)
            PowerProfiles.profile = PowerProfile.Performance;
        else
            PowerProfiles.profile = PowerProfile.PowerSaver;
    }

    Process {
        id: uptime
        command: ["uptime", "-p"]
        stdout: StdioCollector {
            onStreamFinished: uptimeText.text = text.trim()
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.centre.open
        onTriggered: uptime.running = true
    }

    // ---- left column: date, uptime, hardware ----
    ColumnLayout {
        id: hwCol
        Layout.alignment: Qt.AlignTop
        Layout.rightMargin: 12
        // fixed width: the surface must not change size while open, and the date and uptime
        // lines would otherwise set it (long month names, multi-day uptimes)
        Layout.preferredWidth: 300
        Layout.minimumWidth: 300
        Layout.maximumWidth: 300
        spacing: 2

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.topMargin: 2
            elide: Text.ElideRight
            text: Qt.formatDate(root.date, "dddd, dd MMMM yyyy")
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.bold: true
            color: Theme.fg
        }

        Text {
            id: uptimeText
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.bottomMargin: 6
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            color: Theme.fgMuted
        }

        // the CPU/memory hover panel's body; samples only while the control centre is open,
        // the CPU figure comes from the readout beside the clock
        SysInfoPanel {
            Layout.leftMargin: 10
            Layout.rightMargin: 4
            Layout.topMargin: 4
            active: root.centre.open
            drives: false
            // the island's CPU readout, on whichever side centreLeft put it
            cpu: (Settings.centreLeft === "audio" ? root.centre.rightItem : root.centre.leftItem)?.cpu ?? 0
        }
    }

    Rectangle {
        Layout.alignment: Qt.AlignTop
        Layout.rightMargin: 12
        implicitWidth: 1
        implicitHeight: tiles.implicitHeight
        color: Theme.containerHighest
    }

    // ---- middle column: quick settings and tools ----
    ColumnLayout {
        id: quickCol
        Layout.alignment: Qt.AlignTop
        // 372, not 340: with the larger tool icons "Shuffle wallpaper" overran its half
        Layout.preferredWidth: 372
        Layout.minimumWidth: 372
        // the middle hangs well below the outer columns (the shape is deliberately
        // uneven); the tools rows spread over the rest.
        // Not with the uneven shape off (Centre island tab, Shape): the panel is then one rectangle.
        Layout.minimumHeight: Settings.centreUneven ? root.centre.sideDepth + 80 : 0
        spacing: 8

        // The quick-setting tiles, two to a row, in the order of Settings.tiles (Centre island tab; the tiles are
        // reorderable and hideable like the tools). The Wi-Fi and Bluetooth lists open under the row their tile is in, so the
        // rows are cut in two at that row: the rows up to it, the list, the rest. `tileComponents` holds the tiles, which keep
        // their state in Net, Notifs, Caffeine and NightLight; the editor in the settings window draws the same names.
        ColumnLayout {
            id: tiles
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.rowsAbove
                delegate: tileRow
            }

            Rectangle {
                visible: root.listRow >= 0
                Layout.fillWidth: true
                radius: Theme.radiusMd
                color: Theme.tileBg
                implicitHeight: lists.implicitHeight + 8

                ColumnLayout {
                    id: lists
                    x: 4
                    y: 4
                    width: parent.width - 8
                    spacing: 0

                    WifiList {
                        id: wifiList
                        visible: root.section === "wifi"
                        Layout.fillWidth: true
                        scanning: visible && root.centre.open
                    }

                    BtList {
                        visible: root.section === "bt"
                        Layout.fillWidth: true
                        scanning: visible && root.centre.open
                    }
                }
            }

            Repeater {
                model: root.rowsBelow
                delegate: tileRow
            }
        }

        Component {
            id: tileRow

            RowLayout {
                id: tr
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                uniformCellSizes: true

                Repeater {
                    model: tr.modelData

                    Loader {
                        required property string modelData
                        Layout.fillWidth: true
                        sourceComponent: root.tileComponents[modelData]
                    }
                }

                // a row with one tile keeps the other half empty, as the grid did
                Item {
                    visible: tr.modelData.length < 2
                    Layout.fillWidth: true
                }
            }
        }

        Component {
            id: tileWifi

            Tile {
                icon: Net.glyph()
                label: Net.wifi ? "Wi-Fi" : "Network"   // the click toggles the Wi-Fi radio; the sub line says if wired is up
                sub: Net.label
                active: Net.wifi ? Net.wifiEnabled : Net.wiredUp
                expandable: Net.wifi !== null
                expanded: root.section === "wifi"
                onClicked: {
                    if (Net.wifi)
                        Net.setWifi(!Net.wifiEnabled);
                }
                onExpand: root.toggleSection("wifi")
            }
        }

        Component {
            id: tileBluetooth

            Tile {
                icon: root.adapter && root.adapter.enabled ? (root.btConnected > 0 ? 0xF00B1 : 0xF00AF) : 0xF00B2
                label: "Bluetooth"
                sub: !root.adapter ? "No adapter" : !root.adapter.enabled ? "Off" : root.btConnected > 0 ? root.btConnected + " connected" : "On"
                active: root.adapter?.enabled ?? false
                expandable: root.adapter !== null
                expanded: root.section === "bt"
                onClicked: {
                    if (root.adapter)
                        root.adapter.enabled = !root.adapter.enabled;
                }
                onExpand: root.toggleSection("bt")
            }
        }

        Component {
            id: tileDnd

            Tile {
                icon: Notifs.dnd ? 0xF009B : 0xF009A
                label: "Do not disturb"
                sub: Notifs.dnd ? "On" : "Off"
                active: Notifs.dnd
                onClicked: Notifs.toggleDnd()
            }
        }

        Component {
            id: tileAwake

            Tile {
                icon: 0xF0176
                label: "Keep awake"
                sub: Caffeine.on ? "Screen stays on" : "Off"
                active: Caffeine.on
                onClicked: Caffeine.on = !Caffeine.on
            }
        }

        Component {
            id: tileProfile

            Tile {
                icon: root.profileGlyph(PowerProfiles.profile)
                label: "Power profile"
                sub: root.profileName(PowerProfiles.profile)
                active: PowerProfiles.profile === PowerProfile.Performance
                // greyed out and inert while power-profiles-daemon is not there (Battery probes it once)
                blocked: Battery.profilesMissing ? "Needs power-profiles-daemon (not running)" : ""
                onClicked: root.cycleProfile()
            }
        }

        // Night light takes the slot a Notifications tile would have, since notifications have their own
        // right-island dropdown
        Component {
            id: tileNight

            Tile {
                icon: NightLight.on ? 0xF0594 : 0xF05A8
                label: "Night light"
                sub: NightLight.on ? "On" : "Off"
                active: NightLight.on
                onClicked: NightLight.toggle()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 4
            implicitHeight: 1
            color: Theme.containerHighest
        }

        // tools, two per row; the rows share the middle block's spare height evenly, so it is
        // filled instead of ending in a gap
        GridLayout {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            columnSpacing: 6
            rowSpacing: 0

            // Which of these show, and in what order, is Settings.tools (the Centre island tab);
            // names, labels and icons are Settings.toolNames, toolLabels and
            // toolIcons (the settings window draws the same tiles), the action is here, so a new
            // tool goes in both. `theme` with no path: a random wallpaper
            // and its palette (it changes the wallpaper too); same as SUPER + SHIFT + W. `--palette`: a
            // new palette from the wallpaper on screen, which stays. There are no Audio effects,
            // Screenshot or Lock tools (Easy Effects opens from its tray icon; SUPER+L and the
            // session menu still lock, hyprshot has its bind).
            readonly property var table: ({
                    shuffle: () => root.theme([]),
                    // the wallpaper picker (WallpaperPicker.qml), also behind the Theme tab's Choose wallpaper
                    wallpaper: () => {
                        root.centre.open = false;
                        Popouts.toggle("wallpaper");
                    },
                    picker: () => root.run("sleep 0.2; hyprpicker -a"),
                    // the Calendar tool: the month popup, khal is its backend
                    calendar: () => {
                        root.centre.open = false;
                        Popouts.toggle("calendar"); // the month popup (CalendarPopup); khal is its backend
                    },
                    mixer: () => root.run("pwvucontrol"),
                    palette: () => root.theme(["--palette"]),
                    settings: () => {
                        root.centre.open = false;
                        Popouts.toggle("settings");
                    }
                })

            Repeater {
                // an optional tool whose program is not installed (Calendar without khal) is left out, not greyed
                model: Settings.toolsDrawn(n => Deps.needs(Settings.toolRequires[n] ?? []))

                MenuItem {
                    id: toolItem
                    required property string modelData
                    // the user's own tool (Settings.customTools), null for a built-in one
                    readonly property var custom: Settings.customTool(modelData, false)
                    Layout.fillHeight: true
                    iconSize: Theme.iconSize + 6
                    // icon and label live in Settings, which the settings window shares; the user can give a built-in tool
                    // another label or icon (Settings.toolOverrides)
                    icon: Settings.toolIcon(modelData, false)
                    label: Settings.toolLabel(modelData, false)
                    // greyed out and inert while a program the tool runs is missing (services/Deps.qml)
                    requires: custom ? ToolRun.programs(custom) : (Settings.toolRequires[modelData] ?? [])
                    // a custom app that is not installed (not a program Deps can look for)
                    blocked: custom && custom.kind === "app" ? ToolRun.needs(custom) : ""
                    onClicked: {
                        if (custom) {
                            root.centre.open = false;
                            ToolRun.run(custom);
                        } else {
                            grid.table[modelData]();
                        }
                    }
                    // the first word of a command is asked of Deps once (greyed out while it is not installed)
                    onCustomChanged: if (custom)
                        ToolRun.want([custom])
                    Component.onCompleted: if (custom)
                        ToolRun.want([custom])
                }
            }

            // the session menu, last, full width and centred so the block stays symmetric
            MenuItem {
                Layout.fillHeight: true
                iconSize: Theme.iconSize + 6
                centred: true
                Layout.columnSpan: 2
                Layout.fillWidth: true
                icon: Settings.powerIcon
                label: Settings.powerLabel
                danger: true
                onClicked: {
                    root.centre.open = false;
                    Popouts.toggle("session");
                }
            }
        }
    }

    Rectangle {
        Layout.alignment: Qt.AlignTop
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        implicitWidth: 1
        implicitHeight: tiles.implicitHeight
        color: Theme.containerHighest
    }

    // ---- right column: audio ----
    ColumnLayout {
        id: audioCol
        Layout.alignment: Qt.AlignTop
        Layout.preferredWidth: 300
        Layout.minimumWidth: 300
        Layout.maximumWidth: 300
        spacing: 6

        AudioPanel {
            input: false
            showMixer: false
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 4
            implicitHeight: 1
            color: Theme.containerHighest
        }

        // its "Audio mixer" link is in the middle column's tools
        AudioPanel {
            input: true
            showMixer: false
        }

        // the laptop panel's brightness, only when a backlight exists (DDC monitors are on
        // the Display tab)
        Rectangle {
            visible: Brightness.available
            Layout.fillWidth: true
            Layout.margins: 4
            implicitHeight: 1
            color: Theme.containerHighest
        }

        BrightnessPanel {
            active: root.centre.open
        }
    }
}
