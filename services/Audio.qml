pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Default sink and source through PipeWire, hardware device lists for switching, and the node
// whose volume is shown and changed.
//
// Every sink and source is listed, including Easy Effects' virtual ones (as pwvucontrol does).
// Volume and mute, however, go to a hardware node: a virtual sink's own volume is not applied to
// what Easy Effects reads from it (observed: the number changed, the sound did not), and the
// virtual source has no audio object at all. So when the default is virtual, the bar shows and
// controls the hardware device at the other end of the Easy Effects chain, found via the links:
//   sink:   easyeffects_sink -> ee_soe_* ... -> alsa_output.*
//   source: alsa_input.* -> ee_sie_* ... -> easyeffects_source
Singleton {
    id: root

    readonly property PwNode defaultSink: Pipewire.defaultAudioSink
    readonly property PwNode defaultSource: Pipewire.defaultAudioSource

    function isVirtual(n) {
        return !!n && (String(n.properties["node.virtual"] ?? "") === "true" || n.name.startsWith("easyeffects"));
    }
    function isHardwareSink(n) {
        return !!n && !!n.audio && n.isSink && !n.isStream && !isVirtual(n);
    }
    function isHardwareSource(n) {
        return !!n && !!n.audio && !n.isSink && !n.isStream && (n.type & 2) === 0 && !isVirtual(n);
    }

    function mediaClass(n) {
        return String(n.properties["media.class"] ?? "");
    }
    function isSinkDevice(n) {
        return !n.isStream && ((n.audio && n.isSink) || mediaClass(n).startsWith("Audio/Sink"));
    }
    function isSourceDevice(n) {
        return !n.isStream && !n.isSink && ((n.audio && (n.type & 2) === 0) || mediaClass(n).startsWith("Audio/Source"));
    }

    readonly property var sinks: Pipewire.nodes.values.filter(n => isSinkDevice(n))
    readonly property var sources: Pipewire.nodes.values.filter(n => isSourceDevice(n))

    // audio and properties are only valid on tracked nodes; track them all (a dozen on this machine)
    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    // Follow link groups downstream (sink chain) or upstream (source chain) to the hardware node.
    // Depth-first over every link out of a node, not just the first one found: a level meter or a
    // screen share capturing easyeffects_sink's monitor, or a link group left over while Easy
    // Effects rebuilds its filters (it recreates ee_soe_* nodes at runtime), would otherwise end
    // the walk early. Once the walk failed, the fallback picked a USB speaker
    // instead of the onboard output, and the volume OSD flashed the other device's level.
    // Easy Effects' own nodes are explored first so a stray loopback cannot win over them.
    function chainEnd(start, downstream) {
        const groups = Pipewire.linkGroups.values;
        const seen = {};
        const stack = [start];
        let steps = 0;
        while (stack.length > 0 && steps++ < 64) {
            const cur = stack.pop();
            if (!cur || seen[cur.id])
                continue;
            seen[cur.id] = true;
            const ee = [];
            const others = [];
            for (const g of groups) {
                const next = downstream ? (g.source === cur ? g.target : null) : (g.target === cur ? g.source : null);
                if (!next || seen[next.id])
                    continue;
                if (downstream ? isHardwareSink(next) : isHardwareSource(next))
                    return next;
                (next.name.startsWith("ee_") ? ee : others).push(next);
            }
            // ee_ nodes on top of the stack, so they are explored before any other branch
            stack.push(...others, ...ee);
        }
        return null;
    }

    // Easy Effects names the device its output stream plays to (its input stream records from) in
    // target.object, by serial or name. Used when the chain cannot be walked and nothing was
    // resolved before (bar start while the filters are unlinked). Returns null if the property is
    // absent; whether this Easy Effects version sets it is not verified.
    function eeTarget(downstream) {
        const prefix = downstream ? "ee_soe_" : "ee_sie_";
        const nodes = Pipewire.nodes.values;
        for (const n of nodes) {
            if (!n.name.startsWith(prefix))
                continue;
            const t = String(n.properties["target.object"] ?? "");
            if (!t)
                continue;
            const hit = nodes.find(h => (downstream ? isHardwareSink(h) : isHardwareSource(h)) && (h.name === t || String(h.properties["object.serial"] ?? "") === t));
            if (hit)
                return hit;
        }
        return null;
    }

    // The last hardware nodes the chain resolved to, kept while the chain is being rebuilt. Fields
    // of one plain JS object, not QML properties: a property read inside the sink / source binding
    // and written from onSinkChanged / onSourceChanged is a binding loop (seen on the first try).
    // A device that has gone is never returned: the binding checks it is still in Pipewire.nodes.
    readonly property var last: ({
            sink: null,
            source: null
        })
    onSinkChanged: {
        if (sink && !isVirtual(sink))
            last.sink = sink;
    }
    onSourceChanged: {
        if (source && !isVirtual(source))
            last.source = source;
    }

    // the nodes whose volume and mute are shown and changed
    readonly property PwNode sink: {
        if (!defaultSink)
            return null;
        if (isHardwareSink(defaultSink))
            return defaultSink;
        const end = chainEnd(defaultSink, true);
        if (end)
            return end;
        if (last.sink && Pipewire.nodes.values.includes(last.sink))
            return last.sink;
        return eeTarget(true) ?? sinks.find(n => isHardwareSink(n)) ?? (defaultSink.audio ? defaultSink : null);
    }
    readonly property PwNode source: {
        if (!defaultSource)
            return null;
        if (isHardwareSource(defaultSource))
            return defaultSource;
        const end = chainEnd(defaultSource, false);
        if (end)
            return end;
        if (last.source && Pipewire.nodes.values.includes(last.source))
            return last.source;
        return eeTarget(false) ?? sources.find(n => isHardwareSource(n)) ?? (defaultSource.audio ? defaultSource : null);
    }

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? true
    readonly property real micVolume: source?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? true

    function clamp(v) {
        return Math.max(0, Math.min(1, v));
    }

    function setVolume(v) {
        if (!sink?.audio)
            return;
        sink.audio.volume = clamp(v);
        if (v > 0 && sink.audio.muted)
            sink.audio.muted = false;
    }

    function setMicVolume(v) {
        if (!source?.audio)
            return;
        source.audio.volume = clamp(v);
        if (v > 0 && source.audio.muted)
            source.audio.muted = false;
    }

    function step(d) {
        setVolume(volume + d);
    }

    function stepMic(d) {
        setMicVolume(micVolume + d);
    }

    function toggleMute() {
        if (sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    function toggleMicMute() {
        if (source?.audio)
            source.audio.muted = !source.audio.muted;
    }

    // Quickshell refuses untyped (virtual) nodes as defaults; wpctl takes any node id
    function setSink(n) {
        if (n.audio)
            Pipewire.preferredDefaultAudioSink = n;
        else
            Quickshell.execDetached(["wpctl", "set-default", String(n.id)]);
    }

    function setSource(n) {
        if (n.audio)
            Pipewire.preferredDefaultAudioSource = n;
        else
            Quickshell.execDetached(["wpctl", "set-default", String(n.id)]);
    }

    // description first: the onboard sink and source share the nickname "Analog"
    function deviceName(n) {
        return n.description || n.nickname || n.name;
    }

    // nerd-font glyphs
    function sinkGlyph() {
        if (!sink?.audio || muted)
            return 0xF0581;
        const p = volume * 100;
        if (p === 0)
            return 0xF075F;
        return p < 25 ? 0xF057F : p < 60 ? 0xF0580 : 0xF057E;
    }

    function micGlyph() {
        return !source?.audio || micMuted ? 0xF036D : 0xF036C;
    }
}
