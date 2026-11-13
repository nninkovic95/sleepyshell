pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// The one place the shell plays a sound: an urgent notification's chime (Notifs). Quickshell has no
// sound player of its own, so pw-play (PipeWire) plays the file, on the main output (Audio.sink) at a
// volume relative to it (Settings.urgentSoundVolume). One at a time: a chime asked for
// while one plays is dropped, so a burst of notifications rings once instead of piling up.
// The file is the user's setting only; a notification's own sound-file hint is never played, so an
// app cannot make the shell open a file of its choosing.
Singleton {
    id: root

    // the number of chimes started, read by the tests
    property int played: 0

    function play() {
        const f = Settings.urgentSoundFile;
        if (!Settings.urgentSound || f === "" || !f.startsWith("/") || !Deps.has("pw-play") || player.running)
            return;
        // a name of its own: WirePlumber restores each app's volume by its name, and a bare pw-play
        // left at volume 0 by any other use of it would silence the chime; mixers show it by this name
        // pw-play's volume is linear; mixers show the cube root of it, and the setting follows the mixers
        // (100 % = as loud as any other app's sound at full volume; above it amplifies, as a mixer can)
        const vol = Math.pow(Math.max(0, Math.min(150, Settings.urgentSoundVolume)) / 100, 3);
        if (vol <= 0)
            return;
        // straight to the output the volume keys and the audio pill control (Audio.sink, which follows the
        // default output and looks through Easy Effects to the device), so the volume above is relative to
        // that output and a stream target remembered by the audio server cannot send it elsewhere
        const target = Audio.sink?.name ?? "";
        player.command = ["pw-play", "-P", "{ application.name = \"Sleepy Shell\" }", "--volume", vol.toFixed(5)]
            .concat(target !== "" ? ["--target", target] : [], ["--", f]);
        player.code = 0;
        player.running = true;
        root.played++;
    }

    Process {
        id: player
        // a missing file or an unreachable audio server only fails pw-play: not worth a message on
        // screen, but it goes to the log so a silent chime can be traced
        // the exit can come before the error text has been read to its end: the code is kept, and the
        // warning written once the text is complete
        property int code: 0
        stderr: StdioCollector {
            onStreamFinished: {
                if (player.code !== 0)
                    console.warn("Chime: pw-play exited with code " + player.code + ": " + text.trim().slice(0, 300));
            }
        }
        onExited: c => code = c
    }

    // a stuck player (a stalled audio server) must not silence every later chime: asked to stop after
    // 10 s, killed 3 s later if it ignored that
    Timer {
        property bool asked: false
        interval: asked ? 3000 : 10000
        repeat: true
        running: player.running
        onRunningChanged: asked = false
        onTriggered: {
            player.signal(asked ? 9 : 15);
            asked = true;
        }
    }
}
