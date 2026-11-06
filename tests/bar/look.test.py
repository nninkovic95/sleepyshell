"""Cosmetic smoke (the bar renders broken: missing glyphs, a wrong palette, islands out of place): the bar's left island
(the workspace dots) and right island at rest, compared with tests/refs/bar-left.png and bar-right.png within a small
tolerance. The centre island is left out: it shows the clock and this machine's live CPU and memory. A new look is
taken on by hand: tests/run.sh --update-refs, check the candidate, copy it to tests/refs/."""
import sys
import time
from ui import Shell, Input, check, done, shot, compare, RUN

s = Shell.launch(sys.argv[1], "shell.qml", name="bar")
Input.move(1280, 1000)
time.sleep(2)  # islands settle
for name, region in (("bar-left", (0, 0, 420, 60)), ("bar-right", (2560 - 420, 0, 420, 60))):
    img = shot(RUN / f"{name}.png", region)
    ok, why = compare(img, name, tolerance=0.0005)  # small crops: a few pixels are a changed glyph
    check(ok, f"the bar's {name.split('-')[1]} island looks as in its reference", why)
done()
