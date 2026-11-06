"""Tier 1 (a user's file written without a yes): every writer of a file outside the shell's own asks first, in the real
window, with the exact line or content, writes nothing on Cancel, and keeps a backup before changing an existing file.

  1. Config/Idle: Create on a missing hypridle.conf asks with the content; Create writes exactly that.
  2. Idle Apply over a hypridle.conf the shell did not write asks with the new content; Cancel keeps it; Replace backs
     it up and writes the content shown.
  3. Keybinds Apply into a keybinds file of the user's (pointed at in the Config tab) asks with the lines; Cancel keeps
     it; the yes backs it up.
The Export question and the require line have their own tests (export-asks, ask-first-config)."""
import sys
import time
from ui import Shell, Input, check, done, RUN

HOME = RUN / "home"
HYPR = HOME / ".config/hypr"
tree = sys.argv[1]
backups = lambda f: sorted(p.name for p in f.parent.iterdir() if p.name.startswith(f.name + ".bak-"))

# a keybinds file of the user's, pointed at before the window starts (as Config > Keybinds > Change location would)
mine = HOME / "mybinds.lua"
mine.write_text('hl.bind("SUPER + F7", hl.dsp.exec_cmd("mine"))\n')
(RUN / "s/sleepysettings.toml").write_text(f'[files]\npathCustombinds = "{mine}"\n')

s = Shell.launch(tree, "sleepysettings.qml")


def answer(title_part, button, timeout=10):
    """Wait for the question whose title holds title_part, return what it shows, press button."""
    if not s.wait(lambda: s.visible(contains=title_part), timeout):
        return None
    d = s.dialog() or {"lines": [], "texts": []}
    s.dialog_button(button)
    s.wait_gone(contains=title_part, timeout=5)
    time.sleep(0.5)
    return d


# 1. Create hypridle.conf from the Idle tab
idle = HYPR / "hypridle.conf"
s.tab("Idle")
s.button("Create")
d = answer("Create ~/.config/hypr/hypridle.conf?", "Cancel")
check(d is not None, "Create on a missing hypridle.conf asks first, naming the path")
check(d and d["lines"] and "listener" in d["lines"][0], "the question shows the file's content", d and d["lines"][:1])
check(not idle.exists(), "Cancel creates nothing")
s.button("Create")
d = answer("Create ~/.config/hypr/hypridle.conf?", "Create")
check(s.wait(lambda: idle.exists()), "Create writes the file")
check(d and idle.exists() and idle.read_text().strip() == d["lines"][0].strip(), "the file holds exactly the content shown",
      idle.read_text()[:200] if idle.exists() else "missing")

# 2. Idle Apply over a hypridle.conf the shell did not write
idle.write_text("# my own idle setup\n")
s.tab("Idle")
s.click(type="Toggle", inside={"props": {"label": "Dim screens when idle"}})
s.apply()
d = answer("Replace hypridle.conf?", "Cancel")
check(d is not None, "Apply over a hypridle.conf the shell did not write asks first")
check(d and d["lines"] and "listener" in d["lines"][0], "the question shows the new content", d and d["lines"][:1])
check(idle.read_text() == "# my own idle setup\n" and not backups(idle), "Cancel leaves the file as it was, no backup")
s.click(type="Toggle", inside={"props": {"label": "Dim screens when idle"}})
s.apply()
d = answer("Replace hypridle.conf?", "Replace")
check(d is not None, "a second Apply asks again")
check(s.wait(lambda: idle.read_text() != "# my own idle setup\n"), "Replace writes the file")
b = backups(idle)
check(len(b) == 1 and (idle.parent / b[0]).read_text() == "# my own idle setup\n", "one backup holds the user's text", f"{b}")
check(d and idle.read_text().strip() == d["lines"][0].strip(), "the file holds exactly the content shown")

# 3. Keybinds Apply into the user's own keybinds file
s.tab("Keybinds")
s.click(contains="Click, then press keys", top=True)  # the first field: Your keybinds
Input.key("super", "f8")
time.sleep(0.3)
s.click(contains="Command, e.g.")
Input.type("echo sleepytest")
s.button("Add keybind")
s.apply()
d = answer("Change mybinds.lua?", "Cancel")
check(d is not None, "Apply into a keybinds file Sleepysettings did not create asks first")
check(d and any("echo sleepytest" in l for l in d["lines"]), "the question shows the lines to be written", d and d["lines"][:3])
check(mine.read_text() == 'hl.bind("SUPER + F7", hl.dsp.exec_cmd("mine"))\n' and not backups(mine), "Cancel leaves the user's file as it was")
s.apply()
d = answer("Change mybinds.lua?", "Change")
check(s.wait(lambda: "echo sleepytest" in mine.read_text()), "the yes writes the new bind into the file")
check("SUPER + F7" in mine.read_text(), "the user's own bind is kept")
b = backups(mine)
check(len(b) == 1 and 'exec_cmd("mine")' in (mine.parent / b[0]).read_text(), "one backup of the user's file", f"{b}")

check(not s.errors(), "no QML errors", "; ".join(s.errors()[:3]))
done()
