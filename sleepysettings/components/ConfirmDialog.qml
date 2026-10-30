import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// In-window question shown when leaving a tab (or closing the window) with changes that only
// take effect after Apply. Fill the window with it; ask() shows it, and the chosen button runs
// applyFn or discardFn and then the pending action (nextFn, may be null). "Keep editing" just
// closes it. The two button labels can be given (the Display tab's countdown asks Keep / Revert);
// an empty discard label hides that button, and the first one ("Keep editing") can be renamed
// (the Config tab's Reset asks only Reset / Cancel).
// Same look as the Apply bar: the Section cards' surface and radiusLg, no red outline or "!";
// for the leave question (`extra`: { count, files }) the accent count pill beside the title and the
// files an Apply would write, as the Apply bar lists them; the same buttons (Keep editing a ghost,
// Discard quiet, Apply filled accent) and the same font sizes.
Item {
    id: dlg
    property string title: ""
    property string body: ""
    property var applyFn: null
    property var discardFn: null
    property var nextFn: null
    property string applyLabel: "Apply"
    property string discardLabel: "Discard"
    property string cancelLabel: "Keep editing"
    // the pending count and the files for a leave question (count 0 with files: a tab with its own draft shows a dot)
    property bool hasPending: false
    property int count: 0
    property var files: []
    // the window's Tooltip, for the file chips
    property var tooltip: null
    // a line shown under the text in a box of its own, monospace (the line "Set up" would add to hyprland.lua); "" for none
    property string line: ""
    visible: false
    z: 30

    function ask(t, b, apply, discard, next, applyText, discardText, cancelText, extra) {
        title = t;
        body = b;
        applyFn = apply;
        discardFn = discard;
        nextFn = next;
        line = "";
        applyLabel = applyText ?? "Apply";
        discardLabel = discardText ?? "Discard";
        cancelLabel = cancelText ?? "Keep editing";
        hasPending = extra !== undefined && extra !== null;
        count = hasPending ? (extra.count ?? 0) : 0;
        files = hasPending ? (extra.files ?? []) : [];
        visible = true;
    }

    // a question with a line to show, two buttons (the apply button and Cancel)
    function askLine(t, b, ln, apply, applyText) {
        ask(t, b, apply, null, null, applyText, "", "Cancel");
        line = ln;
    }

    function finish(fn) {
        visible = false;
        if (fn)
            fn();
        if (nextFn)
            nextFn();
    }

    // dims the window and swallows clicks
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.surface, 0.7)

        MouseArea {
            anchors.fill: parent
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 420
        height: content.implicitHeight + 36
        radius: Theme.radiusLg
        color: Theme.container

        ColumnLayout {
            id: content
            x: 18
            y: 18
            width: parent.width - 36
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: dlg.title
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                    font.weight: Font.Medium
                    color: Theme.fg
                }

                // the same marker as the sidebar entry and the Apply bar
                CountPill {
                    objectName: "dialogMark"
                    visible: dlg.hasPending
                    count: dlg.count
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: dlg.body
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: Theme.fgMuted
            }

            // the line, exactly as it will be written
            Rectangle {
                objectName: "dialogLine"
                visible: dlg.line !== ""
                Layout.fillWidth: true
                // several lines (the Apps tab's programs.lua change) grow the box; one line stays 30 px
                implicitHeight: Math.max(30, lineText.contentHeight + 14)
                radius: Theme.radiusSm
                color: Theme.tileBg

                Text {
                    id: lineText
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: dlg.line.indexOf("\n") >= 0 ? Text.WrapAnywhere : Text.NoWrap
                    elide: dlg.line.indexOf("\n") >= 0 ? Text.ElideNone : Text.ElideMiddle
                    text: dlg.line
                    textFormat: Text.PlainText
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    color: Theme.fg
                }
            }

            // what Apply would write
            ColumnLayout {
                visible: dlg.hasPending && dlg.files.length > 0
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    model: dlg.files

                    FileLine {
                        required property string modelData
                        path: modelData
                        tooltip: dlg.tooltip
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }

                // the quiet one: keep working
                BarButton {
                    text: dlg.cancelLabel
                    glued: false
                    hpad: 14
                    onClicked: dlg.visible = false
                }
                BarButton {
                    visible: dlg.discardLabel !== ""
                    text: dlg.discardLabel
                    glued: false
                    hpad: 14
                    bg: Qt.alpha(Theme.fg, 0.09)
                    onClicked: dlg.finish(dlg.discardFn)
                }
                BarButton {
                    text: dlg.applyLabel
                    glued: false
                    hpad: 18
                    bg: Theme.accent
                    fg: Theme.accentFg
                    onClicked: dlg.finish(dlg.applyFn)
                }
            }
        }
    }
}
