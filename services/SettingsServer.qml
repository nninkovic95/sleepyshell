import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// The bar's end of the settings window's socket (Settings.socketPath), instantiated once in
// shell.qml. The window is its own Quickshell instance (sleepysettings.qml, run as
// `qs -p ~/.config/quickshell/sleepyshell/sleepysettings.qml`), so the bar never loads the settings files and a
// change to them reloads the window alone. Registered with Popouts as "settings", so the control centre's
// Settings entry and the launcher's entry (the main ways in) flip `open`, as does `qs -c sleepyshell ipc call
// bar toggle settings` (one route among them, for scripts); `open` launches the window or asks it to close.
// Lines of JSON over the socket, one message each:
//   window to bar   {type: "preview", previewing: bool, pending: {key: value}}   the staged values
//                   {type: "commit", values: {key: value}}   Apply: the bar writes sleepysettings.toml
//                   {type: "toggle", name: "..."}   open or close a dropdown (the wallpaper picker)
//   bar to window   {type: "committed", keys: [...]}   the written keys are on disk
//                   {type: "close"}   toggle while the window is up: it closes (asking about unapplied changes first)
//                   {type: "show"}    toggle while it is up but hidden: it shows again
//                   {type: "tab", name: "power"}   open this tab (the battery widget); sent after "show"
//                   {type: "power", lidControl: "shell"|"logind"|""}   who handles the lid switch (sent on connect and on change)
QtObject {
    id: root
    readonly property string name: "settings"
    readonly property var bar: null   // no anchor bar; Popouts.toggle falls back to this one
    // what Popouts.toggle flips: true while the window shows or is starting. It follows what the
    // window reports (its preview messages say whether it is visible), so a close request the
    // user cancels at the unapplied-changes dialog leaves it true and the next toggle asks again.
    property bool open: false
    // the connected window's socket, null without one
    property var client: null
    readonly property bool connected: client !== null
    property bool settling: false
    // closed again while the window was still starting: it is sent a close when it connects
    property bool cancelled: false

    Component.onCompleted: Popouts.register(name, root)
    Component.onDestruction: Popouts.unregister(name, root)

    onOpenChanged: {
        if (settling)
            return;
        if (open) {
            cancelled = false;
            if (client)
                send({ type: "show" });
            else
                launch();
        } else if (client) {
            // asked to close; open again until the window says it is hidden
            send({ type: "close" });
            settle(true);
        } else if (launchWait.running) {
            // toggled off before the window connected: the launch cannot be recalled, so close
            // it once it is up, and forget the tab it was to open on
            cancelled = true;
            wantTab = "";
        }
    }

    // open the window on a tab: asks a running window to switch (after showing it), or launches it
    // and sends the tab once it has connected
    property string wantTab: ""

    function openTab(name) {
        if (client) {
            send({ type: "show" });
            send({ type: "tab", name: name });
            settle(true);
        } else {
            wantTab = name;
            open = true;
        }
    }

    // set `open` as a fact, not a request
    function settle(v) {
        settling = true;
        open = v;
        settling = false;
    }

    // -n: a second launch while the window is starting does nothing; its connection tells the
    // bar when it is up
    function launch() {
        Quickshell.execDetached(["qs", "-n", "-p", Quickshell.shellDir + "/sleepysettings.qml"]);
        launchWait.restart();
    }

    function send(msg) {
        if (!client)
            return;
        client.write(JSON.stringify(msg) + "\n");
        client.flush();
    }

    function receive(line) {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            console.warn("settings: unreadable message from the window:", line);
            return;
        }
        switch (m.type) {
        case "preview":
            Settings.pending = m.pending ?? ({});
            Settings.previewing = !!m.previewing;
            // the window previews exactly while it shows
            settle(!!m.previewing);
            break;
        case "commit":
            Settings.commitValues(m.values ?? ({}));
            break;
        case "toggle":
            Popouts.toggle(m.name);
            break;
        default:
            console.warn("settings: unknown message from the window:", line);
        }
    }

    // a launched window that never connects (it failed to start) is not open
    readonly property Timer launchWait: Timer {
        interval: 8000
        onTriggered: if (!root.client) {
            root.wantTab = "";
            root.cancelled = false;
            root.settle(false);
        }
    }

    // Opened a moment after start, not at once: on a hot reload the new server replaced the socket
    // file, then the old generation's server was destroyed and removed that same path, leaving the
    // new one listening on a deleted file, so the settings window could not connect after any reload
    // By the time this fires the old server is gone.
    readonly property Timer openLater: Timer {
        interval: 600
        running: true
        onTriggered: root.server.active = true
    }

    readonly property SocketServer server: SocketServer {
        active: false
        path: Settings.socketPath
        handler: Socket {
            id: sock
            parser: SplitParser {
                onRead: data => root.receive(data)
            }
            onConnectionStateChanged: {
                if (connected) {
                    root.client = sock;
                    root.send({ type: "power", lidControl: Battery.lidControl });
                    if (root.cancelled) {
                        root.cancelled = false;
                        root.wantTab = "";
                        root.send({ type: "close" });
                        root.settle(false);
                        return;
                    }
                    root.settle(true);
                    if (root.wantTab !== "") {
                        root.send({ type: "tab", name: root.wantTab });
                        root.wantTab = "";
                    }
                } else if (root.client === sock) {
                    // the window went away: the bar shows the stored values again
                    root.client = null;
                    root.wantTab = "";
                    Settings.previewing = false;
                    Settings.pending = {};
                    root.settle(false);
                }
            }
        }
    }

    readonly property Connections lid: Connections {
        target: Battery
        function onLidControlChanged() {
            root.send({ type: "power", lidControl: Battery.lidControl });
        }
    }

    // a commit is on disk (also the bell's do-not-disturb switch, which the window may ignore)
    readonly property Connections ack: Connections {
        target: Settings
        function onCommitted(keys) {
            root.send({ type: "committed", keys: keys });
        }
    }
}
