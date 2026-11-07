"""fakehypr.py: a stand-in for Hyprland's IPC sockets inside a test sandbox, so a shell under test can reach no real compositor.

    fakehypr.py serve RUNDIR [STATE.json]   create $XDG_RUNTIME_DIR/hypr/<sig>/.socket.sock and .socket2.sock, print the signature
    fakehypr.py event RUNDIR LINE          broadcast LINE ("custom>>sleepyshell:session") on .socket2.sock

Requests are answered from a small state (one monitor that matches the test compositor's output, workspaces 1-5); every
request is appended to RUNDIR/hypr-requests.log and every dispatch also to RUNDIR/commands.log as "HYPR <text>", so a
test can check what the shell asked for. A focus-workspace dispatch changes the active workspace and sends the events
Hyprland would; nothing else is acted on. Refuses to start without SLEEPYSHELL_SANDBOX.
"""
import json
import os
import re
import socket
import sys
import threading
from pathlib import Path

SIG = "sleepytest_0_0"


def default_state():
    w = int(os.environ.get("SLEEPYSHELL_TEST_W", "2560"))
    h = int(os.environ.get("SLEEPYSHELL_TEST_H", "1440"))
    return {
        "monitor": {
            "id": 0, "name": os.environ.get("SLEEPYSHELL_TEST_OUTPUT", "HEADLESS-1"), "description": "Test output",
            "make": "Test", "model": "Headless", "serial": "0", "width": w, "height": h, "physicalWidth": 0,
            "physicalHeight": 0, "refreshRate": 60.0, "x": 0, "y": 0, "reserved": [0, 0, 0, 0], "scale": 1.0,
            "transform": 0, "focused": True, "dpmsStatus": True, "vrr": False, "solitary": "0", "activelyTearing": False,
            "directScanoutTo": "0", "disabled": False, "currentFormat": "XRGB8888", "mirrorOf": "none",
            "availableModes": [f"{w}x{h}@60.00Hz"],
        },
        "workspaces": [1, 2, 3, 4, 5],
        "occupied": [1],
        "active": 1,
        "clients": [],
    }


class Fake:
    def __init__(self, run, state):
        self.run = Path(run)
        self.st = state
        self.listeners = []
        self.lock = threading.Lock()
        base = Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr" / SIG
        base.mkdir(parents=True, exist_ok=True)
        self.base = base

    def log(self, name, line):
        with open(self.run / name, "a") as f:
            f.write(line + "\n")

    def ws(self, i):
        m = self.st["monitor"]
        return {"id": i, "name": str(i), "monitor": m["name"], "monitorID": m["id"],
                "windows": 1 if i in self.st["occupied"] else 0, "hasfullscreen": False,
                "lastwindow": "0x0", "lastwindowtitle": "", "ispersistent": False}

    def monitors(self):
        m = dict(self.st["monitor"])
        m["activeWorkspace"] = {"id": self.st["active"], "name": str(self.st["active"])}
        m["specialWorkspace"] = {"id": 0, "name": ""}
        return [m]

    def answer(self, req):
        flags, _, cmd = req.partition("/") if re.match(r"^[a-z]*/", req) else ("", "", req)
        word, _, rest = cmd.partition(" ")
        if word == "dispatch":
            self.log("commands.log", "HYPR " + rest)
            self.apply(rest)
            return "ok"
        if word in ("eval", "keyword", "reload", "output", "setcursor", "notify", "dismissnotify"):
            self.log("commands.log", "HYPR " + cmd)
            return "ok"
        data = {
            "monitors": self.monitors,
            "workspaces": lambda: [self.ws(i) for i in self.st["workspaces"] if i in self.st["occupied"] or i == self.st["active"]],
            "activeworkspace": lambda: self.ws(self.st["active"]),
            "clients": lambda: self.st["clients"],
            "activewindow": lambda: {},
            "layers": lambda: {},
            "devices": lambda: {"mice": [], "keyboards": [], "tablets": [], "touch": [], "switches": []},
            "binds": lambda: [],
            "workspacerules": lambda: [],
            "cursorpos": lambda: {"x": 0, "y": 0},
            "version": lambda: {"branch": "", "commit": "", "tag": "v0.57.1", "flags": []},
            "getoption": lambda: {"option": rest, "int": 0, "float": 0.0, "str": "", "set": False},
        }.get(word)
        if data is None:
            return "unknown request"
        return json.dumps(data())

    def apply(self, text):
        m = re.search(r"workspace\s*=\s*\"?(-?\d+)", text)
        if m and "focus" in text:
            n = int(m.group(1))
            if n != self.st["active"]:
                old, kept = self.st["active"], self.st["occupied"]
                # Hyprland creates a workspace when it is first focused and destroys an empty one when it is left
                if n not in kept:
                    self.broadcast(f"createworkspace>>{n}")
                    self.broadcast(f"createworkspacev2>>{n},{n}")
                self.st["active"] = n
                self.broadcast(f"workspace>>{n}")
                self.broadcast(f"workspacev2>>{n},{n}")
                if old not in kept:
                    self.broadcast(f"destroyworkspace>>{old}")
                    self.broadcast(f"destroyworkspacev2>>{old},{old}")
                self.broadcast(f"focusedmon>>{self.st['monitor']['name']},{n}")

    def broadcast(self, line):
        with self.lock:
            for c in list(self.listeners):
                try:
                    c.sendall((line + "\n").encode())
                except OSError:
                    self.listeners.remove(c)

    def serve_requests(self, srv):
        while True:
            conn, _ = srv.accept()
            with conn:
                conn.settimeout(2)  # a client that connects and says nothing must not stall every later request
                try:
                    req = conn.recv(65536).decode(errors="replace").strip()
                except OSError:
                    continue
                self.log("hypr-requests.log", req)
                try:
                    reply = self.answer(req)
                except Exception as e:  # a test fake: answer, never crash the shell under test
                    reply = f"error {e}"
                conn.sendall(reply.encode())

    def serve_events(self, srv):
        while True:
            conn, _ = srv.accept()
            with self.lock:
                self.listeners.append(conn)

    def serve_control(self, srv):
        while True:
            conn, _ = srv.accept()
            with conn:
                for line in conn.makefile().read().splitlines():
                    if line:
                        self.broadcast(line)
                conn.sendall(b"ok\n")

    def start(self):
        socks = []
        for path, fn in ((self.base / ".socket.sock", self.serve_requests), (self.base / ".socket2.sock", self.serve_events),
                         (self.run / "hypr-control.sock", self.serve_control)):
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.bind(str(path))
            s.listen(16)
            socks.append(s)
            threading.Thread(target=fn, args=(s,), daemon=True).start()
        print(SIG, flush=True)
        threading.Event().wait()


def main():
    if sys.argv[1] == "serve":
        if not os.environ.get("SLEEPYSHELL_SANDBOX"):
            sys.exit("fakehypr: only inside a test sandbox")
        state = default_state()
        if len(sys.argv) > 3:
            state.update(json.loads(Path(sys.argv[3]).read_text()))
        Fake(sys.argv[2], state).start()
    elif sys.argv[1] == "event":
        c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        c.connect(str(Path(sys.argv[2]) / "hypr-control.sock"))
        c.sendall(("\n".join(sys.argv[3:]) + "\n").encode())
        c.shutdown(socket.SHUT_WR)
        sys.exit(0 if c.makefile().readline().strip() == "ok" else 1)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
