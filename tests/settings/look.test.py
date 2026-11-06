"""Cosmetic smoke (the window renders broken: missing fonts or icons, a wrong palette, a layout that fell apart): the
settings window on its first tab, compared with tests/refs/settings-window.png within a small tolerance. The palette
is the theme's built-in one (the test home has no colors.json), the screen size fixed, the pointer parked off the
window. A new look is taken on by hand: tests/run.sh --update-refs, check the candidate, copy it to tests/refs/."""
import sys
import time
from ui import Shell, Input, check, done, shot, compare, floating_rects, RUN

s = Shell.launch(sys.argv[1], "sleepysettings.qml")
s.wait(lambda: s.js("win.tab") == "bar")
Input.move(2500, 1400)
time.sleep(1.5)  # opening animations end
rect = floating_rects(s.proc.pid)[0][1]
img = shot(RUN / "settings-window.png", (rect["x"], rect["y"], rect["width"], rect["height"]))
ok, why = compare(img, "settings-window")
check(ok, "the settings window looks as in its reference", why)
done()
