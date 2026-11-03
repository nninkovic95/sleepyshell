import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// The control centre's display brightness: one slider per output under the audio output
// and input, drawn like AudioPanel's rows: the laptop backlight when there is one, and every external
// monitor that answers DDC/CI (services/Brightness.qml `rows`). A row that cannot work is
// greyed with the reason under it (the backlight write needs busctl, DDC needs access to the display bus).
// `active` is the control centre being open: the DDC levels are read then, not polled.
ColumnLayout {
    id: root
    property bool active: false
    // the laptop backlight only: monitors over DDC are set on the Display tab's monitor page,
    // not here
    readonly property var shownRows: (Brightness.rows ?? []).filter(r => r.kind !== "ddc")
    visible: shownRows.length > 0
    spacing: 6
    Layout.fillWidth: true

    onActiveChanged: if (active)
        Brightness.readDdc()

    Text {
        Layout.leftMargin: 8
        text: "Display"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.bold: true
        color: Theme.fg
    }

    // the model is the rows' keys, not the rows: every change of a level makes new row objects, which
    // would rebuild the slider under the pointer; ScriptModel keeps a delegate while its key stays
    Repeater {
        model: ScriptModel {
            values: root.shownRows.map(r => r.kind + ":" + r.id)
        }

        ColumnLayout {
            id: row
            required property string modelData
            readonly property var info: root.shownRows.find(r => r.kind + ":" + r.id === row.modelData) ?? ({ kind: "", id: "", label: "", level: -1, ok: false, reason: "" })
            readonly property bool known: row.info.level >= 0
            Layout.fillWidth: true
            spacing: 2
            enabled: row.info.ok
            opacity: row.info.ok ? 1 : 0.5

            // the monitor's model; the lone laptop panel needs no name
            Text {
                visible: root.shownRows.length > 1 || row.info.kind === "ddc"
                Layout.leftMargin: 8
                text: row.info.label
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
                color: Theme.fgMuted
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 8

                // the sun glyph in the slot AudioPanel gives its mute button; a click goes to full or low
                BarButton {
                    glyph: row.info.level > 0.66 ? 0xF00E0 : row.info.level > 0.33 ? 0xF00DF : 0xF00DE
                    hpad: 6
                    glued: false
                    onClicked: Brightness.setOutput(row.info.kind, row.info.id, row.info.level > 0.5 ? 0.1 : 1)
                }

                VSlider {
                    Layout.fillWidth: true
                    value: Math.max(0, row.info.level)
                    text: row.known ? Math.round(row.info.level * 100) + "%" : "-"
                    textWidth: 52
                    textColor: Theme.fg
                    // one wheel notch is 5 %, the backlight's floor is Brightness.floorRaw
                    onMoved: v => Brightness.setOutput(row.info.kind, row.info.id, v)
                }
            }
        }
    }

    // the reasons, one line each, under the sliders
    Repeater {
        model: ScriptModel {
            values: root.shownRows.filter(r => r.reason !== "").map(r => (root.shownRows.length > 1 ? r.label + ": " : "") + r.reason)
        }

        Text {
            required property string modelData
            Layout.leftMargin: 8
            text: modelData
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
            color: Theme.fgMuted
        }
    }
}
