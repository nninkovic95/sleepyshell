pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "KeyNames.js" as KeyNames

// The keybind overlay and the click circles: two features, each switched by its own shell shortcut (Keybinds tab;
// Super+Shift+K and Super+Shift+L suggested) and shown on the right island by a passive indicator while on, drawn by
// sleepybar/popups/inputshow/InputShowOverlay.qml.
//   keybind overlay  the keybind just used, named in a pill at the bottom of the focused screen ("Super + Enter")
//   click circles    an expanding ring at the pointer on a left (accent) or right (alert colour) click
// Nothing reads the keyboard or the mouse. Hyprland reports what happened as custom events on its own socket, and
// only while a switch is on:
//   sleepyshell:keypress:<modmask>:<r|p>:<key>   a keybind fired (data/keyreport.lua, loaded by hyprland.lua, wraps
//                                                hl.bind and reports only while sleepyshell_keys_on is set; r: a
//                                                repeating bind, whose re-fires while held count as one press)
//   sleepyshell:click:<272|273>                  a left or right click, from pass-through binds added while the
//                                                circles are on
//   sleepyshell:keyreport:ready                  the reporter's answer when the overlay goes on; none means
//                                                hyprland.lua does not load it (Sleepysettings offers the line)
// Typing and app shortcuts are never seen. Switching runs `hyprctl eval` with fixed code: the flag, and the click
// binds, kept in a Lua table and removed through their own handles, so a bind of the user's is never touched. Both
// are cleared when the shell starts and when it ends (a crash while on would leave them behind). This is the only
// place that runs these hyprctl calls.
Singleton {
    id: root

    property bool keysOn: false
    property bool clicksOn: false
    // the overlay is on but Hyprland did not answer for the reporter
    property bool reporterMissing: false

    function toggleKeys() {
        root.keysOn = !root.keysOn;
    }
    function toggleClicks() {
        root.clicksOn = !root.clicksOn;
    }

    readonly property string keysOffLua: "sleepyshell_keys_on = false"
    readonly property string keysOnLua: "sleepyshell_keys_on = true; if sleepyshell_keyreport_loaded then hl.dispatch(hl.dsp.event(\"sleepyshell:keyreport:ready\")) end"
    // made with the unwrapped hl.bind, so the reporter does not name a click as a keybind
    readonly property string clicksOffLua: "for _, b in ipairs(sleepyshell_clicks or {}) do pcall(function() b:remove() end) end; sleepyshell_clicks = {}"
    readonly property string clicksOnLua: root.clicksOffLua + "; for _, c in ipairs({ 272, 273 }) do sleepyshell_clicks[#sleepyshell_clicks + 1] = (sleepyshell_bind_original or hl.bind)(\"mouse:\" .. c, function() hl.dispatch(hl.dsp.event(\"sleepyshell:click:\" .. c)) end, { non_consuming = true }) end"

    function hypr(code) {
        Quickshell.execDetached(["hyprctl", "eval", code]);
    }

    onKeysOnChanged: {
        root.label = "";
        root.reporterMissing = false;
        root.hypr(root.keysOn ? root.keysOnLua : root.keysOffLua);
        if (root.keysOn)
            readyWait.restart();
        else
            readyWait.stop();
    }
    onClicksOnChanged: root.hypr(root.clicksOn ? root.clicksOnLua : root.clicksOffLua)
    Component.onCompleted: root.hypr(root.keysOffLua + "; " + root.clicksOffLua)
    Component.onDestruction: root.hypr(root.keysOffLua + "; " + root.clicksOffLua)

    Timer {
        id: readyWait
        interval: 1500
        onTriggered: {
            root.reporterMissing = true;
            root.show("Keybinds can't be named yet: Sleepysettings > Keybinds can set it up");
            hideTimer.interval = 5000;
            hideTimer.restart();
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(e) {
            // a config reload drops the click binds made at run time: what is on is set up again
            if (e.name === "configreloaded") {
                if (root.keysOn)
                    root.hypr(root.keysOnLua);
                if (root.clicksOn)
                    root.hypr(root.clicksOnLua);
                return;
            }
            if (e.name !== "custom" || !e.data.startsWith("sleepyshell:"))
                return;
            const parts = e.data.split(":");
            if (parts[1] === "keyreport" && parts[2] === "ready") {
                readyWait.stop();
                root.reporterMissing = false;
            } else if (parts[1] === "keypress" && parts.length >= 5 && root.keysOn) {
                root.shortcut(Number(parts[2]), parts[3] === "r", parts.slice(4).join(":"));
            } else if (parts[1] === "click" && root.clicksOn) {
                root.click(Number(parts[2]));
            }
        }
    }

    // ---- events -> what to show (the words come from KeyNames.js) ----
    // a repeating bind fires every few tens of milliseconds while held: one press, so it only keeps the pill up
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
    }

    // the latest keybind, and how many times in a row (shown as "x3")
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
        hideTimer.interval = 1500;
        hideTimer.restart();
    }
    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.label = ""
    }

    // ---- a ring where the pointer is: Hyprland is asked for its place on each click ----
    property var ringQueue: []
    function click(button) {
        if (button !== 272 && button !== 273)
            return;
        root.ringQueue = root.ringQueue.concat([button === 272 ? "left" : "right"]);
        if (!cursor.running)
            cursor.running = true;
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
                const sides = root.ringQueue;
                root.ringQueue = [];
                for (const s of sides)
                    root.ring(p.x, p.y, s);
            }
        }
    }
    // gx, gy: the pointer in the global layout; side: "left" or "right"
    signal ring(real gx, real gy, string side)
}
