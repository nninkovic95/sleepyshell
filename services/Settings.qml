pragma Singleton
import Quickshell
import Quickshell.Io
// ---- BEGIN toml ----
import QtQml
import "Toml.js" as Toml
import "SettingsDocs.js" as Docs

// ---- END toml ----

// User settings of the bar, staged in the settings window (sleepysettings/Sleepysettings.qml)
// and written on Apply, or edited by hand in sleepysettings.toml (the old settings.json is still read). The window is its
// own Quickshell instance (sleepysettings.qml, opened by `qs -c sleepyshell ipc call sleepybar toggle settings`), so
// this singleton lives in both processes, each loading sleepysettings.toml; an outside edit of the file
// is picked up by the watcher. The two talk over the socket at `socketPath` (the bar's end is
// services/SettingsServer.qml, the window's sleepysettings/BarLink.qml). While the window is
// open (`previewing`) its staged values show on the bar at once; Apply (commit) sends them to the
// bar, the one writer of the file while the window is linked, and `committed` fires once the bar
// says they are saved. Without the bar the window writes the file itself. Closing the window puts
// the bar back to the stored values. The theme* keys never preview (that would need matugen), nor
// do updateMinutes and wallpaperDir (see below).
// A new key goes into `schema`, the adapter and the typed properties below.
Singleton {
    id: root

    // ---- BEGIN toml ----
    // sleepysettings.toml, one [section] per settings tab with a comment above every key (read and written by Toml.js, see the
    // "sleepysettings.toml" block at the end). settings.json is migrated once, then renamed settings.json.bak.
    // The file sits beside the shell's own files, wherever the repository was cloned (a fixed ~/.config/quickshell/sleepyshell path
    // would let an unpatched test copy reach the real file)
    readonly property string path: Quickshell.shellDir + "/sleepysettings.toml"
    readonly property string legacyPath: Quickshell.shellDir + "/settings.json"   // the file before sleepysettings.toml (its name is not the new name with .json)
    // ---- END toml ----
    // the socket the settings window and the bar talk over (SettingsServer.qml lists the messages)
    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/sleepyshell-settings.sock"

    // in the settings window: its BarLink, which carries the staged values and the commits to the
    // bar; null in the bar itself, and the window works on its own while the bar is away
    property var link: null
    readonly property bool linked: link !== null && link.connected

    // the keys of a commit are on disk: the bar said so, or this process saved the file itself
    signal committed(var keys)
    // this process wrote sleepysettings.toml
    signal saved()

    // true while the settings window is open: staged values then show instead of the stored ones
    // (in the bar, SettingsServer sets it and `pending` from the window's messages)
    property bool previewing: false

    // Every key once: its default (the value the bar was built with, so a missing
    // file changes nothing), the settings tab whose Apply commits it (`groups`), and for numbers
    // the range and step of the tab's slider, or of its spin field (`spin: true`: a typed number
    // with - and + buttons instead of a slider, for small counts, times and sizes).
    // NumberRow reads the flag, so which style a key gets is decided only here.
    // A hand-edited number outside its range is clamped when read (review 4, #50).
    readonly property var schema: ({
            // bar
            barHeight: { tab: "bar", def: 30, min: 24, max: 40, spin: true },
            barFontSize: { tab: "bar", def: 14, min: 11, max: 18, spin: true },
            barIconSize: { tab: "bar", def: 18, min: 14, max: 24, spin: true },
            fontSize: { tab: "bar", def: 13, min: 11, max: 16, spin: true },
            iconSize: { tab: "bar", def: 16, min: 14, max: 20, spin: true },
            iconNudge: { tab: "bar", def: 0, min: -3, max: 3, spin: true },
            barOpacity: { tab: "bar", def: 0.55, min: 0.2, max: 1, step: 0.05 },
            cardHover: { tab: "bar", def: "tilt" },
            corners: { tab: "bar", def: "default" },
            // Popups and indicators (Bar tab: Caps Lock and the volume popup moved here from the Centre tab).
            // The Caps Lock icon on the bar is the Right island's own eye toggle (rightHidden holds "capslock"): one key, two rows.
            capsPeek: { tab: "bar", def: true },
            peekMs: { tab: "bar", def: 1200, min: 500, max: 3000, step: 100, spin: true },
            // how every island opens (Bar tab, Islands): one duration and one easing, read through
            // Theme.islandMs / islandEaseGrow / islandEaseSlide; 260 ms and "standard" are the motion from before the setting
            islandAnimMs: { tab: "bar", def: 260, min: 0, max: 800, step: 20, spin: true },
            islandEasing: { tab: "bar", def: "standard" },
            // left island (a tab for every island)
            workspaces: { tab: "left", def: 5, min: 1, max: 10, spin: true },
            workspaceWave: { tab: "left", def: false },
            workspaceShape: { tab: "left", def: "circle" },
            // the padding around the island's widgets (6 was the island's built-in padding)
            leftPadding: { tab: "left", def: 6, min: 0, max: 16, spin: true },
            // centre island
            clockFont: { tab: "centre", def: "IBM 3270" },
            clockSize: { tab: "centre", def: 20, min: 13, max: 26, spin: true },
            clockFormat: { tab: "centre", def: "HH:mm" },
            showDate: { tab: "centre", def: true },
            dateFormat: { tab: "centre", def: "ddd d MMM" },
            centreSysinfo: { tab: "centre", def: true },
            centreAudio: { tab: "centre", def: true },
            centreLeft: { tab: "centre", def: "sysinfo" },
            hoverOpen: { tab: "centre", def: true },
            hoverCloseMs: { tab: "centre", def: 350, min: 100, max: 1500, step: 50, spin: true },
            // the centre island's shape: stepped while closed (sides bar-high, the clock part deeper),
            // and open with the middle column hanging lower than the sides; off gives a plain rectangle
            centreStep: { tab: "centre", def: true },
            centreUneven: { tab: "centre", def: true },
            // the control centre's tiles (Wi-Fi ... Night light) are ordered and hidden like the tools
            tilesOrder: { tab: "centre", def: "wifi,bluetooth,dnd,awake,profile,night" },
            tilesHidden: { tab: "centre", def: "" },
            toolsOrder: { tab: "centre", def: "shuffle,picker,calendar,mixer,palette,settings" },
            toolsHidden: { tab: "centre", def: "" },
            // tools the user added: [{ id, label, icon (codepoint), kind: "app"|"command"|"link", value, terminal }], ids stable;
            // and the label / icon a built-in tool is shown with instead of its own: { name: { label, icon } }
            customTools: { tab: "centre", def: [] },
            toolOverrides: { tab: "centre", def: {} },
            // right island
            rightOrder: { tab: "widgets", def: "updates,network,bluetooth,privacy,notifications,clipboard,tray" },
            rightHidden: { tab: "widgets", def: "" },
            // the padding around the island's widgets (8 is twice Theme.insetPad, the inset of the right island's highlights)
            rightPadding: { tab: "widgets", def: 8, min: 0, max: 16, spin: true },
            // a dropdown under a side island: "extend" widens the island until the panel hangs flush under its straight
            // bottom edge, "float" leaves the island alone and shows the panel as a card under it
            dropdownFit: { tab: "widgets", def: "extend" },
            updateMinutes: { tab: "widgets", def: 30, min: 5, max: 180, step: 5, spin: true },
            // notifications
            toastStack: { tab: "notifications", def: "top" },
            toastMax: { tab: "notifications", def: 4, min: 1, max: 8, spin: true },
            notifOrder: { tab: "notifications", def: "newest" },
            dnd: { tab: "notifications", def: false },
            shotPreview: { tab: "notifications", def: true },
            shotPreviewMax: { tab: "notifications", def: 200, min: 100, max: 360, step: 20, spin: true },
            // idle: read by scripts/idle.py (hypridle.conf), see IdleTab.qml; the shell itself only
            // reacts to the "sleepyshell:dim" / "undim" events, so these never preview
            idleDim: { tab: "idle", def: true },
            idleDimMin: { tab: "idle", def: 5, min: 1, max: 60, spin: true },
            idleLock: { tab: "idle", def: true },
            idleLockMin: { tab: "idle", def: 10, min: 1, max: 120, spin: true },
            idleSuspend: { tab: "idle", def: false },
            idleSuspendMin: { tab: "idle", def: 30, min: 5, max: 240, spin: true },
            lockBeforeSleep: { tab: "idle", def: true },
            // the on-battery twins of the idle* keys (the plugged-in set), on the Idle tab too since the declutter
            // pass (no key on two tabs); scripts/idle.py picks the set by the power source
            idleBatDim: { tab: "idle", def: true },
            idleBatDimMin: { tab: "idle", def: 2, min: 1, max: 60, spin: true },
            idleBatLock: { tab: "idle", def: true },
            idleBatLockMin: { tab: "idle", def: 5, min: 1, max: 120, spin: true },
            idleBatSuspend: { tab: "idle", def: true },
            idleBatSuspendMin: { tab: "idle", def: 15, min: 5, max: 240, spin: true },
            // power (laptops, Power tab): warnings and the sets for each power source. None of
            // these preview: a staged lid or critical action must not fire while it is being chosen.
            lowBatteryWarn: { tab: "power", def: true },
            lowBatteryPct: { tab: "power", def: 15, min: 5, max: 50, spin: true },
            criticalPct: { tab: "power", def: 5, min: 2, max: 20, spin: true },
            criticalAction: { tab: "power", def: "suspend" },
            profileAc: { tab: "power", def: "balanced" },
            profileBat: { tab: "power", def: "power-saver" },
            lidAc: { tab: "power", def: "lock" },
            lidBat: { tab: "power", def: "suspend" },
            // theme: read by scripts/theme.py (matugen), see ThemeTab.qml
            themeScheme: { tab: "theme", def: "scheme-vibrant" },
            themeMode: { tab: "theme", def: "dark" },
            themeContrast: { tab: "theme", def: 0 },
            themeCoolHues: { tab: "theme", def: true },
            wallpaperDir: { tab: "theme", def: "~/Pictures/Wallpapers" },
            // ---- BEGIN theme2 (community themes, Appearance, folder colours, automatic wallpaper) ----
            // "" is Sleepytheme (matugen from the wallpaper), else "family:variant" of a themes/*.toml
            themePreset: { tab: "theme", def: "" },
            // Appearance: "" means what the desktop uses now (read through scripts/appearance.py); applied through gsettings
            iconTheme: { tab: "theme", def: "" },
            gtkFont: { tab: "theme", def: "" },
            gtkFontSize: { tab: "theme", def: 11, min: 8, max: 24, step: 1, spin: true },
            folderColours: { tab: "theme", def: false },
            // the automatic wallpaper changer (services/WallpaperTimer.qml, off by default): minutes as text, or "custom" with wallpaperCustomMin
            wallpaperAuto: { tab: "theme", def: false },
            wallpaperEvery: { tab: "theme", def: "60" },
            wallpaperCustomMin: { tab: "theme", def: 45, min: 5, max: 1440, step: 1, spin: true },
            wallpaperOrder: { tab: "theme", def: "random" },
            wallpaperOnLogin: { tab: "theme", def: false },
            // ---- END theme2 ----
            // the files Sleepysettings reads and writes (Config tab): the paths are keys (~ for home), staged and
            // applied like the rest; the consumers read the stored values (Displays, Keybinds, scripts/idle.py, Theme)
            pathHypridle: { tab: "files", def: "~/.config/hypr/hypridle.conf" },
            pathMonitors: { tab: "files", def: "~/.config/hypr/modules/monitors.lua" },
            // sleepybinds.lua (the old name custombinds.lua: Keybinds.migrate moves a stored old default over)
            pathCustombinds: { tab: "files", def: "~/.config/hypr/modules/sleepybinds.lua" },
            // keybind files beyond the ones found by following hyprland.lua (replaces pathBinds)
            keybindExtraFiles: { tab: "files", def: [] },
            pathColors: { tab: "files", def: "~/.local/state/quickshell/colors.json" },
            // the settings window itself: a row of the Config tab, staged behind Apply like the rest; the key is the same, so the saved value carries over
            showUnavailableTabs: { tab: "files", def: false },
            // ---- BEGIN apps (Apps tab) ----
            // the terminal emulator's program name (services/DefaultApps.qml); the other defaults live in mimeapps.list
            defaultTerminal: { tab: "apps", def: "kitty" },
            // the apps that start on a workspace: a JSON text of a list (services/WorkspaceApps.qml documents the entries);
            // a string so a draft compares and resets like any other key
            workspaceApps: { tab: "apps", def: "[]" },
            // ---- END apps ----
            // >>> display additions (ss-display)
            // several monitors, read by services/MonitorPolicy.qml: the main one ("" = the first screen) and what the others get ("full", "lean" or "none")
            mainMonitor: { tab: "display", def: "" },
            otherMonitors: { tab: "display", def: "full" },
            // night light, read by services/NightLight.qml in the shell (applied values only, never the staged ones): warmth in kelvin and
            // strength in percent (the schedule, the place and the fade were removed, the night light is just a toggle)
            nightWarmth: { tab: "display", def: 4500, min: 2500, max: 6500, step: 100 },
            nightStrength: { tab: "display", def: 100, min: 0, max: 100, step: 5 },
            // <<< display additions
            // the tabs whose Advanced fold is left open, comma-separated tab keys (declutter pass); saved at once like the switch above
            advancedOpen: { tab: "window", def: "" }
        })

    // the keys of each settings tab, from the schema
    readonly property var groups: {
        const g = {};
        for (const k in schema) {
            const t = schema[k].tab;
            if (!g[t])
                g[t] = [];
            g[t].push(k);
        }
        return g;
    }

    // ---- what the bar reads ----

    // bar
    readonly property int barHeight: live("barHeight")
    readonly property real barOpacity: live("barOpacity")
    readonly property int fontSize: live("fontSize")
    readonly property int iconSize: live("iconSize")
    readonly property int iconNudge: live("iconNudge")
    readonly property int barFontSize: live("barFontSize")
    readonly property int barIconSize: live("barIconSize")
    readonly property int workspaces: live("workspaces")
    readonly property bool workspaceWave: live("workspaceWave")
    // "circle", "square" or "triangle"; anything else reads as circle
    readonly property string workspaceShape: live("workspaceShape")
    // big cards on hover: "tilt" toward the pointer's edge, or "lift" only (components/Lift.qml)
    readonly property string cardHover: live("cardHover")
    // corner set for the whole shell: "sharp", "default" or "round" (Theme.cornerSets)
    readonly property string corners: live("corners")
    // the islands' shape, padding and motion, read through the island block of Theme.qml
    readonly property int islandAnimMs: live("islandAnimMs")
    // "standard", "smooth", "snappy" or "linear"; anything else reads as standard
    readonly property string islandEasing: live("islandEasing")
    readonly property bool centreStep: live("centreStep")
    readonly property bool centreUneven: live("centreUneven")
    readonly property int leftPadding: live("leftPadding")
    readonly property int rightPadding: live("rightPadding")
    // "extend" or "float"; anything else reads as extend
    readonly property string dropdownFit: live("dropdownFit")
    // notification toasts: "top" puts the newest on top and pushes the others down, "bottom"
    // adds it under them (sleepybar/widgets/notifications/NotifPopups.qml)
    readonly property string toastStack: live("toastStack")
    // the notifications dropdown's list: "newest" first (default) or "oldest" first
    readonly property string notifOrder: live("notifOrder")
    // how many notification toasts show at once (the rest wait their turn)
    readonly property int toastMax: live("toastMax")
    // do not disturb, stored so it survives a restart; the bell's switch and the control-centre
    // tile save it at once (Notifs.toggleDnd), the Notifications tab stages it like the rest
    readonly property bool dnd: live("dnd")
    // centre island
    readonly property bool hoverOpen: live("hoverOpen")
    readonly property int hoverCloseMs: live("hoverCloseMs")
    readonly property int peekMs: live("peekMs")
    // which widget sits left of the clock, "sysinfo" or "audio"; the other goes right
    readonly property string centreLeft: live("centreLeft")
    // Caps Lock flashes in the peek / OSD like a volume change (services/OsdState.qml)
    readonly property bool capsPeek: live("capsPeek")
    // a screenshot's notification shows the image under its text, at most this tall
    // (sleepybar/widgets/notifications/NotifCard.qml)
    readonly property bool shotPreview: live("shotPreview")
    readonly property int shotPreviewMax: live("shotPreviewMax")
    readonly property string clockFormat: live("clockFormat")
    readonly property string clockFont: live("clockFont")
    readonly property int clockSize: live("clockSize")
    readonly property bool showDate: live("showDate")
    readonly property bool centreSysinfo: live("centreSysinfo")
    readonly property bool centreAudio: live("centreAudio")
    readonly property string dateFormat: live("dateFormat")
    // right island: widget order and the hidden ones, comma-separated names
    readonly property string rightOrder: live("rightOrder")
    readonly property string rightHidden: live("rightHidden")
    // control centre tools: the same two strings (sleepybar/widgets/clock/ControlCentre.qml builds the grid)
    readonly property string toolsOrder: live("toolsOrder")
    readonly property string toolsHidden: live("toolsHidden")
    readonly property string tilesOrder: live("tilesOrder")
    readonly property string tilesHidden: live("tilesHidden")
    readonly property var customTools: live("customTools") ?? []
    readonly property var toolOverrides: live("toolOverrides") ?? ({})
    // stored values only; previewed, every keystroke in the folder field rescanned the
    // wallpaper folder and every step of the interval restarted the update timer
    readonly property int updateMinutes: stored("updateMinutes")
    readonly property string wallpaperDir: stored("wallpaperDir")
    // the files (Config tab): the applied paths, ~ expanded; the consumers read these, never the staged ones
    readonly property string pathHypridle: expand(stored("pathHypridle"))
    readonly property string pathMonitors: expand(stored("pathMonitors"))
    readonly property string pathCustombinds: expand(stored("pathCustombinds"))
    readonly property var keybindExtraFiles: asList(stored("keybindExtraFiles")).map(p => expand(p))
    // the old key (see the adapter): only Keybinds.migrate reads it
    readonly property string legacyPathBinds: expand(adapter.pathBinds)
    readonly property string pathColors: expand(stored("pathColors"))
    // ---- BEGIN apps ----
    // applied values only: a launch must not follow a draft
    readonly property string defaultTerminal: stored("defaultTerminal")
    readonly property string workspaceApps: stored("workspaceApps")
    // ---- END apps ----
    readonly property string themeScheme: stored("themeScheme")
    readonly property string themeMode: stored("themeMode")
    readonly property real themeContrast: stored("themeContrast")
    readonly property bool themeCoolHues: stored("themeCoolHues")
    // ---- BEGIN theme2 ----
    // applied values only: a draft must not change what the timer does or what the tab thinks is in use
    readonly property string themePreset: stored("themePreset")
    readonly property bool wallpaperAuto: stored("wallpaperAuto")
    readonly property string wallpaperOrder: stored("wallpaperOrder")
    readonly property bool wallpaperOnLogin: stored("wallpaperOnLogin")
    // the changer's interval in minutes (5 to 1440); an unknown text reads as the default hour
    readonly property int wallpaperMinutes: {
        const e = String(stored("wallpaperEvery"));
        const n = e === "custom" ? Number(stored("wallpaperCustomMin")) : Number(e);
        return isFinite(n) && n >= 5 ? Math.min(1440, Math.round(n)) : 60;
    }
    // ---- END theme2 ----
    // idle steps, written to hypridle.conf by scripts/idle.py on Apply
    readonly property bool idleDim: stored("idleDim")
    readonly property int idleDimMin: stored("idleDimMin")
    readonly property bool idleLock: stored("idleLock")
    readonly property int idleLockMin: stored("idleLockMin")
    readonly property bool idleSuspend: stored("idleSuspend")
    readonly property int idleSuspendMin: stored("idleSuspendMin")
    readonly property bool lockBeforeSleep: stored("lockBeforeSleep")
    // power: warnings, and per power source the profile, the lid action and the idle steps (PowerPolicy, LowBattery)
    readonly property bool lowBatteryWarn: stored("lowBatteryWarn")
    readonly property int lowBatteryPct: stored("lowBatteryPct")
    readonly property int criticalPct: stored("criticalPct")
    readonly property string criticalAction: stored("criticalAction")
    readonly property string profileAc: stored("profileAc")
    readonly property string profileBat: stored("profileBat")
    readonly property string lidAc: stored("lidAc")
    readonly property string lidBat: stored("lidBat")
    readonly property bool idleBatDim: stored("idleBatDim")
    readonly property int idleBatDimMin: stored("idleBatDimMin")
    readonly property bool idleBatLock: stored("idleBatLock")
    readonly property int idleBatLockMin: stored("idleBatLockMin")
    readonly property bool idleBatSuspend: stored("idleBatSuspend")
    readonly property int idleBatSuspendMin: stored("idleBatSuspendMin")
    // >>> display additions (ss-display)
    // MonitorPolicy reads these two through live(), so a staged choice shows on the bars at once
    readonly property string mainMonitor: live("mainMonitor")
    readonly property string otherMonitors: live("otherMonitors")
    // night light: stored values, the shader is rewritten only for what was applied
    readonly property int nightWarmth: stored("nightWarmth")
    readonly property int nightStrength: stored("nightStrength")
    // <<< display additions
    // the settings window's sidebar lists the tabs that cannot work here (Power without a battery,
    // a tab whose programs are missing) greyed out; off: it hides them (Sleepysettings). Set in the Config tab, applied like any key; the
    // search's "Show tabs" button saves it at once (setNow).
    readonly property bool showUnavailableTabs: stored("showUnavailableTabs")
    // which tabs keep their Advanced fold open (AdvancedSection), saved at once by setNow() as well
    readonly property string advancedOpen: stored("advancedOpen")

    function clamp(k, v) {
        const s = schema[k];
        return s.min === undefined ? v : Math.max(s.min, Math.min(s.max, v));
    }

    // the stored value, and what the bar shows: the staged value while previewing, else the stored one
    function stored(k) {
        return clamp(k, adapter[k]);
    }

    function live(k) {
        return previewing && pending.hasOwnProperty(k) ? clamp(k, pending[k]) : stored(k);
    }

    // every widget the right island knows, with its label in the settings panel
    // CPU/memory and audio are on the centre island (centreSysinfo, centreAudio)
    // battery is shown only when a battery exists
    // the power button is in the control centre's tools; a stored order
    // that still names it is fine, orderFrom drops unknown names
    readonly property var widgetNames: ["capslock", "updates", "network", "bluetooth", "battery", "privacy", "notifications", "clipboard", "tray"]
    readonly property var widgetLabels: ({
            capslock: "Caps Lock indicator",
            updates: "Package updates",
            network: "Network",
            bluetooth: "Bluetooth status",
            battery: "Battery (laptops only)",
            privacy: "Privacy indicators",
            notifications: "Notification bell",
            clipboard: "Clipboard",
            tray: "System tray"
        })

    // the control centre's tools, their labels and icons (the grid in ControlCentre and the tools
    // editor in the settings window both read these); the action of each is in ControlCentre's
    // table (the settings window cannot load that file), so a new tool goes in both
    // "wallpapers" is now "calendar"; a stored order or hidden list that still says wallpapers is read as calendar (`renamed`)
    readonly property var toolNames: ["shuffle", "picker", "calendar", "mixer", "palette", "settings"]
    readonly property var toolLabels: ({
            shuffle: "Shuffle wallpaper",
            picker: "Colour picker",
            calendar: "Calendar",
            mixer: "Audio mixer",
            palette: "Shuffle colours",
            settings: "Sleepysettings"
        })
    readonly property var toolIcons: ({
            shuffle: 0xF049D,
            picker: 0xF020A,
            calendar: 0xF0E18,   // md-calendar_month_outline
            mixer: 0xF057E,
            palette: 0xF03D8,
            settings: 0xF0493
        })
    // the programs each tool needs (services/Deps.qml): a tool whose programs are missing is greyed
    // out in the control centre and in the tools editor, and runs nothing. The shuffle tools run
    // scripts/theme.py (python3, magick, matugen, awww).
    readonly property var toolRequires: ({
            shuffle: ["python3", "magick", "matugen", "awww"],
            picker: ["hyprpicker"],
            calendar: ["khal"],
            mixer: ["pwvucontrol"],
            palette: ["python3", "magick", "matugen", "awww"],
            settings: []
        })
    // ---- the control centre's quick-setting tiles (reorderable and hideable like the tools) ----
    // names, labels and icons for the settings window's editor (it cannot load ControlCentre, which draws the real tiles with live
    // state); `tileSubs` is the sample second line the editor shows. The Wi-Fi tile says "Network" in the real grid on a machine
    // without Wi-Fi; the editor always says Wi-Fi.
    readonly property var tileNames: ["wifi", "bluetooth", "dnd", "awake", "profile", "night"]
    readonly property var tileLabels: ({
            wifi: "Wi-Fi",
            bluetooth: "Bluetooth",
            dnd: "Do not disturb",
            awake: "Keep awake",
            profile: "Power profile",
            night: "Night light"
        })
    readonly property var tileIcons: ({
            wifi: 0xF05A9,
            bluetooth: 0xF00AF,
            dnd: 0xF009A,
            awake: 0xF0176,
            profile: 0xF0F85,
            night: 0xF05A8
        })
    readonly property var tileSubs: ({
            wifi: "Connected network",
            bluetooth: "On",
            dnd: "Off",
            awake: "Off",
            profile: "Balanced",
            night: "Off"
        })

    // ---- custom tools and overrides ----
    // the user's tools: staged (the editor) or live (the control centre)
    function customList(staged) {
        return asList(staged ? get("customTools") : live("customTools"));
    }
    function customTool(id, staged) {
        return customList(staged).find(c => c.id === id) ?? null;
    }
    function overrideOf(name, staged) {
        const o = staged ? get("toolOverrides") : live("toolOverrides");
        return (o && o[name]) ? o[name] : {};
    }
    // a built-in tool shown with another label or icon
    function overridden(name, staged) {
        const o = overrideOf(name, staged);
        return !!o.label || !!o.icon;
    }
    function toolLabel(name, staged) {
        const c = customTool(name, staged);
        if (c)
            return c.label;
        return overrideOf(name, staged).label || toolLabels[name] || name;
    }
    function toolIcon(name, staged) {
        const c = customTool(name, staged);
        if (c)
            return c.icon;
        return overrideOf(name, staged).icon || toolIcons[name] || 0;
    }
    function newToolId() {
        let id;
        do {
            id = "c" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36);
        } while (customTool(id, true));
        return id;
    }
    // add a tool, or replace the one with the same id (the editor's Save)
    function stageCustomTool(tool) {
        const l = customList(true).filter(c => c.id !== tool.id);
        const i = customList(true).findIndex(c => c.id === tool.id);
        if (i >= 0)
            l.splice(i, 0, tool);
        else
            l.push(tool);
        stage("customTools", l);
    }
    // delete a tool; its place in the order and in the hidden list goes with it
    function removeCustomTool(id) {
        stage("customTools", customList(true).filter(c => c.id !== id));
        stage("toolsOrder", get("toolsOrder").split(",").map(x => x.trim()).filter(x => x !== "" && x !== id).join(","));
        stage("toolsHidden", hiddenFrom(get("toolsHidden")).filter(x => x !== id).join(","));
    }
    // a built-in's own label and icon (empty / 0 clears that part; both cleared removes the entry)
    function stageToolOverride(name, label, icon) {
        const o = Object.assign({}, get("toolOverrides") ?? {});
        const lab = (label ?? "").trim() === toolLabels[name] ? "" : (label ?? "").trim();
        const ic = icon === toolIcons[name] ? 0 : (icon ?? 0);
        if (lab === "" && !ic)
            delete o[name];
        else
            o[name] = { label: lab, icon: ic };
        stage("toolOverrides", o);
    }
    function clearToolOverride(name) {
        stageToolOverride(name, "", 0);
    }

    // tools that are an optional extra of the user's setup: while their programs are missing the control centre does not draw
    // them at all (a greyed tile would nag on a machine that never had the program), and the editor lists them dimmed with what they need.
    // The default order still names them, so they appear by themselves once the program is installed.
    readonly property var toolOptional: ({ calendar: true })
    // the tools the control centre draws: the shown ones in order, without an optional tool whose programs are missing (`needs`: a name's
    // missing programs as text, "" when it can run; ControlCentre passes Deps.needs, the tests their own)
    function toolsDrawn(needs) {
        return tools.filter(n => !(toolOptional[n] === true && needs(n) !== ""));
    }

    // the session menu button, always last in the grid, full width; not an entry of the order
    readonly property int powerIcon: 0xF0425
    readonly property string powerLabel: "Power"

    // ---- ordered lists: the right island's widgets and the control centre's tools ----

    // names that were renamed: a stored list that has the old one keeps its slot and hidden state under the new one
    readonly property var renamed: ({ wallpapers: "calendar" })

    // the names each order key may hold. The tools list also holds the ids of the user's own tools (customTools), staged or stored.
    function namesFor(orderKey, staged) {
        if (orderKey === "rightOrder")
            return widgetNames;
        if (orderKey === "tilesOrder")
            return tileNames;
        return toolNames.concat(customList(staged).map(c => c.id));
    }

    // an order string as a list: names not in `known` dropped; one it does not name yet (added
    // later) goes after its neighbour in `known`, not at the end
    function orderFrom(str, known) {
        const list = str.split(",").map(x => x.trim()).map(x => renamed[x] ?? x).filter(x => known.includes(x));
        for (let k = 0; k < known.length; k++) {
            const n = known[k];
            if (list.includes(n))
                continue;
            const before = k > 0 ? list.indexOf(known[k - 1]) : -1;
            list.splice(before + 1, 0, n);
        }
        return list;
    }

    function hiddenFrom(str) {
        return str.split(",").map(x => x.trim()).map(x => renamed[x] ?? x).filter(x => x !== "");
    }

    readonly property var order: orderFrom(rightOrder, widgetNames)
    readonly property var hidden: hiddenFrom(rightHidden)
    // what the bar shows, in order
    readonly property var rightWidgets: order.filter(n => !hidden.includes(n))
    // what the control centre shows, in order (the power button is not in the list: always last)
    readonly property var tools: orderFrom(toolsOrder, namesFor("toolsOrder", false)).filter(n => !hiddenFrom(toolsHidden).includes(n))
    // the quick-setting tiles it shows, in order
    readonly property var tiles: orderFrom(tilesOrder, tileNames).filter(n => !hiddenFrom(tilesHidden).includes(n))

    // ---- staging: the settings window edits a draft, Apply writes it ----
    // `pending` maps a key to its new value; controls read get() and write stage(). commit()
    // copies the given keys into the stored settings (sleepysettings.toml), drop() forgets them. While
    // `previewing`, the properties above show the staged value. In the bar, `pending` mirrors the
    // window's over the socket.
    property var pending: ({})

    function get(k) {
        return pending.hasOwnProperty(k) ? pending[k] : adapter[k];
    }

    function stage(k, v) {
        const p = Object.assign({}, pending);
        if (v === adapter[k] || (typeof v === "object" && JSON.stringify(v) === JSON.stringify(adapter[k])))
            delete p[k];
        else
            p[k] = v;
        pending = p;
    }

    function changed(keys) {
        return keys.some(k => pending.hasOwnProperty(k));
    }

    // Linked, the bar writes the file and answers `committed`; the values go into this process's
    // adapter at once, without a write, so the controls do not fall back to the old stored value
    // while the file is on its way. Alone, this process writes the file.
    function commit(keys) {
        const p = Object.assign({}, pending);
        const values = {};
        for (const k of keys) {
            if (p.hasOwnProperty(k)) {
                values[k] = p[k];
                delete p[k];
            }
        }
        // the commit first, the draft update after it, so the bar never shows the old stored
        // value of a committed key in between
        if (linked) {
            setStored(values, true);
            link.commit(values);
        } else {
            commitValues(values);
        }
        pending = p;
    }

    // write these values to sleepysettings.toml: the bar does this for the window's commits and for
    // the bell's do-not-disturb switch. `committed` follows once the file is saved, at once when
    // nothing differed from the stored values (then nothing is written).
    function commitValues(values) {
        const keys = Object.keys(values);
        // a damaged file is never written (see `broken`): the values live on in memory and `committed` follows at once
        if (setStored(values, false) && !broken)
            saving = saving.concat(keys);
        else
            committed(keys);
    }

    // set the adapter's properties, quietly (no write) or with one write for the lot, not one
    // per key (the other process would reload a half-written file in between); whether any changed
    property int writes: 0
    property var saving: []

    function setStored(values, quietly) {
        const before = writes;
        // ---- BEGIN toml ---- (the adapter is a plain object now: a change is counted here, not by the JsonAdapter)
        for (const k in values) {
            if (assign(k, values[k]))
                writes++;
        }
        const changed = writes !== before;
        if (changed && !quietly && !broken)
            writeFile();
        return changed;
        // ---- END toml ----
    }

    // open or close one of the bar's dropdowns by name (the Theme tab's wallpaper picker): over
    // the link, or through the bar's IPC when the window runs without it
    function toggleOnBar(name) {
        if (linked)
            link.toggle(name);
        else
            Quickshell.execDetached(["qs", "-c", "sleepyshell", "ipc", "call", "sleepybar", "toggle", name]);
    }

    // The settings search (it also matches descriptions): text and query are
    // folded the same way (accents off, lower case, one space between words), and a row is found when EVERY word of
    // the query is somewhere in its text (label, tip, tags, description lines, the labels of its options, its
    // section's title).
    function norm(s) {
        return String(s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
    }
    function searchMatch(text, query) {
        if (query === "")
            return true;
        const words = query.split(" ");
        for (let i = 0; i < words.length; i++)
            if (!text.includes(words[i]))
                return false;
        return true;
    }

    // A list value as a real JS array. What JsonAdapter loads from the file is an array-like object that Array.isArray calls false (seen
    // in a harness that read a stored list at start), so lists are copied through Array.from before anything else uses them.
    function asList(v) {
        return v !== null && v !== undefined && typeof v === "object" && typeof v.length === "number" ? Array.from(v) : [];
    }

    // a path with ~ for the home folder written out
    function expand(p) {
        return String(p).replace(/^~(?=\/|$)/, Quickshell.env("HOME"));
    }

    // the file name of a path
    function base(p) {
        return String(p).slice(String(p).lastIndexOf("/") + 1);
    }

    // a path with the home folder as ~ (the Apply bar's file names)
    function tilde(p) {
        const home = Quickshell.env("HOME");
        return home !== "" && p.startsWith(home + "/") ? "~" + p.slice(home.length) : p;
    }

    // save one value at once, no draft and no Apply (the sidebar's "Show unavailable tabs"): the
    // same two paths as commit(), linked through the bar and alone by this process
    function setNow(k, v) {
        const values = {};
        values[k] = v;
        if (linked) {
            setStored(values, true);
            link.commit(values);
        } else {
            commitValues(values);
        }
    }

    function drop(keys) {
        if (!keys.some(k => pending.hasOwnProperty(k)))
            return;
        const p = Object.assign({}, pending);
        for (const k of keys)
            delete p[k];
        pending = p;
    }

    // stage the defaults of these keys (the System tab's Reset), to be applied like any other change
    function stageDefaults(keys) {
        for (const k of keys)
            stage(k, schema[k].def);
    }

    // staged versions of the list edits, by key: the order key (rightOrder, toolsOrder) and the
    // hidden key beside it (rightHidden, toolsHidden)
    function stagedOrder(orderKey) {
        return orderFrom(get(orderKey), namesFor(orderKey, true));
    }

    function stagedShown(hiddenKey, name) {
        return !hiddenFrom(get(hiddenKey)).includes(name);
    }

    function stageShown(hiddenKey, name, on) {
        const h = hiddenFrom(get(hiddenKey)).filter(n => n !== name);
        if (!on)
            h.push(name);
        stage(hiddenKey, h.join(","));
    }

    // move an entry one step up the list (-1) or down (+1)
    function stageMove(orderKey, name, delta) {
        const i = stagedOrder(orderKey).indexOf(name);
        if (i >= 0)
            stageMoveTo(orderKey, name, i + delta);
    }

    // move an entry to a slot of the order (the drag in the settings tabs)
    function stageMoveTo(orderKey, name, to) {
        const list = stagedOrder(orderKey);
        const i = list.indexOf(name);
        if (i < 0 || to < 0 || to >= list.length || to === i)
            return;
        list.splice(i, 1);
        list.splice(to, 0, name);
        stage(orderKey, list.join(","));
    }

    // ---- BEGIN toml: sleepysettings.toml (a settings file you can read and edit) ----
    // The file has one [section] per settings tab, in schema order, with a plain comment above every key (SettingsDocs.js: what it does,
    // then the range and default from the schema). Quickshell only parses JSON, so Toml.js reads and writes it. Writing always
    // regenerates the whole file from the schema and the adapter, so the comments survive any edit; a value edited by hand is read back
    // (the file is watched); a key the schema does not know is kept at the end of its section. A value that is an object, or a list that
    // holds anything but plain values (customTools, toolOverrides), is written as a JSON text in a string.
    // A file that does not parse is never overwritten (`broken`): the last good values stay in use (the defaults at start), the window
    // shows the banner with the failing line, and a copy of the text is kept beside the file (sleepysettings.toml.broken). A missing or empty
    // file is not damage: the defaults apply and the first Apply creates it.
    // Migration: with no sleepysettings.toml and a settings.json beside it, the JSON is read once, sleepysettings.toml is written and settings.json is
    // renamed settings.json.bak (never deleted).
    property bool broken: false
    property string brokenText: ""
    // where the damaged text was copied ("" until it has been)
    property string brokenCopy: ""
    // the last write failed (a read-only file or folder): "" or what happened
    property string saveError: ""
    // why the file is not usable ("" when it is), with the line it stopped at and that line's text
    property string brokenWhy: ""
    property int brokenLine: 0
    property string brokenLineText: ""
    // keys the file has that the schema does not know (kept when writing): [{ section, key, value, comments }]
    property var extras: []
    // settings the shell dropped on purpose (the night-light schedule went, the tile is a toggle): an old file or a migrated
    // settings.json may still carry them; they are left out silently (not kept, not listed as unknown). settings.json.bak keeps them.
    readonly property var retiredKeys: ["nightSchedule", "nightOn", "nightOff", "nightFade", "nightLat", "nightLon"]
    // keys of the file whose value had the wrong kind (a word for a number): ignored, the default applies
    property var badKeys: []
    // the JSON file is being migrated: its rename follows the first save
    property bool migrating: false
    property bool migrationTried: false

    function same(a, b) {
        return a === b || (a !== null && b !== null && typeof a === "object" && typeof b === "object" && JSON.stringify(a) === JSON.stringify(b));
    }

    // set one property of the adapter; whether it changed
    function assign(k, v) {
        if (root.same(adapter[k], v))
            return false;
        adapter[k] = v;
        return true;
    }

    // a value from the file for key k, in the kind its default has: { ok, value }
    function coerce(k, v) {
        const d = k === "pathBinds" ? "" : schema[k].def;
        const bad = { ok: false };
        if (Array.isArray(d) || (d !== null && typeof d === "object")) {
            let l = v;
            if (typeof l === "string") {
                try {
                    l = JSON.parse(l);
                } catch (e) {
                    return bad;
                }
            }
            if (l === null || typeof l !== "object")
                return bad;
            return Array.isArray(l) === Array.isArray(d) ? { ok: true, value: l } : bad;
        }
        if (typeof d === "number") {
            const n = typeof v === "string" && v.trim() !== "" ? Number(v) : v;
            return typeof n === "number" && isFinite(n) ? { ok: true, value: n } : bad;
        }
        if (typeof d === "boolean") {
            if (typeof v === "boolean")
                return { ok: true, value: v };
            return v === "true" || v === "false" ? { ok: true, value: v === "true" } : bad;
        }
        if (typeof v === "string")
            return { ok: true, value: v };
        return typeof v === "number" || typeof v === "boolean" ? { ok: true, value: String(v) } : bad;
    }

    // the values of a parsed file into the adapter (no write); keys it lacks go back to their default
    function applyFound(found, extra) {
        const bad = [];
        for (const k in schema) {
            let v = schema[k].def;
            if (found.hasOwnProperty(k)) {
                const c = root.coerce(k, found[k]);
                if (c.ok)
                    v = c.value;
                else
                    bad.push(k);
            }
            root.assign(k, v);
        }
        root.assign("pathBinds", found.hasOwnProperty("pathBinds") && typeof found.pathBinds === "string" ? found.pathBinds : "");
        root.badKeys = bad;
        root.extras = extra;
        if (bad.length > 0)
            console.warn("settings: ignored values of the wrong kind in", root.path + ":", bad.join(", "));
    }

    function clearBroken() {
        root.broken = false;
        root.brokenWhy = "";
        root.brokenLine = 0;
        root.brokenLineText = "";
        root.brokenText = "";
    }

    function setBroken(r, text) {
        root.brokenWhy = r.message;
        root.brokenLine = r.line;
        root.brokenLineText = r.lineText;
        root.brokenText = text;
        root.broken = true;
        if (root.link !== null)
            brokenOut.keep(text);
    }

    // the text of sleepysettings.toml: into the adapter, or into the broken state with the adapter left as it was
    function loadText(text) {
        const t = String(text ?? "");
        if (t.trim() === "") {
            root.clearBroken();
            root.applyFound({}, []);
            return;
        }
        const r = Toml.parse(t);
        if (!r.ok) {
            root.setBroken(r, t);
            return;
        }
        const found = {};
        const extra = [];
        for (const sec of r.sections) {
            for (const e of sec.entries) {
                if (schema[e.key] !== undefined || e.key === "pathBinds") {
                    // a key counts wherever it sits (moved to another section by hand); the first one wins
                    if (!found.hasOwnProperty(e.key))
                        found[e.key] = e.value;
                } else if (!root.retiredKeys.includes(e.key)) {
                    extra.push({ section: sec.name, key: e.key, value: e.value, comments: e.comments });
                }
            }
        }
        root.clearBroken();
        root.applyFound(found, extra);
    }

    function docLine(k) {
        const s = schema[k];
        let t = Docs.DOCS[k] ?? "";
        if (s.min !== undefined)
            t += (t !== "" ? " " : "") + "Range " + s.min + " to " + s.max + ".";
        return (t !== "" ? t + " " : "") + "Default: " + (s.def !== null && typeof s.def === "object" ? JSON.stringify(s.def) : typeof s.def === "string" ? JSON.stringify(s.def) : String(s.def)) + ".";
    }

    function entryFor(k, v, comment) {
        const plain = Toml.plain(v);
        return {
            key: k,
            value: plain ? (typeof v === "object" ? Array.from(v) : v) : JSON.stringify(v),
            comment: comment,
            // JSON text reads better in single quotes (no escaped quotes)
            literal: !plain || (typeof v === "string" && /^\s*[\[{]/.test(v))
        };
    }

    // why a setting does nothing on this machine right now, for a second comment line ("" when it works): a program its tab needs
    // is missing, or it is a laptop setting and there is no battery (greyed settings say why in the file too)
    function idleWhy(L, card, k) {
        const missing = (L.needs ?? []).filter(p => !Deps.has(p));
        if (missing.length > 0)
            return "Has no effect without " + missing.join(" and ") + " installed.";
        if ((L.laptop || card.laptop || (L.laptopKeys ?? []).includes(k)) && !Battery.present)
            return "Only used on a laptop (battery or lid).";
        return "";
    }

    // the whole file from the schema and the adapter
    function render() {
        const head = {
            name: "",
            comment: [
                "Sleepyshell settings. Every option of the shell is here, laid out like the settings window (Sleepysettings): one [section]",
                "per tab in the same order, and inside it the same cards (the ---- Title ---- lines) in the same order.",
                "",
                "How to edit:",
                "  - Change a value after the = and save. The shell picks it up at once; no restart is needed.",
                "  - Text goes in quotes (\"HH:mm\"), switches are true or false, numbers are plain (30, 0.55, -2).",
                "  - A list goes in square brackets: [\"clock\", \"network\", \"battery\"].",
                "  - The comment above each setting says what it does, the values it accepts and its default.",
                "  - To go back to a default, delete the line (or the whole file): the default comes back and Apply writes it here.",
                "  - Paths may start with ~ for your home folder.",
                "",
                "If something here is wrong (a missing quote, a word where a number belongs), the settings window names the line and",
                "keeps your last working settings; nothing is overwritten until you fix it. Settings you add that the shell does not know",
                "stay in their section. The settings window rewrites this file on Apply and keeps these comments."
            ],
            entries: [],
            keepEmpty: true
        };
        const sections = [head];
        const byName = { "": head };
        // the settings window's layout (Docs.LAYOUT): one section per tab in sidebar order, its cards as headings in their order
        const placed = {};
        const byTab = {};
        for (const L of Docs.LAYOUT) {
            const sec = { name: L.section, comment: Docs.SECTIONS[L.tab] ? [Docs.SECTIONS[L.tab]] : [], entries: [] };
            sections.push(sec);
            byName[L.section] = sec;
            byTab[L.tab] = sec;
            for (const card of L.cards) {
                card.keys.forEach((k, i) => {
                    if (schema[k] === undefined)
                        return;
                    placed[k] = true;
                    const c = [root.docLine(k)];
                    const why = root.idleWhy(L, card, k);
                    if (why !== "")
                        c.push(why);
                    sec.entries.push(root.entryFor(k, adapter[k], i === 0 ? ["---- " + card.title + " ----"].concat(c) : c));
                });
            }
        }
        // a key the layout does not list yet still gets written, at the end of its tab's section
        for (const k in schema) {
            if (placed[k])
                continue;
            console.warn("settings: " + k + " is not in SettingsDocs.LAYOUT; written at the end of its section");
            let sec = byTab[schema[k].tab];
            if (!sec) {
                sec = { name: schema[k].tab, comment: [], entries: [] };
                sections.push(sec);
                byTab[schema[k].tab] = sec;
                byName[sec.name] = sec;
            }
            sec.entries.push(root.entryFor(k, adapter[k], [root.docLine(k)]));
        }
        // the old key of the keybind files, only while it still holds something (Keybinds.migrate clears it)
        if (adapter.pathBinds !== "" && byTab.files)
            byTab.files.entries.push(root.entryFor("pathBinds", adapter.pathBinds, ["Old key: a keybinds file from an earlier version; the shell moves it into keybindExtraFiles and clears this."]));
        for (const x of root.extras) {
            if (!byName[x.section]) {
                byName[x.section] = { name: x.section, comment: [], entries: [] };
                sections.push(byName[x.section]);
            }
            byName[x.section].entries.push(root.entryFor(x.key, x.value, x.comments ?? []));
        }
        return Toml.serialise(sections);
    }

    // write the file (atomically: FileView writes beside it and renames). A damaged file is never written.
    function writeFile() {
        if (root.broken)
            return;
        file.setText(root.render());
    }

    // no sleepysettings.toml: a settings.json beside it is migrated, once per process
    function tryMigrate() {
        if (root.migrationTried)
            return;
        if (!root.path.startsWith(Quickshell.shellDir + "/"))
            console.warn("settings: not migrating", root.legacyPath, "(the settings file is not in this shell's own folder)");
        root.migrationTried = true;
    }

    // Migration acts only on a settings file that sits in the folder this shell was loaded from. A copy of this file that was not given its
    // own path (a test copy, a candidate run with `qs -p`) would otherwise rename the real shell's settings.json.
    readonly property bool ownFolder: root.path.startsWith(Quickshell.shellDir + "/")

    function migrate(text) {
        let d = null;
        try {
            d = JSON.parse(text);
        } catch (e) {
            console.warn("settings: not migrating", root.legacyPath, "(not valid JSON):", e.message);
            return;
        }
        if (d === null || typeof d !== "object" || Array.isArray(d)) {
            console.warn("settings: not migrating", root.legacyPath, "(the top level is not an object)");
            return;
        }
        const found = {};
        const extra = [];
        for (const k in d) {
            if (schema[k] !== undefined || k === "pathBinds")
                found[k] = d[k];
            else if (!root.retiredKeys.includes(k))
                extra.push({ section: "other", key: k, value: d[k], comments: [] });
        }
        root.applyFound(found, extra);
        root.migrating = true;
        root.writeFile();
    }

    // sleepysettings.toml's first save done: the JSON is renamed (never deleted); -n so an older .bak is not overwritten
    Process {
        id: mover
        command: ["mv", "-n", "--", root.legacyPath, root.legacyPath + ".bak"]
    }

    // the JSON file is only opened once sleepysettings.toml turned out to be missing (setting the path loads it)
    FileView {
        id: legacy
        path: root.migrationTried && root.ownFolder ? root.legacyPath : ""
        printErrors: false
        onLoaded: root.migrate(text())
    }

    // the user chose to start over: the values in use (the defaults at start) are written over the damaged file (a copy of it is already beside it)
    function replaceBroken() {
        if (!root.broken)
            return;
        root.clearBroken();
        root.writeFile();
    }

    // the copy of a damaged file: sleepysettings.toml.broken, written once for each damaged text (the newest damaged text is the one kept)
    FileView {
        id: brokenOut
        path: root.path + ".broken"
        printErrors: false
        preload: false
        atomicWrites: false
        property string last: ""
        function keep(txt) {
            if (txt === last)
                return;
            last = txt;
            setText(txt);
            root.brokenCopy = path;
        }
    }

    // the file: loaded at start (blocking, so the values are there before anything reads them) and again whenever it changes, by this
    // process or another (a hand edit, the other process's write). A draft in the window (`pending`) is not touched by a reload.
    // one more read 400 ms after a change: when the file is replaced (an editor's or a tool's write-then-rename) the watch moves to the new
    // file during the reload, and a write landing in that moment sends no event, so that edit was never picked up (found by the toml tests)
    Timer {
        id: recheck
        interval: 400
        onTriggered: file.reload()
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.loadText(text())
        onLoadFailed: {
            root.clearBroken();
            Qt.callLater(root.tryMigrate);
        }
        onFileChanged: {
            reload();
            recheck.restart();
        }
        onSaved: {
            root.saveError = "";
            const keys = root.saving;
            root.saving = [];
            if (root.migrating) {
                root.migrating = false;
                mover.running = true;
            }
            root.saved();
            if (keys.length > 0)
                root.committed(keys);
        }
        onSaveFailed: error => {
            root.saving = [];
            root.migrating = false;
            root.saveError = "Could not write " + root.path;
            console.warn("settings: could not write", root.path, error);
        }
    }
    // ---- END toml ----

    // the stored values: plain properties that start at the schema defaults; loading the file replaces them
    QtObject {
        id: adapter
            property int barHeight: root.schema.barHeight.def
            property real barOpacity: root.schema.barOpacity.def
            property int fontSize: root.schema.fontSize.def
            property int iconSize: root.schema.iconSize.def
            property int iconNudge: root.schema.iconNudge.def
            property int barFontSize: root.schema.barFontSize.def
            property int barIconSize: root.schema.barIconSize.def
            property int workspaces: root.schema.workspaces.def
            property bool workspaceWave: root.schema.workspaceWave.def
            property string workspaceShape: root.schema.workspaceShape.def
            property string cardHover: root.schema.cardHover.def
            property string corners: root.schema.corners.def
            property int islandAnimMs: root.schema.islandAnimMs.def
            property string islandEasing: root.schema.islandEasing.def
            property bool centreStep: root.schema.centreStep.def
            property bool centreUneven: root.schema.centreUneven.def
            property int leftPadding: root.schema.leftPadding.def
            property int rightPadding: root.schema.rightPadding.def
            property string dropdownFit: root.schema.dropdownFit.def
            property string toastStack: root.schema.toastStack.def
            property string notifOrder: root.schema.notifOrder.def
            property int toastMax: root.schema.toastMax.def
            property bool dnd: root.schema.dnd.def
            property bool hoverOpen: root.schema.hoverOpen.def
            property int hoverCloseMs: root.schema.hoverCloseMs.def
            property int peekMs: root.schema.peekMs.def
            property bool capsPeek: root.schema.capsPeek.def
            property bool shotPreview: root.schema.shotPreview.def
            property int shotPreviewMax: root.schema.shotPreviewMax.def
            property string clockFormat: root.schema.clockFormat.def
            property string clockFont: root.schema.clockFont.def
            property int clockSize: root.schema.clockSize.def
            property bool showDate: root.schema.showDate.def
            property bool centreSysinfo: root.schema.centreSysinfo.def
            property bool centreAudio: root.schema.centreAudio.def
            property string centreLeft: root.schema.centreLeft.def
            property string dateFormat: root.schema.dateFormat.def
            property string rightOrder: root.schema.rightOrder.def
            property string rightHidden: root.schema.rightHidden.def
            property string toolsOrder: root.schema.toolsOrder.def
            property string toolsHidden: root.schema.toolsHidden.def
            property string tilesOrder: root.schema.tilesOrder.def
            property string tilesHidden: root.schema.tilesHidden.def
            property var customTools: root.schema.customTools.def
            property var toolOverrides: root.schema.toolOverrides.def
            property int updateMinutes: root.schema.updateMinutes.def
            property string wallpaperDir: root.schema.wallpaperDir.def
            property string pathHypridle: root.schema.pathHypridle.def
            property string pathMonitors: root.schema.pathMonitors.def
            property string pathCustombinds: root.schema.pathCustombinds.def
            property var keybindExtraFiles: root.schema.keybindExtraFiles.def
            // pathBinds is an old key (Keybinds now follows hyprland.lua); the value is only read, once, to carry a
            // custom file over into keybindExtraFiles (Keybinds.migrate), then cleared
            property string pathBinds: ""
            property string pathColors: root.schema.pathColors.def
            // ---- BEGIN apps ----
            property string defaultTerminal: root.schema.defaultTerminal.def
            property string workspaceApps: root.schema.workspaceApps.def
            // ---- END apps ----
            property string themeScheme: root.schema.themeScheme.def
            property string themeMode: root.schema.themeMode.def
            property real themeContrast: root.schema.themeContrast.def
            property bool themeCoolHues: root.schema.themeCoolHues.def
            // ---- BEGIN theme2 ----
            property string themePreset: root.schema.themePreset.def
            property string iconTheme: root.schema.iconTheme.def
            property string gtkFont: root.schema.gtkFont.def
            property int gtkFontSize: root.schema.gtkFontSize.def
            property bool folderColours: root.schema.folderColours.def
            property bool wallpaperAuto: root.schema.wallpaperAuto.def
            property string wallpaperEvery: root.schema.wallpaperEvery.def
            property int wallpaperCustomMin: root.schema.wallpaperCustomMin.def
            property string wallpaperOrder: root.schema.wallpaperOrder.def
            property bool wallpaperOnLogin: root.schema.wallpaperOnLogin.def
            // ---- END theme2 ----
            property bool idleDim: root.schema.idleDim.def
            property int idleDimMin: root.schema.idleDimMin.def
            property bool idleLock: root.schema.idleLock.def
            property int idleLockMin: root.schema.idleLockMin.def
            property bool idleSuspend: root.schema.idleSuspend.def
            property int idleSuspendMin: root.schema.idleSuspendMin.def
            property bool lockBeforeSleep: root.schema.lockBeforeSleep.def
            property bool lowBatteryWarn: root.schema.lowBatteryWarn.def
            property int lowBatteryPct: root.schema.lowBatteryPct.def
            property int criticalPct: root.schema.criticalPct.def
            property string criticalAction: root.schema.criticalAction.def
            property string profileAc: root.schema.profileAc.def
            property string profileBat: root.schema.profileBat.def
            property string lidAc: root.schema.lidAc.def
            property string lidBat: root.schema.lidBat.def
            property bool idleBatDim: root.schema.idleBatDim.def
            property int idleBatDimMin: root.schema.idleBatDimMin.def
            property bool idleBatLock: root.schema.idleBatLock.def
            property int idleBatLockMin: root.schema.idleBatLockMin.def
            property bool idleBatSuspend: root.schema.idleBatSuspend.def
            property int idleBatSuspendMin: root.schema.idleBatSuspendMin.def
            // >>> display additions (ss-display)
            property string mainMonitor: root.schema.mainMonitor.def
            property string otherMonitors: root.schema.otherMonitors.def
            property int nightWarmth: root.schema.nightWarmth.def
            property int nightStrength: root.schema.nightStrength.def
            // <<< display additions
            property bool showUnavailableTabs: root.schema.showUnavailableTabs.def
            property string advancedOpen: root.schema.advancedOpen.def
    }
}
