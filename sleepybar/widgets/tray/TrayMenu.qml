import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.components
import qs.sleepybar.components

// Themed tray menu: the entries of a tray item's DBus menu drawn in an IslandDropdown instead of the
// unthemed platform menu. Submenus open in place with a Back row.
IslandDropdown {
    id: root
    required property QsMenuHandle handle
    property var path: []
    readonly property var current: path.length > 0 ? path[path.length - 1] : handle
    pad: 6
    fixedWidth: 230

    onOpenChanged: {
        if (!open)
            path = [];
    }

    QsMenuOpener {
        id: opener
        menu: root.current
    }

    // only icons the theme actually has; a missing one would draw Quickshell's placeholder
    function iconSource(ic) {
        const s = String(ic ?? "");
        if (s.startsWith("image://icon/"))
            return Quickshell.iconPath(s.slice(13), true) ? s : "";
        return s;
    }

    function clean(s) {
        return String(s ?? "").replace(/_(?!_)/g, "");
    }

    Item {
        id: backRow
        visible: root.path.length > 0
        Layout.fillWidth: true
        implicitHeight: 30
        // above its neighbours while lifted, so the shadow is not covered
        z: backSurface.z

        // only the background lifts; the glyph and label stay at scale 1 and sharp.
        // The holder keeps the lifted surface (z 1) from covering the content.
        Item {
            anchors.fill: parent

            Rectangle {
                id: backSurface
                anchors.fill: parent
                radius: Theme.radiusSm
                color: backArea.containsMouse ? Theme.hoverBg : "transparent"

                Lift {
                    radius: parent.radius
                    level: backArea.containsMouse ? 1 : 0
                }
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 10
            spacing: 6

            Glyph {
                cp: 0xF0141
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Back"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: Theme.fg
            }
        }

        MouseArea {
            id: backArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.path = root.path.slice(0, -1)
        }
    }

    Repeater {
        model: opener.children

        Item {
            id: entry
            required property var modelData
            readonly property bool sep: modelData.isSeparator
            Layout.fillWidth: true
            implicitHeight: sep ? 9 : 30
            // above its neighbours while lifted, so the shadow is not covered
            z: rowSurface.z

            Rectangle {
                visible: entry.sep
                anchors.centerIn: parent
                width: parent.width - 8
                height: 1
                color: Theme.containerHighest
            }

            Item {
                visible: !entry.sep
                anchors.fill: parent
                opacity: entry.modelData.enabled ? 1 : 0.45

                // only the background lifts; the content stays at scale 1 and sharp.
                // The holder keeps the lifted surface (z 1) from covering the content.
                Item {
                    anchors.fill: parent

                    Rectangle {
                        id: rowSurface
                        anchors.fill: parent
                        radius: Theme.radiusSm
                        color: area.containsMouse && entry.modelData.enabled ? Theme.hoverBg : "transparent"

                        // disabled entries do not lift
                        Lift {
                            radius: parent.radius
                            level: area.containsMouse && entry.modelData.enabled ? 1 : 0
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Glyph {
                        visible: entry.modelData.buttonType !== QsMenuButtonType.None
                        cp: entry.modelData.buttonType === QsMenuButtonType.RadioButton ? (entry.modelData.checkState === Qt.Checked ? 0xF043E : 0xF0130) : (entry.modelData.checkState === Qt.Checked ? 0xF0132 : 0xF0131)
                        Layout.preferredWidth: Theme.iconCell
                        Layout.alignment: Qt.AlignVCenter
                        font.pixelSize: 15
                        color: Theme.fg
                    }

                    IconImage {
                        visible: source !== "" && status === Image.Ready
                        implicitSize: Theme.iconSize
                        source: root.iconSource(entry.modelData.icon)
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.clean(entry.modelData.text)
                        // tray apps write these labels; a < in one must not start rich text (review 4)
                        textFormat: Text.PlainText
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        color: Theme.fg
                    }

                    Glyph {
                        visible: entry.modelData.hasChildren
                        cp: 0xF0142
                        Layout.preferredWidth: Theme.iconCell
                        Layout.alignment: Qt.AlignVCenter
                        font.pixelSize: 15
                        color: Theme.fgMuted
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!entry.modelData.enabled)
                            return;
                        if (entry.modelData.hasChildren) {
                            root.path = [...root.path, entry.modelData];
                        } else {
                            entry.modelData.triggered();
                            root.open = false;
                        }
                    }
                }
            }
        }
    }

    Text {
        visible: opener.children.values.length === 0
        Layout.margins: 8
        text: "No menu"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fgMuted
    }
}
