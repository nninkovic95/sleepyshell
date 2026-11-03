import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.components
import qs.services

// Volume / microphone / Caps Lock pill at the bottom centre, shown only while a fullscreen window covers the
// bar (otherwise the clock island reveals the level itself, see VolumePeek). State in OsdState.
// A layer surface on the overlay layer (namespace sleepyshell-osd, so the `^sleepyshell` layer rule blurs it),
// click-through (an empty Region mask makes Quickshell set Qt::WindowTransparentForInput), unmapped
// while idle, and only on the focused monitor.
PanelWindow {
    id: root
    required property var bar
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(bar.screen)
    readonly property bool fullscreen: monitor?.activeWorkspace?.hasFullscreen ?? false
    readonly property bool focused: !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === bar.screen.name
    readonly property bool shown: OsdState.shown && fullscreen && focused

    screen: bar.screen
    // stays true until the fade-out has finished, then the surface unmaps
    visible: shown || pill.opacity > 0
    color: "transparent"
    anchors.bottom: true
    anchors.left: true
    margins.bottom: 48
    margins.left: Math.round((bar.screen.width - implicitWidth) / 2)
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 260
    implicitHeight: 44
    WlrLayershell.namespace: "sleepyshell-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}

    // hasFullscreen follows Hyprland's fullscreen event; refresh in case the module lags behind
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (e.name === "fullscreen")
                Hyprland.refreshWorkspaces();
        }
    }

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: Theme.radiusXl
        color: Theme.popupBg
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 120
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10

            Glyph {
                Layout.preferredWidth: 24
                cp: OsdState.glyph
                font.pixelSize: Theme.fontSize + 5
                color: OsdState.muted ? Theme.fgMuted : Theme.fg
            }

            Text {
                Layout.fillWidth: true
                visible: OsdState.capsLast
                text: CapsLock.on ? "Caps Lock on" : "Caps Lock off"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: Theme.fg
            }

            Rectangle {
                visible: !OsdState.capsLast
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: height / 2
                color: Theme.trackBg

                Rectangle {
                    width: OsdState.level * parent.width
                    height: parent.height
                    radius: height / 2
                    color: OsdState.muted ? Theme.fgMuted : Theme.primary
                }
            }

            Text {
                visible: !OsdState.capsLast
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
                text: Math.round(OsdState.level * 100) + "%"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: Theme.fg
            }
        }
    }
}
