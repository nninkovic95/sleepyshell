"""Tier 3 (an urgent notification missed: hidden by do not disturb, timed out unseen, silent, or looking like any other;
or a sound played again for old notifications after a reload). Urgent = critical, or from an app on the user's list
(urgentApps, matched on the desktop entry or the app name). Under do not disturb, with "librewolf" on the list:
  - a normal app's notification shows no popup and plays nothing;
  - LibreWolf's (desktop entry librewolf, as the browser sends it) pops up with the Urgent chip, outlasts its own
    timeout, and plays the chosen sound file once through pw-play;
  - a critical one from an app not on the list is urgent too;
  - an urgent one that asks for no sound (suppress-sound) pops up silently;
  - with the sound switched off nothing plays;
  - a reload of the shell brings the kept notifications back without playing anything."""
import json
import sys
import time
from pathlib import Path
from ui import Shell, Input, check, done, commands, RUN

SOUND = "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga"
TOML = RUN / "s/sleepysettings.toml"
TOML.write_text(f'[notifications]\ndnd = true\nurgentApps = "Librewolf, other"\nurgentSoundFile = "{SOUND}"\n'
                'urgentSoundVolume = 110\n')


def notify(app, summary, body, hints="{}", timeout="8000"):
    import subprocess
    return subprocess.run(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path",
                           "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
                           app, "0", "", summary, body, "[]", hints, timeout], capture_output=True, text=True).returncode == 0


def chimes():
    return [json.loads(c.split(" ", 2)[2]) for c in commands() if c.startswith("RUN pw-play ")]


s = Shell.launch(sys.argv[1], "shell.qml", name="bar")
Input.move(1280, 1000)
check(s.wait(lambda: notify("Sleepytest", "Quiet one", "A normal app under do not disturb")), "the bar answers on the bus")
time.sleep(1.5)
check(not s.visible(text="Quiet one"), "under do not disturb a normal app's notification shows no popup")
check(chimes() == [], "and plays no sound")

notify("LibreWolf", "A website says hi", "A web page's notification", "{'desktop-entry': <'librewolf'>}", timeout="1500")
check(s.wait(lambda: s.visible(text="A website says hi")), "LibreWolf's notification pops up under do not disturb")
check(s.visible(objectName="urgentChip"), "with the Urgent chip")
check(s.wait(lambda: len(chimes()) == 1), "it plays the sound")
check(chimes()[:1] == [["-P", '{ application.name = "Sleepy Shell" }', "--volume", "1.33100", "--", SOUND]],
      "the chosen sound file, through pw-play, as a stream of its own name at the set 110 % (mixer scale)",
      json.dumps(chimes()))
time.sleep(3)
check(s.visible(text="A website says hi"), "it is still on screen after its own 1.5 s timeout")
check(len(chimes()) == 1, "the sound played once", json.dumps(chimes()))

time.sleep(1)  # the stand-in player has exited: the next chime is not merged into the first
notify("Sleepytest", "Critical one", "Not on the list but critical", "{'urgency': <byte 2>}")
check(s.wait(lambda: s.visible(text="Critical one")), "a critical notification from an app not on the list pops up")
check(s.wait(lambda: len(chimes()) == 2), "and plays the sound too")

time.sleep(1)
notify("LibreWolf", "Muted one", "Asks for no sound", "{'desktop-entry': <'librewolf'>, 'suppress-sound': <true>}")
check(s.wait(lambda: s.visible(text="Muted one")), "an urgent one that asks for no sound still pops up")
time.sleep(1)
check(len(chimes()) == 2, "but plays nothing", json.dumps(chimes()))

# a reload hands every kept notification to the server again (lastGeneration): none of them may ring
loads = s.log.read_text(errors="replace").count("Configuration Loaded")
edited = Path(sys.argv[1]) / "sleepybar/Sleepybar.qml"
edited.write_text(edited.read_text() + "\n// changed on disk\n")
if check(s.wait(lambda: s.log.read_text(errors="replace").count("Configuration Loaded") > loads, 15),
         "an edit to the bar's file reloads the shell"):
    time.sleep(2)
    check(s.js("Notifs.count") >= 3, "the notifications are kept", str(s.js("Notifs.count")))
    check(len(chimes()) == 2, "and no sound plays for them", json.dumps(chimes()))

# the sound switched off (saved the way the settings window's Apply does)
s.js("Settings.commitValues({ urgentSound: false })")
check(s.wait(lambda: s.js("Settings.urgentSound") is False), "the sound is switched off")
notify("LibreWolf", "Silent one", "Sound off", "{'desktop-entry': <'librewolf'>}")
check(s.wait(lambda: s.visible(text="Silent one")), "an urgent one still pops up with the sound off")
time.sleep(1)
check(len(chimes()) == 2, "and plays nothing", json.dumps(chimes()))

# the Urgent look: a preset, a look written out by hand, and one that cannot be read
s.js("Settings.commitValues({ urgentLook: 'edge' })")
check(s.wait(lambda: not s.visible(objectName="urgentChip")), "the Edge only look drops the Urgent chip")
s.js("Settings.commitValues({ urgentLook: 'tint 30, edge 6, chip' })")
check(s.wait(lambda: s.visible(objectName="urgentChip")), "a look written out with chip shows the chip again")
style = s.js("Notifs.urgentStyle") or {}
check(style.get("tint") == 30 and style.get("edge") == 6, "and its tint and edge are read", json.dumps(style))
check((s.js("Notifs.lookParts('nonsense')") or {}).get("chip") is True, "a look that cannot be read falls back to the full one")
check((s.js("Notifs.lookParts('toString')") or {}).get("chip") is True, "a look named like a built-in function falls back too")
check(s.js("Notifs.lookParts(' Tint ')") == {"tint": 55, "edge": 4, "chip": False}, "a preset name typed in another case is the preset",
      json.dumps(s.js("Notifs.lookParts(' Tint ')")))

env_errors = ("pipewire", "quickshell.network", "Network will not work")
errs = [e for e in s.errors() if not any(x in e for x in env_errors)]
check(not errs, "no QML errors", "; ".join(errs[:3]))
done()
