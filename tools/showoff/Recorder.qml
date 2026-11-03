import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Screen recording with gpu-screen-recorder, for demo videos. `toggle()` starts recording the focused
// monitor, or stops the recording in progress.
//
// gpu-screen-recorder encodes on the GPU (VAAPI on this AMD card), so 60 fps at high quality costs almost
// no CPU, and it captures a whole monitor through its own KMS helper with no portal dialog. A monitor is
// captured, not a window: switching workspaces while recording is recorded too.
//
// A recording: H.264 in MP4 (plays everywhere), 60 fps, "very_high" quality, saved as
// <dir>/Recording_<date>_<time>.mp4. Sound: what you hear (default output) unless `audio` is false;
// the microphone (default input) only when `mic` is true; both on are mixed into one track.
//
// Stop: SIGINT, on which gpu-screen-recorder finishes the file. Then a notification with Open and
// Show in folder; a failed recording says so with the recorder's last error line.
QtObject {
    id: root

    // ---- options (edit here; this tool has no settings window) ----
    property bool audio: true
    property bool mic: false
    property string dir: Quickshell.env("HOME") + "/Videos/Recordings"

    // ---- state ----
    readonly property bool recording: recorder.running
    property string file: ""
    property bool stopping: false
    property real startedAt: 0
    property int elapsed: 0

    function toggle() {
        if (root.recording)
            root.stop();
        else
            root.start();
    }

    function start() {
        if (root.recording)
            return;
        root.file = root.dir + "/Recording_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4";
        const monitor = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "screen";
        const sources = [];
        if (root.audio)
            sources.push("default_output");
        if (root.mic)
            sources.push("default_input");
        const args = ["-w", monitor, "-f", "60", "-k", "h264", "-q", "very_high", "-c", "mp4"];
        // one -a with sources joined by "|" mixes them into a single track
        if (sources.length > 0)
            args.push("-a", sources.join("|"));
        args.push("-o", root.file);
        // mkdir first; exec so that the process signalled on stop is the recorder itself
        recorder.command = ["sh", "-c", 'mkdir -p -- "$1" && shift && exec gpu-screen-recorder "$@"', "sh", root.dir].concat(args);
        root.stopping = false;
        root.elapsed = 0;
        root.startedAt = Date.now();
        recorder.running = true;
    }

    function stop() {
        if (!root.recording || root.stopping)
            return;
        root.stopping = true;
        recorder.signal(2);   // SIGINT: write the end of the MP4 and exit
    }

    property Process recorder: Process {
        property string lastError: ""
        stderr: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    root.recorder.lastError = line.trim();
            }
        }
        onStarted: lastError = ""
        onExited: (code, status) => {
            if (root.stopping && code === 0)
                Opener.notifySaved(root.file);
            else
                Quickshell.execDetached(["notify-send", "-a", "Screen recorder", "-u", "critical", "-i", "media-record", "Screen recording failed", root.recorder.lastError !== "" ? root.recorder.lastError : "gpu-screen-recorder exited with code " + code + "."]);
            root.stopping = false;
        }
    }

    property Timer ticker: Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.elapsed = Math.floor((Date.now() - root.startedAt) / 1000)
    }
}
