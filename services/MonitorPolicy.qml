pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Which monitor is the main one and what the others get.
// Settings keys, both read defensively (the schema entries come from the settings side; until they
// exist, or when the value is unusable, the defaults below apply):
//   mainMonitor    a monitor name ("HDMI-A-1"); "" or a name that is not connected -> the first screen
//   otherMonitors  "full" (every island except the tray and the notification bell; the approved
//                  default: "full bar minus tray and bell"), "lean" (workspaces and clock
//                  only) or "none" (no bar; the main screen always keeps one)
// Toasts appear only on the focused monitor, or on the main one when the focused one has no bar.
// Test hooks, never set by the shell: mockScreens ([{name, width, height}]), mockSettings
// ({mainMonitor, otherMonitors}) and mockFocused (a monitor name).
Singleton {
    id: root

    property var mockScreens: null
    property var mockSettings: null
    property string mockFocused: ""

    // the test kit's virtual monitors ("sleepytest…", sleepyshell-tests) are not the user's: no bar there, not listed
    readonly property var screenList: Array.from(root.mockScreens ?? Quickshell.screens).filter(s => !String(s.name).startsWith("sleepytest"))
    readonly property var names: root.screenList.map(s => s.name)

    // a settings value, undefined when the key is missing or reading it throws; Settings.live clamps
    // through schema[k], which does not exist for a key the settings side has not added yet
    function setting(k) {
        if (root.mockSettings)
            return root.mockSettings[k];
        try {
            if (!Settings.schema || Settings.schema[k] === undefined)
                return undefined;
            return Settings.live(k);
        } catch (e) {
            return undefined;
        }
    }

    // main monitor and mode resolved together, and everything below reads this one object: a change of
    // both keys at once (one Apply) must not pass through a half-new state, which built and tore down
    // bars within one tick
    readonly property var resolved: {
        const want = String(root.setting("mainMonitor") ?? "").trim();
        const v = root.setting("otherMonitors");
        return {
            main: root.names.includes(want) ? want : (root.names[0] ?? ""),
            mode: ["full", "lean", "none"].includes(v) ? v : "full"
        };
    }
    readonly property string mainName: root.resolved.main
    readonly property string mode: root.resolved.mode

    function isMain(screen) {
        return !!screen && screen.name === root.resolved.main;
    }

    // "main", or the mode for any other screen
    function roleOf(screen) {
        return root.isMain(screen) ? "main" : root.resolved.mode;
    }

    function hasBar(screen) {
        return root.roleOf(screen) !== "none";
    }

    // the screens that get a Bar window (shell.qml's Variants model)
    readonly property var barScreens: root.screenList.filter(s => root.hasBar(s))

    // the right island's widgets on this screen, given the names the setting lists in order
    readonly property var notOnOthers: ["tray", "notifications"]
    function rightNames(screen, names) {
        const role = root.roleOf(screen);
        if (role === "main")
            return names;
        if (role === "full")
            return names.filter(n => !root.notOnOthers.includes(n));
        return [];
    }

    // where toasts go: the focused monitor when it has a bar, else the main one
    readonly property string focusedName: root.mockFocused !== "" ? root.mockFocused : (Hyprland.focusedMonitor?.name ?? "")
    readonly property string toastName: root.barScreens.some(s => s.name === root.focusedName) ? root.focusedName : root.mainName

    function isToastScreen(screen) {
        return !!screen && screen.name === root.toastName;
    }
}
