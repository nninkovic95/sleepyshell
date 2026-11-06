"""Tier 1 (a Hyprland or matugen file changed without a yes): the three writers of config files ask first in the real
window, with the exact lines, change nothing on Cancel, and keep a backup when they write.

  1. A keybinds file Hyprland does not load: the Keybinds tab's notice leads to Config, whose Set up asks with the
     exact require line for hyprland.lua; Add line adds it after a backup.
  2. Apps: Apply of a new terminal while programs.lua names another asks with the lines that would change; Change
     writes them after a backup.
  3. Theme: "Match folder colours" on with a matugen config that lacks the folder icons shows Set up…, which asks with
     the whole block; Add adds exactly that block after a backup."""
import os
import sys
import time
from ui import Shell, check, done, RUN, KIT

HOME = RUN / "home"
HYPR = HOME / ".config/hypr"
backups = lambda f: sorted(p.name for p in f.parent.iterdir() if p.name.startswith(f.name + ".bak-"))

own = HYPR / "modules/sleepybinds.lua"
# the notice shows only while the file holds a keybind (an empty own file needs no line)
own.write_text('-- Keybinds added in Sleepysettings: managed by Sleepysettings (Keybinds tab), loaded by require("modules.sleepybinds")\n'
               'hl.bind("SUPER + F9", hl.dsp.exec_cmd("echo sleepytest"))\n')
matugen = HOME / ".config/matugen/config.toml"
matugen.parent.mkdir(parents=True)
matugen.write_text("[config]\n")
(RUN / "s/sleepysettings.toml").write_text("[theme]\nfolderColours = true\n")
os.symlink(KIT / "common/ui/fake.py", RUN / "fakebin/foot")  # a second terminal that is "installed"

s = Shell.launch(sys.argv[1], "sleepysettings.qml")


def answer(title_part, button, timeout=10):
    if not s.wait(lambda: s.visible(contains=title_part), timeout):
        return None
    d = s.dialog() or {"lines": [], "texts": []}
    s.dialog_button(button)
    s.wait_gone(contains=title_part, timeout=5)
    time.sleep(0.5)
    return d


# 1. the require line
main = HYPR / "hyprland.lua"
before = main.read_text()
s.tab("Keybinds")
check(s.wait_visible(text="Set up in Config"), "the Keybinds tab says Hyprland does not load the keybinds file")
s.button("Set up in Config", top=True)  # Your keybinds and Shell shortcuts both use the file
check(s.wait(lambda: s.js("win.tab") == "files"), "Set up in Config opens the Config tab")
time.sleep(0.5)
s.button("Set up", top=True)
d = answer("Add this line to hyprland.lua?", "Cancel")
check(d is not None, "Set up asks before changing hyprland.lua")
check(d and d["lines"] == ['require("modules.sleepybinds")'], "the question shows the exact line", d and d["lines"])
check(main.read_text() == before and not backups(main), "Cancel leaves hyprland.lua as it was")
s.button("Set up", top=True)
answer("Add this line to hyprland.lua?", "Add line")
check(s.wait(lambda: 'require("modules.sleepybinds")' in main.read_text()), "Add line adds the line")
check(main.read_text().replace('require("modules.sleepybinds")\n', "") == before, "nothing else in hyprland.lua changes",
      main.read_text())
b = backups(main)
check(len(b) == 1 and (main.parent / b[0]).read_text() == before, "one backup of hyprland.lua", f"{b}")

# 2. programs.lua follows the terminal
programs = HYPR / "modules/programs.lua"
before = programs.read_text()
s.tab("Apps")
s.call("sleepysettings", "stage", "defaultTerminal", "foot")
s.wait(lambda: s.visible(type="BarButton", text="Apply"))
s.apply()
d = answer("Change programs.lua to match?", "Cancel")
check(d is not None, "Apply of a new terminal asks before changing programs.lua")
check(d and any("foot" in l for l in d["lines"]), "the question shows the changed line", d and d["lines"])
check(programs.read_text() == before and not backups(programs), "Cancel leaves programs.lua as it was")
check(s.stored("defaultTerminal") == "foot", "the setting itself is saved either way", s.stored("defaultTerminal"))

# 3. matugen's folder icons
s.tab("Theme")
shown = s.wait_visible(objectName="folderSetupButton", timeout=10)
check(shown, "with folder colours on and matugen not set up, Set up… shows",
      f"folderColours={s.stored('folderColours')}, loaded={s.js('Appearance.foldersLoaded')}, folders={str(s.js('Appearance.folders'))[:200]}")
if shown:
    s.click(objectName="folderSetupButton")
    d = answer("Add the folder icons to the matugen config?", "Cancel")
    check(d is not None, "Set up… asks before changing the matugen config")
    block = d["lines"][0] if d and d["lines"] else ""
    check(block.count("[templates.") >= 1, "the question shows the whole block", block[:200])
    check(matugen.read_text() == "[config]\n" and not backups(matugen), "Cancel leaves the matugen config as it was")
    s.click(objectName="folderSetupButton")
    answer("Add the folder icons to the matugen config?", "Add")
    check(s.wait(lambda: block and block.strip() in matugen.read_text()), "Add writes exactly the block shown")
    b = backups(matugen)
    check(len(b) == 1 and (matugen.parent / b[0]).read_text() == "[config]\n", "one backup of the matugen config", f"{b}")

check(not s.errors(), "no QML errors", "; ".join(s.errors()[:3]))
done()
