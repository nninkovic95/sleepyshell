"""Tier 1-3 for the keybind overlay and the click circles (services/InputShow.qml), on the real bar with the stand-in
Hyprland. Failures it guards against: an overlay that shows input while it says it is off, or keeps Hyprland's flag
or click binds behind; a shortcut that also turns on the other feature; a feature on with nothing on the bar saying
so; an overlay surface that swallows clicks meant for the windows under it; a missing reporter that fails silently.
  - each shortcut's event turns only its own feature on and off;
  - each feature's indicator shows on the right island only while it is on, in the current workspace's colour (like the
    Caps Lock indicator; the capturing ones, microphone, camera, screen share and recording, use the alert colour), on the same line as the buttons beside it, as information: no
    hover, and a click on it changes nothing;
  - the overlay tells Hyprland exactly the fixed code (flag on; two pass-through click binds), and takes it back off;
  - a reported keybind shows by name ("Super + Enter"), a second press as "x2"; nothing shows while the overlay is off;
  - the keybind pill has the corner preset's island radius (sharp, default, round), like the islands;
  - a reported click draws a ring only while the circles are on;
  - with no answer from the reporter the overlay says it cannot name keybinds yet;
  - while both are on, a click still reaches the bar under the overlay."""
import sys
import time
from ui import Shell, Input, check, done, commands, hypr_event, RUN

s = Shell.launch(sys.argv[1], "shell.qml", name="bar")
time.sleep(1)
evals = lambda: [c for c in commands() if c.startswith("HYPR eval")]
on = lambda: (s.js("InputShow.keysOn"), s.js("InputShow.clicksOn"))
pill = lambda: [e["text"] for e in s.find(objectName="keyPillText")]
rings = lambda: s.find(objectName="clickRing", all=True)
shows = lambda name: s.visible(objectName=name)
radius = lambda: s.js("sleepytestDriver.scan().items.find(e => e.obj.objectName === 'keyPill').obj.radius")

check(not shows("keysIndicator") and not shows("clicksIndicator"), "while both are off neither indicator shows")
check(on() == (False, False), "both start off")
check(any("sleepyshell_keys_on = false" in c and "sleepyshell_clicks = {}" in c for c in evals()),
      "at start both are cleared in Hyprland (a crash while on left nothing behind)")

# the keybind overlay, from its shortcut's event
n = len(evals())
hypr_event("custom>>sleepyshell:keys")
check(s.wait(lambda: on() == (True, False)), "the overlay's shortcut turns on the overlay only", f"{on()}")
check(s.wait(lambda: shows("keysIndicator")) and not shows("clicksIndicator"), "its indicator shows, the other does not")
check(not s.find(type="Lift", inside={"objectName": "keysIndicator"}, all=True) and not s.find(type="QQuickMouseArea", inside={"objectName": "keysIndicator"}, all=True),
      "the indicator is information only: no hover, nothing to click")
Input.click(*s.centre(s.one(objectName="keysIndicator")))
time.sleep(0.4)
check(on() == (True, False), "a click on the indicator changes nothing", f"{on()}")
check(s.wait(lambda: any("sleepyshell_keys_on = true" in c for c in evals()[n:])), "it sets Hyprland's flag", f"{evals()[n:]}")
check(s.wait(lambda: any("can't be named" in t for t in pill()), 4), "with no answer from the reporter it says it cannot name keybinds yet",
      f"{pill()}")
check(s.js("InputShow.reporterMissing") is True, "and remembers that the reporter is missing")
hypr_event("custom>>sleepyshell:keyreport:ready")
check(s.wait(lambda: s.js("InputShow.reporterMissing") is False), "the reporter's answer clears it")

hypr_event("custom>>sleepyshell:keypress:64:p:Return")
check(s.wait(lambda: "Super + Enter" in pill()), "a reported keybind shows by name", f"{pill()}")
hypr_event("custom>>sleepyshell:keypress:64:p:Return")
check(s.wait(lambda: any("×2" in t for t in pill())), "a second press shows as x2", f"{pill()}")

# the pill follows the corner preset, like the islands
TOML = RUN / "s/sleepysettings.toml"
seen = {}
for preset in ("sharp", "round", "default"):
    TOML.write_text(f'[sleepybar]\ncorners = "{preset}"\n')
    want = {"sharp": 7, "default": 14, "round": 20}[preset]
    s.wait(lambda: s.js("Theme.islandRadius") == want, 5)
    seen[preset] = (radius(), s.js("Theme.islandRadius"))
check(all(r == isl == {"sharp": 7, "default": 14, "round": 20}[p] for p, (r, isl) in seen.items()),
      "the keybind pill has the island radius of each corner preset", f"{seen}")

hypr_event("custom>>sleepyshell:click:272")
time.sleep(0.15)
check(not rings(), "a click draws no ring while only the overlay is on")

# the click circles, from their shortcut's event
n = len(evals())
hypr_event("custom>>sleepyshell:clicks")
check(s.wait(lambda: on() == (True, True)), "the circles' shortcut turns them on, the overlay stays as it was", f"{on()}")
check(s.wait(lambda: shows("clicksIndicator")) and shows("keysIndicator"), "both indicators show while both are on")
icons = s.bar_icons()
check(icons.get("keysIndicator") == icons.get("clicksIndicator") == icons.get("Clipboard") is not None,
      "both indicators sit on the same line as the buttons beside them", f"{icons}")
glyph_colour = lambda name: s.js(f"String(sleepytestDriver.scan().items.find(e => e.obj.objectName === '{name}').obj.children[0].color)")
accent = s.js("String(Theme.accent)")
by_type = lambda typ, prop: s.js(f"(function () {{ const e = sleepytestDriver.scan().items.find(e => sleepytestDriver.typeName(e.obj) === '{typ}'); "
                                 f"return e ? String(e.obj.{prop}) : null }})()")
caps = s.js("(function () { const e = sleepytestDriver.scan().items.find(e => sleepytestDriver.typeName(e.obj) === 'CapsIndicator'); "
            "return e ? String(e.obj.children[0].color) : null })()")
check(glyph_colour("keysIndicator") == glyph_colour("clicksIndicator") == accent,
      "both indicators are drawn in the current workspace's colour (Theme.accent)",
      f"{glyph_colour('keysIndicator')}, {glyph_colour('clicksIndicator')}, accent {accent}")
check(caps in (accent, None), "the Caps Lock indicator uses the same colour", f"caps {caps}, accent {accent}")
alert = s.js("String(Theme.urgentFg)")
check(by_type("PrivacyPill", "fg") == alert, "the microphone, camera and screen-share indicator uses the alert colour, like the recording dot",
      f"privacy {by_type('PrivacyPill', 'fg')}, alert {alert}")
added = [c for c in evals()[n:] if "sleepyshell_clicks[" in c]
check(added and "{ 272, 273 }" in added[-1] and "non_consuming = true" in added[-1], "they add two pass-through click binds, left and right",
      f"{evals()[n:]}")
hypr_event("custom>>sleepyshell:click:272")
check(s.wait(lambda: rings(), 1), "a reported click draws a ring")

# a config reload drops run-time binds: what is on is set up again
n = len(evals())
hypr_event("configreloaded>>")
check(s.wait(lambda: any("{ 272, 273 }" in c for c in evals()[n:]) and any("sleepyshell_keys_on = true" in c for c in evals()[n:])),
      "after a Hyprland config reload both are set up again", f"{evals()[n:]}")

# the overlay surface takes no input: a click on a workspace dot still reaches the bar under it
s.click(props={"wsId": 2})
check(s.wait(lambda: any("workspace = 2" in c for c in commands() if c.startswith("HYPR hl.dsp"))), "a click still reaches the bar under the overlay")

# the overlay off, the circles on: no pill
n = len(evals())
hypr_event("custom>>sleepyshell:keys")
check(s.wait(lambda: on() == (False, True)), "the overlay's shortcut turns it off, the circles stay on", f"{on()}")
check(s.wait(lambda: not shows("keysIndicator")) and shows("clicksIndicator"), "its indicator goes, the circles' stays")
check(s.wait(lambda: any(c.endswith("sleepyshell_keys_on = false") for c in evals()[n:])), "its flag is cleared in Hyprland")
hypr_event("custom>>sleepyshell:keypress:64:p:Return")
time.sleep(0.6)
check(not pill(), "no keybind shows while the overlay is off", f"{pill()}")

n = len(evals())
hypr_event("custom>>sleepyshell:clicks")
check(s.wait(lambda: on() == (False, False)), "the circles' shortcut turns them off")
check(s.wait(lambda: not shows("clicksIndicator")), "and their indicator goes")
check(s.wait(lambda: any("b:remove()" in c and "sleepyshell_clicks = {}" in c and "{ 272, 273 }" not in c for c in evals()[n:])),
      "their click binds are removed by their own handles", f"{evals()[n:]}")
hypr_event("custom>>sleepyshell:click:273")
time.sleep(0.2)
check(not rings(), "no ring once they are off")

env_errors = ("pipewire", "quickshell.network", "Network will not work")
errs = [e for e in s.errors() if not any(x in e for x in env_errors)]
check(not errs, "no QML errors", "; ".join(errs[:3]))
done()
