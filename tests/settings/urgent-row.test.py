"""Tier 3 (the urgent apps cannot be chosen, or a look of one's own is lost or offered as a choice): the Notifications
tab's Urgent section, with librewolf listed and a look written by hand in sleepysettings.toml:
  - the listed app shows as a chip with its name from its desktop entry;
  - "Add an app…" opens the list of installed apps, without the ones already listed; picking one stages it;
  - the chip's remove button stages the list without it;
  - the hand-written look shows as "Custom" with its value and where it was set, and the dropdown offers the presets;
    picking a preset stages it."""
import sys
import time
from ui import Shell, Input, check, done, RUN

LOOK = "tint 30, edge 6, chip"
(RUN / "s/sleepysettings.toml").write_text(f'[notifications]\nurgentApps = "librewolf"\nurgentLook = "{LOOK}"\n')

s = Shell.launch(sys.argv[1], "sleepysettings.qml")
s.tab("Notifications")
chip = s.reveal(objectName="urgentAppChip")
check(chip is not None, "the listed app shows as a chip")
check(s.wait(lambda: s.find(text="LibreWolf", inside={"objectName": "urgentAppChip"})), "named from its desktop entry")

# add an app from the installed ones
s.click(objectName="urgentAppAdd")
opened = s.wait(lambda: s.find(type="QQuickText", inside={"type": "Picker"}))
check(opened, "Add an app opens the list of installed apps")
if opened:
    texts = [e for e in s.find(type="QQuickText", inside={"type": "Picker"}) if e["text"] and len(e["text"]) > 1]
    check(not [e for e in texts if e["text"] == "LibreWolf"], "without the app already listed")
    if texts:
        Input.click(*s.centre(texts[0]))
        check(s.wait(lambda: str(s.staged().get("urgentApps", "")).startswith("librewolf, ")),
              f"picking {texts[0]['text']!r} adds it to the list", f"{s.staged()}")
        check(s.wait(lambda: len(s.find(objectName="urgentAppChip")) == 2), "and it shows as a second chip")

# remove the first app
removes = sorted(s.find(objectName="urgentAppRemove"), key=lambda e: (e["y"], e["x"]))
check(len(removes) == 2, "each chip has a remove button", f"{len(removes)}")
if removes:
    Input.click(*s.centre(removes[0]))
check(s.wait(lambda: "librewolf" not in str(s.staged().get("urgentApps", "librewolf")).split(", ")),
      "the remove button takes the app off the list", f"{s.staged()}")

# a look of one's own
s.reveal(props={"key": "urgentLook"})
check(s.find(text="Custom", inside={"props": {"key": "urgentLook"}}), "a look written by hand shows as Custom")
check(s.find(contains=LOOK, inside={"props": {"key": "urgentLook"}}), "with its value and where it was set")
s.click(type="Combo", inside={"props": {"key": "urgentLook"}})
listed = s.wait(lambda: [e["text"] for e in s.find(type="QQuickText", inside={"type": "Picker"}) if e["text"]])
check(listed and "Red card and label" in listed and "Edge only" in listed, "the dropdown offers the presets", f"{listed}")
check(listed and "Custom" not in listed, "but no Custom entry: Custom is a label, not a choice", f"{listed}")
pick = [e for e in s.find(type="QQuickText", inside={"type": "Picker"}) if e["text"] == "Edge only"]
if pick:
    Input.click(*s.centre(pick[0]))
    check(s.wait(lambda: s.staged().get("urgentLook") == "edge"), "picking a preset stages it", f"{s.staged()}")
time.sleep(0.3)
check(not s.errors(), "no QML errors", "; ".join(s.errors()[:3]))
done()
