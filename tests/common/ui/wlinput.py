"""wlinput.py: a virtual pointer and keyboard on the test compositor, for clicks and typing with no real device.

    wlinput.py serve SOCKET     connect to $WAYLAND_DISPLAY (the private test compositor, never the session's),
                                create one virtual pointer and one virtual keyboard, take commands on SOCKET
    wlinput.py send SOCKET CMD  send one command, print the answer; exit 1 unless it is "ok"

Commands: move X Y | click X Y [left|right|middle] | press [button] | release [button] | scroll DY |
          key NAME [NAME...] (one chord, e.g. "key ctrl s") | type TEXT
The Wayland wire protocol is spoken directly (stdlib only): zwlr_virtual_pointer_v1 and zwp_virtual_keyboard_v1.
It refuses to start without SLEEPYSHELL_SANDBOX, so it can only ever reach a compositor inside a test sandbox.
"""
import os
import socket
import struct
import sys
import time

BUTTONS = {"left": 0x110, "right": 0x111, "middle": 0x112}
KEYMAP = """xkb_keymap {
    xkb_keycodes { include "evdev+aliases(qwerty)" };
    xkb_types { include "complete" };
    xkb_compat { include "complete" };
    xkb_symbols { include "pc+us+inet(evdev)" };
};
"""
# evdev key codes of a US layout; the second value says Shift is needed
KEYS = {
    "esc": 1, "escape": 1, "backspace": 14, "tab": 15, "enter": 28, "return": 28, "ctrl": 29, "shift": 42,
    "alt": 56, "space": 57, "super": 125, "up": 103, "left": 105, "right": 106, "down": 108, "home": 102,
    "end": 107, "pageup": 104, "pagedown": 109, "delete": 111, "f1": 59, "f2": 60, "f3": 61, "f4": 62, "f5": 63,
    "f6": 64, "f7": 65, "f8": 66, "f9": 67, "f10": 68, "f11": 87, "f12": 88,
}
CHARS = {}
for row, codes in (("1234567890-=", range(2, 14)), ("qwertyuiop[]", range(16, 28)),
                   ("asdfghjkl;'", range(30, 41)), ("zxcvbnm,./", range(44, 54))):
    for ch, code in zip(row, codes):
        CHARS[ch] = (code, False)
for plain, shifted in zip("1234567890-=[];',./`\\", "!@#$%^&*()_+{}:\"<>?~|"):
    if plain in CHARS:
        CHARS[shifted] = (CHARS[plain][0], True)
CHARS["`"], CHARS["~"], CHARS["\\"], CHARS["|"] = (41, False), (41, True), (43, False), (43, True)
for ch in "abcdefghijklmnopqrstuvwxyz":
    CHARS[ch.upper()] = (CHARS[ch][0], True)
CHARS[" "] = (57, False)


class Wayland:
    def __init__(self):
        path = os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ["WAYLAND_DISPLAY"])
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(path)
        self.next_id = 2
        self.buf = b""
        self.globals = {}
        self.mods = 0

    def new_id(self):
        i = self.next_id
        self.next_id += 1
        return i

    @staticmethod
    def string(v):
        b = v.encode() + b"\0"
        return struct.pack("<I", len(b)) + b + b"\0" * (-len(b) % 4)

    def send(self, obj, opcode, payload=b"", fds=()):
        msg = struct.pack("<II", obj, ((8 + len(payload)) << 16) | opcode) + payload
        if fds:
            socket.send_fds(self.s, [msg], list(fds))
        else:
            self.s.sendall(msg)

    def roundtrip(self):
        cb = self.new_id()
        self.send(1, 0, struct.pack("<I", cb))  # wl_display.sync
        while True:
            obj, op, data = self.read()
            if obj == cb and op == 0:
                return
            if obj == 1 and op == 0:  # wl_display.error
                oid, code = struct.unpack_from("<II", data)
                n = struct.unpack_from("<I", data, 8)[0]
                raise RuntimeError(f"wayland error on object {oid}, code {code}: {data[12:12 + n - 1].decode()}")
            if obj == self.registry and op == 0:  # wl_registry.global
                name, n = struct.unpack_from("<II", data)
                iface = data[8:8 + n - 1].decode()
                version = struct.unpack_from("<I", data, 8 + n + (-n % 4))[0]
                self.globals[iface] = (name, version)

    def read(self):
        while len(self.buf) < 8 or len(self.buf) < struct.unpack_from("<I", self.buf, 4)[0] >> 16:
            chunk = self.s.recv(65536)
            if not chunk:
                raise RuntimeError("compositor closed the connection")
            self.buf += chunk
        obj, word = struct.unpack_from("<II", self.buf)
        size = word >> 16
        data = self.buf[8:size]
        self.buf = self.buf[size:]
        return obj, word & 0xFFFF, data

    def bind(self, iface, version):
        name, have = self.globals[iface]
        oid = self.new_id()
        self.send(self.registry, 0, struct.pack("<I", name) + self.string(iface) + struct.pack("<II", min(version, have), oid))
        return oid

    def setup(self):
        self.registry = self.new_id()
        self.send(1, 1, struct.pack("<I", self.registry))  # wl_display.get_registry
        self.roundtrip()
        for need in ("wl_seat", "zwlr_virtual_pointer_manager_v1", "zwp_virtual_keyboard_manager_v1"):
            if need not in self.globals:
                raise RuntimeError(f"the compositor has no {need}")
        seat = self.bind("wl_seat", 1)
        pm = self.bind("zwlr_virtual_pointer_manager_v1", 1)
        km = self.bind("zwp_virtual_keyboard_manager_v1", 1)
        self.pointer = self.new_id()
        self.send(pm, 0, struct.pack("<II", seat, self.pointer))
        self.keyboard = self.new_id()
        self.send(km, 0, struct.pack("<II", seat, self.keyboard))
        keymap = KEYMAP.encode() + b"\0"
        fd = os.memfd_create("keymap")
        os.write(fd, keymap)
        self.send(self.keyboard, 0, struct.pack("<II", 1, len(keymap)), fds=[fd])  # xkb_v1
        os.close(fd)
        self.roundtrip()
        out = self.output_size()
        self.extent = out

    def output_size(self):
        w = int(os.environ.get("SLEEPYSHELL_TEST_W", "2560"))
        h = int(os.environ.get("SLEEPYSHELL_TEST_H", "1440"))
        return w, h

    def now(self):
        return int(time.monotonic() * 1000) & 0xFFFFFFFF

    def move(self, x, y):
        w, h = self.extent
        self.send(self.pointer, 1, struct.pack("<IIIII", self.now(), int(x), int(y), w, h))
        self.send(self.pointer, 4)  # frame

    def button(self, code, pressed):
        self.send(self.pointer, 2, struct.pack("<III", self.now(), code, 1 if pressed else 0))
        self.send(self.pointer, 4)

    def scroll(self, dy):
        self.send(self.pointer, 5, struct.pack("<I", 0))  # axis_source wheel
        self.send(self.pointer, 3, struct.pack("<IIi", self.now(), 0, int(dy * 256)))  # axis vertical, fixed
        self.send(self.pointer, 4)

    # xkb modifier masks of the keymap above; a virtual keyboard has to state them itself
    MODS = {42: 1, 29: 4, 56: 8, 125: 64}

    def key(self, code, pressed):
        self.send(self.keyboard, 1, struct.pack("<III", self.now(), code, 1 if pressed else 0))
        if code in self.MODS:
            self.mods = (self.mods | self.MODS[code]) if pressed else (self.mods & ~self.MODS[code])
            self.send(self.keyboard, 2, struct.pack("<IIII", self.mods, 0, 0, 0))

    def flush(self):
        self.roundtrip()


def run_command(wl, words):
    cmd, args = words[0], words[1:]
    if cmd == "move":
        wl.move(float(args[0]), float(args[1]))
    elif cmd == "click":
        b = BUTTONS[args[2] if len(args) > 2 else "left"]
        wl.move(float(args[0]), float(args[1]))
        wl.flush()
        time.sleep(0.05)
        wl.button(b, True)
        wl.flush()
        time.sleep(0.05)
        wl.button(b, False)
    elif cmd in ("press", "release"):
        wl.button(BUTTONS[args[0] if args else "left"], cmd == "press")
    elif cmd == "scroll":
        wl.scroll(float(args[0]))
    elif cmd == "key":
        codes = [KEYS.get(a.lower()) or CHARS[a.lower()][0] for a in args]
        for c in codes:
            wl.key(c, True)
        wl.flush()
        for c in reversed(codes):
            wl.key(c, False)
    elif cmd == "type":
        for ch in " ".join(args):
            code, shift = CHARS[ch]
            if shift:
                wl.key(KEYS["shift"], True)
            wl.key(code, True)
            wl.key(code, False)
            if shift:
                wl.key(KEYS["shift"], False)
            wl.flush()
            time.sleep(0.01)
    else:
        raise ValueError(f"unknown command {cmd}")
    wl.flush()


def serve(path):
    if not os.environ.get("SLEEPYSHELL_SANDBOX"):
        sys.exit("wlinput: only inside a test sandbox")
    wl = Wayland()
    wl.setup()
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(path)
    srv.listen(4)
    print("ready", flush=True)
    while True:
        conn, _ = srv.accept()
        with conn:
            line = conn.makefile().readline().rstrip("\r\n")  # typed text may end in a space
            try:
                run_command(wl, line.split(" "))
                conn.sendall(b"ok\n")
            except Exception as e:  # report to the caller, keep serving
                conn.sendall(f"error {e}\n".encode())


def send(path, words):
    c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    c.connect(path)
    c.sendall((" ".join(words) + "\n").encode())
    answer = c.makefile().readline().strip()
    print(answer)
    return answer == "ok"


if __name__ == "__main__":
    if sys.argv[1] == "serve":
        serve(sys.argv[2])
    elif sys.argv[1] == "send":
        sys.exit(0 if send(sys.argv[2], sys.argv[3:]) else 1)
    else:
        sys.exit(__doc__)
