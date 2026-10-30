import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// A value picked from a list. The list is drawn by the window's Picker overlay (passed in as
// picker), so it can reach past the tab's bounds. options: [{value, label}].
Item {
    id: cb
    required property var picker
    property var options: []
    property var value
    signal picked(var v)
    // the shown option (null when `value` is none of them); headers are never one
    readonly property var shown: options.find(x => x.header !== true && x.value === value) ?? null
    readonly property string current: cb.shown ? cb.shown.label : String(value)
    Layout.fillWidth: true
    implicitHeight: 30
    property real radius: Theme.radiusSm
    // above its neighbours while lifted, so the shadow is not covered
    z: surface.z

    // only the field's background lifts; the text and chevron stay at scale 1 and sharp
    // The holder keeps the lifted surface (z 1) from covering them.
    Item {
        anchors.fill: parent

        Rectangle {
            id: surface
            anchors.fill: parent
            radius: cb.radius
            color: cbMouse.containsMouse || (cb.picker && cb.picker.target === cb) ? Theme.hoverBg : Theme.tileBg

            Lift {
                radius: cb.radius
                level: cbMouse.containsMouse ? 1 : 0
            }
        }
    }

    // the shown option's colours or pictures (OptionMarks), left of the chevron
    OptionMarks {
        id: marks
        anchors.right: chevron.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        strip: cb.shown ? (cb.shown.strip ?? []) : []
        images: cb.shown ? (cb.shown.images ?? []) : []
        // tiny and few: the list has the full strip
        imageSize: 14
        maxImages: 4
    }

    Text {
        anchors.left: parent.left
        anchors.right: marks.visible ? marks.left : chevron.left
        anchors.rightMargin: marks.visible ? 8 : 0
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: cb.current
        font.family: cb.shown && cb.shown.fontFamily ? cb.shown.fontFamily : Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fg
    }

    Glyph {
        id: chevron
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        cp: 0xF0140
    }

    MouseArea {
        id: cbMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cb.picker.show(cb)
    }
}
