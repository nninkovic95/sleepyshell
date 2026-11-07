"""Tier 2 (a change shows as applied but is not saved, or the preview never reaches the bar): the real bar and the real
settings window on the same test screen, linked over their socket.
  - the window links to the bar (its "Bar not running" note goes away);
  - a change in the window shows on the bar at once (live preview) and is not written yet;
  - Apply is saved by the bar (the bar is the writer while linked), and the window then shows nothing unapplied;
  - Discard takes the preview back off the bar."""
import sys
import time
import tomllib
from ui import Shell, Input, check, done, RUN

TOML = RUN / "s/sleepysettings.toml"


def written(key):
    try:
        data = tomllib.loads(TOML.read_text())
    except (OSError, ValueError):
        return None
    return next((v[key] for v in data.values() if isinstance(v, dict) and key in v), None)


bar = Shell.launch(sys.argv[1], "shell.qml", name="bar")
time.sleep(1)  # the bar opens its settings socket a moment after it starts
win = Shell.launch(sys.argv[1], "sleepysettings.qml", name="window")
check(win.wait(lambda: win.js("Settings.linked"), 10), "the window links to the bar")
check(win.wait(lambda: not win.visible(objectName="linkNote")), "the 'Bar not running' note is gone")

dot_h = lambda: (bar.find(props={"wsId": 1}) or [{"h": None}])[0]["h"]
start = dot_h()
check(start == 30, "the bar starts at the default height", f"{start}")


def plus():
    win.reveal(props={"key": "barHeight"})
    steps = win.find(type="StepButton", inside={"props": {"key": "barHeight"}})
    Input.click(*win.centre(max(steps, key=lambda e: e["x"])))
    time.sleep(0.3)


win.tab("Sleepybar")
plus()
check(bar.wait(lambda: dot_h() == 31), "a + in the window shows on the bar at once", f"bar height {dot_h()}")
check(written("barHeight") is None, "nothing is written before Apply")
win.apply()
check(win.wait(lambda: written("barHeight") == 31), "Apply saves the value", f"file has {written('barHeight')!r}")
check(win.wait(lambda: "barHeight" not in win.staged()), "the window shows nothing unapplied after the bar saved it")
check(bar.js("Settings.stored('barHeight')") == 31, "the bar holds the saved value")

plus()
check(bar.wait(lambda: dot_h() == 32), "a second + previews on the bar")
win.button("Discard")
check(bar.wait(lambda: dot_h() == 31), "Discard takes the preview back off the bar", f"bar height {dot_h()}")
check(written("barHeight") == 31, "and leaves the saved value")

env_errors = ("pipewire", "quickshell.network", "Network will not work")
errs = [e for e in bar.errors() + win.errors() if not any(x in e for x in env_errors)]
check(not errs, "no QML errors in the bar or the window", "; ".join(errs[:3]))
done()
