pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Which apps are using the microphone, the camera or a screen share right now, read off PipeWire's
// stream nodes so nothing polls. Audio.qml already runs one PwObjectTracker over Pipewire.nodes.values,
// so properties, audio and ready are valid on the video nodes too; this file adds no tracker.
//
// Microphone: Stream/Input/Audio clients, minus Easy Effects' own nodes (it sits between the hardware
// mic and every app), level meters (stream.monitor, "monitor" or "peak detect" media names, cava),
// captures of a sink's monitor (stream.capture.sink) and streams whose audio object is muted.
//
// Camera and screen share are both Stream/Input/Video. Following DankMaterialShell's PrivacyService, a
// stream with media.role "Screen" is a screen share and a not-live one (stream.is-live "false") is ignored.
// Unlike DMS, which reads only the node's own properties, this also looks at the node linked upstream:
// the portal's screencast producer (xdg-desktop-portal-hyprland, xdpw ...) marks a stream as a screen share
// even when the app sets another role. Everything else counts as a camera.
Singleton {
    id: root

    readonly property var nodes: Pipewire.nodes.values

    // nerd-font glyphs (md-microphone, md-camera, md-monitor-share)
    readonly property int micGlyph: 0xF036C
    readonly property int cameraGlyph: 0xF0100
    readonly property int screenGlyph: 0xF1483

    function prop(n, key) {
        return String(n.properties[key] ?? "");
    }
    function appLabel(n) {
        return prop(n, "application.name") || prop(n, "application.process.binary") || n.name;
    }
    function unique(list) {
        return list.filter((x, i) => list.indexOf(x) === i);
    }

    function isEasyEffects(n) {
        const app = prop(n, "application.name").toLowerCase();
        return n.name.startsWith("ee_") || n.name.startsWith("easyeffects") || app === "easy effects" || app === "easyeffects";
    }
    function isMic(n) {
        if (!n.ready || prop(n, "media.class") !== "Stream/Input/Audio" || isEasyEffects(n))
            return false;
        if (prop(n, "stream.monitor") === "true" || prop(n, "stream.capture.sink") === "true")
            return false;
        if (/monitor|peak detect/.test(prop(n, "media.name").toLowerCase()))
            return false;
        if (/cava/.test((n.name + " " + appLabel(n)).toLowerCase()))
            return false;
        return !n.audio?.muted;
    }

    function isLiveVideo(n) {
        return n.ready && prop(n, "media.class") === "Stream/Input/Video" && prop(n, "stream.is-live") !== "false";
    }
    // name, application and media name of the node this stream is linked from, lower case
    function upstreamText(n) {
        const up = Pipewire.linkGroups.values.find(l => l.target === n)?.source;
        return up ? (up.name + " " + prop(up, "application.name") + " " + prop(up, "media.name")).toLowerCase() : "";
    }
    function isScreen(n) {
        return prop(n, "media.role") === "Screen" || prop(n, "media.name").toLowerCase().includes("screen") || /xdg-desktop-portal|xdpw|xdph|screen|hyprland|gnome shell|kwin|wlroots|niri/.test(upstreamText(n));
    }

    readonly property var videoNodes: nodes.filter(n => isLiveVideo(n))
    readonly property var micApps: unique(nodes.filter(n => isMic(n)).map(n => appLabel(n)))
    readonly property var cameraApps: unique(videoNodes.filter(n => !isScreen(n)).map(n => appLabel(n)))
    readonly property var screenApps: unique(videoNodes.filter(n => isScreen(n)).map(n => appLabel(n)))

    readonly property bool micActive: micApps.length > 0
    readonly property bool cameraActive: cameraApps.length > 0
    readonly property bool screenActive: screenApps.length > 0
    readonly property bool anyActive: micActive || cameraActive || screenActive

    // glyphs of the active kinds, for the bar
    readonly property string barGlyphs: [micActive ? micGlyph : 0, cameraActive ? cameraGlyph : 0, screenActive ? screenGlyph : 0].filter(c => c > 0).map(c => String.fromCodePoint(c)).join(" ")

    // one entry per app: { app, glyphs, uses } with what it uses, for the dropdown
    readonly property var rows: {
        const by = Object.create(null);
        const add = (apps, glyph, use) => apps.forEach(a => {
            by[a] = by[a] ?? { app: a, glyphs: [], uses: [] };
            by[a].glyphs.push(String.fromCodePoint(glyph));
            by[a].uses.push(use);
        });
        add(micApps, micGlyph, "microphone");
        add(cameraApps, cameraGlyph, "camera");
        add(screenApps, screenGlyph, "screen share");
        return Object.keys(by).map(k => ({ app: k, glyphs: by[k].glyphs.join(" "), uses: by[k].uses.join(", ") }));
    }
}
