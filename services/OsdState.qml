pragma Singleton
import QtQuick
import Quickshell

// Shared state of the volume / microphone OSD. Two views show it: VolumePeek, a row the clock
// island reveals under its title (GrowingIsland.peek), and Osd, a pill at the bottom of the screen that
// only appears over a fullscreen window, which hides the bar. The level flashes for Settings.peekMs (default 1.2 s) after a
// change of the default sink's or source's level or mute; not in the first 2 s after start
// (PipeWire's initial values arrive as changes) and not while the audio dropdown is open (it shows
// the same levels).
Singleton {
    id: root

    property bool shown: false      // the level is meant to be on screen
    property bool armed: false      // false until the initial PipeWire values have settled
    property bool micLast: false    // the last change was the microphone, not the speaker
    property bool capsLast: false   // the last change was Caps Lock (on/off text instead of a level)
    readonly property bool suppressed: !armed || (Popouts.current !== null && Popouts.current.name === "audio")
    readonly property real level: Math.max(0, Math.min(1, micLast ? Audio.micVolume : Audio.volume))
    readonly property bool muted: capsLast ? !CapsLock.on : micLast ? Audio.micMuted : Audio.muted
    readonly property int glyph: capsLast ? 0xF0632 : micLast ? Audio.micGlyph() : Audio.sinkGlyph()

    function flash(mic) {
        micLast = mic;
        capsLast = false;
        if (suppressed)
            return;
        shown = true;
        hideTimer.restart();
    }

    // Caps Lock: not held back by the audio dropdown, only by the start
    function flashCaps() {
        if (!Settings.capsPeek)
            return;
        capsLast = true;
        if (!armed)
            return;
        shown = true;
        hideTimer.restart();
    }

    Connections {
        target: CapsLock
        // every key press, not only a change: two quick presses can end where they began
        function onKeyRead() {
            root.flashCaps();
        }
    }

    onSuppressedChanged: {
        if (suppressed && !capsLast)
            shown = false;
    }

    Timer {
        interval: 2000
        running: true
        onTriggered: root.armed = true
    }

    Timer {
        id: hideTimer
        interval: Settings.peekMs
        onTriggered: root.shown = false
    }

    Component.onCompleted: {
        sinkId = Audio.sink?.id ?? -1;
        sourceId = Audio.source?.id ?? -1;
    }

    // A level that differs only because Audio.sink / Audio.source now points at another device is
    // not a volume change: no flash. Checked here by node id, because the volume binding fires
    // before the sinkChanged handler (for example 0.7361 -> 0.6596 was the USB speaker's level,
    // shown when the resolver lost the Easy Effects chain).
    property int sinkId: -1
    property int sourceId: -1

    function switched(mic) {
        const id = mic ? (Audio.source?.id ?? -1) : (Audio.sink?.id ?? -1);
        const was = mic ? sourceId : sinkId;
        if (mic)
            sourceId = id;
        else
            sinkId = id;
        return id !== was;
    }

    function onLevelChange(mic) {
        if (!switched(mic))
            flash(mic);
    }

    Connections {
        target: Audio
        function onSinkChanged() {
            root.switched(false);
        }
        function onSourceChanged() {
            root.switched(true);
        }
        function onVolumeChanged() {
            root.onLevelChange(false);
        }
        function onMutedChanged() {
            root.onLevelChange(false);
        }
        function onMicVolumeChanged() {
            root.onLevelChange(true);
        }
        function onMicMutedChanged() {
            root.onLevelChange(true);
        }
    }
}
