#!/usr/bin/env python3
"""The parts of install.sh that need more than bash: reading the user's config files and writing files safely.

  install.py plan [--theming]     what the installer would do with the user's files, as one JSON object (reads only)
  install.py write PATH --was SHA|none --backup-dir DIR
                                  write stdin to PATH (atomic; a symlink is written through to its target) only when
                                  PATH is still what the user was shown: SHA is the sha256 of its content then, "none"
                                  that it did not exist. An existing file is first copied into DIR (its path below DIR is
                                  its path below /). Prints {"ok", "path", "backup", "created", "message"}; exit 0 when ok,
                                  6 when PATH changed since it was shown (nothing written), 1 on any other refusal.
  install.py backup DIR PATH...   copy each PATH that exists into DIR the same way (for the files a theme run rewrites);
                                  prints {"ok", "backups": [{"path", "backup"}], "missing": [path]}
  install.py sha PATH             the sha256 of PATH's content, or "none" when it does not exist
  install.py notes PLAN           the sentences the final report gives for what plan found and left alone: programs the
                                  config starts that do the shell's jobs, keys that were already bound

`plan` reads (never writes): the Hyprland Lua config through scripts/hyprconf.py discover (whether the installer's module
is loaded, which of its keys are already bound, what the config already starts), the matugen config (whether it has a
template that writes the shell's colors.json, every output path a theme run would rewrite), and the shell's settings file
(the colours and keybinds paths). The module's text and the matugen lines are built here, so the installer shows exactly
what it writes. Paths: the shell is this file's parent's parent; HOME and XDG_CONFIG_HOME as the session has them.

Python standard library only.
"""
import hashlib
import json
import os
import shutil
import sys
import tempfile
import tomllib
from pathlib import Path

# hyprconf.py is loaded as a module for its header text; a --dry-run must leave no bytecode in the clone
sys.dont_write_bytecode = True

SHELL = Path(__file__).resolve().parent.parent
HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
HYPR = CONFIG / "hypr"
LINK = CONFIG / "quickshell" / "sleepyshell"
MODULE = HYPR / "modules" / "sleepyshell.lua"
MODULE_NAME = "modules.sleepyshell"
# theme.py reads matugen's config from this place, whatever XDG_CONFIG_HOME says
MATUGEN = HOME / ".config" / "matugen" / "config.toml"
MARK = "-- Sleepy Shell: written by its installer"
# the module's second line: the sha256 of everything after it, so an edit by hand is noticed
SUM = "-- sha256 of the rest: "
COLORS_DEFAULT = "~/.local/state/quickshell/colors.json"
BINDS_DEFAULT = "~/.config/hypr/modules/sleepybinds.lua"

# programs that do a job the shell does itself: two of them fight over it (only reported, never stopped or removed)
CONFLICTS = {
    "waybar": "another bar", "hyprpanel": "another bar", "nwg-panel": "another bar", "ags": "another shell",
    "eww": "another bar", "quickshell": "another Quickshell config", "swaync": "another notification daemon",
    "mako": "another notification daemon", "dunst": "another notification daemon", "fnott": "another notification daemon",
    "hyprpolkitagent": "another polkit agent", "polkit-gnome-authentication-agent-1": "another polkit agent",
    "lxpolkit": "another polkit agent", "polkit-kde-authentication-agent-1": "another polkit agent",
    "hyprpaper": "another wallpaper program", "swaybg": "another wallpaper program",
}

# the keys the module binds: (mods, key, the line, what it does); one that is already bound is left out
BINDS = [
    (["SUPER"], "ESCAPE", 'hl.bind("SUPER + ESCAPE", hl.dsp.event("sleepyshell:toggle:session"))', "the session menu"),
    ([], "Caps_Lock", 'hl.bind("Caps_Lock", hl.dsp.event("sleepyshell:capslock"), { non_consuming = true, ignore_mods = true, locked = true })',
     "the Caps Lock indicator (the key still reaches the app)"),
    (["SUPER"], "L", 'hl.bind("SUPER + L", hl.dsp.exec_cmd("qs -n -p ~/.config/quickshell/sleepyshell/sleepylock.qml"), { locked = true })',
     "the lock screen"),
]
# the Keybinds window's key lives in the Keybinds tab's own file, so the tab can change it later
KEYS_WINDOW = (["SUPER"], "slash", 'hl.bind("SUPER + slash", hl.dsp.event("sleepyshell:keybinds"))', "the Keybinds window")


def sha(path):
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except FileNotFoundError:
        return "none"


def tilde(p):
    p = Path(p)
    try:
        return "~/" + str(p.relative_to(HOME))
    except ValueError:
        return str(p)


def expand(p):
    return Path(os.path.expanduser(str(p)))


def discover():
    """hyprconf.py discover, as the shell itself reads the config ({} when it cannot be read)."""
    import subprocess
    r = subprocess.run([sys.executable, "-I", str(SHELL / "scripts" / "hyprconf.py"), "discover", "--root", str(HYPR)],
                       capture_output=True, text=True, timeout=60)
    try:
        return json.loads(r.stdout)
    except ValueError:
        return {}


def settings():
    """The colours and keybinds paths of the settings file ({} when there is none or it does not parse)."""
    try:
        flat = {}
        for k, v in tomllib.loads((SHELL / "sleepysettings.toml").read_text()).items():
            if isinstance(v, dict):
                flat.update(v)
        return flat
    except (OSError, ValueError):
        return {}


def combo(mods, key):
    return (frozenset(m.upper() for m in mods), key.lower())


def plan(theming):
    d = discover()
    st = settings()
    colors = expand(st.get("pathColors") or COLORS_DEFAULT)
    binds_path = expand(st.get("pathCustombinds") or BINDS_DEFAULT)
    own = {str(MODULE.resolve()) if MODULE.exists() else str(MODULE)}
    files = [f for f in d.get("files", []) if not f.get("missing")]
    loaded = {str(Path(f["path"]).resolve()) for f in files}
    # files the user's own config loads (not only through the installer's module, which is rewritten from this plan)
    loaded_elsewhere = {str(Path(f["path"]).resolve()) for f in files if not f.get("from") or str(Path(f["from"]).resolve()) not in own}

    # what the config already starts, outside the installer's own module
    execs = [e for e in d.get("execs", []) if str(Path(e["file"]).resolve()) not in own]
    def launched(*names):
        return [e for e in execs if e.get("command", "").split()[:1] and os.path.basename(e["command"].split()[0]) in names]
    shell_started = [e for e in execs if e.get("command", "").strip() in ("qs -c sleepyshell", "quickshell -c sleepyshell")]
    conflicts = []
    for e in execs:
        words = e.get("command", "").split()
        if not words:
            continue
        name = os.path.basename(words[0])
        if name in ("qs", "quickshell") and e["command"].strip() not in ("qs -c sleepyshell", "quickshell -c sleepyshell"):
            conflicts.append({"name": e["command"].strip(), "why": "another Quickshell config", "file": e["file"], "line": e["line"]})
        elif name in CONFLICTS:
            conflicts.append({"name": name, "why": CONFLICTS[name], "file": e["file"], "line": e["line"]})

    # keys already bound outside the installer's module: those are left out of it
    bound = {}
    for b in d.get("binds", []):
        if str(Path(b["file"]).resolve()) in own:
            continue
        bound.setdefault(combo(b.get("mods", []), b.get("key", "")), b)
    keys, taken = [], []
    for mods, key, line, what in BINDS:
        hit = bound.get(combo(mods, key))
        event = line.split("hl.dsp.event(", 1)[1].split(")", 1)[0] if "hl.dsp.event(" in line else None
        if hit and (event and event in hit.get("raw", "") or "sleepylock.qml" in line and "sleepylock.qml" in hit.get("raw", "")):
            continue  # the user's config already binds this key to the same thing
        if hit:
            taken.append({"combo": " + ".join(mods + [key]), "what": what, "action": hit.get("action", ""),
                          "file": hit["file"], "line": hit["line"]})
        else:
            keys.append({"combo": " + ".join(mods + [key]), "what": what, "line": line})

    # the Keybinds tab's file: made with the Keybinds window's key when it does not exist yet
    binds_req = None
    try:
        rel = binds_path.relative_to(HYPR).with_suffix("")
        binds_req = ".".join(rel.parts)
    except ValueError:
        pass
    kw_hit = bound.get(combo(KEYS_WINDOW[0], KEYS_WINDOW[1]))
    # any key that already opens the Keybinds window (the Keybinds tab's own, or one of the user's) is enough
    kw_set = any('"sleepyshell:keybinds"' in b.get("raw", "") for b in d.get("binds", []))
    if kw_set:
        kw_hit = None
    # a new file gets the header the Keybinds tab writes, so the tab knows the file as its own
    header = binds_header()
    binds = {"path": str(binds_path), "exists": binds_path.exists(), "require": binds_req,
             "text": header + (KEYS_WINDOW[2] + "\n" if not kw_hit and not kw_set else ""),
             "loaded": str(binds_path.resolve()) in loaded_elsewhere if binds_path.exists() else False,
             "keysWindow": None if kw_hit or kw_set else {"combo": "SUPER + slash", "line": KEYS_WINDOW[2]},
             "keysWindowTaken": {"action": kw_hit.get("action", ""), "file": kw_hit["file"], "line": kw_hit["line"]} if kw_hit else None}

    wall = theming and not launched("awww-daemon", "swww-daemon")
    text = module_text(keys, start_shell=not shell_started, start_wallpaper=wall,
                       binds_require=binds_req if binds_req and not binds["loaded"] else None)
    # the same module without the Keybinds tab's require, for when that file could not be made
    text_no_binds = module_text(keys, start_shell=not shell_started, start_wallpaper=wall, binds_require=None)
    mod_exists = MODULE.exists() or MODULE.is_symlink()
    old = ""
    if mod_exists:
        try:
            old = MODULE.read_text(errors="replace")
        except OSError:
            old = ""
    module = {"path": str(MODULE), "exists": mod_exists, "ours": old.startswith(MARK), "intact": module_intact(old),
              "sha": sha(MODULE), "same": mod_exists and old == text, "text": text, "textNoBinds": text_no_binds,
              "keys": keys, "taken": taken, "startsShell": not shell_started, "startsWallpaper": wall}

    main = d.get("main") or str(HYPR / "hyprland.lua")
    # a require of the module counts even while the module file is missing (a config copied from another machine)
    required = any(str(Path(f["path"]).resolve()) == str(MODULE.resolve()) for f in d.get("files", []))
    hypr = {"main": main, "format": d.get("format", ""), "readable": bool(d), "requireLine": f'require("{MODULE_NAME}")',
            "required": required, "mainSha": sha(main), "conflicts": conflicts,
            "startsHypridle": bool(launched("hypridle")),
            "shellStartedBy": [{"file": e["file"], "line": e["line"]} for e in shell_started]}

    return {"shell": str(SHELL), "link": str(LINK), "colors": str(colors), "hypr": hypr, "module": module,
            "binds": binds, "matugen": matugen_plan(colors, str(st.get("themePreset") or "")), "settings": settings_plan(),
            # theme.py and the shell read matugen's config at ~/.config; matugen itself at $XDG_CONFIG_HOME: when the two
            # differ, a theme run could write files that were never shown
            "themeSafe": CONFIG.resolve() == (HOME / ".config").resolve(),
            "themeCache": str(Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "theme-last-source")}


def binds_header():
    """BINDS_HEADER of scripts/hyprconf.py (the Keybinds tab writes the same lines into a new file)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("hyprconf", SHELL / "scripts" / "hyprconf.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.BINDS_HEADER


def notes(plan_path):
    d = json.loads(Path(plan_path).read_text())
    out = []
    for c in d["hypr"]["conflicts"]:
        out.append(f"Your Hyprland config starts {c['name']} ({c['why']}) in {c['file']}, line {c['line']}. Sleepy Shell does "
                   "that job itself; remove that line so the two do not clash.")
    for t in d["module"]["taken"]:
        out.append(f"{t['combo']} is already bound ({t['action'] or 'your bind'}, {t['file']} line {t['line']}), so "
                   f"{t['what']} got no key. Change your bind, or add a key for it in your own config.")
    t = d["binds"]["keysWindowTaken"]
    if t:
        out.append(f"SUPER + slash is already bound ({t['action'] or 'your bind'}), so the Keybinds window got no key. "
                   "Set one in Sleepysettings, Keybinds tab, Shell shortcuts.")
    return out


def module_intact(text):
    """Is text the installer's module exactly as it wrote it (its second line holds the sha256 of the rest)?"""
    lines = text.split("\n", 2)
    if len(lines) < 3 or not lines[0].startswith(MARK) or not lines[1].startswith(SUM):
        return False
    return lines[1][len(SUM):].split()[0:1] == [hashlib.sha256(lines[2].encode()).hexdigest()]


def module_text(keys, start_shell, start_wallpaper, binds_require):
    out = ["-- Running install.sh again rewrites this file while it is unchanged; an edited one is replaced only after a",
           "-- question, with a copy kept. Your own settings belong in your other files.",
           ""]
    if start_shell or start_wallpaper:
        out.append("hl.on(\"hyprland.start\", function()")
        if start_wallpaper:
            out.append("    hl.exec_cmd(\"awww-daemon\") -- the wallpaper daemon; it brings back the last wallpaper")
        if start_shell:
            out.append("    hl.exec_cmd(\"qs -c sleepyshell\") -- the bar, notifications and the polkit prompt")
        out += ["end)", ""]
    out += ["-- a lock screen that stopped while locked is taken over by a new one instead of leaving a red screen",
            "hl.config({ misc = { allow_session_lock_restore = true } })",
            "",
            "-- the settings, Keybinds and calendar windows float, centred; so does the terminal of Update now",
            'hl.window_rule({ name = "sleepyshell-settings-float", match = { class = "^org\\\\.quickshell$", title = "^Sleepysettings$" }, float = true, center = true })',
            'hl.window_rule({ name = "sleepyshell-keybinds-float", match = { class = "^org\\\\.quickshell$", title = "^Keybinds$" }, float = true, center = true })',
            'hl.window_rule({ name = "sleepyshell-calendar-float", match = { class = "^org\\\\.quickshell$", title = "^Calendar$" }, float = true, center = true })',
            'hl.window_rule({ name = "sleepyshell-update-float", match = { class = "^bar-update$" }, float = true, center = true, size = "monitor_w*0.45 monitor_h*0.55" })',
            "",
            "-- blur behind the islands and every popup of the shell (their surfaces are named sleepyshell...)",
            "if hl.layer_rule then",
            '    hl.layer_rule({ name = "sleepyshell-blur", match = { namespace = "^sleepyshell.*$" }, blur = true, blur_popups = true, ignore_alpha = 0.1 })',
            "end"]
    if keys:
        out += ["", "-- keys of the shell (a key your config already bound was left out)"]
        out += [k["line"] + " -- " + k["what"] for k in keys]
    if binds_require:
        out += ["", "-- the keybinds you add in Sleepysettings (Keybinds tab)", f'require("{binds_require}")']
    body = "\n".join(out) + "\n"
    return (MARK + " (install.sh). Loaded by one require line in hyprland.lua.\n"
            + SUM + hashlib.sha256(body.encode()).hexdigest() + "\n" + body)


def matugen_plan(colors, preset=""):
    """Does matugen's config write the shell's colours, and which files would a theme run rewrite?"""
    out = {"path": str(MATUGEN), "exists": MATUGEN.exists(), "parses": True, "error": "", "hasColors": False,
           "name": "sleepyshell", "snippet": "", "outputs": [], "sha": sha(MATUGEN), "hooks": [], "preset": bool(preset)}
    conf = {}
    if MATUGEN.exists():
        try:
            conf = tomllib.loads(MATUGEN.read_text())
        except (OSError, ValueError) as e:
            out.update(parses=False, error=str(e))
            return out
    templates = conf.get("templates", {}) if isinstance(conf.get("templates", {}), dict) else {}
    outputs = []
    for name, t in templates.items():
        # commands of the user's own config that matugen runs around a template (named in the question)
        if isinstance(t, dict) and any("hook" in k for k in t):
            out["hooks"].append(name)
        if isinstance(t, dict) and "output_path" in t:
            p = expand(t["output_path"])
            outputs.append(p)
            if p == colors or (p.exists() and colors.exists() and p.resolve() == colors.resolve()):
                out["hasColors"] = True
    name = "sleepyshell"
    n = 2
    while name in templates:
        name = f"sleepyshell-{n}"
        n += 1
    out["name"] = name
    template = tilde(LINK / "templates" / "quickshell" / "colors.json")
    if not out["hasColors"]:
        out["snippet"] = ("\n# Sleepy Shell: the bar's colours, from the same palette as your other templates (added by its installer)\n"
                          f"[templates.{name}]\ninput_path = \"{template}\"\noutput_path = \"{tilde(colors)}\"\n")
        outputs.append(colors)
    # a community theme (themePreset) is rendered by theme.py itself, which also writes this file when no template does
    fixed = expand(COLORS_DEFAULT)
    if preset and not any(p.name == "colors.json" and p.parent.name == "quickshell" for p in outputs):
        outputs.append(fixed)
    seen = []
    for p in outputs:
        if p not in seen:
            seen.append(p)
    out["outputs"] = [{"path": str(p), "exists": p.exists()} for p in seen]
    return out


def settings_plan():
    toml = SHELL / "sleepysettings.toml"
    legacy = SHELL / "settings.json"
    return {"path": str(toml), "exists": toml.exists(), "legacy": legacy.exists(),
            "defaults": str(SHELL / "data" / "default-settings.toml")}


def backup_into(base, path):
    """Copy path (its target when it is a link) to base/<path below />; returns the copy's path."""
    path = Path(path)
    dest = Path(base) / str(path.absolute()).lstrip("/")
    dest.parent.mkdir(parents=True, exist_ok=True)
    base_name, n = dest.name, 1
    while dest.exists():
        dest = dest.with_name(f"{base_name}.{n}")
        n += 1
    shutil.copy2(path, dest)
    return dest


def write(path, was, backup_dir, text):
    path = Path(path)
    real = Path(os.path.realpath(path))
    if path.is_symlink() and not real.exists():
        return {"ok": False, "path": str(path), "message": f"{path} is a link to a file that does not exist; nothing was written."}, 1
    now = sha(real)
    if now != was:
        return {"ok": False, "path": str(path), "message": f"{path} changed after it was shown; nothing was written."}, 6
    if real.exists() and not real.is_file():
        return {"ok": False, "path": str(path), "message": f"{path} is not a regular file; nothing was written."}, 1
    backup = None
    if real.exists():
        backup = str(backup_into(backup_dir, real))
    real.parent.mkdir(parents=True, exist_ok=True)
    try:
        mode = real.stat().st_mode & 0o777
    except OSError:
        mode = 0o644
    fd, tmp = tempfile.mkstemp(dir=real.parent, prefix="." + real.name + ".")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, real)
    except BaseException as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return {"ok": False, "path": str(path), "message": f"could not write {path}: {e}"}, 1
    return {"ok": True, "path": str(path), "backup": backup, "created": backup is None, "message": ""}, 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if argv else 2
    cmd = argv[0]
    if cmd == "plan":
        print(json.dumps(plan("--theming" in argv[1:]), indent=1))
        return 0
    if cmd == "notes" and len(argv) == 2:
        for line in notes(argv[1]):
            print(line)
        return 0
    if cmd == "sha" and len(argv) == 2:
        print(sha(argv[1]))
        return 0
    if cmd == "write" and len(argv) == 6 and argv[2] == "--was" and argv[4] == "--backup-dir":
        res, code = write(argv[1], argv[3], argv[5], sys.stdin.read())
        print(json.dumps(res))
        return code
    if cmd == "backup" and len(argv) >= 2:
        done, missing = [], []
        for p in argv[2:]:
            if os.path.isfile(p):
                done.append({"path": p, "backup": str(backup_into(argv[1], os.path.realpath(p)))})
            else:
                missing.append(p)
        print(json.dumps({"ok": True, "backups": done, "missing": missing}))
        return 0
    print("install.py: unknown command; see --help", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
