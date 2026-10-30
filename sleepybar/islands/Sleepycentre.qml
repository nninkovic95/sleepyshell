import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.components
import qs.services
import qs.sleepybar.widgets.audio
import qs.sleepybar.widgets.clock
import qs.sleepybar.popups.osd
import qs.sleepybar.widgets.sysinfo
import qs.sleepybar.components

// The centre island: the clock with the date under it, CPU and memory on one side and audio on the
// other, hanging from the top edge; open, it is the control centre (clock/ControlCentre.qml). It is
// its own layer surface (GrowingIsland.qml): one outline that grows from the island into the panel, so the
// open shape mirrors the closed one (Centre island tab, Shape). Its Popouts name stays "clock", the
// name `ipc call sleepybar toggle clock` and the binds use.
GrowingIsland {
    id: sleepycentre
    name: "clock"

    // ---- the island: clock and date (Centre island tab, Clock) ----
    // big clock in its own font, the date under it
    title: Qt.formatDateTime(clock.date, Settings.clockFormat)
    titleFont: Settings.clockFont
    titleSize: Settings.clockSize
    subtitle: Settings.showDate ? Qt.formatDateTime(clock.date, Settings.dateFormat) : ""

    SystemClock {
        id: clock
        // tick every second only when the format shows seconds
        precision: Settings.clockFormat.includes("s") ? SystemClock.Seconds : SystemClock.Minutes
    }

    // ---- the island: widgets beside the clock (Centre island tab, Next to the clock) ----
    // CPU and memory and audio beside the clock.
    // Each can be hidden (`shown` hides the slot), and centreLeft picks which one sits left
    // (swapped there, not by dragging).
    leftComponent: Settings.centreLeft === "audio" ? audioC : sysinfoC
    rightComponent: Settings.centreLeft === "audio" ? sysinfoC : audioC

    Component {
        id: sysinfoC
        SysInfo {
            bar: sleepycentre.bar
            readonly property bool shown: Settings.centreSysinfo
        }
    }
    Component {
        id: audioC
        AudioPill {
            bar: sleepycentre.bar
            readonly property bool shown: Settings.centreAudio
            // a click opens this panel, which has the audio column; no dropdown of its own
            dropdown: false
            onOpenRequested: sleepycentre.open = true
        }
    }

    // ---- the island: the volume / mic peek under the clock ----
    // shown on the focused monitor only (state in OsdState)
    peek: VolumePeek {}
    peeking: OsdState.shown && (!Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === sleepycentre.bar.screen.name)

    // ---- the open panel: the control centre ----
    // the Wi-Fi list's password field needs keys (layer surfaces get none by default)
    wantsKeyboard: body.typing
    // the outer columns end higher than the tiles column, which alone hangs to the bottom
    // the dividers beside it end with the tiles
    middleItem: body.middleColumn
    leftSide: body.leftColumn
    rightSide: body.rightColumn

    ControlCentre {
        id: body
        centre: sleepycentre
        date: clock.date
    }
}
