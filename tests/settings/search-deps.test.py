"""Tier 3 (a setting that cannot be found, or a control that runs a missing program):
  - typing in the search box narrows the sidebar to the tabs with a match, and Enter opens the first one, with the row;
  - a row whose program is missing (matugen, through Deps' test hook) is greyed, says what is missing, and a click on
    its control stages nothing and runs nothing."""
import sys
import time
from ui import Shell, Input, check, done, commands

s = Shell.launch(sys.argv[1], "sleepysettings.qml")

# search
s.click(contains="Search settings")
Input.type("clock font")
check(s.wait(lambda: s.js("win.query") != ""), "typing goes into the search box", s.js("win.query"))
listed = s.wait(lambda: [p["key"] for p in s.js("win.navPages.map(p => ({ key: p.key }))") or []])
check(listed == ["centre"], "the sidebar lists only the tab with the row", f"{listed}")
Input.key("enter")
check(s.wait(lambda: s.js("win.tab") == "centre"), "Enter opens that tab", s.js("win.tab"))
check(s.reveal(props={"key": "clockFont"}), "the row is shown")
Input.key("escape")
check(s.wait(lambda: s.js("win.query") == ""), "Escape clears the search")

# a missing program
s.js("Deps.fakeMissing = ['matugen']")
s.tab("Theme")
row = s.reveal(props={"key": "themeMode"})
check(row is not None, "the Light or dark row is there")
check(s.wait(lambda: s.js("win.current") and not (s.find(props={"key": "themeMode"}) or [{}])[0].get("enabled", True)),
      "a row whose program is missing is greyed")
check(s.wait(lambda: any("matugen" in e["text"] for e in s.find(inside={"props": {"key": "themeMode"}}) + s.find(contains="matugen"))),
      "the row says matugen is missing")
ran_before = len(commands())
light = [e for e in s.find(type="QQuickText", inside={"props": {"key": "themeMode"}}) if e["text"] == "Light"]
check(light, "the row shows its Light option")
if not light:
    done()
Input.click(*s.centre(light[0]))
time.sleep(0.6)
check("themeMode" not in s.staged(), "a click on the greyed control stages nothing", f"{s.staged()}")
check(not [c for c in commands()[ran_before:] if "matugen" in c or "theme.py" in c], "and runs nothing", f"{commands()[ran_before:]}")
check(not s.errors(), "no QML errors", "; ".join(s.errors()[:3]))
done()
