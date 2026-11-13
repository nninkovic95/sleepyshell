import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
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
    readonly property bool urgent: Notifs.isUrgent(notif)
    // the local icons this notification can show, best first, like NotifCard: an image that fails to
    // load gives way to the app's icon, and with none left the bell shows
    readonly property var iconSources: Notifs.iconUrls(notif)
    property int iconTry: 0
    onIconSourcesChanged: iconTry = 0
    readonly property string iconSource: iconSources[iconTry] ?? ""
    implicitHeight: 34
    radius: Theme.radiusMd
    // tinted like an urgent card when the Urgent look tints them (NotifCard)
    color: Qt.tint(Qt.tint(Theme.popupBg, urgent && Notifs.urgentStyle.tint > 0 ? Qt.alpha(Theme.urgent, Notifs.urgentStyle.tint / 100) : "transparent"), hovered ? Theme.hoverBg : "transparent")
    border.width: urgent ? 1 : 0
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
                onStatusChanged: if (status === Image.Error) row.iconTry++
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
            text: Notifs.appLabel(row.notif)
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
