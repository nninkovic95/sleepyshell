"""Tier 3 (the keybinds list is empty, wrong or cannot be searched): the Keybinds window (Sleepykeys) lists the binds of
the Hyprland config it reads (the fixture's: Super+Enter opens the terminal, Super+Q closes a window, Super+1..5),
typing in its search narrows the list, and Escape closes the window, ending its process."""
import sys
import time
from ui import Shell, Input, check, done

s = Shell.launch(sys.argv[1], "sleepykeys.qml")
check(s.wait(lambda: s.visible(text="Open the terminal")), "the list shows the config's binds", f"{[e['text'] for e in s.find(type='QQuickText')][:30]}")
check(s.visible(text="Close the focused window") and s.visible(contains="Workspace 1"), "every group is listed")
s.click(contains="Search keybinds")
Input.type("terminal")
check(s.wait(lambda: s.visible(text="Open the terminal") and not s.visible(text="Close the focused window")),
      "typing in the search narrows the list")
Input.key("ctrl", "a")
Input.key("backspace")
check(s.wait(lambda: s.visible(text="Close the focused window")), "clearing the search shows every bind again")
Input.key("escape")
time.sleep(0.3)
if s.proc.poll() is None:
    Input.key("escape")  # the first Escape may only clear or leave the search field
check(s.wait(lambda: s.proc.poll() is not None, 5) and s.proc.returncode == 0, "Escape closes the window and its process ends",
      f"exit {s.proc.poll()}")
check(not s.errors(), "no QML errors", "; ".join(s.errors()[:3]))
done()
