.pragma library

// A small TOML subset reader and writer for sleepysettings.toml. Quickshell only parses JSON, so the settings file is
// read and written here. Pure JS with no QML in it, so it runs the same in the shell, in the settings window and under node in
// the tests.
//
// What is understood (anything else is a parse error that names its line, so a typo is never silently dropped):
//   - [section] headers (bare names: letters, digits, _ and -; no dots, no [[arrays of tables]])
//   - key = value, the key bare or in "double quotes"
//   - basic strings "..." with the escapes \b \t \n \f \r \" \\ \uXXXX \UXXXXXXXX, and literal strings '...' (no escapes)
//   - integers and floats (a sign, _ between digits, a fraction, an exponent), true and false
//   - flat arrays of those scalars, on one line or over several, with comments between the items and a trailing comma
//   - # comments, on their own line or after a value
// Not understood: inline tables, nested arrays, multi-line strings, dates, hex numbers, dotted keys, inf and nan.
//
// parse(text) -> { ok: true, sections: [{ name, entries: [{ key, value, comments: [text], line }] }] }
//             or { ok: false, line, lineText, message }
// The entries before the first [section] sit in a section named "". `comments` are the comment lines directly above a key
// (a blank line ends the block), without their "# ".
// serialise(sections) is the reverse: [{ name, comment?: [text], entries: [{ key, value, comment: [text], literal?: bool }] }].

var BARE = /^[A-Za-z0-9_-]+$/;

function fail(text, pos, message) {
    pos = Math.max(0, Math.min(pos, text.length));
    var line = text.slice(0, pos).split("\n").length;
    var start = pos > 0 ? text.lastIndexOf("\n", pos - 1) + 1 : 0;
    var end = text.indexOf("\n", start);
    return { ok: false, line: line, lineText: text.slice(start, end < 0 ? text.length : end), message: message };
}

function Failure(pos, message) {
    this.pos = pos;
    this.message = message;
}

function isSpace(c) {
    return c === " " || c === "\t";
}

function parse(input) {
    var text = String(input === undefined || input === null ? "" : input).replace(/\r\n?/g, "\n");
    if (text.charCodeAt(0) === 0xFEFF)
        text = text.slice(1);
    var n = text.length;
    var p = 0;
    var sections = [{ name: "", entries: [] }];
    var seenSections = { "": true };
    var cur = sections[0];
    var comments = [];
    var lineStart = true;

    function skipSpace() {
        while (p < n && isSpace(text.charAt(p)))
            p++;
    }

    function parseKey() {
        var c = text.charAt(p);
        if (c === '"' || c === "'") {
            var s = parseString();
            return s;
        }
        var m = /^[A-Za-z0-9_-]+/.exec(text.slice(p, p + 200));
        if (!m)
            throw new Failure(p, "expected a key name");
        p += m[0].length;
        return m[0];
    }

    function parseString() {
        var q = text.charAt(p);
        if (text.substr(p, 3) === q + q + q)
            throw new Failure(p, "multi-line strings are not supported");
        p++;
        var out = "";
        for (;;) {
            if (p >= n || text.charAt(p) === "\n")
                throw new Failure(p, "the string is not closed");
            var c = text.charAt(p);
            if (c === q) {
                p++;
                return out;
            }
            if (q === '"' && c === "\\") {
                var e = text.charAt(p + 1);
                var map = { b: "\b", t: "\t", n: "\n", f: "\f", r: "\r", '"': '"', "\\": "\\" };
                if (map[e] !== undefined) {
                    out += map[e];
                    p += 2;
                } else if (e === "u" || e === "U") {
                    var len = e === "u" ? 4 : 8;
                    var hex = text.substr(p + 2, len);
                    if (hex.length !== len || !/^[0-9A-Fa-f]+$/.test(hex))
                        throw new Failure(p, "a \\" + e + " escape needs " + len + " hex digits");
                    var cp = parseInt(hex, 16);
                    if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF))
                        throw new Failure(p, "that \\" + e + " escape is not a character");
                    out += String.fromCodePoint(cp);
                    p += 2 + len;
                } else {
                    throw new Failure(p, "unknown escape \\" + e);
                }
                continue;
            }
            if (q === '"' && c < " " && c !== "\t")
                throw new Failure(p, "a control character in a string must be escaped");
            out += c;
            p++;
        }
    }

    // after a value (or a header): spaces, an optional comment, then the end of the line
    function endOfLine() {
        skipSpace();
        if (text.charAt(p) === "#") {
            while (p < n && text.charAt(p) !== "\n")
                p++;
        }
        if (p < n && text.charAt(p) !== "\n")
            throw new Failure(p, "unexpected text after the value");
    }

    function parseScalar(inArray) {
        var c = text.charAt(p);
        if (c === '"' || c === "'")
            return parseString();
        if (c === "{")
            throw new Failure(p, "inline tables are not supported");
        if (c === "[")
            throw new Failure(p, "only a flat list of plain values is supported");
        var rest = text.slice(p, p + 80);
        var m = /^(true|false)(?![A-Za-z0-9_.-])/.exec(rest);
        if (m) {
            p += m[0].length;
            return m[0] === "true";
        }
        m = /^[+-]?[0-9](?:_?[0-9])*(?:\.[0-9](?:_?[0-9])*)?(?:[eE][+-]?[0-9](?:_?[0-9])*)?(?![A-Za-z0-9_.:-])/.exec(rest);
        if (m) {
            if (/^[+-]?0[0-9]/.test(m[0]))
                throw new Failure(p, "a number cannot start with a zero");
            p += m[0].length;
            return Number(m[0].replace(/_/g, ""));
        }
        if (/^[0-9]{4}-[0-9]{2}-[0-9]{2}|^[0-9]{2}:[0-9]{2}/.test(rest))
            throw new Failure(p, "dates and times are not supported (put the value in quotes)");
        if (rest === "" || rest.charAt(0) === "\n" || rest.charAt(0) === "#")
            throw new Failure(p, "the value is missing");
        throw new Failure(p, "not a value: put text in quotes");
    }

    function parseArray() {
        p++;
        var list = [];
        for (;;) {
            // spaces, newlines and comments between items
            for (;;) {
                skipSpace();
                var c = text.charAt(p);
                if (c === "\n") {
                    p++;
                } else if (c === "#") {
                    while (p < n && text.charAt(p) !== "\n")
                        p++;
                } else {
                    break;
                }
            }
            if (p >= n)
                throw new Failure(p, "the list is not closed");
            if (text.charAt(p) === "]") {
                p++;
                return list;
            }
            list.push(parseScalar(true));
            for (;;) {
                skipSpace();
                var d = text.charAt(p);
                if (d === "\n") {
                    p++;
                } else if (d === "#") {
                    while (p < n && text.charAt(p) !== "\n")
                        p++;
                } else {
                    break;
                }
            }
            var s = text.charAt(p);
            if (s === ",") {
                p++;
            } else if (s === "]") {
                p++;
                return list;
            } else {
                throw new Failure(p, p >= n ? "the list is not closed" : "expected , or ] in the list");
            }
        }
    }

    try {
        while (p < n) {
            skipSpace();
            var c = text.charAt(p);
            if (c === "\n") {
                // a blank line ends the block of comments above the next key; the end of a comment line does not
                if (text.slice(text.lastIndexOf("\n", p - 1) + 1, p).trim() === "" || p === 0)
                    comments = [];
                p++;
                continue;
            }
            if (p >= n)
                break;
            if (c === "#") {
                var e = text.indexOf("\n", p);
                if (e < 0)
                    e = n;
                comments.push(text.slice(p + 1, e).replace(/^ /, "").replace(/\s+$/, ""));
                p = e;
                continue;
            }
            if (c === "[") {
                if (text.charAt(p + 1) === "[")
                    throw new Failure(p, "lists of tables are not supported");
                var close = text.indexOf("]", p);
                var nl = text.indexOf("\n", p);
                if (close < 0 || (nl >= 0 && close > nl))
                    throw new Failure(p, "the section header is not closed");
                var name = text.slice(p + 1, close).trim();
                if (!BARE.test(name))
                    throw new Failure(p, name.indexOf(".") >= 0 ? "dotted section names are not supported" : "a section name is letters, digits, _ and - only");
                if (seenSections[name])
                    throw new Failure(p, "the section [" + name + "] appears twice");
                seenSections[name] = true;
                p = close + 1;
                endOfLine();
                cur = { name: name, entries: [], comments: comments };
                comments = [];
                sections.push(cur);
                continue;
            }
            var startPos = p;
            var key = parseKey();
            skipSpace();
            if (text.charAt(p) === ".")
                throw new Failure(p, "dotted keys are not supported");
            if (text.charAt(p) !== "=")
                throw new Failure(p, p >= n || text.charAt(p) === "\n" ? "expected = after the key" : "expected = after the key (put text in quotes)");
            p++;
            skipSpace();
            var line = 1;
            for (var i = 0; i < startPos; i++)
                if (text.charAt(i) === "\n")
                    line++;
            var value;
            if (text.charAt(p) === "[")
                value = parseArray();
            else
                value = parseScalar(false);
            endOfLine();
            if (cur.entries.some(function (x) { return x.key === key; }))
                throw new Failure(startPos, "the key " + key + " appears twice in this section");
            cur.entries.push({ key: key, value: value, comments: comments, line: line });
            comments = [];
        }
    } catch (err) {
        if (err instanceof Failure)
            return fail(text, err.pos, err.message);
        throw err;
    }
    return { ok: true, sections: sections };
}

// ---- writing ----

function quote(s) {
    var out = '"';
    for (var i = 0; i < s.length; i++) {
        var c = s.charAt(i);
        var code = s.charCodeAt(i);
        if (c === '"')
            out += '\\"';
        else if (c === "\\")
            out += "\\\\";
        else if (c === "\n")
            out += "\\n";
        else if (c === "\t")
            out += "\\t";
        else if (c === "\r")
            out += "\\r";
        else if (c === "\b")
            out += "\\b";
        else if (c === "\f")
            out += "\\f";
        else if (code < 0x20 || code === 0x7F)
            out += "\\u" + ("0000" + code.toString(16).toUpperCase()).slice(-4);
        else
            out += c;
    }
    return out + '"';
}

// a literal string ('...') reads better for JSON text; only when nothing in it needs an escape
function canLiteral(s) {
    return s.indexOf("'") < 0 && !/[\u0000-\u0008\u000A-\u001F\u007F]/.test(s);
}

function formatScalar(v, literal) {
    if (typeof v === "string")
        return literal && canLiteral(v) ? "'" + v + "'" : quote(v);
    if (typeof v === "boolean")
        return v ? "true" : "false";
    if (typeof v === "number") {
        if (!isFinite(v))
            return "0";
        return String(v);
    }
    return quote(String(v));
}

function isScalar(v) {
    return typeof v === "string" || typeof v === "number" || typeof v === "boolean";
}

// is this value written as a TOML value as it is (a scalar, or a flat list of scalars), not as JSON text?
function plain(v) {
    if (isScalar(v))
        return true;
    if (v !== null && typeof v === "object" && typeof v.length === "number" && !(v instanceof String)) {
        for (var i = 0; i < v.length; i++)
            if (!isScalar(v[i]))
                return false;
        return true;
    }
    return false;
}

function formatValue(v, literal) {
    if (v !== null && typeof v === "object" && typeof v.length === "number") {
        var parts = [];
        for (var i = 0; i < v.length; i++)
            parts.push(formatScalar(v[i], false));
        return "[" + parts.join(", ") + "]";
    }
    return formatScalar(v, literal);
}

function formatKey(k) {
    return BARE.test(k) ? k : quote(k);
}

function commentLines(list, prefix) {
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var t = String(list[i]);
        out.push(t === "" ? "#" : "# " + t);
    }
    return out;
}

function serialise(sections) {
    var lines = [];
    for (var s = 0; s < sections.length; s++) {
        var sec = sections[s];
        if (sec.entries.length === 0 && !(sec.keepEmpty))
            continue;
        if (lines.length > 0)
            lines.push("");
        if (sec.comment && sec.comment.length > 0)
            lines = lines.concat(commentLines(sec.comment));
        if (sec.name !== "")
            lines.push("[" + sec.name + "]");
        for (var i = 0; i < sec.entries.length; i++) {
            var e = sec.entries[i];
            if (i > 0 && e.comment && e.comment.length > 0)
                lines.push("");
            if (e.comment && e.comment.length > 0)
                lines = lines.concat(commentLines(e.comment));
            lines.push(formatKey(e.key) + " = " + formatValue(e.value, e.literal === true));
        }
    }
    return lines.join("\n") + "\n";
}
