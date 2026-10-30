import QtQuick
import qs
import qs.components

// A small icon button on a file chip (open in the editor, or show in the file
// manager): a glyph in a 22 x 18 box that lights up under the pointer (a Lift in a background holder, so
// the glyph stays sharp) and says what it does in the window's Tooltip. `enabled: false` greys it.
Item {
    id: fa
    property int glyph: 0
    property string tip: ""
    property var tooltip: null
    signal activated()
    implicitWidth: 22
    implicitHeight: 18
    // above its neighbours while lifted, so the shadow is not covered
    z: face.z
    opacity: fa.enabled ? 1 : 0.4

    Item {
        anchors.fill: parent

        Rectangle {
            id: face
            anchors.fill: parent
            radius: Theme.radiusXs
            color: area.containsMouse && fa.enabled ? Theme.hoverBg : "transparent"

            Lift {
                radius: face.radius
                level: area.containsMouse && fa.enabled ? 1 : 0
            }
        }
    }

    Glyph {
        anchors.centerIn: parent
        cp: fa.glyph
        width: implicitWidth
        font.pixelSize: 14
        color: area.containsMouse && fa.enabled ? Theme.fg : Theme.fgMuted
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: fa.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (fa.enabled) fa.activated()
        onContainsMouseChanged: {
            if (!fa.tooltip)
                return;
            if (containsMouse)
                fa.tooltip.show(fa, fa.tip, false);
            else
                fa.tooltip.hide(fa);
        }
    }
}
