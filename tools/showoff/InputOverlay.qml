import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "KeyNames.js" as KeyNames

// Click circles and a shortcuts popup, for demo recordings: an expanding ring at the pointer on a left or right
// click, and a pill at the bottom centre naming the Hyprland shortcut used ("Super + 1", "Super + Shift + R") or
// the click ("Left click"). On while `on` is true (SUPER + SHIFT + K through showoff.sh keys).
//
// Nothing reads the keyboard or the mouse. Hyprland reports what happened as custom events on its own socket:
//   showoff:bind:<modmask>:<r|p>:<key>   a keyboard bind fired (showoff.lua, loaded by hyprland.lua, wraps hl.bind);
//                                  r: a repeating bind, whose re-fires while held count as one press
//                                  a click with a modifier (SUPER + drag) arrives here too, as key mouse:272
//   showoff:click:<button>         a plain click (272 left ... 276 forward), from pass-through binds added here
// Both exist only while this is on: switching on sets showoff_keys_on and adds the click binds through
// `hyprctl eval`, switching off clears the flag and removes exactly those binds. Typing and app shortcuts are
// never seen; a click with a modifier shows only when it is bound (a click bind that ignores modifiers
// blocked clicks).
// A "KEYS" pill shows while it is on, so it is never on unnoticed.
Scope {
    id: root

    property bool on: false
    // the colours of the pills and rings (shell.qml reads matugen's colours)
    property color fill: "#2f353e"
    property color text: "#dde3ee"
    property color leftRing: "#9dcaff"
    property color rightRing: "#ffb4ab"

    function toggle() {
        root.on = !root.on;
    }

    // ---- switching Hyprland's side on and off ----
    // the click binds are kept in a Lua table and removed through their own handles, so a click bind of the
    // user's is never touched; they are made with the unwrapped hl.bind, so showoff.lua does not report them twice
    readonly property string luaOff: "showoff_keys_on = false; for _, b in ipairs(showoff_clicks or {}) do pcall(function() b:remove() end) end; showoff_clicks = {}"
    readonly property string luaOn: root.luaOff + "; showoff_keys_on = true; for _, c in ipairs({ 272, 273, 274, 275, 276 }) do showoff_clicks[#showoff_clicks + 1] = (showoff_bind_original or hl.bind)(\"mouse:\" .. c, function() hl.dispatch(hl.dsp.event(\"showoff:click:\" .. c)) end, { non_consuming = true }) end"

    function hypr(code) {
        Quickshell.execDetached(["hyprctl", "eval", code]);
    }
    onOnChanged: root.hypr(root.on ? root.luaOn : root.luaOff)
    // a crash or kill while on would leave the flag and the click binds behind: cleared at every start and on exit
    Component.onCompleted: root.hypr(root.luaOff)
    Component.onDestruction: root.hypr(root.luaOff)

    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (!root.on || e.name !== "custom" || !e.data.startsWith("showoff:"))
                return;
            const parts = e.data.split(":");
            if (parts[1] === "bind" && parts.length >= 5)
                root.shortcut(Number(parts[2]), parts[3] === "r", parts.slice(4).join(":"));
            else if (parts[1] === "click")
                root.click(Number(parts[2]));
        }
    }

    // ---- events -> what to show (the words come from the shell's KeyNames.js) ----
    // a repeating bind fires every few tens of milliseconds while held: that is one press, as a held key
    // always was, so it only keeps the pill up
    property real lastFire: 0
    function shortcut(mask, repeating, key) {
        const now = Date.now(), since = now - root.lastFire;
        root.lastFire = now;
        const mods = KeyNames.mods(mask);
        const word = KeyNames.key(key);
        // a modifier on its own (SUPER_L as the key) is named once
        const text = (KeyNames.mod(key) !== undefined && mods.includes(word) ? mods : mods.concat([word])).join(" + ");
        if (repeating && text === root.label && since < 250) {
            hideTimer.restart();
            return;
        }
        root.show(text);
        // a click bound with a modifier (SUPER + drag) rings like a plain click
        const button = String(key).toLowerCase();
        if (button === "mouse:272" || button === "mouse:273")
            ring.ask(button === "mouse:272" ? root.leftRing : root.rightRing);
    }

    function click(button) {
        if (button < 272 || button > 276)
            return;
        root.show(KeyNames.key("mouse:" + button));
        if (button === 272 || button === 273)
            ring.ask(button === 272 ? root.leftRing : root.rightRing);
    }

    // the latest press, and how many times in a row (shown as "x3")
    property string label: ""
    property int repeats: 1
    property real shownAt: 0
    function show(t) {
        if (t === root.label && Date.now() - root.shownAt < 1500)
            root.repeats++;
        else
            root.repeats = 1;
        root.label = t;
        root.shownAt = Date.now();
        hideTimer.restart();
    }
    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.label = ""
    }

    // ---- where the pointer is, for a ring: asked of Hyprland on each click ----
    QtObject {
        id: ring
        property var queue: []
        function ask(color) {
            queue = queue.concat([color]);
            if (!cursor.running)
                cursor.running = true;
        }
    }
    Process {
        id: cursor
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p;
                try {
                    p = JSON.parse(text);
                } catch (e) {
                    return;
                }
                const colors = ring.queue;
                ring.queue = [];
                for (const c of colors)
                    root.ripple(p.x, p.y, c);
            }
        }
    }
    signal ripple(real gx, real gy, color c)

    // ---- one overlay per screen: rings where the pointer is, the pill on the focused screen ----
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            visible: root.on
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "showoff-input"
            WlrLayershell.layer: WlrLayer.Overlay
            // takes no input at all: clicks go to whatever is under it
            mask: Region {}

            Connections {
                target: root
                function onRipple(gx, gy, c) {
                    const x = gx - win.modelData.x, y = gy - win.modelData.y;
                    if (x >= 0 && y >= 0 && x < win.width && y < win.height)
                        ringC.createObject(win.contentItem, { cx: x, cy: y, tint: c });
                }
            }

            Component {
                id: ringC
                Rectangle {
                    id: r
                    property real cx: 0
                    property real cy: 0
                    property color tint: "white"
                    property real size: 8
                    x: cx - size / 2
                    y: cy - size / 2
                    width: size
                    height: size
                    radius: size / 2
                    color: "transparent"
                    border.width: 3
                    border.color: tint
                    ParallelAnimation {
                        running: true
                        NumberAnimation { target: r; property: "size"; to: 64; duration: 420; easing.type: Easing.OutCubic }
                        NumberAnimation { target: r; property: "opacity"; from: 1; to: 0; duration: 420; easing.type: Easing.InQuad }
                        onFinished: r.destroy()
                    }
                }
            }

            // the pressed keys, bottom centre of the focused screen, above where the volume OSD shows
            Rectangle {
                readonly property bool here: !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === win.modelData.name
                visible: here && root.label !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 160
                width: keyText.implicitWidth + 40
                height: 52
                radius: 14
                color: root.fill
                Text {
                    id: keyText
                    anchors.centerIn: parent
                    text: root.label + (root.repeats > 1 ? "  ×" + root.repeats : "")
                    color: root.text
                    font.pixelSize: 22
                    font.bold: true
                }
            }
        }
    }
}
