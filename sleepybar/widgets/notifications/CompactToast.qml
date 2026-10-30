import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs
import qs.components
import qs.services

// One line for a notification that arrived while a toast was hovered (NotifPopups): it joins the
// far end of the chain small, so the hovered card does not move, and becomes a full toast when the
// pointer leaves. A click
// opens it like a full card.
Rectangle {
    id: row
    required property var notif
    readonly property bool hovered: mouse.containsMouse
    readonly property bool critical: notif?.urgency === NotificationUrgency.Critical
    // an app icon given as a file path (Hyprshot names the screenshot) loads as a file, like NotifCard:
    // the icon theme lookup warned "Could not load icon" for it
    readonly property string iconSource: Notifs.iconUrl(notif)
    implicitHeight: 34
    radius: Theme.radiusMd
    color: Qt.tint(Qt.alpha(Theme.containerHighest, 0.92), hovered ? Theme.hoverBg : "transparent")
    border.width: critical ? 1 : 0
    border.color: Theme.urgent

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8

        Item {
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18

            IconImage {
                anchors.fill: parent
                visible: row.iconSource !== ""
                source: row.iconSource
            }

            Glyph {
                anchors.centerIn: parent
                visible: row.iconSource === ""
                cp: 0xF009A
                color: Theme.fgMuted
            }
        }

        Text {
            Layout.fillWidth: true
            text: row.notif?.summary ?? ""
            textFormat: Text.PlainText   // app text, never markup (review 4)
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
            font.weight: Font.Medium
            color: Theme.fg
        }

        Text {
            text: row.notif?.appName ?? ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            Layout.maximumWidth: 120
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            color: Theme.fgMuted
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Notifs.activate(row.notif);
            Notifs.unpop(row.notif);
        }
    }
}
