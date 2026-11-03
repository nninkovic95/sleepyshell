import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// A Combo whose options carry an application icon ({value, label, icon}; the Picker draws the icons too). Used by
// the Apps tab. With no options it is greyed and says `emptyText`; with no value it says `unsetText`.
Item {
    id: cb
    required property var picker
    property var options: []
    property var value
    property string emptyText: "No installed app handles this"
    property string unsetText: "Not set"
    signal picked(var v)
    readonly property var option: options.find(x => x.value === value) ?? null
    readonly property bool empty: options.length === 0
    Layout.fillWidth: true
    implicitHeight: 30
    property real radius: Theme.radiusSm
    enabled: !empty
    opacity: empty ? 0.5 : 1
    // above its neighbours while lifted, so the shadow is not covered
    z: surface.z

    // only the field's background lifts; the icon, text and chevron stay at scale 1 and sharp (CLAUDE.md, Hover)
    Item {
        anchors.fill: parent
        Rectangle {
            id: surface
            anchors.fill: parent
            radius: cb.radius
            color: cbMouse.containsMouse || (cb.picker && cb.picker.target === cb) ? Theme.hoverBg : Theme.tileBg
            Lift {
                radius: cb.radius
                level: cbMouse.containsMouse && !cb.empty ? 1 : 0
            }
        }
    }
    readonly property string iconSrc: cb.option ? (cb.option.icon ?? "") : ""
    Image {
        id: icon
        visible: cb.iconSrc !== ""
        source: cb.iconSrc === "glyph:" ? "" : cb.iconSrc
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
            visible: cb.iconSrc === "glyph:"
            cp: 0xF08C6
            width: implicitWidth
            font.pixelSize: 16
            color: Theme.fgMuted
        }
    }
    Text {
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.leftMargin: icon.visible ? 34 : 10
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: cb.empty ? cb.emptyText : cb.option ? cb.option.label : cb.value ? String(cb.value).replace(/\.desktop$/, "") : cb.unsetText
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: cb.empty || (!cb.option && !cb.value) ? Theme.fgMuted : Theme.fg
    }
    Glyph {
        id: chevron
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        cp: 0xF0140
        visible: !cb.empty
    }
    MouseArea {
        id: cbMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: cb.empty ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: if (!cb.empty)
            cb.picker.show(cb)
    }
}
