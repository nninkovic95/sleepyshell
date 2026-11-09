"""Tier 3 (a recording runs with nothing on the bar saying so, or a dot that stays after it stopped): a recorder tells
the shell over its IPC (`sleepybar recording true|false`, as showoff's recorder does); the right island shows a dot
only while the shell has been told a recording runs, as information only (no hover, a click changes nothing), in a
fixed red, larger than the other indicators and blinking, so it is not missed."""
import sys
import time
from ui import Shell, Input, check, done

s = Shell.launch(sys.argv[1], "shell.qml", name="bar")
time.sleep(1)
shows = lambda: s.visible(objectName="recordingIndicator")

check(not shows(), "no dot while nothing records")
s.call("sleepybar", "recording", "true")
check(s.wait(shows), "the dot shows once a recorder says it records")
check(not s.find(type="Lift", inside={"objectName": "recordingIndicator"}, all=True)
      and not s.find(type="QQuickMouseArea", inside={"objectName": "recordingIndicator"}, all=True),
      "the dot is information only: no hover, nothing to click")
Input.click(*s.centre(s.one(objectName="recordingIndicator")))
time.sleep(0.4)
check(shows() and s.js("Recording.on") is True, "a click on it changes nothing")
check(not s.find(type="QQuickText", inside={"objectName": "recordingIndicator"}), "no timer, only the dot")
glyph_js = """(function () {
  const o = sleepytestDriver.scan().items.find(e => e.obj.objectName === 'recordingIndicator').obj;
  const glyph = o.children.find(k => sleepytestDriver.typeName(k) === 'Glyph');
  return { behind: o.children.filter(k => k !== glyph).length, icon: String(glyph.color), size: glyph.font.pixelSize,
           opacity: glyph.opacity };
})()"""
parts = s.js(glyph_js)
check(parts["behind"] == 0 and parts["icon"] == s.js("String(Theme.recording)") and parts["icon"] != s.js("String(Theme.accent)"),
      "it is the icon alone, in the fixed recording red, not the palette's accent", f"{parts}")
check(parts["size"] > s.js("Theme.barIconSize"), "the dot is drawn larger than the other indicators", f"{parts}")
seen = set()
for _ in range(16):
    seen.add(round(s.js(glyph_js)["opacity"], 1))
    time.sleep(0.1)
check(max(seen) - min(seen) >= 0.4, "the dot blinks while the recording runs", f"opacities seen {sorted(seen)}")
icons = s.bar_icons()
check(icons.get("recordingIndicator") == icons.get("Clipboard") is not None, "the dot sits on the same line as the buttons beside it", f"{icons}")
s.call("sleepybar", "recording", "false")
check(s.wait(lambda: not shows()), "the dot goes once the recorder says it stopped")
env_errors = ("pipewire", "quickshell.network", "Network will not work")
errs = [e for e in s.errors() if not any(x in e for x in env_errors)]
check(not errs, "no QML errors", "; ".join(errs[:3]))
done()
