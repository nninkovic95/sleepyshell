pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Events from khal for the calendar popup (sleepybar/popups/calendar/CalendarPopup.qml).
// Read-only: it only runs `khal list ... --json ...` and `khal printformats`, never `new` or `edit`.
//
// How khal answers (khal 0.14.1, checked on the machine): `khal list FROM TO --json f1 --json f2 ...`
// prints ONE JSON array per day of the range, FROM to TO inclusive, in order, `[]` for an empty day,
// and repeats a multi-day event on every day it covers. Each event is an object of strings
// (start-date, start-time, end-date, end-time, title, location, all-day "True"/"False", uid,
// calendar, calendar-color; empty strings when unset). So a line's day is FROM plus its line number,
// never read from the event, and the human format is never parsed.
// The dates go in and come out in the user's `dateformat`, which khal has no flag to override:
// `khal printformats` prints 21.12.2013 in that format, from which a template ("{d}.{m}.{Y}") is
// derived, used to write FROM and TO and to read start-date and end-date back (the first/last day of
// a multi-day event). A format with localised month names cannot be derived: error, no events.
// `firstweekday` is not exposed by a khal command, so it is read from khal's config file.
//
// Refresh: the popup calls setRange() when it opens and on a month change; while `active` (popup
// open) a timer re-reads the current range every 10 minutes. Results are merged per day, so a month
// already visited shows its dots at once while the re-read runs.
Singleton {
    id: root

    // ---- test hooks (the harness sets them; nothing in the shell does) ----
    property var khalCmd: ["khal"]
    property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/khal/config"

    // ---- state ----
    property bool available: true          // false once the probe finds no khal
    property string reason: ""             // why not available, or why the formats are unusable
    property bool loading: false
    property string error: ""              // last failed read ("" when fine)
    property bool active: false            // popup open: the 10 minute timer runs
    property int firstWeekday: 0           // 0 Monday ... 6 Sunday, khal's [locale] firstweekday
    property var byDay: ({})               // "YYYY-MM-DD" -> [event, ...]
    property double lastRead: 0

    property bool probed: false
    property string template: ""           // e.g. "{d}.{m}.{Y}", "" until printformats answered
    property var rangeFrom: null
    property var rangeTo: null

    readonly property var monthsShort: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    readonly property var monthsLong: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    // khal colour names (terminal colours) as the popup draws them; a "#rrggbb" value is used as is
    readonly property var colourNames: ({
            "black": "#555555", "white": "#e8e8e8", "brown": "#b08050", "yellow": "#e0c040",
            "dark gray": "#808080", "dark grey": "#808080", "light gray": "#c0c0c0", "light grey": "#c0c0c0",
            "dark green": "#40a060", "dark blue": "#4060d0", "dark cyan": "#30b0b0", "dark magenta": "#b050b0",
            "dark red": "#c04040", "light green": "#70e080", "light blue": "#70a0ff", "light cyan": "#70e0e0",
            "light magenta": "#f080f0", "light red": "#ff7070"
        })

    // ---- dates ----
    function pad(n) {
        return (n < 10 ? "0" : "") + n;
    }

    // "YYYY-MM-DD" of a local Date: the key of byDay
    function key(d) {
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
    }

    // a Date at local noon (daylight-saving shifts never move it across midnight)
    function day(y, m, d) {
        return new Date(y, m, d, 12, 0, 0);
    }

    function addDays(d, n) {
        return day(d.getFullYear(), d.getMonth(), d.getDate() + n);
    }

    // a date written the way the user's khal wants it ("" while the format is unknown)
    function fmt(d) {
        if (root.template === "")
            return "";
        return root.template.replace("{d}", pad(d.getDate())).replace("{m}", pad(d.getMonth() + 1)).replace("{Y}", d.getFullYear()).replace("{y}", pad(d.getFullYear() % 100)).replace("{b}", monthsShort[d.getMonth()]).replace("{B}", monthsLong[d.getMonth()]);
    }

    // "21.12.2013" -> "{d}.{m}.{Y}"; "" when it holds no day or month that can be written back
    function makeTemplate(sample) {
        let t = sample.trim();
        if (/2013/.test(t))
            t = t.replace("2013", "{Y}");
        else if (/13/.test(t))
            t = t.replace("13", "{y}");
        t = t.replace("21", "{d}");
        if (/12/.test(t))
            t = t.replace("12", "{m}");
        else if (/December/.test(t))
            t = t.replace("December", "{B}");
        else if (/Dec/.test(t))
            t = t.replace("Dec", "{b}");
        return t.includes("{d}") && /\{(m|b|B)\}/.test(t) ? t : "";
    }

    // a date as khal printed it -> "YYYY-MM-DD", "" when it does not fit the template
    function parseDate(s) {
        if (root.template === "" || !s)
            return "";
        const esc = root.template.replace(/[.*+?^$()|[\]\\]/g, "\\$&");
        const names = [];
        const re = new RegExp("^" + esc.replace(/\{(d|m|Y|y|b|B)\}/g, (all, k) => {
            names.push(k);
            return k === "Y" ? "(\\d{4})" : k === "b" || k === "B" ? "([A-Za-z]+)" : "(\\d{1,2})";
        }) + "$");
        const m = re.exec(s.trim());
        if (!m)
            return "";
        let y = 0, mo = 0, d = 0;
        names.forEach((k, i) => {
            const v = m[i + 1];
            if (k === "d")
                d = parseInt(v);
            else if (k === "m")
                mo = parseInt(v);
            else if (k === "Y")
                y = parseInt(v);
            else if (k === "y")
                y = 2000 + parseInt(v);
            else
                mo = 1 + monthsShort.findIndex(n => n.toLowerCase() === v.slice(0, 3).toLowerCase());
        });
        return y > 0 && mo > 0 && d > 0 ? y + "-" + pad(mo) + "-" + pad(d) : "";
    }

    // ---- reading the data ----
    function eventsOn(date) {
        return root.byDay[key(date)] ?? [];
    }

    function hasEvents(date) {
        return eventsOn(date).length > 0;
    }

    // up to three distinct calendar colours on a day, for the dots; "" means "no colour set"
    function dotColours(date) {
        const seen = [];
        for (const e of eventsOn(date)) {
            if (!seen.includes(e.color))
                seen.push(e.color);
            if (seen.length === 3)
                break;
        }
        return seen;
    }

    // the time column of an event on the day `iso`: "All day", "10:00 - 11:30", "21:00 >" on the first
    // day of an event that runs past midnight, "> 09:00" on its last day, "All day" in between
    function timeLabel(e, iso) {
        if (e.allDay)
            return "All day";
        const first = e.sd === "" || e.sd === iso, last = e.ed === "" || e.ed === iso;
        if (first && last)
            return e.et === "" || e.et === e.st ? e.st : e.st + " – " + e.et;
        if (first)
            return e.st + " →";
        if (last)
            return "→ " + e.et;
        return "All day";
    }

    function colourOf(name) {
        const n = (name ?? "").trim().toLowerCase();
        if (n.startsWith("#"))
            return n;
        return colourNames[n] ?? "";
    }

    // lines of `khal list` output for [from, to] -> merged into byDay; false when a line is not JSON
    function ingest(text, from) {
        const lines = text.split("\n").filter(l => l.trim() !== "");
        const merged = Object.assign({}, root.byDay);
        for (let i = 0; i < lines.length; i++) {
            let arr;
            try {
                arr = JSON.parse(lines[i]);
            } catch (e) {
                return false;
            }
            if (!Array.isArray(arr))
                return false;
            merged[key(addDays(from, i))] = arr.map(o => ({
                        uid: o["uid"] ?? "",
                        title: o["title"] ?? "",
                        location: o["location"] ?? "",
                        calendar: o["calendar"] ?? "",
                        color: colourOf(o["calendar-color"]),
                        allDay: String(o["all-day"]).toLowerCase() === "true",
                        st: o["start-time"] ?? "",
                        et: o["end-time"] ?? "",
                        sd: parseDate(o["start-date"] ?? ""),
                        ed: parseDate(o["end-date"] ?? "")
                    }));
        }
        root.byDay = merged;
        return true;
    }

    // ---- running khal ----
    // the popup asks for the days it draws; asking again for the same range just re-reads it
    function setRange(from, to) {
        root.rangeFrom = from;
        root.rangeTo = to;
        launch();
    }

    function refresh() {
        launch();
    }

    property bool again: false
    property var runFrom: null
    property int parts: 0
    property int exitCode: 0

    function launch() {
        if (!root.available || root.rangeFrom === null)
            return;
        if (root.template === "") {
            // printformats has not answered yet, or failed; the answer starts the read
            if (!formats.running && root.probed && root.reason === "")
                formats.running = true;
            return;
        }
        if (lister.running) {
            root.again = true;
            return;
        }
        root.again = false;
        root.runFrom = root.rangeFrom;
        root.parts = 3;
        root.loading = true;
        lister.command = root.khalCmd.concat(["list", fmt(root.rangeFrom), fmt(root.rangeTo), "--json", "uid", "--json", "title", "--json", "start-date", "--json", "start-time", "--json", "end-date", "--json", "end-time", "--json", "all-day", "--json", "location", "--json", "calendar", "--json", "calendar-color"]);
        lister.running = true;
        watchdog.restart();
    }

    function partDone() {
        root.parts--;
        if (root.parts > 0)
            return;
        watchdog.stop();
        root.loading = false;
        if (root.exitCode !== 0) {
            const first = errCollector.text.trim().split("\n")[0];
            root.error = first !== "" ? first : "khal exited with code " + root.exitCode;
        } else if (!root.ingest(outCollector.text, root.runFrom)) {
            root.error = "khal printed something that is not JSON";
        } else {
            root.error = "";
            root.lastRead = Date.now();
        }
        if (root.again)
            root.launch();
    }

    Process {
        id: lister
        stdout: StdioCollector {
            id: outCollector
            onStreamFinished: root.partDone()
        }
        stderr: StdioCollector {
            id: errCollector
            onStreamFinished: root.partDone()
        }
        onExited: code => {
            root.exitCode = code;
            root.partDone();
        }
    }

    // a hung khal (a locked vdir, a stuck sync hook) must not leave "loading" on for good
    Timer {
        id: watchdog
        interval: 20000
        onTriggered: {
            root.loading = false;
            root.error = "khal did not answer";
            lister.running = false;
        }
    }

    // (re)start from the probe: khal present? then its date format. Queued from the start-up, so a
    // caller that sets khalCmd right after the singleton appears (the test harness) is heard
    function recheck() {
        root.available = true;
        root.reason = "";
        root.template = "";
        root.probed = false;
        probe.running = true;
    }
    Component.onCompleted: Qt.callLater(root.recheck)

    // is khal there at all? `command -v` finds a name on PATH or accepts a path
    Process {
        id: probe
        command: ["sh", "-c", "command -v \"$1\" >/dev/null", "sh", root.khalCmd[0]]
        onExited: code => {
            root.probed = true;
            root.available = code === 0;
            root.reason = code === 0 ? "" : "khal is not installed";
            if (code === 0)
                formats.running = true;
        }
    }

    // khal's own error (a broken config) shows as the reason; an answer that holds no usable date
    // format is a reason too
    property int fmtParts: 0
    property int fmtCode: 0
    function fmtDone() {
        root.fmtParts--;
        if (root.fmtParts > 0)
            return;
        const first = fmtErr.text.trim().split("\n")[0];
        if (root.fmtCode !== 0) {
            root.reason = first !== "" ? first : "khal exited with code " + root.fmtCode;
            return;
        }
        const m = /^dateformat:[ \t]*(.+)$/m.exec(fmtOut.text);
        const t = m ? root.makeTemplate(m[1]) : "";
        if (t === "") {
            root.reason = "khal's date format is not supported";
            return;
        }
        root.template = t;
        root.reason = "";
        root.launch();
    }

    Process {
        id: formats
        command: root.khalCmd.concat(["printformats"])
        onRunningChanged: if (running)
            root.fmtParts = 3
        stdout: StdioCollector {
            id: fmtOut
            onStreamFinished: root.fmtDone()
        }
        stderr: StdioCollector {
            id: fmtErr
            onStreamFinished: root.fmtDone()
        }
        onExited: code => {
            root.fmtCode = code;
            root.fmtDone();
        }
    }

    FileView {
        path: root.configPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = /^\s*firstweekday\s*=\s*([0-6])/m.exec(text());
            root.firstWeekday = m ? parseInt(m[1]) : 0;
        }
        onLoadFailed: root.firstWeekday = 0
    }

    readonly property bool timerRunning: refreshTimer.running
    Timer {
        id: refreshTimer
        interval: 10 * 60 * 1000
        repeat: true
        running: root.active && root.available
        onTriggered: root.refresh()
    }
}
