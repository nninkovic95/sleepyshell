import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Idle dimming (hypridle): a black layer over one screen that fades
// in while `dimmed`. hypridle sends "sleepyshell:dim" / "sleepyshell:undim" (scripts/idle.py writes
// its config) and shell.qml sets `dimmed`. An external monitor has no backlight to lower, so the
// shell darkens the picture instead. Click-through (an empty mask) and unmapped once faded out.
// Namespace "sleepydim", not "sleepyshell-…": the `^sleepyshell` layer rule would blur the whole
// screen behind it.
PanelWindow {
    id: root
    required property var modelData
    property bool dimmed: false

    screen: modelData
    visible: dimmed || shade.opacity > 0
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "sleepydim"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}

    Rectangle {
        id: shade
        anchors.fill: parent
        color: "black"
        opacity: root.dimmed ? 0.55 : 0
        Behavior on opacity {
            // slow in, quick out: input should bring the picture straight back
            NumberAnimation {
                duration: root.dimmed ? 1500 : 150
            }
        }
    }
}
