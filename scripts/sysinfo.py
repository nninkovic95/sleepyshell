#!/usr/bin/env python3
"""System information for sleepyshell's settings window (System tab), printed as one JSON object.

Python standard library only. Reads /etc/os-release, /proc, /sys and os.uname; asks hyprctl and qs
for their versions and lspci for GPU names when they are there. No network details (addresses,
Wi-Fi names) on purpose: the tab may end up in a screenshot.
"""
import json
import os
import pwd
import re
import shutil
import subprocess


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def run(cmd):
    if not shutil.which(cmd[0]):
        return ""
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=3).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def os_name():
    fields = dict(re.findall(r'^(\w+)="?([^"\n]*)"?$', read("/etc/os-release"), re.M))
    return fields.get("PRETTY_NAME") or fields.get("NAME") or "Linux"


def host():
    parts = [read(f"/sys/class/dmi/id/{k}") for k in ("board_vendor", "board_name")]
    name = " ".join(p for p in parts if p and "To be filled" not in p)
    return name or read("/sys/class/dmi/id/product_name")


def cpu():
    info = read("/proc/cpuinfo")
    m = re.search(r"^model name\s*:\s*(.+)$", info, re.M)
    model = re.sub(r"\s+", " ", m.group(1)) if m else os.uname().machine
    threads = os.cpu_count() or 0
    mhz = read("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")
    ghz = f"{int(mhz) / 1e6:.2f} GHz" if mhz.isdigit() else ""
    return {"model": model, "threads": threads, "maxClock": ghz}


def gpus():
    out = run(["lspci", "-mm"])
    found = []
    for line in out.splitlines():
        f = re.findall(r'"([^"]*)"', line)
        # class, vendor, device, ...
        if len(f) >= 3 and re.search(r"VGA|3D|Display", f[0]):
            # "Advanced Micro Devices, Inc. [AMD/ATI]" -> "AMD"; otherwise the name without "Inc." etc.
            short = re.search(r"\[([^\]/]+)", f[1])
            vendor = short.group(1) if short else re.sub(r",? (Inc|Corporation|Corp)\.?", "", f[1]).strip()
            device = re.search(r"\[([^\]]+)\]", f[2])
            found.append(f"{vendor} {device.group(1) if device else f[2]}")
    if found:
        return found
    # without pciutils: the PCI ids of each DRM card
    for card in sorted(os.listdir("/sys/class/drm")) if os.path.isdir("/sys/class/drm") else []:
        if re.fullmatch(r"card\d+", card):
            v, d = read(f"/sys/class/drm/{card}/device/vendor"), read(f"/sys/class/drm/{card}/device/device")
            if v:
                found.append(f"PCI {v[2:]}:{d[2:]}")
    return found


def memory():
    m = dict(re.findall(r"^(\w+):\s+(\d+) kB", read("/proc/meminfo"), re.M))
    kib = lambda k: int(m.get(k, 0)) * 1024
    return {"total": kib("MemTotal"), "used": kib("MemTotal") - kib("MemAvailable"),
            "swapTotal": kib("SwapTotal"), "swapUsed": kib("SwapTotal") - kib("SwapFree")}


def disks():
    seen, out = set(), []
    for line in read("/proc/mounts").splitlines():
        dev, mnt, fs = line.split()[:3]
        if not dev.startswith("/dev/") or fs not in {"ext4", "btrfs", "xfs", "f2fs", "bcachefs", "zfs", "ntfs3", "exfat"}:
            continue
        mnt = mnt.replace("\\040", " ")
        try:
            st = os.statvfs(mnt)
        except OSError:
            continue
        key = (dev, st.f_blocks)  # btrfs subvolumes of one device count once
        if key in seen:
            continue
        seen.add(key)
        out.append({"mount": mnt, "fs": fs, "total": st.f_blocks * st.f_frsize,
                    "used": (st.f_blocks - st.f_bfree) * st.f_frsize})
    return sorted(out, key=lambda d: (d["mount"] != "/", d["mount"]))


def displays():
    try:
        mons = json.loads(run(["hyprctl", "monitors", "-j"]) or "[]")
    except ValueError:
        return []
    # the description ends in the monitor's serial number, which is left out: by Hyprland's own
    # serial field when it has one, else a trailing hex-looking token
    def label(m):
        desc = m.get("description") or m.get("name")
        serial = str(m.get("serial") or "").strip()
        if "serial" in m:  # trusted when present, so a model name that looks like hex stays whole
            return desc[:-len(serial)].rstrip() if serial and desc.endswith(serial) else desc
        return re.sub(r"\s+(0x)?[0-9A-Fa-f]{6,}$", "", desc)
    # the test kit's virtual monitors ("sleepytest…") are not the user's: left out, like in the Display tab
    mons = [m for m in mons if not str(m.get("name", "")).startswith("sleepytest")]
    return [f"{label(m)}: {m['width']}x{m['height']} @ {round(m['refreshRate'])} Hz" for m in mons]


def versions():
    try:
        hypr = json.loads(run(["hyprctl", "version", "-j"]) or "{}").get("version", "")
    except ValueError:
        hypr = ""
    qs = re.search(r"Quickshell (\S+)", run(["qs", "--version"]))
    return {"hyprland": hypr, "quickshell": qs.group(1) if qs else ""}


def main():
    u = os.uname()
    up = read("/proc/uptime").split()
    print(json.dumps({
        "os": os_name(),
        "host": host(),
        "kernel": u.release,
        "uptime": int(float(up[0])) if up else 0,
        "cpu": cpu(),
        "gpus": gpus(),
        "memory": memory(),
        "disks": disks(),
        "displays": displays(),
        # the login shell from the user database, not $SHELL of whatever started this
        "shell": os.path.basename(pwd.getpwuid(os.getuid()).pw_shell),
        **versions(),
    }))


if __name__ == "__main__":
    main()
