import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services
import qs.sleepybar.components

// Network pill: connection glyph, plus the signal strength while on Wi-Fi; the dropdown shows the
// state and the network list (Wi-Fi on/off is a control-centre tile).
BarButton {
    id: root
    required property var bar
    readonly property bool onWifi: Net.wifiUp && !Net.wiredUp
    // figure before the glyph, like the CPU and memory readouts
    readonly property int percent: Math.round(Net.strength * 100)
    text: onWifi ? percent + "%" : ""
    // on Wi-Fi the fan is filled to the same percentage as the figure beside it
    glyph: onWifi ? 0 : Net.glyph()
    iconItem: onWifi ? barFan : null

    Component {
        id: barFan
        SignalFan {
            level: root.percent / 100
            alert: Net.noInternet
            pixelSize: root.glyphSize
            color: root.currentFg
        }
    }
    // the width of "100%" plus the glyph is reserved, so the island does not jitter as the strength changes
    minWidth: onWifi ? Math.ceil(widest.width) + 4 + Theme.iconCell + hpad * 2 : 0
    inset: true
    bg: pop.open ? Theme.hoverBg : "transparent"
    onClicked: pop.toggle()

    TextMetrics {
        id: widest
        font.family: Theme.font
        font.pixelSize: Theme.barFontSize
        text: "100%"
    }

    IslandDropdown {
        id: pop
        name: "network"
        fixedWidth: 320
        anchorItem: root
        bar: root.bar
        // the password field needs keys, which a layer surface only gets when it asks for them
        wantsKeyboard: wifi.typing

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 4
            spacing: 8

            Glyph {
                Layout.preferredWidth: 24
                visible: !root.onWifi
                cp: Net.glyph()
                font.pixelSize: 18
                color: Net.online && !Net.noInternet ? Theme.primary : Theme.fg
            }

            SignalFan {
                Layout.preferredWidth: 24
                visible: root.onWifi
                level: root.percent / 100
                alert: Net.noInternet
                pixelSize: 18
                color: Net.noInternet ? Theme.fg : Theme.primary
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: Net.label
                textFormat: Text.PlainText   // a network name is someone else's string (review 4)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
                color: Theme.fg
            }

        }

        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 4
            implicitHeight: 1
            color: Theme.containerHighest
        }

        WifiList {
            id: wifi
            Layout.fillWidth: true
            scanning: pop.open
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 4
            implicitHeight: 1
            color: Theme.containerHighest
        }

        // samples /proc/net/dev only while the dropdown is open
        NetSpeed {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            active: pop.open
            iface: Net.iface
        }

        MenuItem {
            icon: 0xF05A9
            label: "Network settings"
            onClicked: {
                pop.open = false;
                DefaultApps.runInTerminal(["nmtui"]);
            }
        }
    }
}
