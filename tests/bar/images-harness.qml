// Harness of tests/bar/local-images.sh, copied into the root of the tree under test and run there with
// `qs -p` on the offscreen platform (nothing is drawn on a real screen). It holds the tree's real notification
// cards, toasts and tray, plus one control image pointed at the request counter (it must be fetched: proof that a
// fetch would be seen). Once every expected notification and tray item is in and the images had time to load, it
// prints one line "RESULT <json>" and quits; after 25 s it prints what it has.
// Environment: T3_PORT (the counter), T3_NOTIFS and T3_TRAY (how many to wait for), T3_NAME (an icon the theme has),
// T3_PIC (a local PNG).
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.services
import qs.sleepybar.widgets.notifications
import qs.sleepybar.widgets.tray
import "services/LocalImage.js" as LocalImage

Scope {
    id: h
    readonly property string port: Quickshell.env("T3_PORT") ?? ""
    readonly property int wantNotifs: Number(Quickshell.env("T3_NOTIFS") ?? "0")
    readonly property int wantTray: Number(Quickshell.env("T3_TRAY") ?? "0")
    readonly property string name: Quickshell.env("T3_NAME") ?? ""
    readonly property string pic: Quickshell.env("T3_PIC") ?? ""
    readonly property bool ready: Notifs.list.length >= wantNotifs && SystemTray.items.values.length >= wantTray
    property bool done: false

    // the pure checks: [what, got, expected]
    function units() {
        const r = [];
        const u = "http://127.0.0.1:" + h.port + "/unit.png";
        const t = (what, got, want) => r.push([what, got, want]);
        for (const s of [u, "https://127.0.0.1:" + h.port + "/u.ico", "ftp://127.0.0.1/x.png", "data:image/png;base64,AAAA",
                "qrc:/x.png", "file://127.0.0.1/x.png", "image://other/x", "//127.0.0.1/x.png", ""])
            t("only(" + s + ")", LocalImage.only(s), "");
        for (const s of ["file:///a.png", "image://icon/a", "image://qsimage/1/2", "image://qspixmap/1/2"])
            t("only(" + s + ")", LocalImage.only(s), s);
        t("fileUrl(/a b#c?.png)", LocalImage.fileUrl("/a b#c?.png"), "file:///a%20b%23c%3F.png");
        t("fileUrl(relative)", LocalImage.fileUrl("a.png"), "");
        t("fileUrl(//host/a)", LocalImage.fileUrl("//host/a.png"), "");
        t("fromFileUrl(file:/a.png)", LocalImage.fromFileUrl("file:/a.png"), "file:///a.png");
        t("fromFileUrl(file://localhost/a.png)", LocalImage.fromFileUrl("file://localhost/a.png"), "file:///a.png");
        t("fromFileUrl(file://host/a.png)", LocalImage.fromFileUrl("file://127.0.0.1/a.png"), "");
        t("fromFileUrl(file:////host/a.png)", LocalImage.fromFileUrl("file:////127.0.0.1/a.png"), "");
        t("localIcon(theme name)", Notifs.localIcon(h.name), "image://icon/" + h.name);
        t("localIcon(missing name)", Notifs.localIcon("sleepyshell-test-no-such-icon"), "");
        t("localIcon(path)", Notifs.localIcon(h.pic), "file://" + h.pic);
        t("localIcon(url)", Notifs.localIcon(u), "");
        t("localIcon(name?path=)", Notifs.localIcon(h.name + "?path=/tmp"), "");
        t("tray(name?path=url)", tray.iconSource("image://icon/sleepyshell-test-no-such-icon?path=http://127.0.0.1:" + h.port + "/d"), "");
        t("tray(name?path=/dir)", tray.iconSource("image://icon/sleepyshell-test-no-such-icon?path=/tmp/d/"), "file:///tmp/d/sleepyshell-test-no-such-icon");
        t("tray(theme name?path=)", tray.iconSource("image://icon/" + h.name + "?path=/tmp/d"), "image://icon/" + h.name);
        t("tray(url)", tray.iconSource(u), "");
        return r;
    }

    function report() {
        if (h.done)
            return;
        h.done = true;
        const cards = [];
        for (let i = 0; i < cardRep.count; i++) {
            const c = cardRep.itemAt(i);
            const tt = toastRep.itemAt(i);
            cards.push({ summary: c.notif?.summary ?? "", image: String(c.notif?.image ?? ""), appIcon: String(c.notif?.appIcon ?? ""),
                sources: c.iconSources, card: c.iconSource, toast: tt ? tt.iconSource : null });
        }
        const trays = SystemTray.items.values.map(it => ({ id: it.id, raw: String(it.icon), src: tray.iconSource(it.icon) }));
        console.log("RESULT " + JSON.stringify({ control: control.status, units: h.units(), cards: cards, tray: trays }));
        quit.start();
    }

    onReadyChanged: if (ready) settle.start()

    Timer {
        id: settle
        interval: 3000
        onTriggered: h.report()
    }
    Timer {
        running: true
        interval: 25000
        onTriggered: h.report()
    }
    Timer {
        id: quit
        interval: 200
        onTriggered: Qt.exit(0)
    }

    FloatingWindow {
        implicitWidth: 520
        implicitHeight: 1800

        Column {
            width: 500

            Image {
                id: control
                width: 16
                height: 16
                source: "http://127.0.0.1:" + h.port + "/control.png"
            }

            Repeater {
                id: cardRep
                model: Notifs.list
                NotifCard {
                    required property var modelData
                    notif: modelData
                    width: 500
                }
            }

            Repeater {
                id: toastRep
                model: Notifs.list
                CompactToast {
                    required property var modelData
                    notif: modelData
                    width: 500
                }
            }

            Tray {
                id: tray
                bar: null
            }
        }
    }
}
