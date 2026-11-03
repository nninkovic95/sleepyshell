.pragma library

// Validators for the "Custom…" entries under the settings rows that offer presets. Each returns
// { ok: true, value } or { ok: false, error }; the error is plain language, one short sentence. Pure JS, so the tests can run it under node.

// a whole number from lo to hi (digits only), as text
function integer(text, lo, hi, what) {
    const t = String(text).trim();
    if (!/^[0-9]+$/.test(t))
        return { ok: false, error: "Type a whole number" + (what ? " of " + what : "") + ", " + lo + " to " + hi + "." };
    const n = parseInt(t, 10);
    if (n < lo || n > hi)
        return { ok: false, error: "That is outside " + lo + " to " + hi + "." };
    return { ok: true, value: String(n) };
}

// a decimal number from lo to hi, as a number
function number(text, lo, hi) {
    const t = String(text).trim().replace(",", ".");
    if (!/^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)$/.test(t))
        return { ok: false, error: "Type a number from " + lo + " to " + hi + ", such as 0.25." };
    const n = Number(t);
    if (n < lo || n > hi)
        return { ok: false, error: "That is outside " + lo + " to " + hi + "." };
    return { ok: true, value: n };
}

// a short piece of text drawn on every workspace dot: one or two characters (a letter, a symbol or a Nerd Font icon), no spaces
function glyph(text) {
    const t = String(text).trim();
    if (t === "")
        return { ok: false, error: "Type one or two characters." };
    if (/\s/.test(t))
        return { ok: false, error: "No spaces: type one or two characters." };
    if (Array.from(t).length > 2)
        return { ok: false, error: "Too long: a dot fits one or two characters." };
    return { ok: true, value: t };
}

// a shell command line for an event (the lid closing, the critical battery level); stored with the prefix "cmd:"
var COMMAND_PREFIX = "cmd:";
function command(text) {
    const t = String(text).trim();
    if (t === "")
        return { ok: false, error: "Type the command to run." };
    if (/[\r\n]/.test(t))
        return { ok: false, error: "One line only." };
    if (t.length > 300)
        return { ok: false, error: "Too long: keep it under 300 characters." };
    return { ok: true, value: COMMAND_PREFIX + t };
}
function isCommand(v) {
    return typeof v === "string" && v.indexOf(COMMAND_PREFIX) === 0;
}
function commandText(v) {
    return isCommand(v) ? v.slice(COMMAND_PREFIX.length) : "";
}

// "" for a usable Qt format string (the clock's time or date): not empty, not absurdly long, quotes closed. Qt prints any
// letter it does not know as it is, so a typo shows in the preview instead of being an error.
function format(text) {
    const t = String(text);
    if (t.trim() === "")
        return { ok: false, error: "Type a format, such as HH:mm." };
    if (t.length > 40)
        return { ok: false, error: "Too long: keep it under 40 characters." };
    if ((t.match(/'/g) || []).length % 2 !== 0)
        return { ok: false, error: "A single quote is not closed." };
    return { ok: true, value: t };
}
