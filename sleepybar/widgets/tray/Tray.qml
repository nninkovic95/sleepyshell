import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs
import qs.components
import "../../../services/LocalImage.js" as LocalImage

// StatusNotifier tray. Quickshell registers org.kde.StatusNotifierWatcher itself,
// so the gdbus wait in autostart.lua keeps working. Left: activate, middle: secondary,
// right: the item's menu, drawn themed by TrayMenu.
RowLayout {
    id: root
    required property var bar
    spacing: 4
    // `shown` is what the right island's Loader follows (Sleepybar.qml), so an empty tray takes no slot
    readonly property bool shown: SystemTray.items.values.length > 0
    visible: shown

    Repeater {
        model: SystemTray.items

        MouseArea {
            id: item
            required property SystemTrayItem modelData
            implicitWidth: 24
            implicitHeight: Theme.buttonHeight
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            onClicked: m => {
                if (m.button === Qt.LeftButton && !modelData.onlyMenu)
                    modelData.activate();
                else if (m.button === Qt.MiddleButton)
                    modelData.secondaryActivate();
                else if (modelData.hasMenu)
                    menu.toggle();
            }
            onWheel: w => {
                if (w.angleDelta.y !== 0)
                    modelData.scroll(w.angleDelta.y, false);
            }

            // above its neighbours while lifted, so the shadow is not covered
            z: surface.z

            // same inset geometry as the right island's BarButtons; only the highlight lifts, the
            // icon stays at scale 1 so it stays sharp; the holder keeps the
            // lifted highlight (z 1) under the icon
            Item {
                anchors.fill: parent

            Item {
                id: surface
                anchors.fill: parent

                Lift {
                    pointer: item
                    level: item.containsMouse ? 1 : 0
                    shape: trayHl
                    radius: trayHl.radius
                }

                Highlight {
                    id: trayHl
                    anchors.fill: parent
                    anchors.topMargin: Theme.insetPad
                    glued: false
                    radius: Theme.insetRadius
                    color: item.containsMouse ? Theme.hoverBg : "transparent"
                }
            }
            }

            IconImage {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: Theme.insetPad / 2
                implicitSize: Theme.barIconSize
                asynchronous: true
                source: root.iconSource(item.modelData.icon)
            }

            TrayMenu {
                id: menu
                handle: item.modelData.menu
                anchorItem: item
                bar: root.bar
            }
        }
    }

    // A tray icon as a local source only (LocalImage.js). Quickshell gives "image://icon/<name>",
    // "image://icon/<name>?path=<dir>" (the app's own icon folder) or its pixmap provider; for a
    // folder the theme icon wins, else the file in that folder when the folder is an absolute path.
    function iconSource(icon) {
        const s = String(icon ?? "");
        if (!s.includes("?path="))
            return LocalImage.only(s);
        const [name, path] = s.split("?path=");
        const file = name.slice(name.lastIndexOf("/") + 1);
        return Quickshell.iconPath(file, true) || LocalImage.fileUrl(path.replace(/\/+$/, "") + "/" + file);
    }
}
