import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// The settings window's end of its socket to the bar (Settings.socketPath; the messages are
// listed in services/SettingsServer.qml). Sends the staged values whenever they change and each
// commit on Apply; the bar answers `committed` once the file is saved (the Apply stays unapplied
// until then, and after a dropped link), and sends `close` when its
// toggle is used while the window is up. While the bar is away (a bar restart) it tries again
// every two seconds and resends the state once connected. Without the bar the window works on
// its own: Settings then writes the file itself and the wallpaper picker goes through the bar's IPC.
QtObject {
    id: root
    required property var window   // the Sleepysettings window
    readonly property bool connected: sock.connected

    function send(msg) {
        if (!sock.connected)
            return;
        sock.write(JSON.stringify(msg) + "\n");
        sock.flush();
    }

    function sendPreview() {
        send({ type: "preview", previewing: Settings.previewing, pending: Settings.pending });
    }

    function commit(values) {
        send({ type: "commit", values: values });
    }

    function toggle(name) {
        send({ type: "toggle", name: name });
    }

    function chime() {
        send({ type: "chime" });
    }

    function receive(line) {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            console.warn("settings: unreadable message from the bar:", line);
            return;
        }
        switch (m.type) {
        case "committed":
            // the bar wrote these keys: this window's Apply of them counts as saved only now
            Settings.landed(Array.isArray(m.keys) ? m.keys : []);
            break;
        case "close":
            window.leave(() => window.open = false);
            break;
        case "show":
            window.open = true;
            break;
        case "tab":
            // a widget on the bar asks for a tab (the battery widget: Power); a name the window has no tab for is ignored
            if (window.pages.some(p => p.key === m.name))
                window.leave(() => window.tab = m.name);
            break;
        case "power":
            // who handles the lid, as the bar's PowerPolicy found out (shown in the Power tab)
            Battery.lidControl = m.lidControl ?? "";
            break;
        default:
            console.warn("settings: unknown message from the bar:", line);
        }
    }

    // the socket's path is known once Settings has resolved the shell folder, a moment after start
    Component.onCompleted: {
        Settings.link = root;
        if (Settings.socketPath !== "")
            sock.connected = true;
    }
    Component.onDestruction: if (Settings.link === root) Settings.link = null

    readonly property Socket sock: Socket {
        id: sock
        path: Settings.socketPath
        parser: SplitParser {
            onRead: data => root.receive(data)
        }
        // a commit the bar had not confirmed when the link dropped is not saved (Settings.linkLost)
        onConnectionStateChanged: connected ? root.sendPreview() : Settings.linkLost()
    }

    // the bar is not there (yet): try again
    readonly property Timer retry: Timer {
        interval: 2000
        running: !sock.connected && Settings.socketPath !== ""
        repeat: true
        onTriggered: sock.connected = true
    }

    readonly property Connections changes: Connections {
        target: Settings
        function onPendingChanged() {
            root.sendPreview();
        }
        function onPreviewingChanged() {
            root.sendPreview();
        }
        function onSocketPathChanged() {
            if (Settings.socketPath !== "")
                sock.connected = true;
        }
    }
}
