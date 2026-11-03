import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// One file a Sleepysettings tab writes (the Apply bar, the leave dialog, the Config tab): a file glyph, the
// directory muted and cut in the middle when the line is too long, the file name in the normal text colour,
// never cut. Nothing smaller than fontSize - 1. `onAccent` for a line on the accent surface (the
// keep-or-revert countdown).
// Click the path (the glyph and the text) and its absolute path goes to the clipboard: the text lights up under the pointer (a chip behind it, a Lift in a
// background holder so the text stays sharp), the tip says "Copy path", and the name says "Copied" for a
// moment. Two small icon buttons follow it, each with its own tip and hover: open in the editor (the one the
// Keybinds tab uses: Keybinds.openFile, `editor` of programs.lua, else the desktop default; greyed with the
// usual "Needs ..." while that program is missing) and show in the file manager (the file's folder through
// the desktop opener; greyed while that is missing). `clickable: false` leaves the two icons out, for a line
// that has its own buttons (the Config tab); the path still copies.
Item {
    id: fl
    property string path: ""
    property bool onAccent: false
    property bool clickable: true
    // the file is not there (the Config tab): its name is muted and "Not found" follows it
    property bool missing: false
    // the window's Tooltip (the Apply bar and the dialog pass it in); null: no tip
    property var tooltip: null
    readonly property int cut: path.lastIndexOf("/") + 1
    // the path as the clipboard gets it, ~ written out
    readonly property string full: fl.path.replace(/^~(?=\/|$)/, Quickshell.env("HOME"))
    // what the last click copied (the tests read it; the clipboard itself is the compositor's)
    property string lastCopied: ""
    property bool copied: false
    readonly property string needsText: Deps.needs([Keybinds.editorProgram])
    readonly property bool available: fl.needsText === ""
    readonly property bool hovered: pathMouse.containsMouse
    readonly property bool canReveal: Deps.has(Keybinds.openerProgram)
    // what the path area says now: the name, or "Copied" for a moment after a click (the tests read it)
    readonly property string shownText: fl.copied ? "Copied" : fl.path.slice(fl.cut)
    Layout.fillWidth: true
    Layout.preferredHeight: 20
    implicitHeight: 20
    // above its neighbours while lifted, so the shadow is not covered
    z: chip.z

    // the same actions the icons run (the tests call them too)
    function open() {
        if (fl.available)
            Keybinds.openFile(fl.path);
    }
    function reveal() {
        if (fl.canReveal)
            Keybinds.revealFile(fl.path);
    }
    function copy() {
        Quickshell.clipboardText = fl.full;
        fl.lastCopied = fl.full;
        fl.copied = true;
        copiedTimer.restart();
        if (fl.tooltip && fl.tooltip.anchor === chip)
            fl.tooltip.show(chip, "Copied", false);
    }

    Timer {
        id: copiedTimer
        interval: 1200
        onTriggered: fl.copied = false
    }

    // the chip behind the path (glyph, folder, name) reaches 6 px into the margin, so the glyph lines up with what is above
    Item {
        anchors.fill: parent

        Rectangle {
            id: chip
            x: -6
            y: 1
            width: Math.min(fl.width + 6, nameText.x + nameText.width + 4 + 6)
            height: fl.height - 2
            radius: Theme.radiusSm
            color: fl.hovered ? Theme.hoverBg : "transparent"

            Lift {
                radius: chip.radius
                level: fl.hovered ? 1 : 0
            }
        }
    }

    RowLayout {
        id: line
        anchors.fill: parent
        spacing: 6

        // md-file_document_outline
        Glyph {
            cp: 0xF09EE
            color: fl.onAccent ? Theme.accentFg : Theme.fgMuted
        }

        // grows only as far as its text, so the name follows right after it; a long directory is
        // shortened in the middle. Its natural width is measured (TextMetrics) and not read from the Text:
        // an elided Text's implicit width followed the width it was given, and the directory stayed cut
        // with room to spare (seen on the Config tab).
        TextMetrics {
            id: dirMetrics
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            text: fl.path.slice(0, fl.cut)
        }

        Text {
            id: dirText
            objectName: "fileDir"
            // hidden, not removed, while "Copied" shows: the icons after it must stay where they are
            opacity: fl.copied ? 0 : 1
            Layout.fillWidth: true
            Layout.preferredWidth: Math.ceil(dirMetrics.advanceWidth) + 1
            Layout.maximumWidth: Math.ceil(dirMetrics.advanceWidth) + 1
            Layout.minimumWidth: 24
            elide: Text.ElideMiddle
            text: fl.path.slice(0, fl.cut)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            color: fl.onAccent ? Qt.alpha(Theme.accentFg, 0.75) : Theme.fgMuted
        }

        // never elided: the name is what the line is for
        Text {
            id: nameText
            objectName: "fileName"
            Layout.leftMargin: -6
            opacity: fl.copied ? 0 : 1
            text: fl.path.slice(fl.cut)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            font.weight: Font.Medium
            color: fl.onAccent ? Theme.accentFg : fl.missing ? Theme.fgMuted : Theme.fg
        }

        Text {
            objectName: "notFound"
            visible: fl.missing
            text: "Not found"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            font.italic: true
            color: Theme.fgMuted
        }

        // the two actions, after the path
        Row {
            id: actions
            visible: fl.clickable
            spacing: 2

            FileAction {
                objectName: "editAction"
                glyph: 0xF11E7
                tip: fl.available ? "Open in editor" : fl.needsText
                tooltip: fl.tooltip
                enabled: fl.available
                onActivated: fl.open()
            }

            FileAction {
                objectName: "revealAction"
                glyph: 0xF0DCF
                tip: fl.canReveal ? "Show in file manager" : Deps.needs([Keybinds.openerProgram])
                tooltip: fl.tooltip
                enabled: fl.canReveal
                onActivated: fl.reveal()
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }

    // "Copied", over the path for a moment after a click (the path keeps its room, so nothing moves)
    Text {
        visible: fl.copied
        x: dirText.x
        anchors.verticalCenter: parent.verticalCenter
        text: "Copied"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
        font.weight: Font.Medium
        color: Theme.primary
    }

    // the path (glyph, folder and name) copies; the icons are separate click targets after it
    MouseArea {
        id: pathMouse
        x: chip.x
        y: chip.y
        width: chip.width
        height: chip.height
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: fl.copy()
        onContainsMouseChanged: {
            if (!fl.tooltip)
                return;
            if (containsMouse)
                fl.tooltip.show(chip, fl.copied ? "Copied" : "Copy path", false);
            else
                fl.tooltip.hide(chip);
        }
    }
}
