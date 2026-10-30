import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services

// Session menu: lock, suspend, log out, reboot, shut down. There is no "Display off" entry
// (hypridle turns the displays off on idle).
// A full-screen overlay on the focused monitor, the backdrop dimmed and blurred (namespace
// sleepyshell-session, matched by the sleepyshell blur rule) and fading in, the uptime line, and
// five big buttons (SessionButton) that rise in one after another. No clock, date or greeting.
// A much darker backdrop, the cards on one
// frosted rounded panel with a quiet key footer inside it, the uptime as a caption pill above.
//
// Log out, reboot and shut down must be held for 600 ms (a ring fills around the icon), so one
// stray click or key press cannot end the session; a tap only shows the hint line. Lock and suspend
// run at once. Opened by the bar's Power button, SUPER + ESCAPE and
// `qs -c sleepyshell ipc call sleepybar toggle session`. Keys: the letter on each button (hold it for
// the three above), arrows or Tab to move, Enter or Space to run (hold) the selected one, Escape
// or a click on the backdrop to close.
Scope {
    id: root
    property string name: "session"
    property bool open: false
    property int sel: 0
    // the selection came from the keyboard (shows the focus ring); a pointer move clears it
    property bool kbd: false
    // button currently held down by the pointer or a key (-1 none), and the key that holds it
    property int held: -1
    property int heldKey: 0
    // line under the buttons: the refused-tap hint, else the key help
    property string hint: ""
    readonly property var bar: null     // no anchor bar; Popouts.toggle falls back to this one

    readonly property var actions: [
        {
            label: "Lock",
            key: "l",
            icon: 0xF033E,
            cmd: "loginctl lock-session"
        },
        {
            label: "Sleep",
            key: "z",
            icon: 0xF04B2,
            cmd: "systemctl suspend"
        },
        {
            label: "Log out",
            key: "e",
            icon: 0xF0343,
            cmd: "uwsm stop",
            danger: true
        },
        {
            label: "Reboot",
            key: "r",
            icon: 0xF0709,
            cmd: "systemctl reboot",
            danger: true
        },
        {
            label: "Shut down",
            key: "s",
            icon: 0xF0425,
            cmd: "systemctl poweroff",
            danger: true
        }
    ]

    function run(i) {
        held = -1;
        open = false;
        Quickshell.execDetached(["sh", "-c", actions[i].cmd]);
    }

    // a danger button runs only after its ring is full (SessionButton.confirmed)
    function beginHold(i) {
        const b = rep.itemAt(i);
        // only one button can be held: an earlier one keeps pressing otherwise, and its ring
        // would finish and run it without its own hold
        for (let j = 0; j < rep.count; j++) {
            if (j !== i)
                rep.itemAt(j).pressing = false;
        }
        sel = i;
        held = i;
        hint = "";
        b.pressing = true;
    }

    // released before the ring was full: drain it, shake the button, say what is needed
    function endHold() {
        if (held < 0)
            return;
        const i = held;
        const b = rep.itemAt(i);
        held = -1;
        heldKey = 0;
        if (!b.pressing)
            return;
        b.pressing = false;
        if (b.hold > 0.02 && b.hold < 1) {
            hint = "Hold to " + actions[i].label.toLowerCase();
            hintTimer.restart();
            b.nudge();
        }
    }

    // keyboard and test entry points: one place for what a key press and release do
    function activate(i) {
        if (actions[i].danger)
            beginHold(i);
        else
            run(i);
    }

    function keyDown(key, text, shift, repeat) {
        const n = actions.length;
        kbd = true;
        if (key === Qt.Key_Escape) {
            open = false;
        } else if (key === Qt.Key_Right || (key === Qt.Key_Tab && !shift)) {
            endHold();
            sel = (sel + 1) % n;
        } else if (key === Qt.Key_Left || key === Qt.Key_Backtab || (key === Qt.Key_Tab && shift)) {
            endHold();
            sel = (sel + n - 1) % n;
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            // key repeat of a held key must not restart the ring or run a button twice
            if (!repeat) {
                heldKey = key;
                activate(sel);
            }
        } else {
            const i = actions.findIndex(a => a.key === text.toLowerCase());
            if (i < 0)
                return false;
            if (!repeat) {
                heldKey = key;
                activate(i);
            }
        }
        return true;
    }

    function keyUp(key, repeat) {
        if (!repeat && key === heldKey)
            endHold();
    }

    Component.onCompleted: Popouts.register(name, root)
    Component.onDestruction: Popouts.unregister(name, root)
    onOpenChanged: {
        held = -1;
        heldKey = 0;
        hint = "";
        if (open) {
            sel = 0;
            kbd = false;
            win.screen = Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0];
            uptimeFile.reload();
            Popouts.opened(root);
        } else {
            Popouts.closed(root);
        }
    }

    Timer {
        id: hintTimer
        interval: 1800
        onTriggered: root.hint = ""
    }

    // uptime straight from the kernel, no process; refreshed while open
    property string up: ""
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        // "up 5 h 21 min": days, hours and minutes, leaving off the leading zeros
        onLoaded: {
            const m = Math.floor(parseFloat(text().split(" ")[0] || "0") / 60);
            const d = Math.floor(m / 1440), h = Math.floor(m % 1440 / 60), r = m % 60;
            root.up = "up " + (d > 0 ? d + " d " : "") + (d > 0 || h > 0 ? h + " h " : "") + r + " min";
        }
    }
    Timer {
        interval: 30000
        repeat: true
        running: root.open
        onTriggered: uptimeFile.reload()
    }

    PanelWindow {
        id: win
        // stays up while the fade-out runs
        visible: root.open || fade > 0.001
        // fixed when the menu opens (onOpenChanged), so focus moving to another monitor does not
        // drag an open menu along
        screen: Quickshell.screens[0]
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "sleepyshell-session"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // 0..1, eased: drives the backdrop, the uptime line and the hint
        property real fade: root.open ? 1 : 0
        Behavior on fade {
            NumberAnimation {
                duration: root.open ? 260 : 170
                easing.type: Easing.OutCubic
            }
        }

        readonly property int gap: 16
        readonly property int panelPad: 28
        // five cards across inside the panel, shrinking on a narrow screen
        readonly property int bw: Math.round(Math.max(104, Math.min(164, (width - 96 - 2 * panelPad - 4 * gap) / 5)))

        onVisibleChanged: if (visible) keys.forceActiveFocus()

        // much darker than the desktop: the desktop text
        // behind showed through and competed with the buttons, and the blur is weak here
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.surface, 0.97)
            opacity: win.fade

            MouseArea {
                anchors.fill: parent
                onClicked: root.open = false
            }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => e.accepted = root.keyDown(e.key, e.text, (e.modifiers & Qt.ShiftModifier) !== 0, e.isAutoRepeat)
            Keys.onReleased: e => {
                root.keyUp(e.key, e.isAutoRepeat);
                e.accepted = true;
            }
        }

        // positions are whole pixels throughout: fractional ones blur text
        Column {
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2) - 24
            spacing: 0

            // the only header: how long the machine has been up, as a small caption pill; it
            // settles from above as the backdrop fades in (no clock, date or
            // greeting on this screen)
            Rectangle {
                x: Math.round((parent.width - width) / 2)
                width: Math.round(upText.implicitWidth) + 28
                height: Math.ceil(upText.implicitHeight) + 12
                radius: height / 2
                color: Theme.tileBg
                border.width: 1
                border.color: Theme.tileBg
                opacity: win.fade
                transform: Translate {
                    y: Math.round((1 - win.fade) * -16)
                }

                Text {
                    id: upText
                    x: Math.round((parent.width - width) / 2)
                    y: Math.round((parent.height - height) / 2)
                    text: root.up
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.letterSpacing: 1
                    color: Theme.fgMuted
                }
            }

            Item {
                width: 1
                height: 22
            }

            // the frosted panel that holds the cards and the footer
            Rectangle {
                id: panel
                width: cards.width + 2 * win.panelPad
                height: win.panelPad + cards.height + 22 + footer.height + 22
                radius: Theme.radiusXxl
                color: Theme.popupBg
                border.width: 1
                border.color: Theme.hoverBg
                opacity: win.fade
                transform: Translate {
                    y: Math.round((1 - win.fade) * 14)
                }

                Row {
                    id: cards
                    x: win.panelPad
                    y: win.panelPad
                    spacing: win.gap

                    Repeater {
                        id: rep
                        model: root.actions

                        SessionButton {
                            width: win.bw
                            active: root.sel === index
                            keyboard: root.kbd
                            shown: root.open
                            onHovered: {
                                root.kbd = false;
                                if (root.held < 0)
                                    root.sel = index;
                            }
                            onDown: if (modelData.danger) {
                                root.heldKey = 0;   // a key's release must not cancel this mouse hold
                                root.beginHold(index);
                            }
                            onUp: root.endHold()
                            onClicked: if (!modelData.danger)
                                root.run(index)
                            onConfirmed: root.run(index)
                        }
                    }
                }

                // a quiet footer: the refused-tap hint or the hold message when there is one, else
                // the key help with small key caps
                Item {
                    id: footer
                    y: win.panelPad + cards.height + 22
                    width: panel.width
                    height: 22

                    readonly property bool msg: root.held >= 0 || root.hint !== ""

                    Row {
                        x: Math.round((parent.width - width) / 2)
                        spacing: 20
                        opacity: footer.msg ? 0 : 1
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 120
                            }
                        }

                        Repeater {
                            model: [["Esc", "close"], ["\u2190 \u2192", "move"], ["Enter", "run"]]

                            Row {
                                id: tip
                                required property var modelData
                                spacing: 8
                                height: 22

                                Rectangle {
                                    width: Math.round(capText.implicitWidth) + 14
                                    height: 20
                                    y: 1
                                    radius: Theme.radiusXs
                                    color: Theme.tileBg
                                    border.width: 1
                                    border.color: Theme.trackBg

                                    Text {
                                        id: capText
                                        x: Math.round((parent.width - width) / 2)
                                        y: Math.round((parent.height - height) / 2)
                                        text: tip.modelData[0]
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize - 2
                                        color: Theme.fgMuted
                                    }
                                }

                                Text {
                                    y: Math.round((parent.height - height) / 2)
                                    text: tip.modelData[1]
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 1
                                    color: Theme.fgMuted
                                }
                            }
                        }
                    }

                    Text {
                        x: Math.round((parent.width - width) / 2)
                        y: Math.round((parent.height - height) / 2)
                        text: root.held >= 0 ? "Keep holding to " + root.actions[root.held].label.toLowerCase() : root.hint
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 1
                        font.weight: Font.Medium
                        color: Theme.urgentFg
                        opacity: footer.msg ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 120
                            }
                        }
                    }
                }
            }
        }
    }
}
