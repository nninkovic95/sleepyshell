.pragma library

// Text that goes into Lua the shell writes or sends to Hyprland (sleepybinds.lua, dispatches). One escaper for every
// writer, so a name or command from outside (a workspace name, a pasted command) cannot end the string early or
// break the line it sits on.

// a double-quoted Lua string holding exactly s: backslash and quote escaped, newline and carriage return as \n and
// \r, every other control character as a decimal escape
function str(s) {
    let out = "";
    for (const ch of String(s)) {
        const c = ch.codePointAt(0);
        if (ch === "\\")
            out += "\\\\";
        else if (ch === '"')
            out += '\\"';
        else if (ch === "\n")
            out += "\\n";
        else if (ch === "\r")
            out += "\\r";
        // three digits, so a digit that follows is never read as part of the escape
        else if (c < 32 || c === 127)
            out += "\\" + String(c).padStart(3, "0");
        else
            out += ch;
    }
    return '"' + out + '"';
}

// the text of a Lua short string's body (no quotes), escapes undone: the reverse of str(), so a command written
// by the shell reads back unchanged
function unstr(body) {
    const named = { n: "\n", r: "\r", t: "\t", a: "\u0007", b: "\b", f: "\f", v: "\v" };
    return String(body).replace(/\\(\d{1,3}|.)/g, (m, e) => {
        if (/^\d+$/.test(e))
            return String.fromCharCode(Number(e));
        return named[e] ?? e;
    });
}
