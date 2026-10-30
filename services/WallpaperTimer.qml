import QtQuick
import Quickshell

// The automatic wallpaper changer (off by default, Theme tab > Wallpaper). While the setting is on, every
// `Settings.wallpaperMinutes` it runs `scripts/theme.py --auto` like the Random wallpaper button does: the script picks the next picture by
// the chosen order (random or by name), never the one on screen, sets it, and renders the theme again (a community theme keeps its colours).
// A step is skipped while the screen is dimmed for idling (`dimmed`, from hypridle's event); the script itself does nothing while the lock
// screen runs (it looks at the process list), so a locked session never changes its wallpaper behind the lock. A skipped step is not made
// up: the next one comes a full interval later. "Also on login" runs one step shortly after the shell starts (the wallpaper daemon starts
// from the session's autostart, so it gets a few seconds), once per login (`persist` survives a hot reload of the shell).
// Only the applied settings count, never a draft.
QtObject {
    id: root

    // the shell's dim state (shell.qml binds it)
    property bool dimmed: false
    // what the last step did: "", "ran", "dimmed", "off"
    property string last: ""
    property int ran: 0
    readonly property bool on: Settings.wallpaperAuto
    readonly property int intervalMs: Settings.wallpaperMinutes * 60000
    // seconds between the shell's start and the login step
    property int loginDelayMs: 8000

    readonly property var command: [Quickshell.shellPath("scripts/theme.py"), "--auto"]

    // one step; the result is also in `last`
    function tick() {
        let r = "ran";
        if (!root.on)
            r = "off";
        else if (root.dimmed)
            r = "dimmed";
        else {
            root.ran++;
            Quickshell.execDetached(root.command);
        }
        root.last = r;
        return r;
    }

    readonly property PersistentProperties persist: PersistentProperties {
        reloadableId: "wallpaperTimer"
        property bool loginDone: false
    }

    readonly property Timer every: Timer {
        interval: root.intervalMs
        repeat: true
        running: root.on
        onTriggered: root.tick()
    }

    // the login step: once per login, and only when "Also on login" is on
    function loginStep() {
        if (root.persist.loginDone)
            return "done";
        root.persist.loginDone = true;
        return Settings.wallpaperOnLogin ? root.tick() : "off";
    }

    readonly property Timer login: Timer {
        interval: root.loginDelayMs
        running: !root.persist.loginDone
        onTriggered: root.loginStep()
    }
}
