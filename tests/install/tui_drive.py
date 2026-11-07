"""The full-screen interface of install.sh, driven by key presses through a pseudo-terminal (100x30, xterm-256color).

  tui_drive.py WORLD    (inside the sandbox of installer.test.sh, with inner.sh's world in WORLD)

Waits for each screen by its title, sends the keys a user would press, and prints what it saw:
Welcome (Enter), the picker (j, Space to untick Wallpaper theming, Enter), the AUR helper (Enter: the default, leave them
out), hyprland.lua (y), every service, the i2c-dev and the start question (Enter: the default, No), the summary (q:
cancel), the cancelled page (Enter). Prints "SCREEN <title>" per screen, "PICKER <line>" for the picker's theming line
after the untick, "SUMMARY <text>" for the summary screen, "EXIT <code>" and "RESTORED yes|no" (the terminal's screen and
cursor given back at the end). Exit 0 when every screen came; 1 on a timeout.
"""
import fcntl
import os
import pty
import re
import select
import struct
import sys
import termios
import time
from pathlib import Path

W = Path(sys.argv[1])
ESC_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][A-Z0-9]|\x1b[=>]")


def env():
    e = {"HOME": str(W / "home"), "PATH": str(W / "bin"), "LANG": "C.UTF-8", "TERM": "xterm-256color",
         "XDG_CONFIG_HOME": str(W / "home/.config"), "XDG_STATE_HOME": str(W / "home/.local/state"),
         "XDG_CACHE_HOME": str(W / "home/.cache"), "XDG_DATA_HOME": str(W / "home/.local/share"),
         "XDG_RUNTIME_DIR": os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "HYPRLAND_INSTANCE_SIGNATURE": "test",
         "SLEEPYSHELL_OS_RELEASE": str(W / "os-release"), "SLEEPYSHELL_DEV": str(W / "dev"),
         "SLEEPYSHELL_MODULES_LOAD": str(W / "modules-load.d"), "SLEEPYSHELL_HYPRIDLE_SERVICE": "none",
         "SLEEPYSHELL_HYPRIDLE_PROC": str(W / "proc"), "STUB_DIR": str(W / "stub"), "STUB_BIN": str(W / "bin")}
    return e


pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    os.execve("/usr/bin/bash", ["bash", str(W / "clone/install.sh")], env())

raw = b""
seen_upto = 0


def pump(t):
    global raw
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return False
            if not chunk:
                return False
            raw += chunk
    return True


def screen_text(b):
    return ESC_RE.sub("", b.decode("utf-8", "replace"))


def wait_for(*titles, timeout=20):
    """The newest frame that names one of titles (after the last one used); returns (title, frame text)."""
    global seen_upto
    end = time.time() + timeout
    while time.time() < end:
        pump(0.1)
        frames = raw[seen_upto:].split(b"\x1b[H\x1b[2J")
        for frame in reversed(frames):
            text = screen_text(frame)
            for t in titles:
                if f"installer: {t}" in text:
                    time.sleep(0.15)
                    pump(0.1)
                    # every screen as drawn, for a look when a check fails
                    last = screen_text(raw[seen_upto:].split(b"\x1b[H\x1b[2J")[-1])
                    with open(W / "frames.txt", "a") as f:
                        f.write(f"==== {t}\n{last}\n")
                    seen_upto = len(raw)
                    return t, text
    print("TIMEOUT waiting for " + " | ".join(titles))
    print(screen_text(raw[-3000:]))
    return None, ""


def key(k):
    os.write(fd, k.encode())


ok = True
t, _ = wait_for("Welcome")
ok &= t is not None
print("SCREEN", t)
key("\r")
t, text = wait_for("Pick the parts")
ok &= t is not None
print("SCREEN", t)
key("j")
key(" ")
time.sleep(0.3)
pump(0.3)
last = screen_text(raw[seen_upto:].split(b"\x1b[H\x1b[2J")[-1])
for line in last.split("\n"):
    if "Wallpaper theming" in line:
        print("PICKER", line.strip())
# down to System tools, whose package line is longer than the screen is wide: it must wrap, not be cut off
for _ in range(9):
    key("j")
    time.sleep(0.05)
# the newest frame, once the cursor has reached System tools (a redraw per key)
frame, end = "", time.time() + 10
while time.time() < end:
    pump(0.2)
    frame = screen_text(raw[seen_upto:].split(b"\x1b[H\x1b[2J")[-1])
    if "> [x] System tools" in frame and "Up/Down move" in frame:
        break
lines = frame.split("\n")
print("WRAPPED", "yes" if "libnotify" in frame and "> [x] System tools" in frame and max(len(l.rstrip()) for l in lines) <= 100 else "no")
with open(W / "frames.txt", "a") as f:
    f.write("==== picker at System tools\n" + frame + "\n")
key("\r")
t, _ = wait_for("AUR helper")
ok &= t is not None
print("SCREEN", t)
key("\r")
t, _ = wait_for("Your file: hyprland.lua")
ok &= t is not None
print("SCREEN", t)
key("y")
while True:
    t, text = wait_for("Service", "Monitor brightness", "Start the shell", "Summary", "First theme run")
    if t is None:
        ok = False
        break
    print("SCREEN", t)
    if t == "Summary":
        print("SUMMARY", " ".join(text.split()))
        key("q")
        break
    key("\r")
t, _ = wait_for("Cancelled")
ok &= t is not None
print("SCREEN", t)
key("\r")
pump(2)
_, status = os.waitpid(pid, 0)
print("EXIT", os.waitstatus_to_exitcode(status))
tail = raw[-400:]
print("RESTORED", "yes" if b"\x1b[?1049l" in tail and b"\x1b[?25h" in tail else "no")
sys.exit(0 if ok else 1)
