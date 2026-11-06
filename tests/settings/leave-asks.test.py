"""Tier 2 (changes lost or written without a choice): leaving a tab or closing the window with unapplied changes asks
first; Keep editing keeps the draft, Discard drops it and writes nothing, Apply writes it. Escape closes a question
before the window; Ctrl+S applies the open tab. All through real clicks and keys on the real window."""
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


s = Shell.launch(sys.argv[1], "sleepysettings.qml")
s.tab("Centre island")
default = s.stored("showDate")

# leaving a tab with a draft
s.toggle("showDate")
s.wait(lambda: "showDate" in s.staged())
s.tab("Sleepybar", expect=False)
check(s.wait_visible(contains="Centre island changes not applied"), "leaving a tab with unapplied changes asks first")
check(s.js("win.tab") == "centre", "the tab stays open while it asks")
s.dialog_button("Keep editing")
check(s.wait_gone(contains="Centre island changes not applied") and s.js("win.tab") == "centre" and "showDate" in s.staged(),
      "Keep editing stays on the tab with the draft")
s.tab("Sleepybar", expect=False)
s.wait_visible(contains="Centre island changes not applied")
s.dialog_button("Discard")
check(s.wait(lambda: s.js("win.tab") == "bar"), "Discard moves on to the clicked tab")
check("showDate" not in s.staged() and written("showDate") is None, "Discard drops the draft and writes nothing", f"{s.staged()}")

# Ctrl+S applies the open tab
s.tab("Centre island")
s.toggle("showDate")
s.wait(lambda: "showDate" in s.staged())
Input.key("ctrl", "s")
check(s.wait(lambda: written("showDate") == (not default)), "Ctrl+S applies the open tab", f"file has {written('showDate')!r}")

# Escape: first the question, then the window
s.toggle("showDate")
s.wait(lambda: "showDate" in s.staged())
Input.key("escape")
check(s.wait_visible(contains="Centre island changes not applied"), "Escape with unapplied changes asks before closing")
Input.key("escape")
check(s.wait_gone(contains="Centre island changes not applied") and s.js("win.visible"), "a second Escape closes the question, not the window")
Input.key("escape")
s.wait_visible(contains="Centre island changes not applied")
s.dialog_button("Apply")
check(s.wait(lambda: written("showDate") == default), "Apply in the closing question writes the draft", f"file has {written('showDate')!r}")
check(s.wait(lambda: s.proc.poll() is not None, 10) and s.proc.returncode == 0, "the window closes and its process ends cleanly",
      f"exit {s.proc.poll()}")
check(not s.errors(), "no QML errors", "; ".join(s.errors()[:3]))
done()
