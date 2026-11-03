import QtQuick
import qs
import qs.components
import qs.services

// Battery on the right island: the charge in % and a level glyph, which turns
// into a charging variant while plugged in. Shown only when a battery exists (a laptop), like the
// Bluetooth status's `shown`. A click opens the settings window on the Power tab (SettingsServer.openTab).
// The figure turns red at or below the critical level while discharging, the glyph green-ish
// (the theme's primary) while charging.
BarButton {
    id: root
    // read by the Loader in Sleepybar.qml, which hides itself (and frees the space) while this is false
    readonly property bool shown: Battery.present
    readonly property bool low: Battery.discharging && Battery.percent <= Settings.lowBatteryPct
    inset: true
    text: Math.round(Battery.percent) + "%"
    glyph: Battery.glyph()
    fg: root.low ? Theme.urgentFg : Battery.charging ? Theme.primary : Theme.fg
    onClicked: {
        const s = Popouts.byName["settings"];
        if (s && s.length > 0)
            s[0].openTab("power");
    }
}
