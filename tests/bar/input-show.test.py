"""Tier 1-3 for the keybind overlay and the click circles (services/InputShow.qml), on the real bar with the stand-in
Hyprland. Failures it guards against: an overlay that shows input while it says it is off, or keeps Hyprland's flag
or click binds behind; a shortcut that also turns on the other feature; a feature on with nothing on the bar saying
so; an overlay surface that swallows clicks meant for the windows under it; a missing reporter that fails silently.
  - each shortcut's event turns only its own feature on and off;
  - each feature's indicator shows on the right island only while it is on, as its icon alone in the warning colour
    (like Caps Lock and recording; the clickable microphone, camera and screen-share indicator looks the same and shows
    the hover highlight and lift on hover only), on the same line as the buttons beside it, as information: no hover,
    and a click on it changes nothing;
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
# the state indicators (BarIndicator): the icon alone, nothing drawn behind it; its colour and size
pill_parts = lambda name: s.js(f"""(function () {{
  const e = sleepytestDriver.scan().items.find(e => e.obj.objectName === '{name}' || sleepytestDriver.typeName(e.obj) === '{name}');
  if (!e) return null;
  const kids = e.obj.children, glyph = kids.find(k => sleepytestDriver.typeName(k) === 'Glyph');
  return {{ behind: kids.filter(k => k !== glyph).length, icon: glyph ? String(glyph.color) : null, size: glyph ? glyph.font.pixelSize : null }};
}})()""")
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
urgent, hover = s.js("String(Theme.alertIcon)"), s.js("String(Theme.hoverBg)")


def contrast(a, b):
    """WCAG contrast of two #rrggbb colours, worked out here, apart from the shell's own code."""
    def lum(h):
        r, g, b_ = (int(h.lstrip("#")[-6:][i:i + 2], 16) / 255 for i in (0, 2, 4))
        f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b_)
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


bar_bg = s.js("String(Theme.containerHighest)")
check(contrast(urgent, bar_bg) >= 4.4, "the warning icon colour reads against the bar (at least 4.5:1)", f"{urgent} on {bar_bg}: {contrast(urgent, bar_bg):.2f}:1")
for name in ("keysIndicator", "clicksIndicator", "CapsIndicator"):
    parts = pill_parts(name)
    check(parts and parts["behind"] == 0 and parts["icon"] == urgent, f"{name} is the icon alone, in the readable warning colour",
          f"{parts}, urgent {urgent}")
bar_icon = s.js("Theme.barIconSize")
caps = pill_parts("CapsIndicator") or {}
check(caps.get("size") == round(bar_icon * 5 / 6) and (pill_parts("keysIndicator") or {}).get("size") == bar_icon,
      "the Caps Lock symbol is drawn at 5/6 of the icon size, so it looks as big as the others", f"caps {caps}, bar icon {bar_icon}")
privacy = s.js("(function () { const e = sleepytestDriver.scan().items.find(e => sleepytestDriver.typeName(e.obj) === 'PrivacyPill'); "
               "return e ? { bg: String(e.obj.bg), hover: String(e.obj.hoverBg), fg: String(e.obj.fg), hoverFg: String(e.obj.hoverFg), "
               "lift: e.obj.lift } : null })()")
check(privacy and privacy["bg"] == s.js("String(Qt.color('transparent'))") and privacy["fg"] == privacy["hoverFg"] == urgent,
      "the microphone, camera and screen-share indicator has the same warning icon and nothing behind it at rest", f"{privacy}")
check(privacy and privacy["hover"] == hover and privacy["lift"] is True,
      "and, being clickable, the hover highlight and lift, on hover only", f"{privacy}")
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
# a light palette: the alert red is pale there, so the icon colour must turn dark to stay readable
# fed through Theme.apply, the function a theme run's new palette file goes through
s.js("""Theme.apply('{"surface_container_highest": "#e6e0e9", "error_container": "#ffdad6", "on_error_container": "#410002", "surface": "#fef7ff", "on_surface": "#1d1b20"}')""")
light = s.wait(lambda: s.js("String(Theme.containerHighest)") == "#e6e0e9", 5)
icon = s.js("String(Theme.alertIcon)")
check(light and contrast(icon, "#e6e0e9") >= 4.4 and contrast("#ffdad6", "#e6e0e9") < 1.5,
      "in a light palette the pale alert red becomes a dark red that still reads (at least 4.5:1)", f"{icon}: {contrast(icon, '#e6e0e9'):.2f}:1")
check(not errs, "no QML errors", "; ".join(errs[:3]))
done()
