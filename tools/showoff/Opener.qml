pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Terminal.js" as Terminal

// The "Recording saved" notification and its two buttons.
//
// notify-send with actions waits until the notification is closed or an action is chosen, then prints
// the action's name. Open plays the file with xdg-open. Show in folder opens the folder in the default
// file manager: xdg-mime's default for inode/directory. A terminal one (yazi, Terminal=true) cannot be
// started by xdg-open without $TERMINAL / x-terminal-emulator / xdg-terminal-exec, so it runs in the
// terminal chosen in sleepyshell's settings (defaultTerminal), built the way the shell builds it
// (Terminal.js); any other file manager goes through xdg-open.
//
// Quickshell reads the desktop entries in the background, starting with the first question about them, so an
// entry asked for only on the click is not there yet. They are asked for at start, and a click before they
// are in waits for them.
Singleton {
    id: root

    // sleepyshell's terminal setting, read from its settings file; kitty, the shell's default, until read
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    property string terminal: "kitty"
    property FileView settingsFile: FileView {
        path: root.configHome + "/quickshell/sleepyshell/sleepysettings.toml"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = text().match(/^defaultTerminal\s*=\s*"([^"]*)"/m);
            // a program name only, never a path or a command line
            root.terminal = m && /^[A-Za-z0-9._+-]+$/.test(m[1]) ? m[1] : "kitty";
        }
    }

    Component.onCompleted: DesktopEntries.applications.values.length

    function notifySaved(path) {
        saved.path = path;
        saved.command = ["notify-send", "-a", "Screen recorder", "-i", "media-record", "--action=open=Open", "--action=folder=Show in folder", "Recording saved", path];
        saved.running = true;
    }

    function showFolder(dir) {
        folderDefault.dir = dir;
        folderDefault.running = true;
    }

    property Process saved: Process {
        property string path: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const action = text.trim();
                console.info("showoff: notification action '" + action + "'");
                if (action === "open")
                    Quickshell.execDetached(["xdg-open", root.saved.path]);
                else if (action === "folder")
                    root.showFolder(root.saved.path.slice(0, root.saved.path.lastIndexOf("/")));
            }
        }
    }

    property Process folderDefault: Process {
        property string dir: ""
        property string id: ""
        command: ["xdg-mime", "query", "default", "inode/directory"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.folderDefault.id = text.trim().replace(/\.desktop$/, "");
                entryWait.tries = 0;
                root.reveal();
            }
        }
    }

    // up to 3 s for the desktop entries when the first click comes before they are read
    property Timer entryWait: Timer {
        property int tries: 0
        interval: 250
        onTriggered: root.reveal()
    }

    function reveal() {
        const id = root.folderDefault.id, dir = root.folderDefault.dir;
        const e = id !== "" ? DesktopEntries.byId(id) : null;
        if (!e && id !== "" && entryWait.tries < 12) {
            entryWait.tries++;
            entryWait.restart();
            return;
        }
        let cmd;
        if (e && e.runInTerminal && e.command && e.command.length > 0) {
            const argv = Array.from(e.command).filter(x => !/^%[a-zA-Z%]$/.test(x));
            cmd = Terminal.command(root.terminal, argv.concat([dir]));
        } else {
            cmd = ["xdg-open", dir];
        }
        console.info("showoff: folder default '" + id + "' entry " + (e ? "found" : "missing") + ", running " + JSON.stringify(cmd));
        Quickshell.execDetached(cmd);
    }
}
