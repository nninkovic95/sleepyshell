pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "Lua.js" as Lua
import "LocalImage.js" as LocalImage
import qs.services

// The bar is the notification daemon; it replaced swaync. Notifications arrive here, stay in `list` until dismissed, and new ones pop
// up as toasts (NotifPopups). The dropdown is sleepybar/widgets/notifications/Notifications.qml.
// Notifications carry no timestamp of their own, so the receive time is kept in a map by id.
// Do not disturb is a stored setting (Settings.dnd). Urgent ones (isUrgent) still pop up under it.
Singleton {
    id: root

    // Urgent: critical, or from an app the user listed (Settings.urgentApps). An urgent one pops up under
    // do not disturb, stays until dismissed, keeps its toast slot and its place in the history, rings
    // (Chime) and is drawn apart (NotifCard). Matched on the desktop entry or the app name only: a browser
    // sends neither the site nor its address, so every site allowed to notify in a listed browser counts.
    function isUrgent(n) {
        if (!n)
            return false;
        if (n.urgency === NotificationUrgency.Critical)
            return true;
        const keys = root.urgentKeys;
        return keys.length > 0 && [n.desktopEntry, n.appName].some(k => k && keys.includes(String(k).toLowerCase()));
    }
    // the listed apps (desktop entry names, from the settings window's app list) and their display names:
    // some apps send only a name ("LibreWolf") and no desktop entry. Found in the list, not with byId, so
    // the names arrive once the list has filled after start
    readonly property var urgentKeys: {
        const out = [];
        const apps = DesktopEntries.applications.values;
        for (const id of Settings.urgentApps) {
            const low = id.toLowerCase();
            out.push(low);
            const name = apps.find(x => x.id.toLowerCase() === low)?.name ?? "";
            if (name !== "")
                out.push(name.toLowerCase());
        }
        return out;
    }
    // The Urgent look (Settings.urgentLook): a preset name, or its parts written out in sleepysettings.toml,
    // e.g. "tint 30, edge 6, chip". tint: how strongly the card is coloured red, 0-100 (55 without a number);
    // edge: the red edge's width in pixels, 0-12 (0 hides it); chip: the "Urgent" label. A value with no
    // known part reads as the "full" preset, so a typo never hides what is urgent.
    readonly property var urgentLooks: ({
            full: "tint 55, edge 4, chip",
            tint: "tint 55, edge 4",
            chip: "edge 3, chip",
            edge: "edge 3"
        })
    function lookParts(s) {
        const name = String(s ?? "").trim().toLowerCase();
        // own keys only: a typed "toString" must not find the object's built-in function
        const spec = Object.prototype.hasOwnProperty.call(root.urgentLooks, name) ? root.urgentLooks[name] : name;
        const out = { tint: 0, edge: 0, chip: false };
        let known = false;
        for (const part of spec.split(",")) {
            const [k, v] = part.trim().toLowerCase().split(/\s+/);
            const n = v === undefined ? NaN : Number(v);
            if (k === "tint")
                out.tint = isFinite(n) ? Math.max(0, Math.min(100, n)) : 55;
            else if (k === "edge")
                out.edge = isFinite(n) ? Math.max(0, Math.min(12, Math.round(n))) : 4;
            else if (k === "chip")
                out.chip = true;
            else
                continue;
            known = true;
        }
        return known ? out : root.lookParts("full");
    }
    readonly property var urgentStyle: lookParts(Settings.urgentLook)
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
            root.capHistory(n);
            if (n.lastGeneration)
                return;
            const urgent = root.isUrgent(n);
            if (!root.dnd || urgent)
                root.popups = [n, ...root.popups.filter(p => p !== n)];
            // rings under do not disturb too, since urgent is what must not be missed (urgentSound
            // silences it); an app's own "no sound" hint is kept
            if (urgent && n.hints?.["suppress-sound"] !== true)
                Chime.play();
        }
    }

    // The history is capped at the newest `maxHistory` notifications (SECURITY.md finding #40: an app that sends
    // notifications in a loop grew the list, the popups and the bell without limit). When a new one arrives and the list is over the cap,
    // the oldest are dismissed, silently: no popup, no sound, the sending app is only told the notification closed. An urgent
    // notification that is still a popup on screen is skipped, so an urgent one is never taken away before it was seen; the next
    // oldest goes instead.
    readonly property int maxHistory: 100
    // `arriving` is the one that triggered the cap: it is never the one dismissed (it is not yet a popup, so the
    // urgent exemption cannot see it; dismissed here it would still be added to the popups as a closed object)
    function capHistory(arriving) {
        const all = server.trackedNotifications.values;
        let over = all.length - root.maxHistory;
        for (let i = 0; i < all.length && over > 0; i++) {
            const o = all[i];
            if (o === arriving || (root.isUrgent(o) && root.popups.includes(o)))
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
            a.invoke();   // invoking an action closes a non-resident notification by itself
        else if (!focused)
            openImage(n);
        // a second close on one already closed by its action logs "Cannot close destroyed notification"
        if (!a && !n.resident)
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
        Hyprland.dispatch("hl.dsp.focus({ window = " + Lua.str("address:" + addr) + " })");
        return true;
    }

    function openImage(n) {
        const path = imagePath(n);
        if (path)
            DefaultApps.openUrl(path);
    }

    // a file:// URL for an absolute local path, else ""
    function fileUrl(p) {
        return LocalImage.fileUrl(p);
    }

    // One icon name, path or URL an app sent, as a local source, else "": a path or file: URL loads
    // as a file, a name only when the icon theme has it (Quickshell draws a magenta checkerboard for
    // one it lacks), anything else (a web address) never loads.
    function localIcon(s) {
        s = String(s ?? "");
        if (s === "")
            return "";
        if (s.startsWith("/"))
            return LocalImage.fileUrl(s);
        if (s.startsWith("file:"))
            return LocalImage.fromFileUrl(s);
        if (s.includes(":") || s.includes("?"))
            return "";
        return Quickshell.iconPath(s, true);
    }

    // The icons a card can show, best first, each a local source: the notification's image, then
    // the app's icon. The card moves to the next when one fails to load, and shows the bell when
    // none is left. Quickshell hands the image over as image data ("image://qsimage/…"), a file:
    // URL, or "image://icon/" + whatever the app sent as its image path; a path there loads as a
    // file (through the icon theme it warned "Could not load icon … at size QSize(2, 2)" for every
    // Hyprshot toast).
    function iconUrls(n) {
        if (!n)
            return [];
        const img = String(n.image ?? "");
        const out = [];
        if (img.startsWith("image://icon/"))
            out.push(localIcon(img.slice("image://icon/".length)));
        else if (img.startsWith("file:"))
            out.push(LocalImage.fromFileUrl(img));
        else
            out.push(LocalImage.only(img));
        out.push(localIcon(n.appIcon));
        return out.filter((s, i) => s !== "" && LocalImage.isLocal(s) && out.indexOf(s) === i);
    }

    function iconUrl(n) {
        return iconUrls(n)[0] ?? "";
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

    // The app name shown on a card: empty for notify-send, which sends its own name when a script does not pass
    // one (-a), and that name tells the reader nothing about who sent it
    function appLabel(n) {
        const a = n?.appName ?? "";
        return a.toLowerCase() === "notify-send" ? "" : a;
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
