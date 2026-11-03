.pragma library

// Words for Hyprland's key names, so people read "Super + Left click" and "Mute" instead of "SUPER + mouse:272"
// and "XF86AudioMute". One table for every place that shows a key: the Keybinds window, the settings window's
// Keybinds tab, and a second Quickshell config that reuses this file through a link (Quickshell imports nothing
// from outside a config's own folder). Names the table does not know are shown as written.

// modifiers in the order they are shown, and Hyprland's modmask bits
const modOrder = ["Super", "Ctrl", "Alt", "AltGr", "Shift"];
const modBits = { Shift: 1, Ctrl: 4, Alt: 8, Super: 64, AltGr: 128 };
const modWords = {
    super: "Super", mod4: "Super", win: "Super", super_l: "Super", super_r: "Super",
    ctrl: "Ctrl", control: "Ctrl", control_l: "Ctrl", control_r: "Ctrl",
    alt: "Alt", mod1: "Alt", alt_l: "Alt", alt_r: "Alt",
    shift: "Shift", shift_l: "Shift", shift_r: "Shift",
    altgr: "AltGr", mod5: "AltGr", iso_level3_shift: "AltGr"
};

// Hyprland key names (xkb names, lower case) and mouse names
const words = {
    "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click", "mouse:275": "Back",
    "mouse:276": "Forward", mouse_down: "Scroll down", mouse_up: "Scroll up", mouse_left: "Scroll left",
    mouse_right: "Scroll right",
    escape: "Esc", minus: "-", equal: "=", backspace: "Backspace", tab: "Tab", bracketleft: "[", bracketright: "]",
    return: "Enter", semicolon: ";", apostrophe: "'", grave: "`", backslash: "\\", comma: ",", period: ".", slash: "/",
    space: "Space", caps_lock: "Caps Lock", num_lock: "Num Lock", scroll_lock: "Scroll Lock", print: "Print",
    home: "Home", up: "Up", prior: "Page Up", page_up: "Page Up", left: "Left", right: "Right", end: "End",
    down: "Down", next: "Page Down", page_down: "Page Down", insert: "Insert", delete: "Delete", pause: "Pause",
    menu: "Menu", kp_enter: "Num Enter", kp_multiply: "Num *", kp_subtract: "Num -", kp_add: "Num +",
    kp_divide: "Num /", kp_decimal: "Num .",
    xf86audiomute: "Mute", xf86audiolowervolume: "Volume Down", xf86audioraisevolume: "Volume Up",
    xf86audiomicmute: "Mic Mute", xf86audionext: "Next", xf86audioplay: "Play/Pause", xf86audiopause: "Pause",
    xf86audioprev: "Previous", xf86audiostop: "Stop", xf86monbrightnessup: "Brightness Up",
    xf86monbrightnessdown: "Brightness Down", xf86calculator: "Calculator", xf86mail: "Mail", xf86search: "Search",
    xf86explorer: "Files", xf86homepage: "Browser", xf86poweroff: "Power", xf86sleep: "Sleep"
};

// evdev key codes (binds written as code:<xkb keycode>, which is the evdev code + 8)
const evdevWords = {
    1: "Esc", 12: "-", 13: "=", 14: "Backspace", 15: "Tab", 26: "[", 27: "]", 28: "Enter", 39: ";", 40: "'",
    41: "`", 43: "\\", 51: ",", 52: ".", 53: "/", 55: "Num *", 57: "Space", 58: "Caps Lock", 69: "Num Lock",
    70: "Scroll Lock", 74: "Num -", 78: "Num +", 87: "F11", 88: "F12", 96: "Num Enter", 98: "Num /",
    99: "Print", 102: "Home", 103: "Up", 104: "Page Up", 105: "Left", 106: "Right", 107: "End", 108: "Down",
    109: "Page Down", 110: "Insert", 111: "Delete", 113: "Mute", 114: "Volume Down", 115: "Volume Up",
    119: "Pause", 127: "Menu", 163: "Next", 164: "Play/Pause", 165: "Previous"
};

function evdev(c) {
    if (evdevWords[c] !== undefined)
        return evdevWords[c];
    if (c >= 2 && c <= 11)
        return String((c - 1) % 10);
    const rows = [[16, "QWERTYUIOP"], [30, "ASDFGHJKL"], [44, "ZXCVBNM"]];
    for (const [start, letters] of rows)
        if (c >= start && c < start + letters.length)
            return letters[c - start];
    if (c >= 59 && c <= 68)
        return "F" + (c - 58);
    if (c >= 71 && c <= 83)
        return "Num " + ({ 71: "7", 72: "8", 73: "9", 75: "4", 76: "5", 77: "6", 79: "1", 80: "2", 81: "3", 82: "0", 83: "." }[c] ?? c);
    return "Key " + c;
}

// the modifier word for a name, or undefined when it is not a modifier
function mod(name) {
    return modWords[String(name).trim().toLowerCase()];
}

// the modifiers of a modmask, in display order
function mods(mask) {
    return modOrder.filter(n => (mask & modBits[n]) !== 0);
}

// one key or modifier as words
function key(name) {
    const k = String(name).trim();
    const s = k.toLowerCase();
    if (modWords[s] !== undefined)
        return modWords[s];
    if (words[s] !== undefined)
        return words[s];
    if (/^code:\d+$/.test(s))
        return evdev(Number(s.slice(5)) - 8);
    if (/^kp_\d$/.test(s))
        return "Num " + s.slice(3);
    if (/^f\d{1,2}$/.test(s))
        return s.toUpperCase();
    if (k.length === 1)
        return k.toUpperCase();
    // an XF86 key the table lacks: its own words ("XF86AudioMedia" -> "Audio Media")
    if (/^xf86/.test(s))
        return k.slice(4).replace(/([a-z])([A-Z])/g, "$1 $2");
    return k;
}

// a whole combo as written in a config ("SUPER + SHIFT + mouse:272") as words ("Super + Shift + Left click"):
// modifiers first in display order, then the key
function combo(text) {
    const parts = String(text).split("+").map(x => x.trim()).filter(x => x !== "");
    const ms = [], rest = [];
    for (const p of parts) {
        const m = mod(p);
        if (m !== undefined && parts.length > 1 && p !== parts[parts.length - 1])
            ms.push(m);
        else
            rest.push(key(p));
    }
    const ordered = modOrder.filter(n => ms.includes(n));
    // a modifier bound on its own ("SUPER + SUPER_L") is named once
    if (rest.length === 1 && ordered.includes(rest[0]))
        return ordered.join(" + ");
    return ordered.concat(rest).join(" + ");
}
