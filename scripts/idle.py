#!/usr/bin/env python3
"""Writes hypridle's config from sleepyshell's Idle settings, then restarts hypridle if it runs.

  idle.py             write ~/.config/hypr/hypridle.conf and restart hypridle.service
  idle.py --print     print the config instead
  idle.py --path      print the file a run would write (`pathHypridle` of sleepysettings.toml, else the usual place)
  idle.py --battery   use the on-battery set (idleBat*); --ac the plugged-in set (idle*);
                      without either the power source is read from /sys/class/power_supply
                      (a machine with a battery that no mains supply powers: battery; a desktop: plugged in)

Settings (sleepysettings.toml beside this folder, read with tomllib: one [section] per settings tab, so the keys are
collected from every section; settings.json beside it is read instead while the shell has not migrated it yet;
defaults when the file or a key is missing): idleDim and
idleDimMin (sleepyshell darkens the screens), idleLock and idleLockMin (the lock screen),
idleSuspend and idleSuspendMin, lockBeforeSleep; the on-battery set is idleBatDim, idleBatDimMin,
idleBatLock, idleBatLockMin, idleBatSuspend, idleBatSuspendMin (Idle tab, shorter by default).
Python standard library only. For tests: SLEEPYSHELL_SETTINGS (settings file: .toml, or .json by its suffix) and
SLEEPYSHELL_POWER_SUPPLY (a stand-in for /sys/class/power_supply).

No dpms step: under Hyprland's Lua config `hl.dsp.dpms("on")` toggled the display instead of
turning it on, and the table form did nothing, so nothing here touches dpms.
"""
import fcntl
import json
import os
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

SHELL_DIR = Path(__file__).resolve().parent.parent
SETTINGS = Path(os.environ.get("SLEEPYSHELL_SETTINGS", SHELL_DIR / "sleepysettings.toml"))
POWER_SUPPLY = Path(os.environ.get("SLEEPYSHELL_POWER_SUPPLY", "/sys/class/power_supply"))
CONF = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "hypr" / "hypridle.conf"

DEFAULTS = {
    "idleDim": True, "idleDimMin": 5,
    "idleLock": True, "idleLockMin": 10,
    "idleSuspend": False, "idleSuspendMin": 30,
    "lockBeforeSleep": True,
}
# the on-battery twins of the idle steps, same defaults as Settings.qml's schema
BATTERY_DEFAULTS = {
    "idleBatDim": True, "idleBatDimMin": 2,
    "idleBatLock": True, "idleBatLockMin": 5,
    "idleBatSuspend": True, "idleBatSuspendMin": 15,
}


def on_battery():
    """True on a machine that has a system battery and no mains supply online."""
    has_battery = False
    status = ""
    try:
        entries = list(POWER_SUPPLY.iterdir())
    except OSError:
        return False
    for e in entries:
        try:
            kind = (e / "type").read_text().strip()
        except OSError:
            continue
        if kind == "Battery":
            # peripherals (a mouse, a headset) are scope "Device"; only the system's own battery counts
            try:
                if (e / "scope").read_text().strip() != "System":
                    continue
            except OSError:
                pass
            has_battery = True
            try:
                status = (e / "status").read_text().strip()
            except OSError:
                pass
        elif kind == "Mains":
            try:
                if (e / "online").read_text().strip() == "1":
                    return False
            except OSError:
                pass
    # a charger that shows up only as type "USB" (USB-C PD) is not Mains, so a battery that is
    # charging, full or held at its limit counts as plugged in too
    return has_battery and status not in ("Charging", "Full", "Not charging")


def read_settings():
    """Every key of the settings file as one flat dict ({} when it is missing or does not parse, so the defaults apply).
    sleepysettings.toml has one [section] per settings tab; a key counts wherever it sits. A path ending in .json is read as JSON
    (the shell's old file, which it renames to settings.json.bak after migrating it)."""
    paths = [SETTINGS]
    if SETTINGS.suffix == ".toml" and not SETTINGS.exists():
        paths.append(SETTINGS.with_name("settings.json"))   # the old file keeps its own name
    for p in paths:
        try:
            if p.suffix == ".json":
                d = json.loads(p.read_text())
                return d if isinstance(d, dict) else {}
            flat = {}
            for k, v in tomllib.loads(p.read_text()).items():
                if isinstance(v, dict):
                    flat.update(v)
                else:
                    flat[k] = v
            return flat
        except (OSError, ValueError):
            continue
    return {}


def conf_path():
    """The file to write: `pathHypridle` of sleepysettings.toml (the Config tab; ~ is the home folder), else the usual place."""
    p = read_settings().get("pathHypridle")
    if isinstance(p, str) and p.strip():
        p = p.strip()
        return Path(str(Path.home()) + p[1:] if p == "~" or p.startswith("~/") else p)
    return CONF


def settings(battery=False):
    d = read_settings()
    s = {k: d.get(k, v) for k, v in DEFAULTS.items()}
    if battery:
        # the battery set takes the place of the plugged-in one
        for step in ("Dim", "Lock", "Suspend"):
            s["idle" + step] = d.get("idleBat" + step, BATTERY_DEFAULTS["idleBat" + step])
            s["idle" + step + "Min"] = d.get("idleBat" + step + "Min", BATTERY_DEFAULTS["idleBat" + step + "Min"])
    return s


def event(name):
    # a sleepyshell custom event through Hyprland's socket (shell.qml handles "sleepyshell:...")
    return f"hyprctl dispatch 'hl.dsp.event(\"sleepyshell:{name}\")'"


def config(s):
    lock = f"qs -n -p {SHELL_DIR / 'sleepylock.qml'}"
    # the shell's own launcher (services/SleepylockLauncher.qml) answers the same Lock signal: whichever takes
    # the file first starts the lock, the other exits at once (qs -n alone loses when both start together)
    if shutil.which("flock"):
        lock = 'flock -n -E 75 "${XDG_RUNTIME_DIR:-/tmp}/sleepylock.lock" ' + lock
    out = [
        "# Written by sleepyshell's scripts/idle.py from the Idle settings; changes here are",
        "# overwritten. Edit them in the settings window (Idle tab) or sleepysettings.toml.",
        "",
        "general {",
        # `loginctl lock-session` and the before-sleep lock end up here; -n: one lock at a time
        f"    lock_cmd = {lock}",
    ]
    if s["lockBeforeSleep"]:
        out.append("    before_sleep_cmd = loginctl lock-session")
        # hold sleep until the lock is up, so the desktop never shows on wake (the lock draws black then)
        out.append("    inhibit_sleep = 3")
    out += ["}", ""]

    def listener(minutes, on_timeout, on_resume=None):
        out.append("listener {")
        out.append(f"    timeout = {int(minutes) * 60}")
        out.append(f"    on-timeout = {on_timeout}")
        if on_resume:
            out.append(f"    on-resume = {on_resume}")
        out.extend(["}", ""])

    if s["idleDim"]:
        listener(s["idleDimMin"], event("dim"), event("undim"))
    if s["idleLock"]:
        listener(s["idleLockMin"], "loginctl lock-session", event("undim"))
    if s["idleSuspend"]:
        listener(s["idleSuspendMin"], "systemctl suspend", event("undim"))
    return "\n".join(out)


def main(argv):
    if "-h" in argv or "--help" in argv:
        print(__doc__.strip())
        return 0
    if "--path" in argv:
        # for tests and the curious: the file a run would write
        print(conf_path())
        return 0
    battery = True if "--battery" in argv else False if "--ac" in argv else on_battery()
    text = config(settings(battery))
    if "--print" in argv:
        print(text)
        return 0
    conf = conf_path()
    conf.parent.mkdir(parents=True, exist_ok=True)
    # one run at a time, and the file replaced whole: runs started together (the charger flapping)
    # must not leave a half-written config for hypridle to read
    with open(conf.parent / ".hypridle.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        tmp = conf.with_name(conf.name + ".tmp")
        tmp.write_text(text)
        os.replace(tmp, conf)
        # restart only a running hypridle: enabling it is the user's choice
        if shutil.which("systemctl"):
            active = subprocess.run(["systemctl", "--user", "is-active", "--quiet", "hypridle.service"]).returncode == 0
            if active:
                subprocess.run(["systemctl", "--user", "restart", "hypridle.service"])
    print(f"wrote {conf} ({'battery' if battery else 'plugged in'} set)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
