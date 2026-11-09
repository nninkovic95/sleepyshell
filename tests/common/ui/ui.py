"""ui.py: what a whole-window test uses, inside a sandbox with the private desktop of session.sh running.

    from ui import Shell, check, done
    s = Shell.launch(tree, "sleepysettings.qml")      # a run copy's entry file, with the driver added
    s.click(text="Keybinds")                           # through the virtual pointer, at the item's place on screen
    s.wait(lambda: s.js("win.tab") == "keybinds")
    check(s.visible(text="Export…"), "the Export button shows")
    done()                                             # exit 1 if any check failed

Clicks and keys go through the test compositor's virtual devices (wlinput.py), so a hidden, covered or disabled
control does not answer, as for a user. The driver (driver.qml) reports where items are and runs read-only
expressions in the root's context.
"""
import json
import os
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path

RUN = Path(os.environ.get("UI_RUN") or os.environ["SLEEPYSHELL_SANDBOX"])
KIT = Path(os.environ["KIT"])
_fails = 0


def check(ok, what, detail=""):
    global _fails
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or detail == "" else f": {detail}"), flush=True)
    _fails += 0 if ok else 1
    return bool(ok)


def done():
    sys.exit(1 if _fails else 0)


def recording_gaps(rows):
    """What a frame recording (Shell.record_stop) missed: rows inside the motion (from the first change to the last)
    that saw other than exactly one change since the row before, which is the check that counts; also frame numbers
    skipped between rows (FrameAnimation numbers its own ticks, so a stalled render shows as a row with two changes, not
    as a skipped number), an empty recording, or one that saw no change at all. An empty list means it is complete."""
    if not rows:
        return ["nothing was recorded"]
    gaps = [f"frame {a[0]} -> {b[0]}" for a, b in zip(rows, rows[1:]) if b[0] - a[0] != 1]
    changed = [i for i in range(1, len(rows)) if rows[i][1] != rows[i - 1][1]]
    if not changed:
        return gaps + ["no change was recorded"]
    for i in range(changed[0], changed[-1] + 1):
        seen = rows[i][1] - rows[i - 1][1]
        if seen != 1:
            gaps.append(f"frame {rows[i][0]} saw {seen} changes")
    return gaps


def wait_until(fn, timeout=10.0, step=0.1):
    end = time.monotonic() + timeout
    while True:
        try:
            v = fn()
        except Exception:  # not there yet (an instance still loading, a file not written)
            v = None
        if v:
            return v
        if time.monotonic() > end:
            return v
        time.sleep(step)


def commands():
    """The calls the fakes and the stand-in Hyprland logged, one string per line."""
    p = RUN / "commands.log"
    return p.read_text().splitlines() if p.exists() else []


def hypr_event(*lines):
    subprocess.run([sys.executable, "-I", str(KIT / "common/ui/fakehypr.py"), "event", str(RUN), *lines], check=True)


def pam_stack(password):
    """A PAM stack in RUN/pam that accepts only `password` (pam_exec and a script; no account, no pam_faillock), and
    the run copy's lock pointed at it. Returns the folder."""
    d = RUN / "pam"
    d.mkdir(exist_ok=True)
    (d / "password").write_text(password)
    check = d / "check.sh"
    check.write_text('#!/bin/sh\n# test PAM: the typed password arrives on stdin; only the one in the file next to this script passes;\n'
                     '# every check is counted in calls (a test can tell that nothing reached PAM)\n'
                     'IFS= read -r -d "" typed || true\n'
                     'echo check >>"$(dirname "$0")/calls"\n'
                     '[ "$typed" = "$(cat "$(dirname "$0")/password")" ]\n')
    check.chmod(0o755)
    stack = f"auth required pam_exec.so expose_authtok quiet {check}\naccount required pam_permit.so\n"
    (d / "login").write_text(stack)
    return d


class Input:
    @staticmethod
    def send(*words):
        r = subprocess.run([sys.executable, "-I", str(KIT / "common/ui/wlinput.py"), "send", os.environ["UI_INPUT"], *map(str, words)],
                           capture_output=True, text=True, timeout=30)
        if r.stdout.strip() != "ok":
            raise RuntimeError(f"input {words}: {r.stdout.strip()} {r.stderr.strip()}")

    @classmethod
    def click(cls, x, y, button="left"):
        cls.send("click", round(x), round(y), button)

    @classmethod
    def move(cls, x, y):
        cls.send("move", round(x), round(y))

    @classmethod
    def type(cls, text):
        cls.send("type", text)

    @classmethod
    def key(cls, *names):
        cls.send("key", *names)


def sway_tree():
    return json.loads(subprocess.run(["swaymsg", "-t", "get_tree", "-r"], capture_output=True, text=True, check=True).stdout)


def floating_rects(pid):
    out = []

    def walk(n):
        if n.get("pid") == pid:
            out.append((n.get("name") or "", n["rect"]))
        for k in n.get("nodes", []) + n.get("floating_nodes", []):
            walk(k)
    walk(sway_tree())
    return out


class Shell:
    """One Quickshell instance of a run copy's entry file, with the driver."""

    def __init__(self, entry, proc, log):
        self.entry, self.proc, self.log = entry, proc, log

    @classmethod
    def launch(cls, tree, entry_name, env=None, name=None, timeout=30, pam=None):
        tree = Path(tree)
        if "sleepylock" in entry_name and not pam:
            # the account's own PAM counts failed tries (pam_faillock); a lock test only ever uses the test stack
            raise RuntimeError("a lock test must pass pam=pam_stack(...)")
        entry = tree / f"sleepytest-{Path(entry_name).stem}.qml"
        subprocess.run([sys.executable, "-I", str(KIT / "common/ui/prepare.py"), str(tree)] + (["--pam", str(pam)] if pam else []), check=True)
        subprocess.run([sys.executable, "-I", str(KIT / "common/ui/inject.py"), str(tree / entry_name), str(entry)], check=True)
        log = RUN / f"{name or Path(entry_name).stem}.log"
        e = dict(os.environ)
        e.update(env or {})
        proc = subprocess.Popen(["qs", "-p", str(entry)], stdout=open(log, "w"), stderr=subprocess.STDOUT, env=e)
        s = cls(entry, proc, log)
        ok = wait_until(lambda: s.loaded() is not None, timeout)
        if not ok or not s.loaded():
            s.stop()
            raise RuntimeError(f"{entry_name} did not load:\n" + "\n".join(s.errors()[:20]))
        if not wait_until(lambda: s.ipc("ping") == "pong", timeout):
            raise RuntimeError(f"{entry_name}: the driver does not answer")
        return s

    def loaded(self):
        t = self.log.read_text(errors="replace")
        if "Configuration Loaded" in t:
            return True
        if "Failed to load configuration" in t or self.proc.poll() is not None:
            return False
        return None

    def ipc(self, fn, *args):
        r = subprocess.run(["qs", "-p", str(self.entry), "ipc", "call", "sleepytest", fn, *map(str, args)],
                           capture_output=True, text=True, timeout=20)
        if r.returncode != 0:
            raise RuntimeError(f"driver call {fn} failed: {(r.stdout + r.stderr).strip()[:400]}")
        return r.stdout.strip()

    def call(self, target, fn, *args):
        """A function of the instance's own IPC target (as a script would call it), e.g. call("sleepysettings", "stage", k, v)."""
        r = subprocess.run(["qs", "-p", str(self.entry), "ipc", "call", target, fn, *map(str, args)], capture_output=True, text=True, timeout=20)
        return r.stdout.strip()

    def json_call(self, fn, *args):
        out = self.ipc(fn, *args)
        try:
            return json.loads(out or "null")
        except ValueError:
            raise RuntimeError(f"driver call {fn} answered {out[:300]!r}") from None

    def js(self, code):
        return self.json_call("js", code)

    def record_start(self, probe, target, prop):
        """Start the driver's frame recorder: `probe` (a JS expression) is kept every frame, with the frame number and
        the count of `prop` changes on `target` (a JS expression). The probe is wrapped in parentheses so it never
        starts with a bracket on the command line."""
        r = self.ipc("recordStart", f"({probe})", target, prop)
        if r != "ok":
            raise RuntimeError(f"frame recorder did not start: {r}")

    def record_stop(self):
        """Stop the recorder; its rows, each [frame, changes so far, probe value]."""
        return self.json_call("recordStop") or []

    def windows(self):
        return self.json_call("windows") or []

    def find(self, **spec):
        return self.json_call("find", json.dumps(spec)) or []

    def visible(self, **spec):
        return bool(self.find(**spec))

    def texts(self, win):
        return self.json_call("texts", win) or []

    def one(self, top=False, **spec):
        """The one visible item that matches; with top=True the topmost of several (a page with two alike fields)."""
        found = self.find(**spec)
        if top and found:
            return min(found, key=lambda e: (e["y"], e["x"]))
        if len(found) != 1:
            raise LookupError(f"{spec}: {len(found)} visible matches")
        return found[0]

    def origin(self, item):
        """Where the item's window sits on the test screen: a layer surface from its anchors and margins (the driver
        works it out), any other window from the compositor's tree."""
        if item["winKind"] in ("panel", "lock"):
            return item["winX"], item["winY"]
        rects = floating_rects(self.proc.pid)
        match = [r for n, r in rects if n == item["winTitle"]] or [r for _, r in rects]
        if not match:
            raise LookupError(f"window {item['winTitle']!r} is not on screen")
        return match[0]["x"], match[0]["y"]

    def centre(self, item):
        """Where to click an item on the test screen; an item off the screen's edge cannot be clicked by a user either."""
        ox, oy = self.origin(item)
        x, y = ox + item["x"] + item["w"] / 2, oy + item["y"] + item["h"] / 2
        sw, sh = int(os.environ.get("SLEEPYSHELL_TEST_W", "2560")), int(os.environ.get("SLEEPYSHELL_TEST_H", "1440"))
        if not (0 <= x < sw and 0 <= y < sh):
            raise LookupError(f"{item['type']} {item['text']!r} is off the {sw}x{sh} screen at {x:.0f},{y:.0f}")
        return ox + item["x"] + item["w"] / 2, oy + item["y"] + item["h"] / 2

    def reveal(self, tries=40, **spec):
        """Bring an item on screen as a user would: open the page's collapsed Advanced section if the item is in one,
        then scroll with the mouse wheel until it shows. Returns the visible match, or None."""
        hidden = self.find(all=True, **spec)
        if hidden and not self.find(**spec) and self.find(all=True, type="AdvancedSection", props={"expanded": False}):
            for header in self.find(type="CollapseHeader", props={"open": False}):
                if header["winTitle"] == hidden[0]["winTitle"]:
                    Input.click(*self.centre(header))
                    time.sleep(0.4)
        for _ in range(tries):
            seen = self.find(**spec)
            if seen:
                return seen[0]
            hidden = self.find(all=True, **spec)
            if not hidden:
                return None
            h = hidden[0]
            win = next((w for w in self.windows() if w["index"] == h["win"]), None)
            if not win:
                return None
            ox, oy = self.origin(h)
            Input.move(ox + win["width"] * 0.6, oy + win["height"] / 2)
            Input.send("scroll", 3 if h["y"] > win["height"] / 2 else -3)
            time.sleep(0.12)
        return None

    def settled(self, top=False, timeout=3.0, **spec):
        """The item once it has stopped moving (a bar or dialog that slides in): two looks 150 ms apart agree."""
        end = time.monotonic() + timeout
        last = None
        while True:
            item = self.one(top=top, **spec)
            pos = lambda e: (e["x"], e["y"], e.get("winX"), e.get("winY"))
            if last and pos(item) == pos(last):
                return item
            if time.monotonic() > end:
                return item
            last = item
            time.sleep(0.15)

    def click(self, button="left", settle=0.25, top=False, **spec):
        if not self.find(**spec):
            self.reveal(**spec)
        item = self.settled(top=top, **spec)
        Input.click(*self.centre(item), button)
        time.sleep(settle)
        return item

    # --- settings window helpers -------------------------------------------------------------------------------
    def row(self, key):
        """The visible row of a settings key."""
        return next(iter(self.find(props={"key": key})), None)

    def toggle(self, key):
        """Click the switch of a key's row, as a user does."""
        return self.click(type="Toggle", inside={"props": {"key": key}})

    def button(self, text, **spec):
        """Click the button with this text (a BarButton: its label alone would match twice)."""
        return self.click(type="BarButton", text=text, **spec)

    def dialog_button(self, text):
        """Click a button of the open question (the page's own buttons stay visible behind its dimmer)."""
        return self.click(type="BarButton", text=text, inside={"type": "ConfirmDialog"})

    def apply(self):
        return self.button("Apply")

    def tab(self, label, expect=True):
        """Open a tab from its sidebar entry (the entry once it stopped moving; the sidebar re-sorts after a search).
        expect=False: one click only, for a test that expects a question instead of the tab."""
        for _ in range(2 if expect else 1):
            entry = [e for e in self.find(text=label) if e["x"] < 200]
            if not entry:
                raise LookupError(f"no sidebar entry {label!r}")
            time.sleep(0.3)  # the sidebar slides back after a search; read the entry again once it stands
            entry = [e for e in self.find(text=label) if e["x"] < 200] or entry
            Input.click(*self.centre(entry[0]))
            if not expect:
                time.sleep(0.3)
                return True
            if self.wait(lambda: self.js("win.current.label") == label, 3):
                return True
        return False

    def dialog(self):
        """The open question of the settings window (ConfirmDialog): its title, the lines it shows (the exact line or
        file content of an ask-first prompt), and its buttons; None when none is open."""
        lines = [e["text"] for e in self.find(inside={"objectName": "dialogLine"}) if e["text"]]
        mark = self.find(objectName="dialogMark")
        if not mark and not lines:
            return None
        win = (mark or self.find(objectName="dialogLine"))[0]["win"]
        return {"lines": lines, "texts": self.texts(win)}

    def bar_icons(self):
        """The bar's visible icons (Glyph items in the islands' surface) by their widget: {name: vertical centre}. The
        name is the nearest objectName up the tree, else the type of the widget the icon sits in."""
        js = """(function () {
          const out = {};
          for (const e of sleepytestDriver.scan().items) {
            const o = e.obj;
            if (sleepytestDriver.typeName(o) !== "Glyph" || !o.visible || o.text === "" || e.win.info.type !== "Sleepybar") continue;
            let h = o.parent;
            while (h && !h.objectName && h.parent && !/^(Clipboard|PrivacyPill|Network|Notifications|Updates|Bluetooth)/.test(sleepytestDriver.typeName(h)))
              h = h.parent;
            const name = (h && (h.objectName || sleepytestDriver.typeName(h))) || "?";
            const p = o.mapToItem(null, 0, 0);
            out[name] = Math.round((p.y + o.height / 2) * 10) / 10;
          }
          return out;
        })()"""
        return self.js(js) or {}

    def stored(self, key):
        return self.js(f"Settings.stored({json.dumps(key)})")

    def staged(self):
        return self.js("Settings.pending") or {}

    def hover(self, **spec):
        Input.move(*self.centre(self.one(**spec)))

    def wait(self, fn, timeout=10.0):
        return wait_until(fn, timeout)

    def wait_visible(self, timeout=10.0, **spec):
        return wait_until(lambda: self.find(**spec), timeout)

    def wait_gone(self, timeout=10.0, **spec):
        return wait_until(lambda: not self.find(**spec), timeout)

    def errors(self):
        """QML errors and script exceptions in this instance's log."""
        bad = ("ERROR", "TypeError", "ReferenceError", "is not a type", "Cannot assign", "Unable to assign", "is not defined",
               "is not a function", "Cannot read property", "Binding loop")
        lines = self.log.read_text(errors="replace").splitlines() if self.log.exists() else []
        return [l for l in lines if any(b in l for b in bad)]

    def stop(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()


# --- screenshots -----------------------------------------------------------------------------------------------------

def shot(path, region=None):
    """grim of the test compositor's screen (or region (x, y, w, h)) into path."""
    cmd = ["grim"]
    if region:
        x, y, w, h = map(round, region)
        cmd += ["-g", f"{x},{y} {w}x{h}"]
    subprocess.run(cmd + [str(path)], check=True)
    return Path(path)


def read_png(path):
    """(width, height, rows of RGBA bytes) of an 8-bit RGB or RGBA PNG, as grim writes them."""
    data = Path(path).read_bytes()
    pos, idat, w = 8, b"", 0
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            if depth != 8 or ctype not in (2, 6):
                raise ValueError("only 8-bit RGB/RGBA PNGs")
            bpp = 4 if ctype == 6 else 3
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        f, line = raw[i], bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line) if bpp == 4 else bytes(v for px in range(w) for v in (*line[px * 3:px * 3 + 3], 255)))
        prev = line
    return w, h, rows


def write_png(path, w, h, rows):
    raw = b"".join(b"\0" + r for r in rows)
    chunk = lambda k, b: struct.pack(">I", len(b)) + k + b + struct.pack(">I", zlib.crc32(k + b) & 0xFFFFFFFF)
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def compare(actual, name, tolerance=0.002, channel=24):
    """Compare a screenshot with the reference tests/refs/NAME.png. A pixel differs when a channel is off by more than
    `channel`; the check passes when at most `tolerance` of the pixels differ. On a failure (or a missing reference)
    the actual image and a diff go to RUN/failed/, which run-ui.sh copies to tests/jobs/failed/<run>/. References are
    only ever written by `tests/run.sh --update-refs`."""
    ref = KIT / "refs" / f"{name}.png"
    keep = RUN / "failed"  # run-ui.sh copies it to tests/jobs/failed/ after the sandbox ends
    if os.environ.get("SLEEPYSHELL_UPDATE_REFS") == "1":
        keep.mkdir(parents=True, exist_ok=True)
        (keep / f"{name}.png").write_bytes(Path(actual).read_bytes())
        print(f"note: --update-refs: {name}.png kept as a candidate reference; nothing was compared", flush=True)
        return True, "reference candidate kept"
    if not ref.exists():
        keep.mkdir(parents=True, exist_ok=True)
        (keep / f"{name}.png").write_bytes(Path(actual).read_bytes())
        return False, f"no reference {ref.name}; actual kept in {keep}"
    aw, ah, arows = read_png(actual)
    rw, rh, rrows = read_png(ref)
    if (aw, ah) != (rw, rh):
        keep.mkdir(parents=True, exist_ok=True)
        (keep / f"{name}.png").write_bytes(Path(actual).read_bytes())
        return False, f"size {aw}x{ah}, reference {rw}x{rh}"
    bad, diff = 0, []
    for ra, rr in zip(arows, rrows):
        line = bytearray()
        for i in range(0, len(ra), 4):
            off = max(abs(ra[i + k] - rr[i + k]) for k in range(3)) > channel
            bad += off
            line += b"\xff\x00\x00\xff" if off else bytes((rr[i] // 4, rr[i + 1] // 4, rr[i + 2] // 4, 255))
        diff.append(bytes(line))
    share = bad / (aw * ah)
    if share > tolerance:
        keep.mkdir(parents=True, exist_ok=True)
        (keep / f"{name}.png").write_bytes(Path(actual).read_bytes())
        write_png(keep / f"{name}-diff.png", aw, ah, diff)
        return False, f"{share:.2%} of pixels differ (allowed {tolerance:.2%}); actual and diff in {keep}"
    return True, f"{share:.3%} differ"
