import QtQuick
import qs
import qs.components

// Window-wide overlay that shows a Combo's options under it. Fill the window with it and put it
// above the tabs; Combo calls show(), a pick or a click outside closes it.
Item {
    id: picker
    property var target: null
    visible: target !== null
    z: 10

    function show(cb) {
        target = cb;
        // a menu button (the Config tab's "...") is narrower than its list: `menuWidth` is the list's width, `menuAlignRight` puts its right edge
        // under the button's
        const w = cb.menuWidth ?? cb.width;
        const p = cb.mapToItem(picker, cb.menuAlignRight === true ? cb.width - w : 0, cb.height + 4);
        const want = listView.contentHeight + 8;
        list.x = p.x;
        list.width = w;
        list.height = Math.min(want, Math.max(120, picker.height - p.y - 8));
        list.y = Math.min(p.y, picker.height - list.height - 8);
        const i = cb.options.findIndex(o => o.value === cb.value);
        listView.positionViewAtIndex(Math.max(0, i), ListView.Center);
    }

    function hide() {
        target = null;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: picker.hide()
    }

    Rectangle {
        id: list
        radius: Theme.radiusMd
        color: Theme.containerHigh
        border.width: 1
        border.color: Theme.containerHighest

        ListView {
            id: listView
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: picker.target ? picker.target.options : []

            delegate: Item {
                id: opt
                required property var modelData
                readonly property bool on: picker.target !== null && modelData.header !== true && modelData.value === picker.target.value
                width: listView.width
                // an option with `header: true` is a group title (the Theme tab's "Community themes"), not a choice
                readonly property bool isHeader: modelData.header === true
                height: isHeader ? 26 : 28
                property real radius: Theme.radiusSm
                // above its neighbours while lifted, so the shadow is not covered
                z: surface.z

                // only the row's background lifts; the label stays at scale 1 and sharp
                // The holder keeps the lifted surface (z 1) from covering it.
                Item {
                    anchors.fill: parent

                    Rectangle {
                        id: surface
                        anchors.fill: parent
                        radius: opt.radius
                        color: opt.isHeader ? "transparent" : optMouse.containsMouse ? Theme.hoverBg : opt.on ? Theme.tileBg : "transparent"

                        Lift {
                            radius: opt.radius
                            level: optMouse.containsMouse && !opt.isHeader ? 1 : 0
                        }
                    }
                }

                // an option may carry an `icon` (an Image source: the application pickers of the Apps tab)
                Image {
                    visible: (opt.modelData.icon ?? "") !== ""
                    source: opt.modelData.icon === "glyph:" ? "" : (opt.modelData.icon ?? "")
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    sourceSize: Qt.size(36, 36)
                    fillMode: Image.PreserveAspectFit

                    // no icon in the icon theme (DefaultApps.iconFor)
                    Glyph {
                        anchors.centerIn: parent
                        visible: opt.modelData.icon === "glyph:"
                        cp: 0xF08C6
                        width: implicitWidth
                        font.pixelSize: 16
                        color: Theme.fgMuted
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: (opt.modelData.icon ?? "") !== "" ? 34 : 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: opt.modelData.label
                    // an option may name a font family to draw its label in (the interface font list)
                    font.family: opt.modelData.fontFamily ?? Theme.font
                    font.pixelSize: opt.isHeader ? Theme.fontSize - 2 : Theme.fontSize
                    font.weight: opt.isHeader ? Font.Medium : opt.on ? Font.Medium : Font.Normal
                    font.capitalization: opt.isHeader ? Font.AllUppercase : Font.MixedCase
                    color: opt.isHeader ? Theme.fgMuted : opt.on ? Theme.primary : Theme.fg
                }

                // an option may carry colours (`strip`) or small pictures (`images`), left of its hint (the Theme tab's lists)
                OptionMarks {
                    anchors.right: optHint.left
                    anchors.rightMargin: optHint.text !== "" ? 10 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    strip: opt.modelData.strip ?? []
                    images: opt.modelData.images ?? []
                    imageSize: opt.modelData.imageSize ?? 16
                    maxImages: 6
                }

                // an option may carry a short `hint` (the Theme tab's colour schemes), muted at the right
                Text {
                    id: optHint
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: opt.modelData.hint ?? ""
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.fgMuted
                }

                MouseArea {
                    id: optMouse
                    anchors.fill: parent
                    enabled: !opt.isHeader
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const t = picker.target;
                        picker.hide();
                        t.picked(opt.modelData.value);
                    }
                }
            }
        }
    }
}
