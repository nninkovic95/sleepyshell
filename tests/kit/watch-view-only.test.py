"""Tier 1 for the kit (a watching viewer that could act on the test screen): the watch mode's VNC server (wayvnc with
the exact flags of common/ui/session.sh, on a Unix socket in the run folder) takes no input from a viewer.

A minimal RFB client (stdlib) clicks a workspace dot of the real bar through VNC. As a control, the same click
through a wayvnc started without --disable-input must switch the workspace (so the test can fail); with the watch
mode's flags nothing may happen. No viewer is shown anywhere: everything stays inside the sandbox."""
import os
import socket
import struct
import subprocess
import sys
import time
from ui import Shell, check, done, commands, RUN


def rfb_click(path, x, y):
    """Connect as a VNC viewer over the Unix socket, then press and release the left button at x, y."""
    c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    c.settimeout(10)
    c.connect(str(path))
    def recv(n):
        b = b""
        while len(b) < n:
            chunk = c.recv(n - len(b))
            if not chunk:
                raise ConnectionError("the server closed the connection")
            b += chunk
        return b
    version = recv(12)
    c.sendall(b"RFB 003.008\n")
    types = recv(recv(1)[0])
    if 1 not in types:
        raise ConnectionError(f"no 'None' security type offered: {list(types)}")
    c.sendall(b"\x01")
    if struct.unpack(">I", recv(4))[0] != 0:
        raise ConnectionError("security handshake failed")
    c.sendall(b"\x01")  # ClientInit, shared
    w, h = struct.unpack(">HH", recv(4))
    recv(16)
    recv(struct.unpack(">I", recv(4))[0])
    # a viewer first says which encodings it reads (raw) and asks for the screen, then waits for the first update
    c.sendall(struct.pack(">BBHi", 2, 0, 1, 0))
    c.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, w, h))
    if recv(1)[0] != 0:
        raise ConnectionError("no framebuffer update")
    for mask in (0, 1, 0):  # PointerEvent: move there, press, release
        c.sendall(struct.pack(">BBHH", 5, mask, int(x), int(y)))
        time.sleep(0.2)
    time.sleep(0.5)
    c.close()
    return version, (w, h)


def start_vnc(flags, sock):
    p = subprocess.Popen(["wayvnc", *flags, str(sock)], stdout=open(RUN / f"{sock.name}.log", "w"), stderr=subprocess.STDOUT)
    for _ in range(100):
        if sock.exists():
            break
        time.sleep(0.05)
    return p


s = Shell.launch(sys.argv[1], "shell.qml", name="bar")
time.sleep(1)
asked = lambda n: [c for c in commands() if c.startswith("HYPR") and f"workspace = {n}" in c]
dot = lambda n: s.centre(s.one(props={"wsId": n}))

watch_flags = os.environ["UI_VNC_FLAGS"].split()
check("--disable-input" in watch_flags and watch_flags[-1] == "--unix-socket", "the watch mode's flags disable input and use a Unix socket",
      f"{watch_flags}")

# control: input enabled, the click must work
control_flags = [f for f in watch_flags if f != "--disable-input"]
p = start_vnc(control_flags, RUN / "control.sock")
version, size = rfb_click(RUN / "control.sock", *dot(2))
p.terminate()
p.wait(5)
check(version.startswith(b"RFB ") and size == (2560, 1440), "a VNC client connects over the socket and sees the test screen", f"{version!r} {size}")
check(s.wait(lambda: asked(2), 5), "control: without --disable-input a click through VNC reaches the bar",
      (RUN / "control.sock.log").read_text()[-600:])

# the watch mode's own flags: nothing may reach the screen
p = start_vnc(watch_flags, RUN / "watch.sock")
rfb_click(RUN / "watch.sock", *dot(4))
time.sleep(1.5)
p.terminate()
p.wait(5)
check(not asked(4), "with the watch mode's flags a click through VNC reaches nothing", f"{asked(4)}")
check(s.js("Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1") == 2, "the focused workspace is unchanged")
done()
