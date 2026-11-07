"""Tier 3 (the Caps Lock indicator lags behind the key, or needs several presses to catch up): the shell watches the
keyboard LED itself (services/CapsLock.qml), on a stand-in LED folder (SLEEPYSHELL_TEST_LEDS), without any Hyprland
event or bind.
  - a Caps Lock already on at start shows the indicator, without a flash;
  - the LED switching on shows the indicator within half a second, with no event sent, and flashes the Caps Lock line;
  - the LED switching off hides it again just as fast."""
import sys
import time
from ui import Shell, check, done, commands, RUN

led = RUN / "leds/input3::capslock/brightness"
led.parent.mkdir(parents=True)
led.write_text("1\n")
s = Shell.launch(sys.argv[1], "shell.qml", name="bar", env={"SLEEPYSHELL_TEST_LEDS": str(RUN / "leds")})
indicator = lambda: bool([e for e in s.find(type="CapsIndicator")])

check(s.wait(lambda: s.js("CapsLock.on") is True and indicator(), 3), "a Caps Lock already on at start shows the indicator")
check(s.js("OsdState.capsLast") is not True or s.js("OsdState.shown") is not True, "and does not flash at start")

led.write_text("0\n")
t0 = time.monotonic()
off = s.wait(lambda: s.js("CapsLock.on") is False and not indicator(), 2)
check(off and time.monotonic() - t0 < 0.6, "the LED switching off hides the indicator within half a second", f"{time.monotonic() - t0:.2f} s")

led.write_text("1\n")
t0 = time.monotonic()
on = s.wait(lambda: s.js("CapsLock.on") is True and indicator(), 2)
check(on and time.monotonic() - t0 < 0.6, "the LED switching on shows it within half a second, with no event sent", f"{time.monotonic() - t0:.2f} s")
check(not [c for c in commands() if "capslock" in c.lower()], "no Hyprland event or command was involved")
check(s.wait(lambda: s.js("OsdState.capsLast") is True, 2), "the change flashes the Caps Lock line")

env_errors = ("pipewire", "quickshell.network", "Network will not work")
errs = [e for e in s.errors() if not any(x in e for x in env_errors)]
check(not errs, "no QML errors", "; ".join(errs[:3]))
done()
