#!/usr/bin/env python3
"""Monitor controls over DDC/CI (brightness, contrast, input, colour preset), for sleepyshell.

  ddc.py list                    connected monitors with their DDC bus, as JSON
  ddc.py get BUS CODE            one VCP feature: {"current": n, "max": n}
  ddc.py set BUS CODE VALUE      set a VCP feature
  ddc.py caps BUS                the monitor's capabilities: model, features and allowed values
  ddc.py probe                   {"devices": any /dev/i2c-N exists, "adapters": {"N": adapter name}}, for the
                                 settings window's setup guide (read only, nothing is opened)

CODE is a VCP code in hex or decimal: 0x10 brightness, 0x12 contrast, 0x60 input source,
0x14 colour preset. Python standard library only: it speaks DDC/CI itself on /dev/i2c-N
(needs the i2c-dev module and access to the display buses, see CLAUDE.md), so no ddcutil.
"""
import fcntl
import json
import os
import re
import sys
import time

I2C_SLAVE = 0x0703
DDC_ADDR = 0x37
HOST = 0x51       # source address of the host in a DDC/CI message
DEST = 0x6E       # the monitor's write address (0x37 << 1), part of every checksum
REPLY_SRC = 0x50  # used for the reply checksum


def checksum(first, data):
    c = first
    for b in data:
        c ^= b
    return c


class Bus:
    def __init__(self, n):
        self.fd = os.open(f"/dev/i2c-{n}", os.O_RDWR)
        fcntl.ioctl(self.fd, I2C_SLAVE, DDC_ADDR)

    def close(self):
        os.close(self.fd)

    def write(self, payload):
        msg = bytes([HOST, 0x80 | len(payload)]) + bytes(payload)
        os.write(self.fd, msg + bytes([checksum(DEST, msg)]))

    def read(self, size):
        data = os.read(self.fd, size)
        # [source 0x6E, 0x80 | length, payload..., checksum]
        if len(data) < 3 or data[0] != DEST:
            raise IOError("no reply")
        length = data[1] & 0x7F
        payload = data[2:2 + length]
        if len(payload) != length or checksum(REPLY_SRC, data[:2 + length]) != data[2 + length]:
            raise IOError("bad checksum")
        # a busy monitor answers with a null message (length 0); that is a retry, not a payload
        if not payload:
            raise IOError("null reply")
        return payload

    # the spec wants about 40 ms between a request and its reply, 50 ms after a set; a few
    # retries because monitors drop the odd message
    def get(self, code):
        for _ in range(3):
            try:
                self.write([0x01, code])
                time.sleep(0.05)
                p = self.read(12)
                if len(p) < 8 or p[0] != 0x02 or p[2] != code:
                    raise IOError("unexpected reply")
                if p[1] != 0:
                    raise IOError(f"feature 0x{code:02x} not supported")
                return {"max": p[4] << 8 | p[5], "current": p[6] << 8 | p[7]}
            except OSError as e:
                err = e
                time.sleep(0.05)
        raise err

    def set(self, code, value):
        if not 0 <= value <= 0xFFFF:
            raise ValueError("value out of range 0..65535")
        self.write([0x03, code, value >> 8 & 0xFF, value & 0xFF])
        time.sleep(0.06)

    def caps(self):
        text, offset = b"", 0
        while offset < 4096:
            for attempt in range(3):
                try:
                    self.write([0xF3, offset >> 8, offset & 0xFF])
                    time.sleep(0.05)
                    p = self.read(40)
                    if len(p) < 3 or p[0] != 0xE3:
                        raise IOError("unexpected reply")
                    break
                except OSError:
                    if attempt == 2:
                        raise
                    time.sleep(0.05)
            chunk = p[3:]
            if not chunk:
                break
            text += chunk
            offset += len(chunk)
        return text.rstrip(b"\x00").decode("ascii", "replace")


def monitors():
    """Connected DRM outputs that have a DDC bus, with the EDID's model name when it has one."""
    out = []
    base = "/sys/class/drm"
    for name in sorted(os.listdir(base)):
        d = f"{base}/{name}"
        try:
            if open(f"{d}/status").read().strip() != "connected" or not os.path.exists(f"{d}/ddc"):
                continue
        except OSError:
            continue
        bus = int(os.path.basename(os.path.realpath(f"{d}/ddc")).split("-")[1])
        model = ""
        try:
            edid = open(f"{d}/edid", "rb").read()
            for i in range(54, 126, 18):  # descriptor blocks; 0xFC is the monitor name
                if edid[i:i + 3] == b"\x00\x00\x00" and edid[i + 3] == 0xFC:
                    model = edid[i + 5:i + 18].split(b"\n")[0].decode("ascii", "replace").strip()
        except (OSError, IndexError):
            pass
        out.append({"output": name.split("-", 1)[1], "bus": bus, "model": model,
                    "access": os.access(f"/dev/i2c-{bus}", os.R_OK | os.W_OK)})
    return out


def probe():
    """Is the i2c-dev module loaded (any /dev/i2c-N) and what is each i2c bus called, from sysfs.
    The adapter name ("AMDGPU DM i2c hw bus 1") is what a udev rule matches to give the session access."""
    adapters = {}
    base = "/sys/bus/i2c/devices"
    try:
        for name in os.listdir(base):
            if re.fullmatch(r"i2c-\d+", name):
                try:
                    adapters[name[4:]] = open(f"{base}/{name}/name").read().strip()
                except OSError:
                    pass
    except OSError:
        pass
    try:
        devices = any(re.fullmatch(r"i2c-\d+", n) for n in os.listdir("/dev"))
    except OSError:
        devices = False
    return {"devices": devices, "adapters": adapters}


def parse_caps(text):
    """The vcp(...) part of a capabilities string as {code: [allowed values]} (empty: continuous)."""
    # the balanced vcp(...) group only: a greedy match ran on into mccs_ver(...) and asset_eep(...),
    # whose letters read as feature codes
    body, start = "", text.find("vcp(")
    if start >= 0:
        depth = 0
        for i in range(start + 3, len(text)):
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
                if depth == 0:
                    body = text[start + 4:i]
                    break
        else:
            body = text[start + 4:]
    feats = {}
    for code, values in re.findall(r"\b([0-9A-Fa-f]{2})\b(?:\(([0-9A-Fa-f ]*)\))?", body):
        feats[int(code, 16)] = [int(v, 16) for v in values.split()] if values else []
    model = re.search(r"model\(([^)]*)\)", text)
    return {"model": model.group(1) if model else "", "features": feats}


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    cmd, args = argv[0], argv[1:]
    if cmd == "list":
        print(json.dumps(monitors()))
        return 0
    if cmd == "probe":
        print(json.dumps(probe()))
        return 0
    # bad arguments or a missing bus are reported as JSON like a failed transfer, and the command
    # is checked before the bus is opened
    if cmd not in ("get", "set", "caps"):
        print(f"ddc: unknown command {cmd}", file=sys.stderr)
        return 2
    bus = None
    try:
        bus = Bus(int(args[0]))
        if cmd == "get":
            print(json.dumps(bus.get(int(args[1], 0))))
        elif cmd == "set":
            bus.set(int(args[1], 0), int(args[2], 0))
        elif cmd == "caps":
            print(json.dumps(parse_caps(bus.caps())))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e)}))
        return 1
    finally:
        if bus:
            bus.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
