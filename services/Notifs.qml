pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import qs.services

// The bar is the notification daemon; it replaced swaync. Notifications arrive here, stay in `list` until dismissed, and new ones pop
// up as toasts (NotifPopups). The dropdown is sleepybar/widgets/notifications/Notifications.qml.
// Notifications carry no timestamp of their own, so the receive time is kept in a map by id.
// Do not disturb is a stored setting (Settings.dnd). Critical ones still pop up under it.
Singleton {
    id: root
    readonly property var list: server.trackedNotifications.values.slice().reverse()
    readonly property int count: server.trackedNotifications.values.length
    // stored in Settings
    readonly property bool dnd: Settings.dnd
    // notifications currently shown as toasts, newest first
    property var popups: []
    property var times: ({})
    // bumped every 30 s so ago() labels refresh
    property int tick: 0
    // "Clear all" in the dropdown: the dropdown sends the cards out one at a time from the top on a
    // steady beat (swipeOne), each is removed as it leaves and the rest slide up behind it, so every
    // card visibly goes (earlier tries
    // swiped only the cards on screen, then cleared the rest unseen, or let new cards slide in
    // between waves).
    property bool clearing: false
    // ids of the cards that took their turn (a card far down may have no delegate to take it)
    property var swipeTaken: ({})
    signal swipeOne(var n)
    // marked and read here: written from a card as Notifs.swipeTaken[id] the mark was lost (a var
    // property read from another file can come back as a copy), so no card ever took its turn
    function takeSwipe(id) {
        swipeTaken[id] = true;
    }
    function swipeWasTaken(id) {
        return swipeTaken[id] === true;
    }
    function startClear() {
        if (count === 0)
            return;
        swipeTaken = {};
        clearing = true;
    }
    onCountChanged: {
        if (count === 0)
            clearing = false;
    }

    NotificationServer {
        id: server
        // a reload of the bar must not drop what is waiting
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            // A reload of the bar hands every kept notification (keepOnReload) to this handler
            // again, flagged lastGeneration: it goes back in the list but gets no toast and no new
            // time. Popped again with a fresh stamp, old ones came back as toasts after every
            // reload. Its age is unknown after a reload, so ago() is "".
            if (!n.lastGeneration)
                root.times[n.id] = Date.now();     // stamp first: the delegates read it at once
            // untracked notifications are dropped
            n.tracked = true;
            n.closed.connect(() => root.forget(n));
            root.capHistory();
            if (n.lastGeneration)
                return;
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                root.popups = [n, ...root.popups.filter(p => p !== n)];
        }
    }

    // The history is capped at the newest `maxHistory` notifications (SECURITY.md finding #40: an app that sends
    // notifications in a loop grew the list, the popups and the bell without limit). When a new one arrives and the list is over the cap,
    // the oldest are dismissed, silently: no popup, no sound, the sending app is only told the notification closed. A critical
    // notification that is still a popup on screen is skipped, so a critical warning is never taken away before it was seen; the next
    // oldest goes instead.
    readonly property int maxHistory: 100
    function capHistory() {
        const all = server.trackedNotifications.values;
        let over = all.length - root.maxHistory;
        for (let i = 0; i < all.length && over > 0; i++) {
            const o = all[i];
            if (o.urgency === NotificationUrgency.Critical && root.popups.includes(o))
                continue;
            o.dismiss();
            over--;
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.count > 0
        onTriggered: root.tick++
    }

    function forget(n) {
        delete root.times[n.id];
        root.popups = root.popups.filter(p => p !== n);
    }

    function toggleDnd() {
        // the bell and the tile act at once: this key alone is written, leaving any unapplied
        // change in the settings window (its own process) as it is
        Settings.commitValues({
            dnd: !Settings.dnd
        });
    }

    function clearAll() {
        clearing = false;
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
    }

    function dismiss(n) {
        n.dismiss();
    }

    // Click on a card leads to where it came from: the app's "default" action if it sent one (kitty's
    // raises the exact window), else the app's window found by its class, else the image file a
    // notification points at (Hyprshot sends the screenshot as its icon). Then it is removed
    // unless resident.
    // A screenshot's card copies the image instead; the card shows "Copied" and dismisses itself (NotifCard), and keeps
    // Open / Show in folder buttons for the old click.
    function activate(n) {
        // without wl-copy (wl-clipboard) the click falls back to opening the image, as before
        const shot = Deps.has("wl-copy") ? screenshotPath(n) : "";
        if (shot !== "") {
            copyImage(shot);
            return;
        }
        const a = n.actions.find(x => x.identifier === "default");
        // an app cannot raise its own window from the default action: Hyprland needs an activation token
        // the notification never carries (and focus_on_activate is off by default), so the click focused
        // nothing and the card just went; the window is focused here first, then the action still runs
        // (it may open the chat or tab the notification is about)
        const focused = focusApp(n);
        if (a)
            a.invoke();
        else if (!focused)
            openImage(n);
        if (!n.resident)
            n.dismiss();
    }

    // the most recently used window whose class is the notification's desktop entry or app name
    function focusApp(n) {
        const keys = [n.desktopEntry, n.appName].filter(k => k).map(k => k.toLowerCase());
        const match = c => keys.some(k => c === k || c.endsWith("." + k) || k.endsWith("." + c));
        const wins = Hyprland.toplevels.values.filter(t => match((t.wayland?.appId ?? t.lastIpcObject?.class ?? "").toLowerCase()));
        if (wins.length === 0)
            return false;
        wins.sort((x, y) => (x.lastIpcObject?.focusHistoryID ?? 99) - (y.lastIpcObject?.focusHistoryID ?? 99));
        const addr = wins[0].address.startsWith("0x") ? wins[0].address : "0x" + wins[0].address;
        // Lua dispatch under the Hyprland Lua config (checked with hyprctl)
        Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })");
        return true;
    }

    function openImage(n) {
        const path = imagePath(n);
        if (path)
            DefaultApps.openUrl(path);
    }

    // a file:// URL for a local path; '#' and '?' are encoded too, or QUrl would read them as a
    // fragment or query and load the wrong file
    function fileUrl(p) {
        try {
            return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F");
        } catch (e) {
            return "file://" + p;
        }
    }

    // The icon a card shows. A file path, whether Quickshell hands it over as `image`
    // ("image://icon//home/…png") or the app sent it as `appIcon`, loads as a file: through the
    // icon theme it warned "Could not load icon … at size QSize(2, 2)" for every Hyprshot toast.
    function iconUrl(n) {
        if (!n)
            return "";
        const img = n.image ?? "";
        if (img.startsWith("image://icon//"))
            return fileUrl(img.slice("image://icon/".length));
        if (img !== "")
            return img;
        const icon = n.appIcon ?? "";
        if (icon.startsWith("/"))
            return fileUrl(icon);
        if (icon.startsWith("file://"))
            return icon;
        return icon !== "" ? Quickshell.iconPath(icon, true) : "";
    }

    // the image file of a screenshot notification (Hyprshot, or a file in a Screenshots folder), or
    // "": other apps name their icon or an avatar as an image file too
    function screenshotPath(n) {
        const p = imagePath(n);
        return p !== "" && ((n?.appName ?? "").toLowerCase() === "hyprshot" || p.includes("/Screenshots/")) ? p : "";
    }

    // the image itself onto the clipboard, typed by its extension; the path is an argument, never
    // part of the script
    function copyImage(p) {
        const ext = p.slice(p.lastIndexOf(".") + 1).toLowerCase();
        const type = ext === "jpg" || ext === "jpeg" ? "image/jpeg" : ext === "webp" ? "image/webp" : ext === "gif" ? "image/gif" : "image/png";
        Quickshell.execDetached(["sh", "-c", 'wl-copy --type "$2" < "$1"', "sh", p, type]);
    }

    // the folder holding a file, in the default file manager
    function revealFile(p) {
        DefaultApps.revealDir(p.slice(0, p.lastIndexOf("/")) || "/");
    }

    // the local image file a notification points at, or "": also the card's large preview
    function imagePath(n) {
        if (!n)
            return "";
        const hint = n.hints?.["image-path"] ?? "";
        const local = x => {
            const s = x ?? "";
            if (!s.startsWith("file://"))
                return s;
            try {
                return decodeURIComponent(s.slice(7));
            } catch (e) {
                return s.slice(7);
            }
        };
        // only an image file: the app names these paths, and xdg-open would hand a .desktop or
        // script file to its handler just the same (review 4)
        const isImage = x => x.startsWith("/") && /\.(png|jpe?g|gif|webp|bmp|svg|avif)$/i.test(x);
        return [n.image, n.appIcon, hint].map(local).find(isImage) ?? "";
    }

    function unpop(n) {
        popups = popups.filter(p => p !== n);
    }

    function togglePanel() {
        Popouts.toggle("notifications");
    }

    // "now", "3 min", "2 h", "yesterday", "4 d"
    function ago(n) {
        tick;
        if (!n)
            return "";
        const t = times[n.id];
        if (t === undefined)
            return "";
        const m = Math.floor((Date.now() - t) / 60000);
        if (m < 1)
            return "now";
        if (m < 60)
            return m + " min";
        const h = Math.floor(m / 60);
        if (h < 24)
            return h + " h";
        const d = Math.floor(h / 24);
        return d === 1 ? "yesterday" : d + " d";
    }
}
