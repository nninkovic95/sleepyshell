pragma Singleton
import Quickshell
import Quickshell.Io

// Which of the external programs the shell uses exist (grey out what cannot
// work instead of running it and failing). One probe at start: `sh -c 'for c in "$@"; ...' sh
// <names>` with the names as arguments (never spliced into the script), printing the ones that
// `command -v` finds. Read-only; it starts nothing else.
//
// Settings rows, sections and tabs, the control centre's MenuItems and Tiles take an optional
// `requires: ["prog", ...]`. While anything in it is missing they are greyed out and disabled and
// show needs(list), for example "Needs hyprpicker (not installed)", and run nothing.
// Until the probe has answered (a few ms) every program counts as present, so nothing flashes grey.
// The list below is CLAUDE.md's Dependencies plus the programs the code calls; a name asked about
// that is not in it counts as missing, which is loud on purpose (add it here).
Singleton {
    id: root

    // The programs the shell needs for a feature (only what is needed): the bar needs quickshell, hyprland
    // and python; a feature greys out without its program (theme: matugen, ImageMagick and a wallpaper daemon; idle: hypridle; screenshot
    // copy: wl-copy; the calendar: khal, optional; the rest are tools of the system). `want()` adds the ones found out while running.
    readonly property var builtin: [
        "matugen", "magick", "awww", "swww", "nmcli", "paru", "yay", "pacman", "fakeroot", "lspci", "hypridle", "python3",
        "notify-send", "gdbus", "flock", "loginctl", "systemctl", "wpctl", "hyprctl", "busctl", "systemd-inhibit", "wl-copy", "khal"
    ]
    // Programs the shell only LAUNCHES (the launcher, the audio mixer, the colour picker, the terminal, the file manager and the editor
    // through the desktop's opener): they are the user's own apps, not dependencies. Probed so a tool can grey out, but the message is
    // "Not found: <command>" and there is no install hint. Every command a custom tool runs or the editor of programs.lua names (`extra`)
    // is one too.
    readonly property var apps: ["walker", "pwvucontrol", "hyprpicker", "kitty", "xdg-open", "ikhal"]
    property var extra: []
    // the terminal of the Apps tab is a setting (defaultTerminal): an app like the others, probed too
    readonly property string terminal: Settings.defaultTerminal
    readonly property var wanted: root.builtin.concat(root.apps, root.extra, [root.terminal])
    onTerminalChanged: if (!root.builtin.includes(root.terminal) && !root.isApp(root.terminal))
        probe.running = true
    // programs that stand in for each other: the wallpaper daemon is `awww`, or `swww` (its old name; distributions differ)
    readonly property var alternatives: ({ awww: ["swww"] })
    // the wallpaper daemon that is installed ("awww" unless only swww is)
    readonly property string wallpaperDaemon: root.base("awww") || !root.base("swww") ? "awww" : "swww"
    function isApp(name) {
        return root.apps.includes(name) || root.extra.includes(name) || name === root.terminal;
    }

    // the package that has each program, where the name differs (Arch names; a missing file can mean a missing program)
    readonly property var packages: ({
            "magick": "imagemagick",
            "wl-copy": "wl-clipboard",
            "hyprctl": "hyprland",
            "lspci": "pciutils",
            "busctl": "systemd",
            "loginctl": "systemd",
            "flock": "util-linux",
            "systemctl": "systemd",
            "systemd-inhibit": "systemd",
            "notify-send": "libnotify",
            "xdg-open": "xdg-utils",
            "ikhal": "khal",
            "khal": "khal",
            "python3": "python",
            "nmcli": "networkmanager",
            "gdbus": "glib2",
            "wpctl": "wireplumber"
        })
    // Is the package in this machine's own repositories? Decided offline by pacman's sync database (`pacman -Si <pkg>`, read only, no
    // network), asked once per package and kept for the session; true until the answer is in. Not found there means the AUR for this user
    // (whether it is AUR or pacman; the AUR itself is never queried, it blocks automated requests).
    property var repo: ({})
    property var asking: []
    function inRepos(pkg) {
        const v = root.repo[pkg];
        if (v !== undefined)
            return v;
        // asked from outside the binding that wants the answer
        Qt.callLater(root.ask, pkg);
        return true;
    }
    function ask(pkg) {
        if (root.repo[pkg] !== undefined || root.asking.includes(pkg))
            return;
        root.asking = root.asking.concat([pkg]);
        root.askNext();
    }
    function askNext() {
        if (sync.running || root.asking.length === 0)
            return;
        sync.pkg = root.asking[0];
        sync.command = ["pacman", "-Si", sync.pkg];
        sync.running = true;
    }
    // forget the answers (the tests change what the database knows)
    function forgetRepo() {
        root.repo = {};
        root.asking = [];
    }

    // how to get a program, for a message that is shown and never run: { pkg, text, line }. `text` is the sentence ("Install the x package.");
    // `line` the command: paru if there is paru, else yay, else `sudo pacman -S` when the package is in the repositories; a package that is
    // not (the AUR) with no helper has no command, only the sentence "x is in the AUR. Install an AUR helper like paru or yay first."; off
    // Arch (no pacman) the line is just the package name
    function install(prog) {
        // the wallpaper daemon: awww, unless only swww is known to pacman -Si (a distribution that still ships the old name)
        const pkg = prog === "awww" && !root.inRepos("awww") && root.inRepos("swww") ? "swww" : (root.packages[prog] ?? prog);
        if (!root.has("pacman"))
            return { pkg: pkg, text: "Install the " + pkg + " package.", line: pkg };
        const helper = root.has("paru") ? "paru" : root.has("yay") ? "yay" : "";
        if (helper !== "")
            return { pkg: pkg, text: "Install the " + pkg + " package.", line: helper + " -S " + pkg };
        if (!root.inRepos(pkg))
            return { pkg: pkg, text: pkg + " is in the AUR. Install an AUR helper like paru or yay first.", line: "" };
        return { pkg: pkg, text: "Install the " + pkg + " package.", line: "sudo pacman -S " + pkg };
    }

    // ask for a program the config names (the editor of programs.lua): probed with the rest.
    // Until the new answer is in, it counts as present (has() says yes while the probe runs), so nothing flashes grey.
    function want(name) {
        if (name === "" || root.wanted.includes(name))
            return;
        root.extra = root.extra.concat([name]);
        probe.running = true;
    }

    // the names the probe found, and whether it has answered
    property var found: []
    property bool ready: false
    // test hook: names to treat as missing (the sandbox's IPC `fake` sets it; nothing in the shell does)
    property var fakeMissing: []
    // test hook: names to treat as present (the sandbox has no yay, and the install hint depends on which helper there is)
    property var fakePresent: []

    function has(name) {
        return root.base(name) || (root.alternatives[name] ?? []).some(n => root.base(n));
    }

    function base(name) {
        if (root.fakePresent.includes(name))
            return true;
        return !root.ready || (probe.running && !root.found.includes(name) && !root.fakeMissing.includes(name)) || (root.found.includes(name) && !root.fakeMissing.includes(name));
    }

    // the names of `list` that are missing
    function missing(list) {
        return (list ?? []).filter(n => !root.has(n));
    }

    function available(list) {
        return root.missing(list).length === 0;
    }

    // "Needs matugen (not installed)", "" when nothing is missing; a program the shell only launches (the user's own app) reads
    // "Not found: pwvucontrol" instead, with no hint to install anything
    function needs(list) {
        const m = root.missing(list);
        if (m.length === 0)
            return "";
        const deps = m.filter(n => !root.isApp(n)), apps = m.filter(n => root.isApp(n));
        const out = [];
        if (deps.length > 0)
            out.push("Needs " + (deps.length === 1 ? deps[0] : deps.slice(0, -1).join(", ") + " and " + deps[deps.length - 1]) + " (not installed)");
        if (apps.length > 0)
            out.push("Not found: " + apps.join(", "));
        return out.join(". ");
    }

    // `pacman -Si` for one package at a time: exit 0 when the sync database has it
    Process {
        id: sync
        property string pkg: ""
        onExited: code => {
            const r = Object.assign({}, root.repo);
            r[sync.pkg] = code === 0;
            root.repo = r;
            root.asking = root.asking.slice(1);
            root.askNext();
        }
    }

    Process {
        id: probe
        command: ["sh", "-c", 'for c in "$@"; do command -v "$c" >/dev/null && echo "$c"; done', "sh"].concat(root.wanted)
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.found = text.split("\n").map(x => x.trim()).filter(x => x !== "");
                root.ready = true;
            }
        }
    }
}
