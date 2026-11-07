"""Tier 2-3 (the bar does not load, or its workspaces and popups do not answer): the real bar on the test screen, with
the stand-in Hyprland:
  - the bar loads with its three islands and the clock, without QML errors;
  - a click on a workspace dot asks Hyprland for that workspace, and the dot shows as focused once Hyprland says so;
  - a switch made outside the bar (a keybind's dispatch) moves the focus mark too;
  - a click on the clock opens the control centre panel, and leaving the island closes it (the panel opens on hover; a
    click only opens, never closes)."""
import re
import subprocess
import sys
import time
from ui import Shell, check, done, commands

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
from ui import Input
Input.move(1280, 1000)
check(s.wait(lambda: s.js("Popouts.current === null || Popouts.current.open === false"), 5), "leaving the island closes the panel again")

env_errors = ("pipewire", "quickshell.network", "Network will not work")
errs = [e for e in s.errors() if not any(x in e for x in env_errors)]
check(not errs, "no QML errors (besides the sandbox's missing PipeWire and NetworkManager)", "; ".join(errs[:3]))
done()
