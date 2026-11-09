"""Tier 2-3 (the bar does not load, or its workspaces and popups do not answer): the real bar on the test screen, with
the stand-in Hyprland:
  - the bar loads with its three islands and the clock, without QML errors;
  - a click on a workspace dot asks Hyprland for that workspace, and the dot shows as focused once Hyprland says so;
  - a switch made outside the bar (a keybind's dispatch) moves the focus mark too;
  - a click on the clock opens the control centre panel, and leaving the island closes it (the panel opens on hover; a
    click only opens, never closes);
  - a side island's popup opens by its toggle while its widget is hidden (notifications, updates, privacy), and an
    open one stays open when its widget hides (updates)."""
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from ui import Shell, Input, check, done, commands

s = Shell.launch(sys.argv[1], "shell.qml", name="bar")
time.sleep(1.5)
wins = {w["type"]: w for w in s.windows()}
check(wins.get("Sleepybar", {}).get("visible") and wins.get("Sleepycentre", {}).get("visible"), "the bar and its centre island are up",
      f"{sorted(k for k, w in wins.items() if w['visible'])}")
clock = [e for e in s.find(type="QQuickText") if re.fullmatch(r"\d{1,2}:\d{2}", e["text"])]
check(clock, "the clock shows the time")
focused = lambda n: (s.find(props={"wsId": n}) or [{}])[0]
check(s.js("Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1") == 1, "workspace 1 is focused at start")

s.click(props={"wsId": 3})
check(s.wait(lambda: any("workspace = 3" in c for c in commands() if c.startswith("HYPR"))), "a click on dot 3 asks Hyprland for workspace 3")
check(s.wait(lambda: s.js("(function () { const d = sleepytestDriver.scan().items.find(e => e.obj.wsId === 3); return d ? d.obj.isFocused : false })()")),
      "dot 3 shows as focused once Hyprland switched")

subprocess.run(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = 5 })"], capture_output=True)
check(s.wait(lambda: s.js("(function () { const d = sleepytestDriver.scan().items.find(e => e.obj.wsId === 5); return d ? d.obj.isFocused : false })()")),
      "a switch made outside the bar moves the focus mark")

s.click(text=clock[0]["text"], top=True)
check(s.wait(lambda: s.js("Popouts.current !== null && Popouts.current.open === true")), "a click on the clock opens the panel")
time.sleep(0.6)
# the panel opens on hover and a click never closes it (hover usually opened it already); leaving the island closes it
Input.move(1280, 1000)
check(s.wait(lambda: s.js("Popouts.current === null || Popouts.current.open === false"), 5), "leaving the island closes the panel again")

# A side island's dropdown hangs from the island, not from its widget: a popup whose widget is hidden (nothing to show
# yet: no notifications, no updates pending, nothing using the microphone or camera) still opens by its toggle, and a
# second toggle closes it.
for name in ("notifications", "updates", "privacy"):
    hidden = s.js(f"(function () {{ const d = (Popouts.byName['{name}'] || [])[0]; return d ? d.anchorItem.visible : null; }})()")
    if not check(hidden is False, f"toggle {name}: its widget is hidden", json.dumps(hidden)):
        continue
    s.call("sleepybar", "toggle", name)
    opened = s.wait(lambda: s.js(f"(function () {{ const d = Popouts.byName['{name}'][0]; return d.open && Popouts.current === d && d.panel.visible && d.panel.height > 0; }})()") is True, 2)
    check(opened, f"toggle {name}: the popup opens while its widget is hidden")
    s.call("sleepybar", "toggle", name)
    check(s.wait(lambda: s.js(f"Popouts.byName['{name}'][0].open") is False, 2), f"toggle {name}: a second toggle closes it")
    time.sleep(0.4)

# ... and an open side popup stays open when its widget hides: the updates button leaves the bar once nothing is
# pending, and its dropdown stays. The run copy's checkupdates.sh stands in for pacman and paru; a right click on the
# button checks again.
checker = Path(sys.argv[1]) / "scripts/checkupdates.sh"
UPD = "(function () { const d = Popouts.byName['updates'][0]; return [d.anchorItem.visible, d.open, d.anchorItem.needsText]; })()"
if check(s.js(UPD)[2] == "", "updates: pacman, paru and fakeroot are there, so the button checks", json.dumps(s.js(UPD))):
    checker.write_text("#!/bin/sh\nprintf 'REPO 2\\nAUR 0\\nPKG one 1-1 -> 1-2\\nPKG two 2-1 -> 2-2\\n'\n")
    s.js("Popouts.byName['updates'][0].anchorItem.check(), 0")   # (the button is hidden: nothing to right-click yet)
    if check(s.wait(lambda: s.js(UPD)[0] is True, 5), "updates: with two updates pending the button shows"):
        s.call("sleepybar", "toggle", "updates")
        s.wait(lambda: s.js(UPD)[1] is True, 2)
        checker.write_text("#!/bin/sh\nprintf 'REPO 0\\nAUR 0\\n'\n")
        btn = s.js("(function () { const b = Popouts.byName['updates'][0].anchorItem; const p = b.mapToItem(null, b.width / 2, b.height / 2); return [p.x, p.y]; })()")
        Input.click(btn[0], btn[1], "right")
        hid = s.wait(lambda: s.js(UPD)[0] is False, 5)
        time.sleep(0.5)
        now = s.js(UPD)
        check(hid and now[1] is True, "updates: the dropdown stays open when its button leaves the bar", json.dumps(now))
        s.call("sleepybar", "toggle", "updates")

env_errors = ("pipewire", "quickshell.network", "Network will not work")
errs = [e for e in s.errors() if not any(x in e for x in env_errors)]
check(not errs, "no QML errors (besides the sandbox's missing PipeWire and NetworkManager)", "; ".join(errs[:3]))
done()
