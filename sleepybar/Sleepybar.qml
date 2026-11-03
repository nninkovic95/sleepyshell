import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.sleepybar.islands
import qs.sleepybar.popups.osd
import qs.sleepybar.popups.wallpaper
import qs.sleepybar.widgets.notifications

// Sleepybar: one transparent layer surface per screen, the bar strip. It reserves the space at the
// top of the screen and holds the two side islands; the centre island and the bar's popups are
// their own surfaces on the same screen, placed here so each screen gets one set. Every island is
// one file in islands/ and owns its shape, its widgets and its dropdowns.
// The id is barWin, not bar: a widget declared inside an inline Component has its own `bar`
// property, which shadows an id of that name, so `bar: bar` bound the widget to itself and its
// dropdown opened at x = 0 with no screen.
PanelWindow {
    id: barWin
    required property ShellScreen modelData
    // "main", or "full" / "lean" for the other monitors (MonitorPolicy). Full: every island except the
    // tray and the notification bell; lean: workspaces and clock only.
    readonly property string role: MonitorPolicy.roleOf(modelData)
    readonly property var rightNames: MonitorPolicy.rightNames(modelData, Settings.rightWidgets)

    // ---- dropdowns ----
    // The islands' dropdowns (IslandDropdown.qml) are drawn in this surface, in `dropLayer`, so an island
    // and its open dropdown are one shape in one surface (one fill, one blur, no seam). While one is
    // shown (open or closing) its panel takes input. The surface grows down to hold the tallest dropdown
    // opened this session, in one step (from each panel's full height, not its animated one), and never
    // shrinks: shrinking it after each close made opening and closing jitter (seen on Hyprland 0.57, as
    // with the centre island's surface; likely the area given up is not repainted at once). The space
    // below the strip is transparent and outside the mask.
    readonly property alias dropLayer: dropLayerItem
    property var drops: []
    function dropShown(d) {
        if (!drops.includes(d))
            drops = drops.concat([d]);
    }
    function dropHidden(d) {
        if (drops.includes(d))
            drops = drops.filter(x => x !== d);
    }
    readonly property real dropBottom: drops.reduce((m, d) => Math.max(m, Math.ceil(d.panelTop + d.fullH)), 0)
    property real tallestDrop: 0
    onDropBottomChanged: {
        if (dropBottom > tallestDrop)
            tallestDrop = dropBottom;
    }

    // ---- surface and input ----
    screen: modelData
    anchors {
        top: true
        left: true
        right: true
    }
    // as tall as the screen from the start, so a dropdown always fits and the surface never resizes: grown
    // on a dropdown's first open, the resize moved both side islands up and down for a moment. The dropdowns
    // still animate inside it; outside the islands and an open dropdown it is transparent and passes clicks
    // through (mask below). The reserved space never changes.
    implicitHeight: Math.max(Theme.reserved, tallestDrop, screen ? screen.height : 0)
    exclusiveZone: Theme.exclusive
    // only the islands and a shown dropdown take input; the transparent rest is click-through
    mask: Region {
        item: leftIsland
        regions: (barWin.rightNames.length > 0 ? [rightRegion] : []).concat(barWin.drops.map(d => d.region))
    }
    Region {
        id: rightRegion
        item: rightIsland
    }
    color: "transparent"
    WlrLayershell.namespace: "sleepyshell"
    WlrLayershell.layer: WlrLayer.Top
    // a layer surface gets no keys unless it asks: only while an open dropdown has a text field in use
    // (the Wi-Fi password)
    WlrLayershell.keyboardFocus: drops.some(d => d.open && d.wantsKeyboard) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // "Keep awake" from the control centre (it needs a window)
    IdleInhibitor {
        window: barWin
        enabled: Caffeine.on
    }

    // ---- the three islands ----
    Sleepyleft {
        id: leftIsland
        bar: barWin
        anchors.left: parent.left
        y: Theme.marginTop
    }

    // its own layer surface that expands into the control centre
    Sleepycentre {
        bar: barWin
    }

    Sleepyright {
        id: rightIsland
        bar: barWin
        names: barWin.rightNames
        visible: barWin.rightNames.length > 0
        anchors.right: parent.right
        y: Theme.marginTop
    }

    // the islands' dropdown panels, above the islands so their fillets overlap the island's edge
    Item {
        id: dropLayerItem
        anchors.fill: parent
        z: 1
    }

    // ---- this screen's popups, each its own surface ----
    // volume / mic flash at the bottom of the screen
    Osd {
        bar: barWin
    }

    // toasts for new notifications, top right under the bar
    NotifPopups {
        bar: barWin
    }

    // thumbnail grid under the bar, opened from the control centre (or `qs ipc call sleepybar toggle wallpaper`)
    WallpaperPicker {
        bar: barWin
    }
}
