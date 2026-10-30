.pragma library

// One plain sentence per settings key: what it does. Settings.qml writes it as the comment above the key in sleepysettings.toml, followed
// by the range and the default taken from the schema. A key without a line here gets only the default, so a new key
// works without an entry; add one when you add the key. Sections of the file are the keys' tabs (`SECTIONS`).

var SECTIONS = {
    bar: "The bar: sizes and look.",
    left: "The left island: the workspace dots.",
    centre: "The centre island: the clock and the control centre.",
    widgets: "The right island: which widgets show and in what order.",
    notifications: "Notifications.",
    idle: "Idle timers (read by scripts/idle.py, which writes hypridle.conf).",
    power: "Laptop power: battery warnings, power profiles, the lid.",
    theme: "Theme colours (read by scripts/theme.py).",
    files: "Where the files this shell reads and writes live, and how the settings window lists tabs.",
    apps: "Default terminal and the apps that start on a workspace.",
    display: "Monitors and night light.",
    window: "State of the settings window itself."
};

// The file's layout, the same as the settings window's (one
// [section] per tab in sidebar order, named like the tab, and inside it the tab's cards in the order they appear, each card a
// "---- Title ----" heading. A key that is not listed here still works (Settings.qml appends it to its tab's section and warns);
// sleepytests checks this table against the tab files, so a row added to a tab without a line here fails the tests.
// needs: programs without which the section's settings do nothing (a second comment line says so); laptop (a section or a card) and
// laptopKeys (single keys): only used on a laptop.
var LAYOUT = [
    { tab: "bar", section: "sleepybar", cards: [
        { title: "Bar", keys: ["barHeight", "barFontSize", "barIconSize"] },
        { title: "Dropdowns", keys: ["fontSize", "iconSize"] },
        { title: "Look", keys: ["barOpacity", "corners"] },
        { title: "Islands", keys: ["islandAnimMs", "islandEasing"] },
        { title: "Popups and indicators", keys: ["capsPeek", "peekMs"] },
        { title: "Advanced", keys: ["iconNudge", "cardHover"] }] },
    { tab: "left", section: "left-island", cards: [
        { title: "Workspaces", keys: ["workspaces", "workspaceShape"] },
        { title: "Advanced", keys: ["workspaceWave", "leftPadding"] }] },
    { tab: "centre", section: "centre-island", cards: [
        { title: "Clock", keys: ["clockSize", "showDate"] },
        { title: "Next to the clock", keys: ["centreSysinfo", "centreAudio", "centreLeft"] },
        { title: "Shape", keys: ["centreStep", "centreUneven"] },
        { title: "Control centre", keys: ["hoverOpen", "tilesOrder", "tilesHidden", "toolsOrder", "toolsHidden", "customTools", "toolOverrides"] },
        { title: "Advanced", keys: ["clockFont", "clockFormat", "dateFormat", "hoverCloseMs"] }] },
    { tab: "widgets", section: "right-island", cards: [
        { title: "Widgets", keys: ["rightOrder", "rightHidden", "dropdownFit"] },
        { title: "Advanced", keys: ["updateMinutes", "rightPadding"] }] },
    { tab: "apps", section: "apps", cards: [
        { title: "Default apps", keys: ["defaultTerminal"] },
        { title: "Apps on workspaces", keys: ["workspaceApps"] }] },
    { tab: "notifications", section: "notifications", cards: [
        { title: "Notifications", keys: ["dnd", "toastStack", "shotPreview"] },
        { title: "Advanced", keys: ["toastMax", "shotPreviewMax", "notifOrder"] }] },
    { tab: "theme", section: "theme", needs: ["matugen"], cards: [
        { title: "Colours", keys: ["themePreset", "themeScheme", "themeMode", "themeContrast"] },
        { title: "Appearance", keys: ["iconTheme", "folderColours", "gtkFont", "gtkFontSize"] },
        { title: "Wallpaper", keys: ["wallpaperAuto", "wallpaperEvery", "wallpaperCustomMin", "wallpaperOrder", "wallpaperOnLogin"] },
        { title: "Advanced", keys: ["themeCoolHues", "wallpaperDir"] }] },
    { tab: "idle", section: "idle", needs: ["hypridle"], laptopKeys: ["idleBatSuspend", "idleBatSuspendMin"], cards: [
        { title: "Idle timers", keys: ["idleDim", "idleDimMin", "idleLock", "idleLockMin"] },
        { title: "On battery", laptop: true, keys: ["idleBatDim", "idleBatDimMin", "idleBatLock", "idleBatLockMin"] },
        { title: "Advanced", keys: ["idleSuspend", "idleSuspendMin", "idleBatSuspend", "idleBatSuspendMin", "lockBeforeSleep"] }] },
    { tab: "power", section: "power", laptop: true, cards: [
        { title: "Plugged in", keys: ["profileAc", "lidAc"] },
        { title: "On battery", keys: ["profileBat", "lidBat", "lowBatteryWarn", "lowBatteryPct"] },
        { title: "Advanced", keys: ["criticalPct", "criticalAction"] }] },
    { tab: "display", section: "display", cards: [
        { title: "Several monitors", keys: ["mainMonitor", "otherMonitors"] },
        { title: "Night light", keys: ["nightWarmth", "nightStrength"] }] },
    { tab: "files", section: "config", cards: [
        { title: "Hyprland", keys: ["pathCustombinds", "keybindExtraFiles", "pathMonitors", "pathHypridle"] },
        { title: "Theme", keys: ["pathColors"] },
        { title: "Window", keys: ["showUnavailableTabs"] }] },
    { tab: "window", section: "settings-window", cards: [
        { title: "Remembered by the settings window (no need to edit)", keys: ["advancedOpen"] }] }
];

var DOCS = {
    // bar
    barHeight: "Height of the bar in pixels.",
    barFontSize: "Text size on the bar, in pixels.",
    barIconSize: "Icon size on the bar, in pixels.",
    fontSize: "Text size in dropdowns and panels, in pixels.",
    iconSize: "Icon size in dropdowns and panels, in pixels.",
    iconNudge: "Moves the bar's icons up (negative) or down by a pixel or two so they sit level with the text.",
    barOpacity: "How opaque the islands are (1 is solid).",
    cardHover: "How tiles react to the pointer: lift, tilt (lift and lean toward the pointer), or a number for the lean strength in percent of the standard one.",
    corners: "How round the corners are: sharp, default or round, or a number for the island corner radius in pixels.",
    capsPeek: "Show Caps Lock on or off in the clock island when it is pressed.",
    peekMs: "How long the clock island shows the volume or Caps Lock after a change, in milliseconds.",
    islandAnimMs: "How long an island takes to open or close, in milliseconds (0 opens at once).",
    islandEasing: "How an island's opening speeds up and slows down: standard, smooth, snappy or linear.",
    // left island
    workspaces: "Workspaces 1 to this number always have a dot.",
    workspaceWave: "The active disc slides slower and the dots it passes lift.",
    workspaceShape: "Shape of the workspace dots: circle, square, triangle or number, or any short text (a glyph) to draw on each dot.",
    leftPadding: "Space between the left island's edges and its contents, in pixels.",
    // centre island
    clockFont: "The clock's typeface (an installed font family).",
    clockSize: "Clock text size, in pixels.",
    clockFormat: "The clock's time format, a Qt format string such as HH:mm (HH:mm:ss shows seconds).",
    showDate: "Show the date under the clock.",
    dateFormat: "The date's format, a Qt format string such as ddd d MMM.",
    centreSysinfo: "Show the CPU and memory readout in the centre island.",
    centreAudio: "Show the audio widget in the centre island.",
    centreLeft: "Which widget sits left of the clock: sysinfo or audio (the other goes right).",
    hoverOpen: "Open the control centre when the pointer rests on the clock.",
    hoverCloseMs: "How long the control centre stays open after the pointer leaves, in milliseconds.",
    centreStep: "The closed clock island is stepped: the clock part reaches lower than the widgets beside it.",
    centreUneven: "The open control centre's middle column hangs lower than the two side columns.",
    tilesOrder: "Order of the control centre's quick-setting tiles, comma-separated names.",
    tilesHidden: "Tiles left out of the control centre, comma-separated names.",
    toolsOrder: "Order of the control centre's tools, comma-separated names (and ids of your own tools).",
    toolsHidden: "Tools left out of the control centre, comma-separated names.",
    customTools: "Tools you added, as JSON text: a list of { id, label, icon, kind, value, terminal }. Easier to edit in the settings window.",
    toolOverrides: "Labels and icons you gave built-in tools, as JSON text. Easier to edit in the settings window.",
    // right island
    rightOrder: "Order of the right island's widgets, comma-separated names.",
    rightHidden: "Right-island widgets that are switched off, comma-separated names.",
    rightPadding: "Space between the right island's edges and its widgets, in pixels.",
    dropdownFit: "How a widget's dropdown meets its island: extend (the island widens so the panel hangs flush under it) or float (a separate card under the island).",
    updateMinutes: "How often the updates widget checks for package updates, in minutes.",
    // notifications
    toastStack: "Where a new notification toast goes: top (newest on top) or bottom.",
    toastMax: "How many notification toasts show at once.",
    notifOrder: "Order of the notification list in the bell: newest or oldest first.",
    dnd: "Do not disturb: no toasts for normal notifications.",
    shotPreview: "Show the picture under a screenshot's notification.",
    shotPreviewMax: "Tallest a screenshot preview gets, in pixels.",
    // idle
    idleDim: "Dim the screens after idle time while plugged in.",
    idleDimMin: "Minutes of idle time before dimming while plugged in.",
    idleLock: "Lock the screen after idle time while plugged in.",
    idleLockMin: "Minutes of idle time before locking while plugged in.",
    idleSuspend: "Sleep after idle time while plugged in.",
    idleSuspendMin: "Minutes of idle time before going to sleep while plugged in.",
    lockBeforeSleep: "Lock the screen before the machine goes to sleep.",
    idleBatDim: "Dim the screens after idle time on battery.",
    idleBatDimMin: "Minutes of idle time before dimming on battery.",
    idleBatLock: "Lock the screen after idle time on battery.",
    idleBatLockMin: "Minutes of idle time before locking on battery.",
    idleBatSuspend: "Sleep after idle time on battery.",
    idleBatSuspendMin: "Minutes of idle time before going to sleep on battery.",
    // power
    lowBatteryWarn: "Send one notification when the charge falls to the low level.",
    lowBatteryPct: "Charge in percent at which the low battery warning comes.",
    criticalPct: "Charge in percent at which the critical warning and its countdown start.",
    criticalAction: "What happens 60 seconds after the critical warning: suspend (sleep), hibernate, none, or cmd: followed by a command that sh -c runs only then.",
    profileAc: "Power profile to switch to when the charger is connected: keep, power-saver, balanced or performance.",
    profileBat: "Power profile to switch to when the charger is unplugged: keep, power-saver, balanced or performance.",
    lidAc: "What closing the lid does while plugged in: lock, suspend (sleep), hibernate, nothing, or cmd: followed by a command that sh -c runs only then.",
    lidBat: "What closing the lid does on battery: lock, suspend (sleep), hibernate, nothing, or cmd: followed by a command that sh -c runs only then.",
    // theme
    themeScheme: "matugen's colour scheme, such as scheme-vibrant.",
    themeMode: "dark or light.",
    themeContrast: "Distance between text and background colours: -1 (lowest) to 1 (highest), 0 is matugen's standard.",
    themeCoolHues: "Pull the seed colour taken from the wallpaper into cool hues.",
    themePreset: "The theme: empty for Sleepytheme (colours from the wallpaper), or a community theme as \"family:variant\", for example \"tokyonight:night\" (the families are the files in themes/).",
    iconTheme: "The icon theme by its folder name (for example \"Papirus-Dark\"); empty leaves the system's choice alone. Only installed themes work.",
    gtkFont: "The font apps use for menus and labels (a font family name, for example \"Inter\"); empty leaves the system's choice alone.",
    gtkFontSize: "The size of that font, in points.",
    folderColours: "Folder icons in the theme's colours (an extra icon theme on top of the chosen one, made by matugen).",
    wallpaperAuto: "Change the wallpaper by itself every so often.",
    wallpaperEvery: "How often, in minutes: 5, 10, 15, 30, 60, 120, 180, 360, 720 or 1440, or \"custom\" for wallpaperCustomMin.",
    wallpaperCustomMin: "Minutes between wallpaper changes when wallpaperEvery is \"custom\".",
    wallpaperOrder: "random (any other picture) or name (the wallpaper folder in file-name order, starting over at the end).",
    wallpaperOnLogin: "Also change the wallpaper each time you log in.",
    wallpaperDir: "Folder with your wallpapers.",
    // files
    pathHypridle: "The hypridle config that scripts/idle.py writes.",
    pathMonitors: "The Hyprland file that holds your monitor settings.",
    pathCustombinds: "The Hyprland file that holds the keybinds you add here.",
    keybindExtraFiles: "Keybind files Hyprland loads in some way the settings window cannot see.",
    pathColors: "The colours file that matugen writes and the shell watches.",
    showUnavailableTabs: "List tabs that cannot work here (a missing program, no battery) greyed out instead of hiding them.",
    // apps
    defaultTerminal: "Program name of the terminal emulator.",
    workspaceApps: "Apps that start on a workspace, as JSON text of a list. Easier to edit in the settings window.",
    // display
    mainMonitor: "Name of the main monitor (empty: the first one).",
    otherMonitors: "What the other monitors get: full, lean (workspaces and clock) or none.",
    nightWarmth: "Night light colour temperature in kelvin (lower is warmer).",
    nightStrength: "Night light strength in percent.",
    // window
    advancedOpen: "Tabs whose Advanced fold is left open, comma-separated tab keys."
};
