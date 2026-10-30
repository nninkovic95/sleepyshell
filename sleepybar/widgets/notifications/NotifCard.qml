import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs
import qs.components
import qs.services

// One notification, used by the dropdown and by the toasts. The whole card activates it (the
// app's "default" action, then dismiss); other actions are buttons, the x dismisses.
Item {
    id: root
    required property var notif
    readonly property bool critical: notif?.urgency === NotificationUrgency.Critical
    // the pointer anywhere on the card, its buttons included: over the close or an action button
    // the card's own MouseArea lost the hover and a toast timed out under the pointer
    property int buttonHovers: 0
    readonly property bool hovered: mouse.containsMouse || closeButton.hovered || buttonHovers > 0
    // notif can turn null a moment before the card goes (a dismissed notification is deleted first)
    // an app icon given as a file path (Hyprshot names the screenshot) is loaded as a file: the icon
    // theme lookup warned "Could not load icon" for it on every card
    readonly property string iconSource: Notifs.iconUrl(notif)
    // a screenshot the notification names (Notifs.screenshotPath), shown large under the text;
    // a click copies it, the buttons open it or its folder
    readonly property string shotPath: Notifs.screenshotPath(notif)
    readonly property string previewPath: Settings.shotPreview ? shotPath : ""
    // "Copied to clipboard" for a moment after a click on a screenshot, then the card goes
    property bool copied: false
    readonly property var extraActions: (notif?.actions ?? []).filter(a => a.identifier !== "default")
    // the hover lean in degrees: 4 in the dropdown, less on the toasts (NotifPopups)
    property real tiltMax: 4
    signal activated()

    // Clear all: the dropdown names the next card (Notifs.swipeOne) and it slides out to the right,
    // then is dismissed, and the cards below slide up. -1 on the toasts, which do not take part.
    property int swipeIndex: -1
    // the list this card is a delegate of (null on the toasts); read here, on the card: inside the
    // Connections below `ListView.view` is the Connections object's own attached view, always null
    readonly property var listView: ListView.view

    Connections {
        target: Notifs
        enabled: root.swipeIndex >= 0
        function onSwipeOne(n) {
            if (n !== root.notif || swipe.running)
                return;
            // only once it is in view: a card still below the fold would slide out unseen; the
            // dropdown tries again on its next beat, after the cards above have moved it up
            const v = root.listView;
            if (!v || root.y - v.contentY > v.height - 10)
                return;
            Notifs.takeSwipe(n.id);
            swipe.start();
        }
    }

    SequentialAnimation {
        id: swipe
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "x"
                to: root.width + 40
                duration: 200
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: root
                property: "opacity"
                to: 0
                duration: 200
            }
        }
        ScriptAction {
            script: root.notif?.dismiss()
        }
    }

    implicitHeight: col.implicitHeight + 20
    property real radius: Theme.radiusMd
    // the card's fill; the toasts override it (NotifPopups)
    property color color: hovered ? Theme.hoverBg : Theme.tileBg
    // above its neighbours while lifted, so the shadow is not covered
    z: surface.z

    // Only the background lifts and leans (scaling the whole card left its
    // text and icons blurry on hover); the content stays at scale 1. The holder keeps the lifted
    // surface (z 1) from covering it. The urgent edge is a shape and goes with the background.
    Item {
        anchors.fill: parent

        Rectangle {
            id: surface
            anchors.fill: parent
            radius: root.radius
            color: root.color

            // leans toward the pointer's edge like the other big cards; Settings' Card
            // hover picks tilt or a plain lift for all of them
            Lift {
                radius: root.radius
                tilt: true
                // 4 degrees, not 10: on a wide card the full lean read as too strong
                tiltMax: root.tiltMax
                pointer: mouse
                level: mouse.containsMouse ? 1 : 0
            }

            // thin urgent edge on critical ones
            Rectangle {
                visible: root.critical
                width: 3
                height: parent.height - 2 * root.radius
                y: root.radius
                radius: width / 2
                color: Theme.urgent
            }
        }
    }

    // the card's own click area sits below the buttons, so they take their clicks first
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const shot = root.shotPath !== "" && Deps.has("wl-copy");
            Notifs.activate(root.notif);
            if (!shot) {
                root.activated();
                return;
            }
            root.copied = true;
            copiedTimer.restart();
        }
    }

    Timer {
        id: copiedTimer
        interval: 900
        onTriggered: {
            if (!root.notif?.resident)
                root.notif?.dismiss();
            root.activated();
        }
    }

    RowLayout {
        id: col
        x: 12
        y: 10
        width: root.width - 24
        spacing: 10

        Item {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40

            IconImage {
                anchors.fill: parent
                visible: root.iconSource !== ""
                source: root.iconSource
            }

            Glyph {
                anchors.centerIn: parent
                visible: root.iconSource === ""
                cp: 0xF009A
                color: Theme.fgMuted
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.notif?.summary ?? ""
                    // the summary is app text like the body: a web page's notification title
                    // with <img src=...> would otherwise render as rich text (review 4)
                    textFormat: Text.PlainText
                    font.family: Theme.font
                    // summary 17, app and age 14, body 16 at the default 13
                    font.pixelSize: Theme.fontSize + 4
                    font.bold: true
                    color: Theme.fg
                    elide: Text.ElideRight
                }

                BarButton {
                    id: closeButton
                    glyph: 0xF0156
                    glued: false
                    hpad: 4
                    implicitHeight: 22
                    fg: Theme.fgMuted
                    hoverFg: Theme.fg
                    onClicked: Notifs.dismiss(root.notif)
                }
            }

            Text {
                Layout.fillWidth: true
                text: (root.notif?.appName ?? "") + (Notifs.ago(root.notif) !== "" ? "  ·  " + Notifs.ago(root.notif) : "")
                textFormat: Text.PlainText
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 1
                color: Theme.fgMuted
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                // apps send <b>/<i>/<u> even unasked (Hyprshot's saved path); dropped, not rendered
                text: (root.notif?.body ?? "").replace(/<\/?[biu]>/g, "")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 3
                color: Theme.fg
            }

            // decoded at the card's width only, so a 4K screenshot costs no more than a thumbnail
            Image {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.preferredHeight: status === Image.Ready ? Math.min(Settings.shotPreviewMax, width * implicitHeight / Math.max(1, implicitWidth)) : 0
                visible: root.previewPath !== "" && status === Image.Ready
                source: root.previewPath !== "" ? Notifs.fileUrl(root.previewPath) : ""
                sourceSize.width: width > 0 ? width : 400
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                // smooth edges under the card's hover tilt (Lift): without it they stair-stepped
                antialiasing: true
                asynchronous: true
                cache: false
            }

            Text {
                visible: root.copied
                text: "Copied to clipboard"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 1
                color: Theme.primary
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.extraActions.length > 0 || root.shotPath !== ""
                spacing: 6

                // a screenshot's own actions: the click copies, these open
                Repeater {
                    model: root.shotPath !== "" ? [["Open", 0xF03CC], ["Show in folder", 0xF0770]] : []

                    BarButton {
                        onHoveredChanged: root.buttonHovers += hovered ? 1 : -1
                        Component.onDestruction: if (hovered)
                            root.buttonHovers -= 1
                        required property var modelData
                        text: modelData[0]
                        glyph: modelData[1]
                        glued: false
                        hpad: 10
                        bg: Theme.tileBg
                        onClicked: {
                            if (modelData[0] === "Open")
                                Notifs.openImage(root.notif);
                            else
                                Notifs.revealFile(root.shotPath);
                            if (!root.notif?.resident)
                                root.notif?.dismiss();
                        }
                    }
                }

                Repeater {
                    model: root.extraActions

                    BarButton {
                        onHoveredChanged: root.buttonHovers += hovered ? 1 : -1
                        // a hovered button destroyed by a rebuild must give its count back
                        Component.onDestruction: if (hovered)
                            root.buttonHovers -= 1
                        required property var modelData
                        text: modelData.text
                        glued: false
                        hpad: 10
                        bg: Theme.tileBg
                        onClicked: {
                            modelData.invoke();
                            if (!root.notif?.resident)
                                root.notif?.dismiss();
                        }
                    }
                }
            }
        }
    }
}
