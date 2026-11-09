"""Tier 3 (notifications lost, or do not disturb that does not hold): the bar is the notification server on the
sandbox's private session bus.
  - a notification sent the way an app sends it shows as a popup with its summary and body;
  - the popup names the app that sent it, but not "notify-send", the name a script's notification carries when it
    passes none;
  - the control centre's Do not disturb tile turns it on (saved at once);
  - under do not disturb a normal notification shows no popup, a critical one still does."""
import subprocess
import sys
import time
from ui import Shell, Input, check, done


def notify(summary, body, critical=False, app="Sleepytest"):
    hints = "{'urgency': <byte 2>}" if critical else "{}"
    r = subprocess.run(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path",
                        "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify",
                        app, "0", "", summary, body, "[]", hints, "8000"], capture_output=True, text=True)
    return r.returncode == 0


s = Shell.launch(sys.argv[1], "shell.qml", name="bar")
check(s.wait(lambda: notify("Hello from a test", "First body")), "the bar answers on the notification bus")
check(s.wait(lambda: s.visible(text="Hello from a test")), "the notification shows as a popup")
check(s.visible(contains="First body"), "with its body")
check(s.visible(contains="Sleepytest"), "and the name of the app that sent it")
notify("From a script", "Script body", app="notify-send")
check(s.wait(lambda: s.visible(text="From a script")), "a script's notification shows as a popup")
check(not s.visible(contains="notify-send"), "without the sending tool's own name in place of an app name")

# do not disturb from the control centre
times = [e for e in s.find(type="QQuickText") if len(e["text"]) in (4, 5) and e["text"][-3] == ":"]
Input.click(*s.centre(min(times, key=lambda e: e["y"])))
check(s.wait(lambda: s.visible(text="Do not disturb")), "the control centre opens with its Do not disturb tile")
s.click(text="Do not disturb", top=True)
check(s.wait(lambda: s.js("Settings.stored('dnd')") is True), "the tile turns do not disturb on and saves it")
Input.move(1280, 1000)
time.sleep(1.5)

check(notify("Quiet one", "Should not pop up"), "the quiet notification reaches the bar")
time.sleep(1.5)
check(not s.visible(text="Quiet one"), "under do not disturb a normal notification shows no popup")
notify("Urgent one", "Critical still shows", critical=True)
check(s.wait(lambda: s.visible(text="Urgent one")), "a critical notification still pops up")

env_errors = ("pipewire", "quickshell.network", "Network will not work")
errs = [e for e in s.errors() if not any(x in e for x in env_errors)]
check(not errs, "no QML errors", "; ".join(errs[:3]))
done()
