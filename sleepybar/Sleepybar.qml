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

    // ---- surface and input ----
    screen: modelData
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.reserved
    exclusiveZone: Theme.exclusive
    // only the islands take input; the transparent rest of the strip is click-through
    mask: Region {
        item: leftIsland
        regions: barWin.rightNames.length > 0 ? [rightRegion] : []
    }
    Region {
        id: rightRegion
        item: rightIsland
    }
    color: "transparent"
    WlrLayershell.namespace: "sleepyshell"
    WlrLayershell.layer: WlrLayer.Top

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
