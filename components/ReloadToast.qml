import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.components

// Quickshell's own reload popups are white and unthemed. A successful reload now shows nothing; a failed one shows this card in the
// bar's style at the top right for 8 s (click to dismiss), with the error and the log command.
Scope {
    id: root
    property string error: ""
    property bool shown: false

    Connections {
        target: Quickshell
        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup();
            root.shown = false;
        }
        function onReloadFailed(errorString) {
            Quickshell.inhibitReloadPopup();
            root.error = errorString;
            root.shown = true;
            hide.restart();
        }
    }

    Timer {
        id: hide
        interval: 8000
        onTriggered: root.shown = false
    }

    PanelWindow {
        visible: root.shown
        screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0]
        anchors {
            top: true
            right: true
        }
        margins.top: Theme.exclusive + 12
        margins.right: 12
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: 420
        implicitHeight: card.implicitHeight
        WlrLayershell.namespace: "sleepyshell-toast"
        WlrLayershell.layer: WlrLayer.Overlay

        Item {
            id: card
            anchors.fill: parent
            implicitHeight: col.implicitHeight + 24
            property real radius: Theme.radiusXl

            // only the card's background lifts; the text stays at scale 1 and sharp
            Rectangle {
                id: bg
                anchors.fill: parent
                radius: card.radius
                color: Qt.alpha(Theme.containerHighest, 0.85)
                border.width: 1
                border.color: Qt.alpha(Theme.urgentFg, 0.35)

                Lift {
                    radius: card.radius
                    level: dismiss.containsMouse ? 1 : 0
                }
            }

            ColumnLayout {
                id: col
                x: 14
                y: 12
                width: card.width - 28
                spacing: 6

                RowLayout {
                    spacing: 8

                    Glyph {
                        cp: 0xF0026
                        color: Theme.urgentFg
                    }

                    Text {
                        text: "Bar config failed to load"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 1
                        font.weight: Font.Medium
                        color: Theme.fg
                    }
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    text: root.error
                    textFormat: Text.PlainText   // QML error text quotes source, which may hold tags (review 4)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                    color: Theme.fgMuted
                }

                Text {
                    text: "The previous config keeps running. Log: qs -c sleepyshell log"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                    color: Theme.fgMuted
                }
            }

            MouseArea {
                id: dismiss
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.shown = false
            }
        }
    }
}
