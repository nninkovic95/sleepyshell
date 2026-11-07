"""Shell shortcuts for the keybind overlay and the click circles, and the reporter's line in hyprland.lua.
  Tier 1 (hyprland.lua changed without a yes, or a line other than the one shown): the Keybinds tab's notice says
  Hyprland does not load the key reporter; Set up asks with the exact line; Cancel writes nothing; the yes puts
  exactly that line above the first statement, before the binds, after a backup; the notice then goes.
  Tier 3 (a shortcut that cannot be set, or one that takes a key already in use): both rows offer their suggested
  key (Super+Shift+K, Super+Shift+L); Set key and Apply write exactly the bind that sends the shell's event; a key
  already bound is refused."""
import sys
import time
from ui import Shell, Input, check, done, RUN

HYPR = RUN / "home/.config/hypr"
main = HYPR / "hyprland.lua"
binds_file = HYPR / "modules/sleepybinds.lua"
before = main.read_text()
backups = lambda f: sorted(p.name for p in f.parent.iterdir() if p.name.startswith(f.name + ".bak-"))
expected_line = f'pcall(dofile, "{RUN}/s/data/keyreport.lua")'  # the run copy is not under the test home

s = Shell.launch(sys.argv[1], "sleepysettings.qml")
s.tab("Keybinds")


def row_item(label, **spec):
    """An item in the shell shortcut row whose name is `label` (the rows have no key of their own: same line)."""
    name = s.reveal(text=label)
    if not name:
        return None
    same = [e for e in s.find(**spec) if abs((e["y"] + e["h"] / 2) - (name["y"] + name["h"] / 2)) < 12]
    return same[0] if same else None


check(s.reveal(text="Keybind overlay") and s.reveal(text="Click circles"), "both shortcuts are listed")
check(row_item("Keybind overlay", text="SUPER + SHIFT + K") is not None, "the overlay's row suggests Super+Shift+K")
check(row_item("Click circles", text="SUPER + SHIFT + L") is not None, "the circles' row suggests Super+Shift+L")
check(not binds_file.exists(), "a suggestion writes nothing")

# a key already in use is refused (the fixture binds SUPER + Q)
field = row_item("Click circles", type="KeyCapture")
Input.click(*s.centre(field))
Input.key("super", "q")
time.sleep(0.3)
Input.click(*s.centre(row_item("Click circles", type="BarButton", text="Set key")))
check(s.wait(lambda: s.visible(contains="already bound")), "a key that is already bound is refused")

# the suggestion, set and applied
Input.click(*s.centre(row_item("Keybind overlay", type="BarButton", text="Set key")))
s.apply()
want = 'hl.bind("SUPER + SHIFT + K", hl.dsp.event("sleepyshell:keys"))'
check(s.wait(lambda: binds_file.exists() and want in binds_file.read_text()), "Set key and Apply write the bind that sends the overlay's event",
      binds_file.read_text() if binds_file.exists() else "no file")

# the reporter's line
check(s.wait(lambda: s.visible(contains="doesn't load the key reporter")), "the notice says Hyprland does not load the key reporter")
s.click(type="BarButton", text="Set up", inside={"objectName": "keyreportNotice"})
check(s.wait_visible(contains="Add this line to hyprland.lua?"), "Set up asks first")
d = s.dialog()
check(d and d["lines"] == [expected_line], "the question shows the exact line", d and d["lines"])
s.dialog_button("Cancel")
time.sleep(0.6)
check(main.read_text() == before and not backups(main), "Cancel leaves hyprland.lua as it was")
s.click(type="BarButton", text="Set up", inside={"objectName": "keyreportNotice"})
s.wait_visible(contains="Add this line to hyprland.lua?")
s.dialog_button("Add line")
check(s.wait(lambda: expected_line in main.read_text()), "the yes adds the line")
lines = main.read_text().splitlines()
first_code = next(i for i, l in enumerate(before.splitlines()) if l.strip() and not l.strip().startswith("--"))
check(lines[first_code] == expected_line and "\n".join(lines[:first_code] + lines[first_code + 1:]) == before.rstrip("\n"),
      "exactly that line, above the first statement, and nothing else changed", "\n".join(lines[:4]))
b = backups(main)
check(len(b) == 1 and (main.parent / b[0]).read_text() == before, "one backup of hyprland.lua", f"{b}")
check(s.wait(lambda: not s.visible(contains="doesn't load the key reporter"), 8), "the notice goes once the line is there")
check(not s.errors(), "no QML errors", "; ".join(s.errors()[:3]))
done()
