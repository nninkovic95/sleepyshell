.pragma library

// Image sources built from what other programs send (notification icons and images, tray icons and
// tray menu icons). Quickshell's engine can load http(s) and other network URLs, so a notification
// could otherwise make the shell fetch an address of the sender's choosing (a read receipt, a leaked
// IP address). Only local sources pass: a file, the icon theme and Quickshell's own pixmap providers
// (image data an app sent over D-Bus). Anything else becomes "" and is never requested.
const allowed = ["file:///", "image://icon/", "image://qsimage/", "image://qspixmap/"];

function isLocal(url) {
    const s = String(url ?? "");
    return allowed.some(p => s.startsWith(p));
}

// the source itself when it is local, else ""
function only(url) {
    return isLocal(url) ? String(url) : "";
}

// A file:// URL for an absolute local path, else "". '#' and '?' are encoded too, or QUrl would read
// them as a fragment or query and load the wrong file.
function fileUrl(p) {
    const s = String(p ?? "");
    if (!s.startsWith("/") || s.startsWith("//"))
        return "";
    try {
        return "file://" + encodeURI(s).replace(/#/g, "%23").replace(/\?/g, "%3F");
    } catch (e) {
        return "file://" + s.replace(/#/g, "%23").replace(/\?/g, "%3F");
    }
}

// A file: URL an app sent ("file:///a.png", "file:/a.png", "file://localhost/a.png") as a local
// file:// URL; one that names another host is "".
function fromFileUrl(u) {
    const s = String(u ?? "");
    const rest = s.replace(/^file:(\/\/localhost(?=\/)|\/\/(?=\/))?/, "");
    if (rest === s || !rest.startsWith("/") || rest.startsWith("//"))
        return "";
    return only("file://" + rest);
}
