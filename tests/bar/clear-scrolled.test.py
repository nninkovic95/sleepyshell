"""Tier 3 (Clear all looks broken): Clear all in the notification dropdown after the list was scrolled down.
  - the cards scrolled out above the view are dropped at once, without a swipe nobody can see;
  - every card that was in view slides out to the right, one after another from the top, while it is in view;
  - nothing waits for the fallback (about 2.5 s without a card taking its turn) and then vanishes unseen.
A recorder inside the shell samples every card's place each 15 ms, so the check sees the motion, not only the result."""
import subprocess
import sys
import time
from ui import Shell, Input, check, done

N = 14


def notify(summary, body):
    r = subprocess.run(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path",
                        "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
                        "Sleepytest", "0", "", summary, body, "[]", "{}", "0"], capture_output=True, text=True)
    return r.returncode == 0


# Samples, per card of the dropdown's list: its summary, x, and whether it is inside the list's clip.
RECORDER = r"""
(function () {
    // the dropdown's cards (swipeIndex -1 on the toasts); found by property, as their type name carries two suffixes
    const isCard = o => o && o.swipeIndex !== undefined && o.listView !== undefined;
    const cards = sleepytestDriver.scan().items.map(e => e.obj).filter(o => isCard(o) && o.swipeIndex >= 0);
    if (!cards.length)
        return "no cards";
    const view = cards[0].listView;
    // an Item child of the list, so later calls find it again by its objectName
    const rec = Qt.createQmlObject('import QtQuick; Item { objectName: "sleepytestRecorder"; property var view; property var log: []; property real t0: Date.now(); property alias timer: tm; Timer { id: tm; interval: 15; repeat: true } }', view);
    rec.view = view;
    rec.timer.triggered.connect(() => {
        const v = rec.view, kids = v.contentItem.children, row = { t: Date.now() - rec.t0, count: Notifs.count, cy: Math.round(v.contentY), cards: [] };
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i];
            if (!isCard(c) || !c.notif || !c.visible)
                continue;
            const top = c.y - v.contentY;
            row.cards.push({ s: c.notif.summary, x: Math.round(c.x), top: Math.round(top), pos: top + c.height <= 4 ? -1 : top >= v.height - 4 ? 1 : 0 });
        }
        // assigned, not pushed: a var property can hand back a copy
        rec.log = rec.log.concat([row]);
    });
    return "ok";
})()
"""

s = Shell.launch(sys.argv[1], "shell.qml", name="bar")
check(s.wait(lambda: notify("Card 01", "body")), "the bar answers on the notification bus")
for i in range(2, N + 1):
    notify(f"Card {i:02d}", "body")
check(s.wait(lambda: s.js("Notifs.count") == N), f"{N} notifications wait in the list")
time.sleep(1)

bell = s.wait(lambda: s.find(text=str(N)))
check(bool(bell), "the bell shows the count")
Input.click(*s.centre(bell[0]))
check(s.wait(lambda: s.visible(text="Clear all")), "the dropdown opens")
time.sleep(0.5)

# down until about two cards are out of view above
CONTENT_Y = ('Math.round(sleepytestDriver.scan().items.map(e => e.obj)'
             '.find(o => o && o.swipeIndex >= 0 && o.listView).listView.contentY)')
x, y = s.centre(s.one(text="Clear all", top=True))
Input.move(x - 150, y + 250)
for _ in range(40):
    if s.js(CONTENT_Y) >= 200:
        break
    Input.send("scroll", 3)
    time.sleep(0.1)
time.sleep(0.8)

REC = 'sleepytestDriver.scan().items.map(e => e.obj).find(o => o.objectName === "sleepytestRecorder")'
check(s.js(RECORDER) == "ok", "the recorder starts")
s.js(f"{REC}.timer.start(), 0")
time.sleep(0.2)
s.click(text="Clear all", top=True)
check(s.wait(lambda: s.js("Notifs.count") == 0, timeout=10), "Clear all removes every notification")
time.sleep(0.2)
log = s.js(f"{REC}.log")
s.js(f"{REC}.timer.stop(), 0")

pre = log[0]
above = [c["s"] for c in pre["cards"] if c["pos"] < 0]
in_view = [c["s"] for c in pre["cards"] if c["pos"] == 0]
summaries = [f"Card {i:02d}" for i in range(1, N + 1)]
# cards with no delegate at the start were scrolled further up (above) or further down (to come)
listed = {c["s"] for c in pre["cards"]}
order = list(reversed(summaries))          # newest first, the default list order
first_listed = next(i for i, sm in enumerate(order) if sm in listed)
above += [sm for sm in order[:first_listed]]
print(f"  at the click: {len(above)} above the view, {len(in_view)} in view, contentY {pre['cy']}, {len(log)} samples")
check(len(above) >= 1, "the list was scrolled: at least one card is out of view above", str(pre))

# for every card: the samples where it moved right, and whether it was in view then
moved = {}
for row in log:
    for c in row["cards"]:
        if c["x"] > 0:
            moved.setdefault(c["s"], []).append(c["pos"] == 0)

unseen_swipes = [sm for sm, views in moved.items() if not any(views)]
check(not unseen_swipes, "no card slides out while it is out of view", ", ".join(unseen_swipes))
dropped_late = [sm for sm in above if sm in moved]
check(not dropped_late, "the cards above the view are dropped, not swiped", ", ".join(dropped_late))
slid = [sm for sm in summaries if sm not in above and sm in moved and any(moved[sm])]
not_slid = [sm for sm in summaries if sm not in above and sm not in slid]
check(not not_slid, "every other card slides out while in view", f"{len(slid)} slid; not: {', '.join(not_slid)}")
first_drop = log[next(i for i, r in enumerate(log) if r["count"] < N)]
check(first_drop["count"] <= N - len(above), "the cards above go first, together",
      f"first change left {first_drop['count']}, expected <= {N - len(above)}")
# the cards in view hold still while the ones above go: the first of them stays where it was until it slides
lead = min((c for c in pre["cards"] if c["pos"] == 0), key=lambda c: c["top"])["s"]
tops = [c["top"] for row in log for c in row["cards"] if c["s"] == lead and c["x"] == 0]
check(max(tops) - min(tops) <= 4, "the cards in view do not jump when the ones above are dropped",
      f"{lead} moved between {min(tops)} and {max(tops)}")
# the longest stretch with no card leaving: a stalled sweep sits ~2.5 s before the fallback
stall, run_start = 0, None
for a, b in zip(log, log[1:]):
    if 0 < b["count"] == a["count"] < N:
        run_start = a["t"] if run_start is None else run_start
        stall = max(stall, b["t"] - run_start)
    else:
        run_start = None
check(stall < 1000, "the sweep never stalls", f"longest wait between cards {stall} ms")

errs = [e for e in s.errors() if not any(x in e for x in ("pipewire", "quickshell.network", "Network will not work"))]
check(not errs, "no QML errors", "; ".join(errs[:3]))
done()
