"""Tier 3 (a tab that does not open, or opens broken): every tab listed in the sidebar opens from a click on its entry,
shows its title, and the window logs no QML error on the way; Ctrl+Tab moves to the next tab.

With SLEEPYTEST_DUMP=1 it also keeps, per tab, the visible text, the buttons and a screenshot in tests/jobs/failed/
(a map for writing tests, not a check)."""
import json
import os
import sys
import time
from ui import Shell, Input, check, done, shot, RUN

dump = os.environ.get("SLEEPYTEST_DUMP") == "1"
s = Shell.launch(sys.argv[1], "sleepysettings.qml")
s.wait(lambda: s.js("win.pages.length") > 0)
pages = s.js("win.pages.map(p => ({ key: p.key, label: p.label }))") or []
check(len(pages) >= 10, "the window lists its tabs", f"{pages}")

for p in pages:
    # the sidebar entry: the label's text in the left column (a tab's own title repeats the label further right)
    entry = [e for e in s.find(text=p["label"]) if e["x"] < 200]
    if not entry:
        print(f"note: {p['label']} is not in the sidebar here (a tab that needs something this machine lacks)")
        continue
    Input.click(*s.centre(entry[0]))
    opened = s.wait(lambda: s.js("win.tab") == p["key"], 5)
    check(opened, f"a click on {p['label']} opens its tab", s.js("win.tab"))
    if dump:
        d = RUN / "failed"
        d.mkdir(exist_ok=True)
        time.sleep(0.6)
        shot(d / f"tab-{p['key']}.png")
        win = entry[0]["win"]
        info = {"texts": s.texts(win), "buttons": [b["text"] or b["objectName"] for b in s.find(type="BarButton", win=win)],
                "named": sorted(s.js(f"[...new Set(sleepytestDriver.find({{ win: {win} }}).map(e => e.objectName).filter(n => n))]") or [])}
        (d / f"tab-{p['key']}.json").write_text(json.dumps(info, indent=1))

before = s.js("win.tab")
Input.key("ctrl", "tab")
check(s.wait(lambda: s.js("win.tab") != before, 3), "Ctrl+Tab moves to the next tab", f"{before} -> {s.js('win.tab')}")
errs = s.errors()
check(not errs, "no QML errors while every tab opened", "; ".join(errs[:3]))
done()
