import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.components
import qs.services

// Wallpaper picker: a thumbnail grid of Settings.wallpaperDir (~/Pictures/Wallpapers by default) in a layer surface under the bar
// (same surface kind, focus grab and Popouts bookkeeping as IslandDropdown.qml). A click runs
// scripts/theme.py <path>, which sets the wallpaper (awww) and derives the matugen palette in one
// call; Shuffle runs it without a path (random image). The file list and the image awww shows
// are re-read each time the picker opens. Thumbnails decode at 300x170 so 4K originals stay small.
PanelWindow {
    id: root
    required property var bar
    property string name: "wallpaper"
    property bool open: false
    property var files: []
    property string current: ""        // image awww shows on this screen, "" when unknown
    property string hoveredPath: ""
    readonly property string dir: Settings.wallpaperDir.replace(/^~(?=\/|$)/, Quickshell.env("HOME"))
    readonly property int pad: 10
    readonly property int thumbW: 150
    readonly property int thumbH: 84
    readonly property int thumbRadius: Theme.radiusMd
    readonly property int gap: 8
    readonly property int gridW: 4 * thumbW + 3 * gap
    readonly property int gridH: 4 * thumbH + 3 * gap

    screen: bar.screen
    visible: open
    color: "transparent"
    anchors.top: true
    anchors.left: true
    margins.top: Theme.barHeight + 16
    margins.left: Math.round((bar.screen.width - implicitWidth) / 2)
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: gridW + pad * 2
    implicitHeight: col.implicitHeight + pad * 2
    WlrLayershell.namespace: "sleepyshell-popup"
    WlrLayershell.layer: WlrLayer.Top

    Component.onCompleted: Popouts.register(name, root)
    Component.onDestruction: Popouts.unregister(name, root)

    function pick(path) {
        open = false;
        Quickshell.execDetached([Quickshell.shellPath("scripts/theme.py"), path]);
    }

    function shuffle() {
        open = false;
        Quickshell.execDetached([Quickshell.shellPath("scripts/theme.py")]);
    }

    function setFiles(out) {
        const list = out.split("\n").filter(p => p !== "").sort((a, b) => a.localeCompare(b));
        // an empty or missing folder shows Hyprland's own wallpapers instead, like scripts/theme.py
        if (list.length === 0 && !fallbackLister.running) {
            fallbackLister.running = true;
            return;
        }
        if (list.join("\n") !== files.join("\n"))
            files = list;
    }

    // lines look like ": DP-1: 2560x1440, scale: 1, currently displaying: image: /path/file.png";
    // prefer this screen's line, else the first one that shows an image (not a plain colour)
    function setCurrent(out) {
        let cur = "";
        for (const line of out.split("\n")) {
            const i = line.indexOf("image: ");
            if (i >= 0 && (cur === "" || line.includes(" " + bar.screen.name + ": ")))
                cur = line.slice(i + 7).trim();
        }
        current = cur;
    }

    Process {
        id: lister
        command: ["find", root.dir, "-type", "f", "(", "-iname", "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.webp", ")"]
        stdout: StdioCollector {
            onStreamFinished: root.setFiles(text)
        }
    }

    Process {
        id: fallbackLister
        command: ["find", "/usr/share/hypr", "-maxdepth", "1", "-name", "wall*.png"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(p => p !== "").sort((a, b) => a.localeCompare(b));
                if (list.join("\n") !== root.files.join("\n"))
                    root.files = list;
            }
        }
    }

    Process {
        id: query
        command: ["sh", "-c", "awww query 2>/dev/null || swww query 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.setCurrent(text)
        }
    }

    HyprlandFocusGrab {
        id: grab
        windows: [root, root.bar]
        onCleared: root.open = false
    }

    Timer {
        id: armGrab
        interval: 80
        onTriggered: grab.active = root.open
    }

    onOpenChanged: {
        if (open) {
            Popouts.opened(root);
            armGrab.restart();
            lister.running = true;
            query.running = true;
        } else {
            grab.active = false;
            hoveredPath = "";
            Popouts.closed(root);
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusXl
        color: Theme.popupBg
        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }

        // one alpha mask shared by every thumbnail's MultiEffect (only its alpha is read): a layer
        // so the effects can sample it as a texture, hidden so it is not painted itself
        Rectangle {
            id: thumbMask
            width: root.thumbW
            height: root.thumbH
            radius: root.thumbRadius
            color: Theme.fg
            layer.enabled: true
            visible: false
        }

        ColumnLayout {
            id: col
            x: root.pad
            y: root.pad
            width: root.gridW
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 8

                Text {
                    text: "Wallpapers"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.fg
                }

                Text {
                    text: root.files.length
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    color: Theme.fgMuted
                }

                Text {
                    Layout.fillWidth: true
                    text: root.hoveredPath.split("/").pop()
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.fgMuted
                }

                BarButton {
                    glyph: 0xF049E
                    text: "Shuffle"
                    glyphFirst: true
                    glued: false
                    onClicked: root.shuffle()
                }
            }

            // GridView needs a whole number of cells per row, so it is one gap wider than the
            // visible area; the wrapper clips that trailing gap.
            Item {
                Layout.preferredWidth: root.gridW
                Layout.preferredHeight: root.gridH
                clip: true

                GridView {
                    id: grid
                    width: root.gridW + root.gap
                    height: root.gridH
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cellWidth: root.thumbW + root.gap
                    cellHeight: root.thumbH + root.gap
                    model: root.files

                    delegate: Item {
                        id: cell
                        required property string modelData
                        // thumbnail-sized, not cell-sized: the cell's extra width and height are the gaps
                        width: root.thumbW
                        height: root.thumbH

                        // on the cell that holds the masked layer, so the mask scales with it
                        Lift {
                            radius: root.thumbRadius
                            tilt: true
                            pointer: mouse
                            level: mouse.containsMouse ? 1 : 0
                        }

                        // a layer, so the shared mask rounds the image and the hover overlay together
                        Rectangle {
                            anchors.fill: parent
                            color: Theme.tileBg
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: thumbMask
                            }

                            Image {
                                anchors.fill: parent
                                source: "file://" + cell.modelData.split("/").map(encodeURIComponent).join("/")
                                sourceSize: Qt.size(300, 170)
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Theme.hoverBg
                                visible: mouse.containsMouse
                            }
                        }

                        // outside the layer so the mask cannot cut it; same radius as the mask
                        Rectangle {
                            anchors.fill: parent
                            radius: root.thumbRadius
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.primary
                            visible: cell.modelData === root.current
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.hoveredPath = cell.modelData
                            onExited: {
                                if (root.hoveredPath === cell.modelData)
                                    root.hoveredPath = "";
                            }
                            onClicked: root.pick(cell.modelData)
                        }
                    }
                }
            }
        }
    }
}
