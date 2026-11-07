"""Tier 1-2 (a lock that can be passed without the password, or that cannot be unlocked): the real Sleepylock on the
test screen, checked against a test PAM stack that knows one test password (the account's own PAM and pam_faillock are
never asked; ui.pam_stack, prepare.py --pam).
  - it takes the session lock and covers the screen;
  - Enter and Escape on an empty field never reach PAM, and the lock stays;
  - a wrong test password is refused with "Wrong password", the lock stays;
  - the right test password unlocks, and the lock's process ends with 0."""
import sys
import time
from ui import Shell, Input, check, done, pam_stack

pam = pam_stack("sleepytest-pass")
calls = lambda: len((pam / "calls").read_text().splitlines()) if (pam / "calls").exists() else 0
s = Shell.launch(sys.argv[1], "sleepylock.qml", name="lock", pam=pam)
surface = s.wait(lambda: [w for w in s.windows() if w["kind"] == "lock" and w["visible"]])
check(surface and surface[0]["width"] == 2560 and surface[0]["height"] == 1440, "the lock takes the session and covers the screen",
      f"{surface}")

Input.key("enter")
Input.key("escape")
time.sleep(1.5)
check(calls() == 0, "Enter and Escape on an empty field never reach PAM", f"{calls()} checks")
check(s.proc.poll() is None, "the lock stays")

Input.type("not-the-password")
Input.key("enter")
check(s.wait(lambda: s.visible(text="Wrong password")), "a wrong password is refused with a message")
check(calls() == 1 and s.proc.poll() is None, "one check, and the lock stays", f"{calls()} checks")

Input.type("sleepytest-pass")
Input.key("enter")
check(s.wait(lambda: s.proc.poll() is not None, 10) and s.proc.returncode == 0, "the right password unlocks and the lock ends with 0",
      f"exit {s.proc.poll()}")
check(calls() == 2, "exactly one more check", f"{calls()} checks")
errs = [e for e in s.errors() if "dbus" not in e.lower()]
check(not errs, "no QML errors", "; ".join(errs[:3]))
done()
