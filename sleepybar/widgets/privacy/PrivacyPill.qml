import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services
import qs.sleepybar.components

// Privacy indicator for the right island: the glyphs of what is being captured (microphone, camera,
// screen share) in the primary colour, and nothing at all, no width and no gap, when nothing is.
// Click opens a dropdown with one row per app and what it uses; hover only highlights.
// What counts as "in use" is decided in Privacy.qml.
BarButton {
    id: root
    required property var bar
    // `shown` is what the right island's Loader follows (Sleepybar.qml); `visible` alone left the
    // Loader its width and the row its gap while nothing was captured (review 3, F1)
    readonly property bool shown: Privacy.anyActive
    visible: shown
    glyphText: Privacy.barGlyphs
    fg: Theme.primary
    inset: true
    bg: pop.open ? Theme.hoverBg : "transparent"
    onClicked: pop.toggle()

    // the list would be stale (and empty) once the last capture stops
    onVisibleChanged: {
        if (!visible)
            pop.open = false;
    }

    IslandDropdown {
        id: pop
        name: "privacy"
        fixedWidth: 260
        anchorItem: root
        bar: root.bar

        Repeater {
            model: Privacy.rows

            RowLayout {
                id: entry
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: entry.modelData.app
                        textFormat: Text.PlainText   // PipeWire client names (review 4)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        color: Theme.fg
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: entry.modelData.uses
                        textFormat: Text.PlainText
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.fgMuted
                    }
                }

                Glyph {
                    Layout.alignment: Qt.AlignVCenter
                    text: entry.modelData.glyphs
                    color: Theme.primary
                }
            }
        }
    }
}
