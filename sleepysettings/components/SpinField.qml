import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// A number as a spin field (sliders are only for the values that are really
// continuous): a - button, a typed number, a + button, the unit. Typing is checked when it is
// done (Enter or focus loss): the text is read as a number, snapped to `step` and clamped to
// min..max, and an unreadable text falls back to the current value. Holding - or + repeats, the
// mouse wheel over the number steps once per notch. The parent stages the result in onMoved
// (NumberRow does, so it stays a staged edit like every other).
RowLayout {
    id: sp
    property real value: 0
    property real min: 0
    property real max: 1
    property real step: 1
    property string suffix: ""
    signal moved(real v)

    spacing: 4

    function fmt(v) {
        return sp.step >= 1 ? String(Math.round(v)) : Number(v).toFixed(2);
    }

    // v snapped to the step grid and clamped, without float noise (0.05 steps)
    function snap(v) {
        const s = Math.round(v / sp.step) * sp.step;
        return Math.max(sp.min, Math.min(sp.max, Number(s.toFixed(4))));
    }

    function stepBy(dir) {
        const v = sp.snap(sp.value + dir * sp.step);
        if (v !== sp.value)
            sp.moved(v);
    }

    // the typed text becomes the value; whatever it was, the field then shows the real value
    function finish() {
        const t = box.text.trim().replace(",", ".");
        const n = t === "" || t === "-" || t === "." ? NaN : Number(t);
        if (!isNaN(n)) {
            const v = sp.snap(n);
            if (v !== sp.value)
                sp.moved(v);
        }
        box.text = sp.fmt(sp.value);
    }

    // - and +; the pressed one steps at once, then repeats after a pause while held
    component StepButton: Item {
        id: sb
        required property int dir
        required property int glyph
        readonly property bool atLimit: dir < 0 ? sp.value <= sp.min : sp.value >= sp.max
        implicitWidth: 30
        implicitHeight: 30
        property real radius: Theme.radiusSm
        opacity: atLimit ? 0.35 : 1
        // above its neighbours while lifted, so the shadow is not covered
        z: surface.z

        // only the background lifts; the glyph stays at scale 1 and sharp.
        // The holder keeps the lifted surface (z 1) from covering it.
        Item {
            anchors.fill: parent

            Rectangle {
                id: surface
                anchors.fill: parent
                radius: sb.radius
                color: area.pressed || area.containsMouse ? Theme.hoverBg : Theme.tileBg

                Lift {
                    level: area.containsMouse && !sb.atLimit ? 1 : 0
                    radius: sb.radius
                }
            }
        }

        Glyph {
            anchors.centerIn: parent
            cp: sb.glyph
            color: Theme.fg
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: {
                sp.finish();
                sp.stepBy(sb.dir);
                hold.dir = sb.dir;
                hold.interval = 400;
                hold.restart();
            }
            onReleased: hold.stop()
            onCanceled: hold.stop()
        }
    }

    Timer {
        id: hold
        property int dir: 1
        repeat: true
        onTriggered: {
            interval = 70;
            sp.stepBy(dir);
        }
    }

    StepButton {
        dir: -1
        glyph: 0xF0374
    }

    TextBox {
        id: box
        Layout.fillWidth: false
        Layout.preferredWidth: 60
        input.horizontalAlignment: TextInput.AlignHCenter
        input.validator: RegularExpressionValidator {
            regularExpression: sp.step >= 1 ? /^-?\d{0,6}$/ : /^-?\d{0,6}([.,]\d{0,2})?$/
        }
        input.selectByMouse: true
        onFinished: sp.finish()

        // follows the value unless it is being typed in
        Binding {
            target: box
            property: "text"
            value: sp.fmt(sp.value)
            when: !box.input.activeFocus
            // keep the number in the field when it gets the focus; the default put back the empty text the
            // field had before the Binding, so a click into it emptied it
            restoreMode: Binding.RestoreNone
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: w => {
                if (w.angleDelta.y !== 0) {
                    sp.finish();
                    sp.stepBy(w.angleDelta.y > 0 ? 1 : -1);
                }
            }
        }
    }

    StepButton {
        dir: 1
        glyph: 0xF0415
    }

    Text {
        visible: text !== ""
        text: sp.suffix.trim()
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fgMuted
    }

    Item {
        Layout.fillWidth: true
    }
}
