import QtQuick
import qs

// Horizontal slider, 0..1, in the same family as the settings switch: a rounded-rectangle track (corners from
// the radius tokens, so it follows the Sharp / Standard / Rounded preset), an accent fill from the
// left, and at the end of the fill a rounded-square tab, the drag handle, in the switch's style (the
// same size relation to the track, corners concentric through Theme.nested, the same colours,
// shadow and hover lift). Drag or click anywhere on the track: the tab jumps under the pointer.
// Scroll for wheelStep (5 % by default; a settings slider sets one step of its range, else a short
// range rounded back to the same value).
//
// Step marks: thin vertical marks across the track, one on every step of the setting (`steps`: the
// schema's (max - min) / step for a settings slider, 1 / wheelStep for the volume and brightness,
// which move in 5 % notches), exactly where the tab stands at that value. Where the marks would be
// closer than 4 px only every Nth is drawn, still on step positions. The marks are drawn, they never
// limit the control: dragging, clicking
// and the wheel keep the full resolution of the value, and a settings slider snaps in its parent
// (NumberRow), never here. One thing the marks do: while every one of them is drawn and they are at
// least 10 px apart (`magnetic`), a drag lets go of the pointer's exact position and takes the mark
// when the pointer is within 4 px of it, and that mark lights up for a moment; between those zones the
// drag is free. Wheel and typing step and set as always.
//
// The value is written right of the track in a small field for typed
// input: click or Tab into it and type; Enter, leaving the field or a click elsewhere in the window
// sets it, Escape puts the old text back, text that is not a number is dropped. A number is read as a
// percent unless the parent passes `parseTyped` (a function from the text to 0..1, or NaN). The wheel
// over the field steps like over the track.
Item {
    id: root
    property real value: 0
    property bool muted: false
    property real wheelStep: 0.05
    // the value as words, in the field right of the track; the volume and brightness sliders keep
    // the percent, a settings slider passes its own formatted value
    property string text: Math.round(root.clamped * 100) + "%"
    property int textWidth: 44
    property color textColor: Theme.fgMuted
    // typed text to a value 0..1 (NaN: not a number); null: a percent
    property var parseTyped: null
    // how many steps the range has: one wheel notch is one step, so 1 / wheelStep unless a caller says otherwise
    property int steps: Math.max(1, Math.round(1 / root.wheelStep))
    readonly property real clamped: Math.max(0, Math.min(1, value))
    readonly property bool hovered: area.containsMouse || area.pressed
    // the track's thickness; the tab is that minus the inset on each side, the switch's relation
    readonly property int thick: 22
    readonly property int inset: 3
    readonly property int tabSize: thick - 2 * inset
    readonly property real trackRadius: Math.min(Theme.radiusSm, thick / 2)
    // where the tab travels: from the inset to the inset before the track's end
    readonly property real span: Math.max(1, track.width - tabSize - 2 * inset)
    // the mark spacing in px and how many steps lie between two drawn marks (1: all of them)
    readonly property real tickGap: root.span / root.steps
    readonly property int tickEvery: Math.max(1, Math.ceil(4 / Math.max(0.001, root.tickGap)))
    readonly property int tickCount: Math.floor(root.steps / root.tickEvery) + 1
    // all marks drawn and at least 10 px apart: a drag is pulled onto a mark within `pull` px
    readonly property bool magnetic: root.tickEvery === 1 && root.tickGap >= 10
    readonly property real pull: 4
    // the mark that was just taken (lit for a moment), -1 for none
    property int lit: -1
    // the filled part's width, the tab and the field (read by the tests)
    readonly property real trackWidth: track.width
    readonly property real fillWidth: fill.width
    readonly property real tabX: tab.x
    readonly property real tabWidth: tab.width
    readonly property real tabRadius: tab.radius
    readonly property alias field: field
    signal moved(real v)

    implicitWidth: 200
    implicitHeight: Math.max(thick, fieldBox.height)

    // where the tab's centre stands for step k (item coordinates)
    function xOfStep(k) {
        return root.inset + root.tabSize / 2 + k / root.steps * root.span;
    }

    // pointer x (in the item) to the value: the tab's centre follows the pointer, free at full
    // resolution, except that a magnetic slider takes the mark within `pull` px
    function setFromX(mx) {
        let v = Math.max(0, Math.min(1, (mx - inset - tabSize / 2) / span));
        if (root.magnetic) {
            const k = Math.round(v * root.steps);
            if (Math.abs(mx - root.xOfStep(k)) <= root.pull) {
                v = k / root.steps;
                root.lit = k;
                litTimer.restart();
            }
        }
        root.moved(v);
    }

    // one wheel notch up (dir > 0) or down; the pointer's wheel handler and the tests both use it
    function wheelBy(dir) {
        root.moved(Math.max(0, Math.min(1, root.value + (dir > 0 ? root.wheelStep : -root.wheelStep))));
    }

    // the typed text becomes the value, or is dropped; the field then shows the real value again.
    // Only text that was typed counts: leaving the field untouched must not turn the shown, rounded
    // value (37 %) into the value (a volume of 37.2 % would move)
    property bool typed: false
    function commitTyped() {
        if (!root.typed) {
            field.text = root.text;
            return;
        }
        root.typed = false;
        const t = field.text.trim().replace(",", ".");
        let f = NaN;
        if (root.parseTyped)
            f = root.parseTyped(t);
        else if (t !== "" && /^-?\d*\.?\d*\s*%?$/.test(t))
            f = Number(t.replace("%", "")) / 100;
        if (!isNaN(f))
            root.moved(Math.max(0, Math.min(1, f)));
        field.text = root.text;
    }

    Timer {
        id: litTimer
        interval: 450
        onTriggered: root.lit = -1
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - root.textWidth - 8
        height: root.thick
        radius: root.trackRadius
        color: Theme.trackBg

        // up to and including the tab, plus the inset, so at 0 it is a square cap behind the tab
        Rectangle {
            id: fill
            width: tab.x + tab.width + root.inset
            height: parent.height
            radius: parent.radius
            color: root.muted ? Theme.fgMuted : Theme.accent
        }

        // the step marks: short, centred, rounded; each is where the tab's centre stands at that value
        Repeater {
            model: root.tickCount

            Rectangle {
                id: mark
                required property int index
                readonly property real cx: root.xOfStep(mark.index * root.tickEvery)
                readonly property bool isLit: root.lit >= 0 && mark.index * root.tickEvery === root.lit
                x: mark.cx - width / 2
                y: (parent.height - height) / 2
                width: 2
                height: Math.round(root.thick / 2) + (mark.isLit ? 4 : 0)
                radius: width / 2
                // over the fill: light on the accent (grey, dark, when muted); over the empty track: muted;
                // the mark just taken is bright
                color: mark.isLit ? Theme.fg : mark.cx <= tab.x + tab.width / 2 + 0.5 ? (root.muted ? Qt.alpha(Theme.surface, 0.55) : Qt.alpha(Theme.accentFg, 0.38)) : Qt.alpha(Theme.fgMuted, 0.45)
                Behavior on height {
                    NumberAnimation {
                        duration: 90
                    }
                }
            }
        }

        // the tab: as the switch's, nothing inside; it lifts under the pointer
        Rectangle {
            id: tab
            width: root.tabSize
            height: root.tabSize
            y: root.inset
            x: root.inset + root.clamped * root.span
            radius: Math.min(Theme.nested(root.trackRadius, root.inset), height / 2)
            color: root.muted ? Theme.fg : Theme.accentFg

            Lift {
                radius: tab.radius
                level: root.hovered ? 1 : 0
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: track
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.setFromX(mouseX)
        onPositionChanged: {
            if (pressed)
                root.setFromX(mouseX);
        }
        onWheel: w => {
            if (w.angleDelta.y !== 0)
                root.wheelBy(w.angleDelta.y);
        }
    }

    // the value, typed: the SpinField's field without its - and + buttons
    Rectangle {
        id: fieldBox
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.textWidth
        height: 26
        radius: Theme.radiusSm
        color: field.activeFocus ? Theme.hoverBg : Theme.tileBg

        TextInput {
            id: field
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            color: Theme.fg
            selectionColor: Theme.accent
            selectedTextColor: Theme.accentFg
            // Tab reaches it from the row before
            activeFocusOnTab: true
            onTextEdited: root.typed = true
            onEditingFinished: root.commitTyped()
            // Escape drops what was typed and leaves the field; the window's own Escape (closing it)
            // is claimed first through shortcutOverride, so this first Escape only leaves the field
            Keys.onShortcutOverride: event => {
                if (event.key === Qt.Key_Escape)
                    event.accepted = true;
            }
            Keys.onEscapePressed: {
                root.typed = false;
                field.text = root.text;
                field.focus = false;
            }
        }

        // follows the value unless it is being typed in
        Binding {
            target: field
            property: "text"
            value: root.text
            when: !field.activeFocus
            // keep what is in the field when it gets the focus (the default would put back the empty text it had before)
            restoreMode: Binding.RestoreNone
        }

        // the wheel over the field steps like over the track
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: w => {
                if (w.angleDelta.y !== 0)
                    root.wheelBy(w.angleDelta.y);
            }
        }
    }
}
