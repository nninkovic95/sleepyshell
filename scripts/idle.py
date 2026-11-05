#!/usr/bin/env python3
"""Writes hypridle's config from sleepyshell's Idle settings, then restarts hypridle if it runs.

  idle.py             rewrite the file (see "Which file") and restart hypridle.service; only the shell's own file
                      (its first line is HEADER): a missing file is refused with exit 4 (not set up), a file the user
                      wrote with exit 3; nothing is written then
  idle.py --replace   the same, but a file the user wrote is replaced after a dated backup beside it
                      (hypridle.conf.bak-YYYYMMDD-HHMMSS); the Idle tab passes it after the user said yes
  idle.py --create    write the file only when it does not exist yet (its folder too), exit 5 when it does;
                      Sleepysettings' Create passes it after showing the path and the content and asking
  idle.py --background  for the bar on a power-source change: rewrites only the shell's own file; a missing file
                      or one the user wrote is left alone (exit 0) and nothing is restarted
  idle.py --owned     print {"path", "exists", "owned"} as JSON: whether a plain run would write the file
  idle.py --find      print, as JSON, the file hypridle reads ("active"), how that was found ("how": running,
                      hyprland, service or default), every launch found ("launches"), whether they disagree
                      ("conflict"), whether the setting follows hypridle ("auto"), and the file a run would write
                      ("path") with "exists" and "owned"
  idle.py --print     print the config instead
  idle.py --path      print the file a run would write
  --expect PATH       with a writing run: write nothing (exit 6) unless the file it would write is PATH, the one
                      the user was shown and confirmed
  --expect-target T   the same for the file PATH leads to (a symlink's target, as --owned and --find print it)

Only a file the user may safely own is written. The folder that holds its name and the folder that holds the file
(a symlink's target) must both lie inside the home or config folder (links resolved; an empty or relative
XDG_CONFIG_HOME counts as unset), belong to the user, and be writable by no one else (group write only for the
user's own group); the file and the link, when they exist, must belong to the user. Anything else is refused with
exit 7; --create checks the place before it makes a folder. All checks and the write happen on one resolved
file while the lock is held. The backup and the temporary file are made beside the real file, never through a name
that already exists. The lock is $XDG_RUNTIME_DIR/sleepyshell-hypridle.lock, else a per-user name in the temporary
folder, opened without following links; a lock that cannot be opened or is not the user's stops the run (exit 8).
A settings file that exists but does not parse stops every run that would write or print the file (exit 9; a
notification says why, except for --print): it would be written from the defaults. --find, --owned and --path
still answer, as if the file named no path.

Which file: `pathHypridle` of sleepysettings.toml when it names one (the Config tab's Change location...); empty,
or the old usual place ~/.config/hypr/hypridle.conf, means "the file hypridle reads". That is the -c / --config
of the running hypridle, else of a launch in hyprland.lua or the files it requires (hyprconf.py discover, the
same reading the keybinds use), else of hypridle.service's ExecStart, else $XDG_CONFIG_HOME/hypr/hypridle.conf,
which hypridle reads when started without -c. A file elsewhere is read by hypridle only when it is started
with -c and that path; the shell never changes how hypridle is started.
  idle.py --battery   use the on-battery set (idleBat*); --ac the plugged-in set (idle*);
                      without either the power source is read from /sys/class/power_supply
                      (a machine with a battery that no mains supply powers: battery; a desktop: plugged in)

Settings (sleepysettings.toml beside this folder, read with tomllib: one [section] per settings tab, so the keys are
collected from every section; settings.json beside it is read instead while the shell has not migrated it yet;
defaults when the file or a key is missing): idleDim and
idleDimMin (sleepyshell darkens the screens), idleLock and idleLockMin (the lock screen),
idleSuspend and idleSuspendMin, lockBeforeSleep; the on-battery set is idleBatDim, idleBatDimMin,
idleBatLock, idleBatLockMin, idleBatSuspend, idleBatSuspendMin (Idle tab, shorter by default).
Python standard library only. For tests: SLEEPYSHELL_SETTINGS (settings file: .toml, or .json by its suffix),
SLEEPYSHELL_POWER_SUPPLY (a stand-in for /sys/class/power_supply), SLEEPYSHELL_HYPRIDLE_PROC (for /proc) and
SLEEPYSHELL_HYPRIDLE_SERVICE (the unit's argv as one line; "none" for no unit) in place of systemctl, and
SLEEPYSHELL_HYPRIDLE_UNIT (the unit restarted after a write, hypridle.service by default).

No dpms step: under Hyprland's Lua config `hl.dsp.dpms("on")` toggled the display instead of
turning it on, and the table form did nothing, so nothing here touches dpms.
"""
import fcntl
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import tomllib
from pathlib import Path

SHELL_DIR = Path(__file__).resolve().parent.parent
SETTINGS = Path(os.environ.get("SLEEPYSHELL_SETTINGS", SHELL_DIR / "sleepysettings.toml"))
POWER_SUPPLY = Path(os.environ.get("SLEEPYSHELL_POWER_SUPPLY", "/sys/class/power_supply"))
CONF = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "hypr" / "hypridle.conf"
# the first line of every file this script writes: how it tells its own file from one the user wrote
HEADER = "# Written by sleepyshell's scripts/idle.py from the Idle settings; changes here are"
EXIT_FOREIGN = 3
EXIT_MISSING = 4
EXIT_EXISTS = 5
EXIT_UNEXPECTED = 6
EXIT_UNSAFE = 7
EXIT_LOCK = 8
EXIT_BROKEN = 9
# the setting's default before it followed hypridle: a stored copy of it means "follow hypridle" too
OLD_DEFAULT = "~/.config/hypr/hypridle.conf"
PROC = Path(os.environ.get("SLEEPYSHELL_HYPRIDLE_PROC", "/proc"))
# the unit restarted after a write (tests point it at a stand-in unit)
UNIT = os.environ.get("SLEEPYSHELL_HYPRIDLE_UNIT", "hypridle.service")

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


class SettingsBroken(Exception):
    """The settings file exists but does not parse: a run would use the defaults, so nothing is written."""


def read_settings():
    """Every key of the settings file as one flat dict ({} when it is missing, so the defaults apply; SettingsBroken
    when it exists but does not parse or cannot be read: hypridle.conf is never written from the defaults then).
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
        except FileNotFoundError:
            continue
        except (OSError, ValueError) as exc:
            raise SettingsBroken(str(exc)) from None
    return {}


def broken_line(why):
    """ " on line N" from a parser message that names one, else "" """
    m = re.search(r"line (\d+)", why)
    return f" on line {m.group(1)}" if m else ""


def refuse_broken(why, tell):
    """Say why nothing was written; `tell`: also as a notification (a run from the bar or the window never gets here,
    they check the file first, so this is a run started some other way)."""
    text = (f"hypridle.conf wasn't changed: your settings file has a mistake{broken_line(why)}, and the default "
            "settings would have been used instead. Fix the file, then try again.")
    print(f"not written: {SETTINGS} does not parse ({why})", file=sys.stderr)
    if tell and shutil.which("notify-send"):
        subprocess.run(["notify-send", "-a", "Sleepy Shell", "Your settings file has a mistake", text],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10, check=False)
    return EXIT_BROKEN


def expand(p):
    p = p.strip()
    p = str(Path.home()) + p[1:] if p == "~" or p.startswith("~/") else p
    # a relative -c path is taken from the home folder, where Hyprland and systemd start programs
    return Path(p) if os.path.isabs(p) else Path.home() / p


def setting():
    """The explicit file of `pathHypridle`, or None when the setting follows hypridle (also while the settings file
    does not parse: --find and --owned still answer, and every run that writes refuses before it gets here)."""
    try:
        p = read_settings().get("pathHypridle")
    except SettingsBroken:
        return None
    if not isinstance(p, str) or not p.strip() or expand(p) == expand(OLD_DEFAULT):
        return None
    return expand(p)


def config_arg(argv):
    """The -c / --config path of a hypridle argv, or None."""
    for i, a in enumerate(argv):
        if a in ("-c", "--config") and i + 1 < len(argv):
            return argv[i + 1]
        if a.startswith("--config="):
            return a.split("=", 1)[1]
    return None


def hypridle_argv(words):
    """The part of a command line from the hypridle program on, or None when it does not run hypridle."""
    for i, w in enumerate(words):
        if os.path.basename(w) == "hypridle":
            return words[i:]
    return None


def running():
    out = []
    try:
        entries = [d for d in PROC.iterdir() if d.name.isdigit()]
    except OSError:
        return out
    uid = os.getuid()
    for d in entries:
        try:
            # only this user's processes: another user's hypridle must never choose the file written here (a process
            # that is not dumpable shows as root's and is skipped too, which errs on the safe side)
            if d.stat().st_uid != uid or (d / "comm").read_text().strip() != "hypridle":
                continue
            argv = [a for a in (d / "cmdline").read_bytes().decode(errors="replace").split("\0") if a]
        except OSError:
            continue
        if argv:
            out.append({"how": "running", "where": f"the running hypridle (process {d.name})", "config": config_arg(argv)})
    return out


def hyprland():
    """hypridle launches in hyprland.lua and the files it requires (hl.exec_cmd, also inside hl.on)."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import hyprconf
        d = hyprconf.discover()
    except Exception:
        return []
    out = []
    for e in d.get("execs", []):
        try:
            argv = hypridle_argv(shlex.split(e.get("command", "")))
        except ValueError:
            continue
        if argv:
            out.append({"how": "hyprland", "where": f"{e.get('file')}, line {e.get('line')}", "config": config_arg(argv)})
    return out


def service():
    """hypridle.service when systemd knows it and it is enabled or running."""
    fake = os.environ.get("SLEEPYSHELL_HYPRIDLE_SERVICE")
    if fake is not None:
        if fake == "none":
            return []
        return [{"how": "service", "where": "hypridle.service", "config": config_arg(shlex.split(fake))}]
    if not shutil.which("systemctl"):
        return []
    try:
        res = subprocess.run(["systemctl", "--user", "show", "-p", "LoadState", "-p", "UnitFileState", "-p", "ActiveState",
                              "-p", "ExecStart", "hypridle.service"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return []
    props = dict(line.split("=", 1) for line in res.stdout.splitlines() if "=" in line)
    if props.get("LoadState") != "loaded":
        return []
    if props.get("UnitFileState") not in ("enabled", "enabled-runtime", "static") and props.get("ActiveState") != "active":
        return []
    m = props.get("ExecStart", "")
    argv_text = m.split("argv[]=", 1)[1].split(" ;", 1)[0] if "argv[]=" in m else ""
    try:
        argv = shlex.split(argv_text)
    except ValueError:
        argv = []
    return [{"how": "service", "where": "hypridle.service", "config": config_arg(argv)}]


def find():
    """The file hypridle reads, and how that is known."""
    procs, hypr, units = running(), hyprland(), service()
    launches = procs + hypr + units
    def path_of(l):
        return str(expand(l["config"])) if l["config"] else str(CONF)
    # what runs now wins; else the launch Hyprland makes at start, else the unit
    first = (procs or hypr or units or [None])[0]
    active = path_of(first) if first else str(CONF)
    started = {path_of(l) for l in hypr + units}
    return {
        "active": active,
        "how": first["how"] if first else "default",
        "launches": [dict(l, path=path_of(l)) for l in launches],
        "conflict": len(started) > 1 or (bool(procs) and bool(started) and active not in started),
    }


def conf_path():
    """The file to write: the setting's own file, else the one hypridle reads."""
    return setting() or Path(find()["active"])


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
    # quoted: the repository may be cloned into a folder whose name has a space or a quote
    lock = f"qs -n -p {shlex.quote(str(SHELL_DIR / 'sleepylock.qml'))}"
    # the shell's own launcher (services/SleepylockLauncher.qml) answers the same Lock signal: whichever takes
    # the file first starts the lock, the other exits at once (qs -n alone loses when both start together).
    # The file lives only in the user's own runtime folder: in a shared one such as /tmp another user could hold it
    # and keep the lock from ever starting. Without that folder the lock starts unguarded; it never refuses.
    # Only the ${...} form of the variable: hypridle's config reads a bare $name as one of its own variables.
    if shutil.which("flock"):
        lock = ('if [ -O "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR}" ]; then '
                f'flock -n -E 75 "${{XDG_RUNTIME_DIR}}/sleepylock.lock" {lock}; else {lock}; fi')
    # hypridle run by systemd (hypridle.service) runs lock_cmd inside the unit's cgroup, and the restart after a change
    # of power source (below, from the bar's PowerPolicy) stops everything in it: the lock screen died and left the
    # session locked with nothing to unlock it. The lock gets a scope of its own first. INVOCATION_ID is set only inside
    # a systemd unit; a scope that cannot be made (the trial run fails) leaves the lock to start as before, never not at all.
    if shutil.which("systemd-run"):
        scope = "systemd-run --user --scope --quiet --collect --"
        lock = (f'if [ -n "${{INVOCATION_ID:-}}" ] && {scope} true >/dev/null 2>&1; then '
                f'exec {scope} sh -c {shlex.quote(lock)}; fi; {lock}')
    out = [
        HEADER,
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


def state(conf):
    """"missing", "own" (this script wrote it: HEADER first) or "user" (anything else, an empty or unreadable file too)."""
    try:
        with open(conf, encoding="utf-8", errors="replace") as f:
            first = f.readline().rstrip("\n")
    except FileNotFoundError:
        return "missing"
    except OSError:
        return "user"
    return "own" if first == HEADER else "user"


def roots():
    """The folders a file may be written in, links resolved: the home folder and the config folder (an empty or
    relative XDG_CONFIG_HOME counts as unset)."""
    xdg = os.environ.get("XDG_CONFIG_HOME") or ""
    cfg = Path(xdg) if os.path.isabs(xdg) else Path.home() / ".config"
    return [Path(os.path.realpath(Path.home())), Path(os.path.realpath(cfg))]


def inside(real):
    return any(real == r or r in real.parents for r in roots())


def private_group(gid):
    """True for the user's own group: named like the user, the user's primary group, no other members."""
    try:
        import grp
        import pwd
        g, me = grp.getgrgid(gid), pwd.getpwuid(os.getuid())
    except (ImportError, KeyError):
        return False
    return gid == me.pw_gid and g.gr_name == me.pw_name and all(m == me.pw_name for m in g.gr_mem)


def folder_problem(folder):
    """Why nothing may be written in this existing, resolved folder, or ""."""
    try:
        st = folder.stat()
    except OSError:
        return f"its folder {folder} cannot be read"
    if not inside(folder):
        return f"{folder} is outside the home and config folders"
    if st.st_uid != os.getuid():
        return f"its folder {folder} belongs to someone else"
    # group write is fine only for the user's own group (a umask of 002)
    if st.st_mode & stat.S_IWOTH or (st.st_mode & stat.S_IWGRP and not private_group(st.st_gid)):
        return f"others can write its folder {folder}"
    return ""


def resolve_target(conf):
    """(target, why): the file really written (a symlink's target) and why it must not be, or ""."""
    target = Path(os.path.realpath(conf))
    # the folder that holds the name and the folder that holds the file: a link in a folder others can write could
    # be swapped, and the backup and the temporary file are made beside the target
    for folder in (Path(os.path.realpath(conf.parent)), target.parent):
        why = folder_problem(folder)
        if why:
            return target, why
    for f in (conf, target):
        try:
            if f.lstat().st_uid != os.getuid():
                return target, f"{f} belongs to someone else"
        except FileNotFoundError:
            pass
    return target, ""


def create_problem(conf):
    """Why --create must not make the file or its folder here, or "": checked before any folder is made."""
    real = Path(os.path.realpath(conf.parent))  # the part that exists resolved, the rest as written
    if not inside(real):
        return f"{conf} is outside the home and config folders"
    existing = real
    while not existing.exists():
        existing = existing.parent
    return folder_problem(existing)


def backup(target):
    """Copy the file to <file>.bak-YYYYMMDD-HHMMSS beside it (as hyprconf.py does), never through a name that is
    already there (a link included), and return that path."""
    stamp = time.strftime("%Y%m%d-%H%M%S")
    n = 0
    while True:
        dest = target.with_name(f"{target.name}.bak-{stamp}" + (f"-{n}" if n else ""))
        try:
            fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        except FileExistsError:
            n += 1
            continue
        with os.fdopen(fd, "wb") as out, open(target, "rb") as src:
            shutil.copyfileobj(src, out)
        shutil.copymode(target, dest)
        return dest


def write_through(target, text):
    """Replace the file whole and atomically: a temporary file beside it, then a rename over it."""
    fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=".hypridle-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.chmod(tmp, 0o644)
        os.replace(tmp, target)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def lock_path():
    run = os.environ.get("XDG_RUNTIME_DIR") or ""
    if os.path.isabs(run) and os.path.isdir(run):
        return Path(run) / "sleepyshell-hypridle.lock"
    # no runtime folder: a per-user name in the temporary folder, never beside the config file
    return Path(tempfile.gettempdir()) / f"sleepyshell-hypridle-{os.getuid()}.lock"


def flag_value(argv, name):
    if name in argv:
        i = argv.index(name)
        return argv[i + 1] if i + 1 < len(argv) else ""
    return None


def main(argv):
    if "-h" in argv or "--help" in argv:
        print(__doc__.strip())
        return 0
    if "--path" in argv:
        # for tests and the curious: the file a run would write
        print(conf_path())
        return 0
    if "--owned" in argv:
        conf = conf_path()
        print(json.dumps({"path": str(conf), "target": os.path.realpath(conf), "exists": conf.exists(),
                          "owned": state(conf) == "own"}))
        return 0
    if "--find" in argv:
        found = find()
        explicit = setting()
        conf = explicit or Path(found["active"])
        print(json.dumps(dict(found, auto=explicit is None, path=str(conf), target=os.path.realpath(conf),
                              exists=conf.exists(), owned=state(conf) == "own")))
        return 0
    battery = True if "--battery" in argv else False if "--ac" in argv else on_battery()
    try:
        text = config(settings(battery))
    except SettingsBroken as exc:
        return refuse_broken(str(exc), tell="--print" not in argv)
    if "--print" in argv:
        print(text)
        return 0
    conf = conf_path()
    want, want_target = flag_value(argv, "--expect"), flag_value(argv, "--expect-target")
    if want is not None and (want == "" or expand(want) != conf):
        print(f"not written: the file to write is now {conf}, not the one confirmed ({want})")
        return EXIT_UNEXPECTED
    create = "--create" in argv
    if create:
        # nothing is made outside the home and config folders or in a folder others can write, not even the folder
        why = create_problem(conf)
        if why:
            print(f"not written: {why}")
            return EXIT_UNSAFE
        conf.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    elif not conf.exists():
        # never made in the background or by Apply: Create in Sleepysettings shows it first and asks
        print(f"not set up: {conf} does not exist; Create in Sleepysettings makes it")
        return 0 if "--background" in argv else EXIT_MISSING
    # one run at a time, and the file replaced whole: runs started together (the charger flapping)
    # must not leave a half-written config for hypridle to read
    try:
        fd = os.open(lock_path(), os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    except OSError as exc:
        print(f"not written: the lock {lock_path()} cannot be opened ({exc.strerror})")
        return EXIT_LOCK
    with os.fdopen(fd, "w") as lock:
        if os.fstat(lock.fileno()).st_uid != os.getuid():
            print(f"not written: the lock {lock_path()} belongs to someone else")
            return EXIT_LOCK
        fcntl.flock(lock, fcntl.LOCK_EX)
        # everything from here on works on one resolved file, checked while the lock is held
        target, why = resolve_target(conf)
        if why:
            print(f"not written: {why}")
            return EXIT_UNSAFE
        if want_target is not None and (want_target == "" or Path(os.path.realpath(expand(want_target))) != target):
            print(f"not written: {conf} now leads to {target}, not the file confirmed ({want_target})")
            return EXIT_UNEXPECTED
        saved = None
        now = state(target)
        if create and now != "missing":
            print(f"not written: {target} exists already")
            return EXIT_EXISTS
        if now == "missing" and not create:
            print(f"not set up: {target} does not exist; Create in Sleepysettings makes it")
            return 0 if "--background" in argv else EXIT_MISSING
        # never replace a file the user wrote without their yes (the Idle tab's Apply asks, then passes --replace)
        if now == "user":
            if "--background" in argv:
                print(f"left {target} alone: sleepyshell did not write it; the Idle tab's Apply asks before replacing it")
                return 0
            if "--replace" not in argv:
                print(f"not written: {target} was not written by sleepyshell; run with --replace to replace it after a backup")
                return EXIT_FOREIGN
            saved = backup(target)
        write_through(target, text)
        # restart only a running hypridle: enabling it is the user's choice
        if shutil.which("systemctl"):
            active = subprocess.run(["systemctl", "--user", "is-active", "--quiet", UNIT]).returncode == 0
            if active:
                subprocess.run(["systemctl", "--user", "restart", UNIT])
    print(f"wrote {target} ({'battery' if battery else 'plugged in'} set)" + (f"; the old file is {saved}" if saved else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
