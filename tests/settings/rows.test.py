"""Tier 2 (Apply writes a wrong value, or a control does not stage at all): one click test per row type that every
setting uses. Each control is driven like a user drives it on the real window; the value must be staged, marked as
unapplied, and written by Apply into sleepysettings.toml exactly; Discard must drop a draft and the reset arrow must
stage the default.

  switch (SwitchRow, showDate)      a click on the switch
  number (NumberRow, clockSize)     the + step button
  choice (ChoiceRow, corners)       another segment
  combo  (ComboRow, clockFormat)    the dropdown, another entry
  text   (FieldRow, wallpaperDir)   type into the field, Enter"""
import sys
import time
import tomllib
from ui import Shell, Input, check, done, RUN

TOML = RUN / "s/sleepysettings.toml"
s = Shell.launch(sys.argv[1], "sleepysettings.qml")


def written(section, key):
    """The key's value in sleepysettings.toml (sections are named after the tabs; a key lives in one of them)."""
    try:
        data = tomllib.loads(TOML.read_text())
    except (OSError, ValueError):
        return None
    return next((v[key] for v in data.values() if isinstance(v, dict) and key in v), None)


def sections():
    try:
        return {k: sorted(v) if isinstance(v, dict) else v for k, v in tomllib.loads(TOML.read_text()).items()}
    except (OSError, ValueError) as e:
        return f"unreadable: {e}"


def apply_and_check(section, key, want, what):
    check(s.visible(type="BarButton", text="Apply"), f"{what}: the Apply bar shows")
    s.apply()
    check(s.wait(lambda: written(section, key) == want), f"{what}: Apply writes {key} = {want!r}",
          f"file has {written(section, key)!r}; tab busy={s.js('win.current.busy')} running={s.js('win.current.running')} "
          f"error={s.js('win.current.error')!r}")
    check(s.wait(lambda: key not in s.staged()), f"{what}: nothing is left unapplied", f"{s.staged()}")


# switch
s.tab("Centre island")
before = s.stored("showDate")
s.toggle("showDate")
check(s.wait(lambda: s.staged().get("showDate") == (not before)), "switch: a click stages the other value", f"{s.staged()}")
check(s.wait(lambda: s.row("showDate") and s.js("win.current.changes") == 1), "switch: the tab counts one unapplied change",
      s.js("win.current.changes"))
apply_and_check("centre", "showDate", not before, "switch")

# number: + and Discard, then + and Apply
s.tab("Centre island")


def plus():
    """The + of the row's spin field: the right one of its two step buttons."""
    s.reveal(props={"key": "clockSize"})
    steps = s.find(type="StepButton", inside={"props": {"key": "clockSize"}})
    Input.click(*s.centre(max(steps, key=lambda e: e["x"])))
    time.sleep(0.25)


start = s.stored("clockSize")
plus()
check(s.wait(lambda: s.staged().get("clockSize") == start + 1), "number: + stages one more", f"{s.staged()}")
s.button("Discard")
check(s.wait(lambda: "clockSize" not in s.staged()), "number: Discard drops the draft")
check(s.stored("clockSize") == start and written("centre", "clockSize") in (None, start), "number: Discard writes nothing")
plus()
s.wait(lambda: s.staged().get("clockSize") == start + 1)
apply_and_check("centre", "clockSize", start + 1, "number")

# choice
s.tab("Sleepybar")
cur = s.stored("corners")
# the options are the texts inside the row's segmented control (the row's label is a text of the row too)
s.reveal(props={"key": "corners"})
ctl = s.find(type="Segmented", inside={"props": {"key": "corners"}})
within = lambda e, r: r["x"] <= e["x"] + e["w"] / 2 <= r["x"] + r["w"] and r["y"] <= e["y"] + e["h"] / 2 <= r["y"] + r["h"]
segs = [e for e in s.find(type="QQuickText", inside={"props": {"key": "corners"}}) if e["text"] and ctl and within(e, ctl[0])]
labels = [e["text"] for e in segs]
other = next((e for e in segs if e["text"].lower() != str(cur).lower()), None)
check(len(segs) >= 2, "choice: the row shows its options", f"{labels}")
if other:
    Input.click(*s.centre(other))
    check(s.wait(lambda: s.staged().get("corners") not in (None, cur)), f"choice: a click on {other['text']!r} stages it", f"{s.staged()}")
    want = s.staged().get("corners")
    apply_and_check("bar", "corners", want, "choice")
    # the reset arrow stages the default again
    s.click(type="BarButton", inside={"props": {"key": "corners"}}, props={"glyph": 0xF054C})
    check(s.wait(lambda: s.staged().get("corners") == "default"), "reset arrow: stages the default", f"{s.staged()}")
    apply_and_check("bar", "corners", "default", "reset arrow")

# combo
s.tab("Centre island")
cur = s.stored("clockFormat")
s.reveal(props={"key": "clockFormat"})
# the label the closed dropdown shows for the current value (the list shows labels, not the stored value)
shown_now = [e["text"] for e in s.find(type="QQuickText", inside={"type": "Combo"}) if e["text"]]
s.click(type="Combo", inside={"props": {"key": "clockFormat"}})
opened = s.wait(lambda: s.find(type="QQuickText", inside={"type": "Picker"}))
check(opened, "combo: a click opens the dropdown")
if opened:
    opts = [e for e in s.find(type="QQuickText", inside={"type": "Picker"}) if e["text"] and e["text"] not in shown_now and len(e["text"]) > 1]
    pick = opts[0] if opts else None
    if pick:
        Input.click(*s.centre(pick))
        check(s.wait(lambda: s.staged().get("clockFormat") not in (None, cur)), f"combo: picking {pick['text']!r} stages it", f"{s.staged()}")
        apply_and_check("centre", "clockFormat", s.staged().get("clockFormat"), "combo")

# text field
s.tab("Theme")
box = s.reveal(type="TextBox", inside={"props": {"key": "wallpaperDir"}})
Input.click(*s.centre(box))
Input.key("ctrl", "a")
Input.type("~/Pictures/Sleepytest")
Input.key("enter")
check(s.wait(lambda: s.staged().get("wallpaperDir") == "~/Pictures/Sleepytest"), "text: typing and Enter stage the text", f"{s.staged()}")
apply_and_check("theme", "wallpaperDir", "~/Pictures/Sleepytest", "text")

check(not s.errors(), "no QML errors", "; ".join(s.errors()[:3]))
done()
