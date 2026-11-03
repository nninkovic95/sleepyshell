import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// What is wrong with the files a tab, a section or a row depends on (FileChecks), in plain words: one or two short
// sentences, no path in them, a "!" with the detail (the exact path, why), and the button that fixes it (FileActions). A file that Hyprland
// does not load shows the line to add to hyprland.lua on a row of its own: monospace, a click copies it and says "Copied" for a moment.
// Shows nothing while every file in `ids` is fine. A problem that greys the rest (`grey`) is drawn in the alert colour, one that only
// offers its fix in the accent. `compact` is the form under a settings row: no card, no glyph.
ColumnLayout {
    id: notice
    objectName: "fileNotice"
    // FileChecks ids, in the order they are shown
    property var ids: []
    property var tooltip: null
    property bool compact: false
    // one short sentence and a button to the Config tab, where the fix is (the Keybinds tab)
    property bool brief: false
    readonly property var list: FileChecks.problems(notice.ids)
    visible: notice.list.length > 0
    Layout.fillWidth: true
    spacing: 6

    Repeater {
        model: notice.list

        Rectangle {
            id: card
            required property var modelData
            objectName: "fileNoticeCard"
            property string fileId: modelData.id
            property string kind: modelData.kind
            // what the click on the line copied last (the tests read it)
            property string lastCopied: ""
            property bool copied: false
            // the one-line version of the problem (notice.brief)
            readonly property string briefText: modelData.kind === "notLoaded" ? "Hyprland doesn't load your keybinds file yet." : modelData.kind === "needs" ? modelData.text : modelData.text.replace(/ (Change|Create|Set up)[^.]*\.$/, "")
            Layout.fillWidth: true
            implicitHeight: col.implicitHeight + (notice.compact ? 0 : 20)
            radius: Theme.radiusMd
            color: notice.compact ? "transparent" : Theme.container
            border.width: notice.compact ? 0 : 1
            border.color: Qt.alpha(modelData.grey ? Theme.urgentFg : Theme.primary, 0.4)

            Timer {
                id: copiedTimer
                interval: 1400
                onTriggered: card.copied = false
            }

            ColumnLayout {
                id: col
                x: notice.compact ? 0 : 12
                y: notice.compact ? 0 : 10
                width: parent.width - (notice.compact ? 0 : 24)
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Glyph {
                        visible: !notice.compact
                        Layout.alignment: Qt.AlignTop
                        cp: card.modelData.grey ? 0xF0026 : 0xF02FD
                        color: card.modelData.grey ? Theme.urgentFg : Theme.primary
                    }

                    Text {
                        objectName: "noticeText"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        textFormat: Text.StyledText
                        text: notice.brief ? card.briefText : card.modelData.text
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.fg
                    }

                    InfoTip {
                        objectName: "noticeTip"
                        Layout.alignment: Qt.AlignTop
                        tooltip: notice.tooltip
                        text: card.modelData.tip
                        warn: card.modelData.grey
                    }
                }

                // the line to add, on a row of its own; a click copies it
                Rectangle {
                    id: lineBox
                    visible: card.modelData.requireLine !== "" && !notice.brief
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.radiusSm
                    color: lineMouse.containsMouse ? Theme.hoverBg : Theme.tileBg

                    Text {
                        objectName: "noticeLine"
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                        text: card.copied ? "Copied" : card.modelData.requireLine
                        textFormat: Text.PlainText
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        color: card.copied ? Theme.primary : Theme.fg
                    }

                    MouseArea {
                        id: lineMouse
                        objectName: "noticeLineArea"
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.copyLine()
                        onContainsMouseChanged: {
                            if (!notice.tooltip)
                                return;
                            if (containsMouse)
                                notice.tooltip.show(lineBox, "Click to copy the line", false);
                            else
                                notice.tooltip.hide(lineBox);
                        }
                    }
                }

                // "Set up" did not work: one plain sentence, here until the file is fine or another try
                Text {
                    objectName: "noticeSetupNote"
                    visible: FileChecks.setupNote.id === card.modelData.id && !FileChecks.setupNote.ok
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: FileChecks.setupNote.text
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                    color: Theme.urgentFg
                }

                FileActions {
                    visible: !notice.brief
                    Layout.fillWidth: true
                    problem: card.modelData
                    tooltip: notice.tooltip
                }

                // the brief form: the way to the fix
                BarButton {
                    objectName: "fileConfigureBrief"
                    visible: notice.brief
                    text: card.modelData.kind === "notLoaded" ? "Set up in Config" : "Fix in Config"
                    glyph: 0xF107C
                    glyphFirst: true
                    glued: false
                    bg: Theme.hoverBg
                    onClicked: FileChecks.configureRequested(card.modelData.id)
                }
            }

            function copyLine() {
                Quickshell.clipboardText = card.modelData.requireLine;
                card.lastCopied = card.modelData.requireLine;
                card.copied = true;
                copiedTimer.restart();
            }
        }
    }
}
