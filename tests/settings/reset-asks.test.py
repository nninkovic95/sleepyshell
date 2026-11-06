"""Tier 2 (settings put back to defaults by one stray click): Config > Reset… and Reset all… ask first; Cancel stages
nothing; the yes only stages the defaults (nothing is written until Apply) and Discard brings the user's values back."""
import sys
import tomllib
from ui import Shell, check, done, RUN

TOML = RUN / "s/sleepysettings.toml"
# the user's own values, different from the defaults, on two tabs
TOML.write_text("[sleepybar]\ncorners = \"square\"\n\n[centre-island]\nshowDate = false\n")
before = TOML.read_text()

s = Shell.launch(sys.argv[1], "sleepysettings.qml")
check(s.wait(lambda: s.stored("showDate") is False and s.stored("corners") == "square"), "the user's values load",
      f"{s.stored('showDate')}, {s.stored('corners')}")
s.tab("Config")

s.button("Reset all…")
check(s.wait_visible(contains="Reset all settings?"), "Reset all… asks first")
s.dialog_button("Cancel")
check(s.wait_gone(contains="Reset all settings?") and not s.staged(), "Cancel stages nothing", f"{s.staged()}")

s.button("Reset all…")
s.wait_visible(contains="Reset all settings?")
s.dialog_button("Reset all")
staged = s.wait(lambda: s.staged().get("showDate") is True and s.staged().get("corners") == "default" and s.staged())
check(staged, "Reset all stages the defaults on every tab", f"{s.staged()}")
check(TOML.read_text() == before, "nothing is written before Apply")
for label in ("Sleepybar", "Centre island"):  # the two tabs Reset all changed; Discard is per tab
    s.tab(label)
    s.button("Discard")
    s.wait(lambda: s.js("win.current.dirty") is False, 3)
check(s.wait(lambda: not s.staged()) and s.stored("showDate") is False, "Discard brings the user's values back", f"{s.staged()}")

# one tab: the picker defaults to the first tab, Sleepybar
s.tab("Config")
s.button("Reset…")
check(s.wait_visible(contains="Reset the Sleepybar tab?"), "Reset… asks first, naming the tab")
s.dialog_button("Reset")
check(s.wait(lambda: s.staged().get("corners") == "default"), "Reset stages the tab's defaults", f"{s.staged()}")
check("showDate" not in s.staged(), "another tab's values are left alone", f"{s.staged()}")
check(TOML.read_text() == before, "nothing is written before Apply")
check(not s.errors(), "no QML errors", "; ".join(s.errors()[:3]))
done()
