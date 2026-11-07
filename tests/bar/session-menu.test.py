"""Tier 1 (the session ends or the machine shuts down by a slip): the session menu opens from Hyprland's custom event;
a quick click on Shut down, Reboot or Log out does nothing but say to hold; only a press held until the ring is full
runs the command; Sleep runs at a click; Escape closes the menu.

Every command lands on a logging stand-in in the sandbox (no system bus either), so nothing is ever really run."""
import sys
import time
from ui import Shell, Input, check, done, commands, hypr_event

s = Shell.launch(sys.argv[1], "shell.qml", name="bar")
time.sleep(1)


def open_menu():
    hypr_event("custom>>sleepyshell:toggle:session")
    return s.wait(lambda: s.visible(text="Shut down"))


def ran(word):
    return [c for c in commands() if c.startswith("RUN ") and word in c]


check(open_menu(), "the session menu opens from Hyprland's custom event")

for label, cmd in (("Shut down", "poweroff"), ("Reboot", "reboot"), ("Log out", "uwsm")):
    s.click(text=label)
    time.sleep(0.8)
    check(not ran(cmd), f"a quick click on {label} runs nothing", f"{ran(cmd)}")
check(s.wait(lambda: s.visible(contains="Hold to")), "the menu says to hold")

item = s.one(text="Reboot")
Input.move(*s.centre(item))
Input.send("press")
time.sleep(1.5)  # the ring fills in 600 ms
Input.send("release")
check(s.wait(lambda: ran("reboot")), "a held press on Reboot runs it once the ring is full", f"{commands()[-3:]}")
check(not ran("poweroff") and not ran("uwsm"), "nothing else ran")

check(open_menu(), "the menu opens again")
s.click(text="Sleep")
check(s.wait(lambda: ran("suspend")), "Sleep runs at a click")
check(open_menu(), "and opens again")
Input.key("escape")
check(s.wait(lambda: not s.visible(text="Shut down")), "Escape closes the menu")
env_errors = ("pipewire", "quickshell.network", "Network will not work")
errs = [e for e in s.errors() if not any(x in e for x in env_errors)]
check(not errs, "no QML errors (besides the sandbox's missing PipeWire and NetworkManager)", "; ".join(errs[:3]))
done()
