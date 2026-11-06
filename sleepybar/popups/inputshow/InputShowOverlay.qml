import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services

// What the keybind overlay and the click circles draw (services/InputShow.qml has the switches and the events): one
// transparent surface per screen on the overlay layer that takes no input at all (clicks go to whatever is under
// it), there only while a switch is on. Rings where the pointer is; the keybind pill at the bottom centre of the
// focused screen, above where the volume OSD shows.
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            visible: InputShow.keysOn || InputShow.clicksOn
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "sleepyshell-inputshow"
            WlrLayershell.layer: WlrLayer.Overlay
            mask: Region {}

            Connections {
                target: InputShow
                function onRing(gx, gy, side) {
                    const x = gx - win.modelData.x, y = gy - win.modelData.y;
                    if (x >= 0 && y >= 0 && x < win.width && y < win.height)
                        ringC.createObject(win.contentItem, { cx: x, cy: y, tint: side === "left" ? Theme.primary : Theme.urgentFg });
                }
            }

            Component {
                id: ringC
                Rectangle {
                    id: r
                    objectName: "clickRing"
                    property real cx: 0
                    property real cy: 0
                    property color tint: Theme.primary
                    property real size: 8
                    x: cx - size / 2
                    y: cy - size / 2
                    width: size
                    height: size
                    radius: size / 2
                    color: "transparent"
                    border.width: 3
                    border.color: tint
                    ParallelAnimation {
                        running: true
                        NumberAnimation {
                            target: r
                            property: "size"
                            to: 64
                            duration: 420
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: r
                            property: "opacity"
                            from: 1
                            to: 0
                            duration: 420
                            easing.type: Easing.InQuad
                        }
                        onFinished: r.destroy()
                    }
                }
            }

            Rectangle {
                objectName: "keyPill"
                readonly property bool here: !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === win.modelData.name
                visible: here && InputShow.keysOn && InputShow.label !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 160
                width: keyText.implicitWidth + 2 * Theme.panelPad
                height: keyText.implicitHeight + Theme.panelPad
                // the corner preset's island radius, like the bar's islands and popups
                radius: Theme.radiusXl
                color: Theme.popupBg
                Text {
                    id: keyText
                    objectName: "keyPillText"
                    anchors.centerIn: parent
                    text: InputShow.label + (InputShow.repeats > 1 ? "  ×" + InputShow.repeats : "")
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 8
                    font.bold: true
                }
            }
        }
    }
}
