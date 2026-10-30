pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Night light (it took the control-centre slot of the Notifications tile once
// notifications moved to the right island). A warm screen shader, ~/.config/hypr/shaders/nightlight.frag,
// switched by writing ~/.config/hypr/modules/nightlight.lua, which hyprland.lua requires after
// decorations.lua. A file rather than `hyprctl eval`: a runtime setting is lost on every config
// reload (any save of a hypr module), while the file survives reloads and restarts and is the
// state the tile shows. No hyprsunset (no extra packages).
//
// Settings (the night light is just a toggle; Display tab > Night light, keys nightWarmth and nightStrength, the APPLIED
// values, never the staged ones):
// - The shader file is rewritten by this service with the colour for the warmth and strength (a fixed multiplier per
//   channel: a Hyprland screen shader has no way to take a setting), before nightlight.lua is written. Writing
//   nightlight.lua is what makes Hyprland reload its config and so the shader; the lua text carries the colour in a comment, so it
//   changes whenever the shader does and is never skipped as "unchanged". Nothing is written at start: the files stay as
//   they are until the tile is toggled or Apply changes the warmth or strength while it is on. (The shader write is synchronous so it
//   is complete when the lua write triggers the reload; inferred from Hyprland's behaviour, not checked against the compositor in the tests.)
// - There is no schedule, no sunrise and sunset, no fade: the tile (`toggle`) switches at once.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.config/hypr/modules/nightlight.lua"
    readonly property string shaderPath: Quickshell.env("HOME") + "/.config/hypr/shaders/nightlight.frag"
    readonly property string header: ["-- Night light, written by the Quickshell bar (control centre tile, services/NightLight.qml) and",
        "-- loaded after decorations.lua by require(\"modules.nightlight\") in hyprland.lua. Off: this",
        "-- comment only. On: one hl.config line setting decoration.screen_shader to",
        "-- ~/.config/hypr/shaders/nightlight.frag.", ""].join("\n")
    readonly property string line: 'hl.config({ decoration = { screen_shader = os.getenv("HOME") .. "/.config/hypr/shaders/nightlight.frag" } })'

    property string text: ""
    // the lua file has been read (or does not exist)
    property bool ready: false
    readonly property bool on: text.split("\n").some(l => l.startsWith("hl.config(") && l.includes("screen_shader"))

    // ---- settings (applied values) ----
    readonly property int warmth: Settings.nightWarmth
    readonly property int strength: Settings.nightStrength

    // ---- the colour: kelvin to a tint ----
    function clamp(x, lo, hi) {
        return Math.max(lo, Math.min(hi, x));
    }

    // Tanner Helland's blackbody fit: 0..1 per channel for a temperature in kelvin (1000..40000)
    function rawTint(kelvin) {
        const t = root.clamp(kelvin, 1000, 40000) / 100;
        const r = t <= 66 ? 255 : 329.698727446 * Math.pow(t - 60, -0.1332047592);
        const g = t <= 66 ? 99.4708025861 * Math.log(t) - 161.1195681661 : 288.1221695283 * Math.pow(t - 60, -0.0755148492);
        const b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307);
        return [root.clamp(r, 0, 255) / 255, root.clamp(g, 0, 255) / 255, root.clamp(b, 0, 255) / 255];
    }

    // The multiplier for red, green and blue that a screen shader applies: 6500 K is neutral (1, 1, 1), lower is
    // warmer. strength 0..1 blends from neutral to the full tint.
    function tint(kelvin, strength) {
        const ref = root.rawTint(6500);
        const c = root.rawTint(kelvin);
        const s = root.clamp(strength, 0, 1);
        return c.map((v, i) => {
            const full = Math.min(1, v / ref[i]);
            return Math.round((1 + (full - 1) * s) * 1000) / 1000;
        });
    }

    // ---- the shader ----
    property string shaderText: ""

    function shaderSource(c) {
        return ["#version 300 es",
            "// Night light: a warm tint over the whole screen, switched by the Night light tile in the",
            "// Quickshell bar's control centre through modules/nightlight.lua. Written by",
            "// services/NightLight.qml from the warmth and strength in Sleepysettings, Display:",
            "// one multiplier for red, green and blue below. Edits here are overwritten.",
            "precision highp float;",
            "",
            "in vec2 v_texcoord;",
            "uniform sampler2D tex;",
            "out vec4 fragColor;",
            "",
            "const vec3 tint = vec3(" + c.join(", ") + ");",
            "",
            "void main() {",
            "    vec4 c = texture(tex, v_texcoord);",
            "    fragColor = vec4(c.rgb * tint, c.a);",
            "}",
            ""].join("\n");
    }

    // night light on: the shader first, then the lua file (the write that reloads)
    function applyOn() {
        const c = root.tint(root.warmth, root.strength / 100).map(v => v.toFixed(3));
        const s = root.shaderSource(c);
        if (s !== root.shaderText) {
            root.shaderText = s;
            shaderFile.setText(s);
        }
        // the colour is in a comment too: a lua file whose text does not change is not written again, and the write is what
        // makes Hyprland reload its config and so read the new shader
        const t = root.header + root.line + "\n-- tint " + c.join(" ") + "\n";
        file.setText(t);
        root.text = t;
    }

    function applyOff() {
        file.setText(root.header);
        root.text = root.header;
    }

    // the tile: switches at once
    function toggle() {
        if (root.on)
            root.applyOff();
        else
            root.applyOn();
    }

    // another warmth or strength while on: write it out
    readonly property string shaderKey: root.warmth + "," + root.strength
    onShaderKeyChanged: {
        if (root.on)
            root.applyOn();
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        // in place, so Hyprland's watch on the file sees a plain modification (as sleepybinds.lua)
        atomicWrites: false
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.text = text();
            root.ready = true;
        }
        onLoadFailed: root.ready = true
    }

    // written before the lua file, and synchronously, so it is complete when Hyprland reloads
    FileView {
        id: shaderFile
        path: root.shaderPath
        atomicWrites: false
        blockWrites: true
        printErrors: false
    }
}
