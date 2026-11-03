import QtQuick
import qs
import qs.components
import qs.services
import qs.sleepybar.widgets.bluetooth
import qs.sleepybar.widgets.clipboard
import qs.sleepybar.widgets.keyboard
import qs.sleepybar.widgets.network
import qs.sleepybar.widgets.notifications
import qs.sleepybar.widgets.power
import qs.sleepybar.widgets.privacy
import qs.sleepybar.widgets.tray
import qs.sleepybar.widgets.updates
import qs.sleepybar.components

// The right island: the widgets `names` lists (Settings.rightWidgets through MonitorPolicy, so the
// settings window hides and reorders them), in the screen's top-right corner. It lives in the bar
// window (Sleepybar.qml places it and gives it input). Each widget's dropdown hangs from this island and
// asks it to widen (SideIsland.qml's host contract), so the island and the open dropdown are one shape.
SideIsland {
    id: sleepyright
    // the Bar window of this screen. The id is sleepyright, not root: a widget declared inside an
    // inline Component below has its own properties first in scope, so short names can resolve to
    // the widget itself (see Sleepybar.qml)
    required property var bar
    required property var names

    attach: "topRight"
    // twice the 4 px highlight inset by default: at 4 the first highlight hugged the island's
    // rounded end; set in the Right island tab
    padding: Theme.rightIslandPad

    // ---- the widgets by name; a Loader below instantiates the ones `names` lists ----
    readonly property var widgetComponents: ({
            capslock: capslockC,
            updates: updatesC,
            network: networkC,
            bluetooth: bluetoothC,
            battery: batteryC,
            privacy: privacyC,
            notifications: notificationsC,
            clipboard: clipboardC,
            tray: trayC,
        })

    Component {
        id: capslockC
        CapsIndicator {}
    }
    Component {
        id: updatesC
        Updates {
            bar: sleepyright.bar
        }
    }
    Component {
        id: networkC
        Network {
            bar: sleepyright.bar
        }
    }
    Component {
        id: bluetoothC
        BluetoothStatus {}
    }
    Component {
        id: batteryC
        BatteryStatus {}
    }
    Component {
        id: privacyC
        PrivacyPill {
            bar: sleepyright.bar
        }
    }
    Component {
        id: notificationsC
        Notifications {
            bar: sleepyright.bar
        }
    }
    Component {
        id: clipboardC
        Clipboard {}
    }
    Component {
        id: trayC
        Tray {
            bar: sleepyright.bar
        }
    }

    // ---- content ----
    Repeater {
        model: sleepyright.names

        Loader {
            required property string modelData
            sourceComponent: sleepyright.widgetComponents[modelData] ?? null
            // a widget can hide itself with `shown` (Bluetooth while off); the Loader must hide
            // too, or it keeps the widget's width in the island
            visible: item !== null && (item.shown ?? true)
        }
    }
}
