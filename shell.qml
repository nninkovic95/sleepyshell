//@ pragma UseQApplication
// Top bar for Hyprland. Run with: qs -c sleepyshell
// Colours come from ~/.local/state/quickshell/colors.json, written by matugen (see Theme.qml).
// The QApplication pragma is needed for tray right-click menus (QsMenuAnchor); it takes effect on restart.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services
import qs.sleepybar.popups.calendar
import qs.sleepybar.popups.osd
import qs.sleepybar.popups.polkit
import qs.sleepybar.popups.session
import qs.sleepybar
import qs.components

ShellRoot {
    id: shellRoot
    // apps that start on a workspace (Apps tab): the login ones now, the first-visit ones when their workspace is focused
    Component.onCompleted: WorkspaceApps.autorun = true
    // idle dimming from hypridle ("sleepyshell:dim" / "sleepyshell:undim", scripts/idle.py)
    property bool dimmed: false
    // the NightLight singleton (services/NightLight.qml) reads its lua file as soon as it is named; naming it here does that with the shell,
    // not with whatever first shows the control centre's tile
    readonly property bool nightLightOn: NightLight.on

    // the main monitor always has a bar; the others follow Settings.otherMonitors (full, lean, none)
    // (services/MonitorPolicy.qml); the dim overlay below covers every screen
    Variants {
        model: MonitorPolicy.barScreens
        Sleepybar {}
    }

    Variants {
        model: Quickshell.screens
        DimOverlay {
            dimmed: shellRoot.dimmed
        }
    }

    // ---- BEGIN wallpaper changer: off by default, Theme tab > Wallpaper
    WallpaperTimer {
        dimmed: shellRoot.dimmed
    }
    // ---- END wallpaper changer

    // the lock screen is its own instance (sleepylock.qml, ext-session-lock + PAM); this starts it on
    // `lock` below and on logind's Lock signal
    SleepylockLauncher {
        id: sleepylockLauncher
    }

    // the settings window is its own instance (sleepysettings.qml, launched by `toggle settings` below
    // or from the launcher); this is the bar's end of their socket
    SettingsServer {}

    // laptop power: low-battery notifications and the critical action, the profile and
    // idle set per power source, the lid; all idle on a machine without a battery
    LowBattery {}
    PowerPolicy {
        id: power
    }

    // the session's polkit agent (admin password prompts), replaces hyprpolkitagent
    PolkitPrompt {}

    // lock / suspend / log out / reboot / shut down, replaces wlogout
    SessionMenu {}

    // month calendar with khal's events: a big centred panel on the focused monitor, like the session
    // menu (one instance, no bar); opened by the control centre's Calendar tile or the toggle:calendar event
    CalendarPopup {}

    // themed replacement for Quickshell's reload popups (success: none, failure: a card)
    ReloadToast {}

    // Hyprland binds reach the shell as custom events on Hyprland's own socket, with no process
    // started per key press: `hl.dsp.event("sleepyshell:toggle:<name>")`, `"sleepyshell:sleepylock"`,
    // `"sleepyshell:capslock"`, `"sleepyshell:lid:closed"` / `"open"` (switch binds), and from hypridle `"sleepyshell:dim"` / `"undim"`. IPC only where it
    // is needed (the settings window, scripts): the IpcHandler below is for scripts and other instances.
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (e.name !== "custom" || !e.data.startsWith("sleepyshell:"))
                return;
            const [what, arg] = e.data.slice("sleepyshell:".length).split(":");
            if (what === "toggle" && arg)
                Popouts.toggle(arg);
            else if (what === "sleepylock")
                sleepylockLauncher.lock();
            else if (what === "capslock")
                CapsLock.refresh();
            else if (what === "lid" && arg)
                power.lid(arg);
            else if (what === "dim" || what === "undim")
                shellRoot.dimmed = what === "dim";
        }
    }

    // qs -c sleepyshell ipc call sleepybar toggle <clock|audio|network|privacy|wallpaper|sysinfo|updates|settings|session>,
    // sleepylock, clearNotifications (the dropdown's Clear all, for scripts and recordings)
    // (without `-c sleepyshell` qs looks for a "default" config and finds no instance). The volume
    // keys in binds.lua go through wpctl, not here, so there are no audio handlers.
    IpcHandler {
        target: "sleepybar"

        function toggle(name: string): void {
            Popouts.toggle(name);
        }

        function sleepylock(): void {
            sleepylockLauncher.lock();
        }

        function clearNotifications(): void {
            Notifs.startClear();
        }
    }
}
