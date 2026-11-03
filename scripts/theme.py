#!/usr/bin/env python3
"""Palette from a wallpaper (matugen), settings from sleepyshell's Theme tab.

  theme.py              a random wallpaper from the folder, and its palette
  theme.py PATH         that wallpaper and its palette
  theme.py --palette    a new palette for the main monitor's wallpaper, which stays
  theme.py --preset FAMILY[:VARIANT]   a fixed palette from ../themes (no matugen, wallpaper untouched)
  theme.py --list-presets              the presets as JSON
  theme.py --preset ... --dry-run      render into a temp dir and print the paths, change nothing
  theme.py --auto                      the automatic wallpaper changer's step: the next wallpaper by the Theme tab's order
                                       (random or by name), never the one on screen; does nothing while the session is locked

With a community theme chosen (settings key themePreset, "family:variant"; "" is Sleepytheme) a new
wallpaper only sets the wallpaper and renders the preset again; matugen is not run. `--palette` always
means a new matugen palette (the Theme tab shows its Shuffle button only for Sleepytheme).

Settings come from sleepysettings.toml beside this folder (read with tomllib; one [section] per settings tab, the Theme
and Right island tabs matter here; settings.json is read instead until the shell has migrated it): wallpaper
folder, matugen scheme, dark/light mode, contrast, and whether the seed colour is pulled into cool
hues. A missing file or key falls back to the defaults. Python only, standard library (so sleepyshell
needs no fish); it runs magick,
matugen and awww (or swww, its old name: whichever is installed).

A preset skips matugen: the script reads matugen's config (templates, [config.custom] and the
"custom" table of its import_json_files), replaces {{colors.<role>.default.hex}} and
{{custom.<key>}} in every template itself and writes each output_path atomically. The variant
defaults to the first one of the Theme tab's dark/light mode. An unknown placeholder stops the run
before anything is written. THEME_SETTINGS (a .toml, or a .json by its suffix) and THEME_MATUGEN_CONFIG point it at other files (tests).
"""
import colorsys
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

SETTINGS = Path(os.environ.get("THEME_SETTINGS") or Path(__file__).resolve().parent.parent / "sleepysettings.toml")
PRESETS = Path(__file__).resolve().parent.parent / "themes"
MATUGEN_CONFIG = Path(os.environ.get("THEME_MATUGEN_CONFIG") or "~/.config/matugen/config.toml").expanduser()
LAST = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "theme-last-source"
IMAGES = {".png", ".jpg", ".jpeg", ".webp"}
# Hyprland's own wallpapers, used when the wallpaper folder has no images;
# installed with Hyprland, so they are there without shipping any here
FALLBACK = Path("/usr/share/hypr")


def read_settings():
    """Every key of the settings file as one flat dict ({} when it is missing or does not parse: the defaults apply).
    sleepysettings.toml has one [section] per settings tab, a key counts wherever it sits; a .json path (the shell's old file,
    read while sleepysettings.toml does not exist yet) is plain JSON."""
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


def raw_settings():
    """The settings as one flat dict: the one place that reads the settings file (appearance.py imports it)."""
    return read_settings()


def settings():
    d = raw_settings()
    return {
        # "" is Sleepytheme (matugen); "family:variant" is a community theme from ../themes
        "preset": str(d.get("themePreset", "") or ""),
        "order": d.get("wallpaperOrder", "random"),
        "dir": Path(os.path.expanduser(d.get("wallpaperDir", "~/Pictures/Wallpapers"))),
        "scheme": d.get("themeScheme", "scheme-vibrant"),
        "mode": d.get("themeMode", "dark"),
        "contrast": d.get("themeContrast", 0),
        "cool": d.get("themeCoolHues", True),
        "main": d.get("mainMonitor") or "",
    }


def wallpaper_daemon():
    """The wallpaper client that is installed: `awww`, or `swww` (its old name; distributions differ), else None."""
    return shutil.which("awww") or shutil.which("swww")


def on_screen(main=""):
    """The image awww shows on the main monitor, or None. The main monitor is the settings key
    mainMonitor when awww lists that output, else the first output; an output showing a plain
    colour counts as empty, and the first output with an image takes over."""
    daemon = wallpaper_daemon()
    if not daemon:
        return None
    out = subprocess.run([daemon, "query"], capture_output=True, text=True).stdout
    # one line per output: ": HDMI-A-1: 2560x1440, scale: 1, currently displaying: image: /path"
    outputs = []
    for line in out.splitlines():
        m = re.match(r"\s*:?\s*([^:]+?):\s.*?currently displaying:\s*(.*)$", line)
        if m:
            img = re.match(r"image:\s*(.+)$", m.group(2))
            outputs.append((m.group(1).strip(), img.group(1) if img else None))
    pick = next((o for o in outputs if main and o[0] == main), None) or (outputs[0] if outputs else None)
    if pick and pick[1]:
        return pick[1]
    return next((img for _, img in outputs if img), None)


def wallpaper_files(folder):
    """The images of the wallpaper folder sorted by name, else Hyprland's own wallpapers."""
    found = [p for p in folder.rglob("*") if p.is_file() and p.suffix.lower() in IMAGES] if folder.is_dir() else []
    if not found:
        found = list(FALLBACK.glob("wall*.png"))
    return sorted(found, key=lambda p: (p.name.lower(), str(p)))


def random_wallpaper(folder, avoid=None):
    """A random image of the folder, never the one on screen (`avoid`) unless it is the only one."""
    found = wallpaper_files(folder)
    others = [p for p in found if avoid is None or str(p) != str(avoid)]
    pool = others or found
    return str(random.choice(pool)) if pool else None


def next_wallpaper(folder, current):
    """The image after `current` by name (wrapping), the first one when current is not in the folder."""
    found = wallpaper_files(folder)
    if not found:
        return None
    names = [str(p) for p in found]
    try:
        return names[(names.index(str(current)) + 1) % len(names)]
    except ValueError:
        return names[0]


def session_locked():
    """True while a lock screen (sleepylock: `qs ... sleepylock.qml`) runs. Looks at the process list itself (no pgrep);
    THEME_PROC points it at another /proc (tests)."""
    root = Path(os.environ.get("THEME_PROC") or "/proc")
    me = str(os.getpid())
    try:
        entries = list(root.iterdir())
    except OSError:
        return False
    for e in entries:
        if not e.name.isdigit() or e.name == me:
            continue
        try:
            argv = (e / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        if argv and os.path.basename(argv[0].decode(errors="replace")) == "qs" and any(
                a.decode(errors="replace").endswith("sleepylock.qml") for a in argv[1:]):
            return True
    return False


def seed_source(wall):
    """One of the wallpaper's 16 main colours, never the previous pick, so a shuffle always
    changes the palette. -resize before -colors: quantising a 4K image took seconds, a 400 px
    copy takes 0.07 s and the histogram is the same in practice."""
    out = subprocess.run(["magick", wall, "-resize", "400x400", "-colors", "16", "-depth", "8",
                          "-format", "%c", "histogram:info:"], capture_output=True, text=True).stdout
    colours = re.findall(r"#[0-9A-Fa-f]{6}", out)
    if not colours:
        return None
    try:
        rest = [c for c in colours if c != LAST.read_text().strip()]
    except OSError:
        rest = []
    src = random.choice(rest or colours)
    LAST.parent.mkdir(parents=True, exist_ok=True)
    LAST.write_text(src + "\n")
    return src


def fold_cool(hex_colour):
    """A hue outside 180-300 is folded into that range (blues, cyans, violets)."""
    h = hex_colour.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hh, ll, ss = colorsys.rgb_to_hls(r, g, b)
    hue = hh * 360
    d = (hue - 300) % 360
    hue = hue if 180 <= hue <= 300 else 180 + (1 - d / 240) * 120
    nr, ng, nb = colorsys.hls_to_rgb(hue / 360, ll, ss)
    return "#%02X%02X%02X" % (round(nr * 255), round(ng * 255), round(nb * 255))


def load_presets():
    """{family: toml dict}, files that do not parse are skipped."""
    found = {}
    for p in sorted(PRESETS.glob("*.toml")):
        try:
            found[p.stem] = tomllib.loads(p.read_text())
        except (OSError, ValueError):
            print(f"theme: skipping unreadable preset {p.name}", file=sys.stderr)
    return found


def list_presets():
    keys = ("surface", "surface_container", "on_surface", "primary", "on_primary", "secondary", "tertiary", "error")
    out = []
    for fam, d in load_presets().items():
        out.append({
            "id": fam, "name": d.get("name", fam), "source": d.get("source", ""),
            "license": d.get("license", ""),
            "variants": [{"id": vk, "mode": v.get("mode", "dark"), "colors": {k: v.get(k, "") for k in keys}}
                         for vk, v in d.get("variants", {}).items()],
        })
    return out


def pick_preset(spec, mode):
    """(family, variant, roles) for 'family' or 'family:variant'. Without a variant the first one
    whose mode matches the Theme tab's mode; none of that mode (Nord, Dracula) falls back to the
    first variant."""
    fam, _, var = spec.strip().lower().partition(":")
    presets = load_presets()
    if fam not in presets:
        raise SystemExit(f"theme: unknown preset '{fam}' (have: {', '.join(presets) or 'none'})")
    variants = presets[fam].get("variants", {})
    if var and var not in variants:
        raise SystemExit(f"theme: preset '{fam}' has no variant '{var}' (have: {', '.join(variants)})")
    if not var:
        var = next((k for k, v in variants.items() if v.get("mode") == mode), None)
        if not var:
            var = next(iter(variants), None)
            print(f"theme: {fam} has no {mode} variant, using {var}", file=sys.stderr)
        if not var:
            raise SystemExit(f"theme: preset '{fam}' has no variants")
    roles = {k: v for k, v in variants[var].items() if k not in ("mode", "derived")}
    return fam, var, roles


PLACEHOLDER = re.compile(r"\{\{\s*(?:colors\.([A-Za-z0-9_]+)\.default\.hex|custom\.([A-Za-z0-9_]+))\s*\}\}")


def matugen_setup(config_path):
    """(templates, custom): [(name, input Path, output Path)] and the custom values, from
    matugen's config: [config.custom] and the "custom" table of each import_json_files entry
    (relative to the config's folder); [config.custom] wins."""
    try:
        conf = tomllib.loads(config_path.read_text())
    except OSError as e:
        raise SystemExit(f"theme: cannot read matugen config {config_path}: {e}")
    except ValueError as e:
        raise SystemExit(f"theme: bad matugen config {config_path}: {e}")
    custom = {}
    for f in conf.get("config", {}).get("import_json_files", []):
        try:
            data = json.loads((config_path.parent / os.path.expanduser(f)).read_text())
        except (OSError, ValueError) as e:
            raise SystemExit(f"theme: cannot read {f} named in the matugen config: {e}")
        if isinstance(data.get("custom"), dict):
            custom.update(data["custom"])
    custom.update(conf.get("config", {}).get("custom", {}))
    custom = {k: str(v) for k, v in custom.items()}
    templates = []
    for name, t in conf.get("templates", {}).items():
        if "input_path" not in t or "output_path" not in t:
            raise SystemExit(f"theme: template '{name}' needs input_path and output_path")
        templates.append((name, Path(os.path.expanduser(t["input_path"])),
                          Path(os.path.expanduser(t["output_path"]))))
    return templates, custom


def render(text, roles, custom, where):
    """text with every placeholder replaced; (result, [problems])."""
    problems = []

    def sub(m):
        if m.group(1) is not None:
            if m.group(1) in roles:
                return roles[m.group(1)]
            problems.append(f"{where}: no colour '{m.group(1)}' in the preset")
        else:
            if m.group(2) in custom:
                return custom[m.group(2)]
            problems.append(f"{where}: no custom value '{m.group(2)}' in the matugen config")
        return m.group(0)

    out = PLACEHOLDER.sub(sub, text)
    # whatever is still in braces is a form this script does not render (filters, other modes)
    for m in re.finditer(r"\{\{.*?\}\}|\{%.*?%\}|\{\{|\{%", out, re.S):
        problems.append(f"{where}: unsupported placeholder {m.group(0)[:40]!r}")
    return out, problems


def write_atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        mode = path.stat().st_mode & 0o777
    except OSError:
        mode = 0o644
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix="." + path.name + ".")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def apply_preset(spec, cfg, dry):
    fam, var, roles = pick_preset(spec, cfg["mode"])
    templates, custom = matugen_setup(MATUGEN_CONFIG)
    if not templates:
        print(f"theme: no templates in {MATUGEN_CONFIG}", file=sys.stderr)
        return 1
    jobs, problems = [], []
    for name, src, dest in templates:
        try:
            text = src.read_text()
        except (OSError, UnicodeDecodeError) as e:
            problems.append(f"{name}: cannot read {src}: {e}")
            continue
        out, errs = render(text, roles, custom, f"{name} ({src})")
        problems += errs
        jobs.append((name, dest, out))
    # the shell's own palette file is written even when the config has no template for it
    colors_path = Path(os.path.expanduser("~/.local/state/quickshell/colors.json"))
    if not any(d == colors_path for _, d, _ in jobs) and not any(
            d.name == "colors.json" and d.parent.name == "quickshell" for _, d, _ in jobs):
        body = dict(roles)
        if "corner_radius" in custom:
            body["corner_radius"] = custom["corner_radius"]
        jobs.append(("quickshell", colors_path, json.dumps(body, indent=2) + "\n"))
    if problems:
        print("theme: nothing written:", file=sys.stderr)
        for p in problems:
            print("  " + p, file=sys.stderr)
        return 1
    print(f"preset: {fam}:{var} ({len(roles)} colours, {len(templates)} templates)")
    if dry:
        tmp = Path(tempfile.mkdtemp(prefix="theme-dry-"))
        for name, dest, out in jobs:
            p = tmp / name / dest.name
            write_atomic(p, out)
            print(f"{name}\t{p}\t{dest}")
        return 0
    for name, dest, out in jobs:
        write_atomic(dest, out)
        print(f"wrote {dest}")
    return 0


def main(argv):
    if argv and argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    if "--list-presets" in argv:
        print(json.dumps(list_presets(), indent=2, ensure_ascii=False))
        return 0
    dry = "--dry-run" in argv
    argv = [a for a in argv if a != "--dry-run"]
    preset = None
    if any(a == "--preset" or a.startswith("--preset=") for a in argv):
        if len(argv) == 2 and argv[0] == "--preset":
            preset = argv[1]
        elif len(argv) == 1 and argv[0].startswith("--preset="):
            preset = argv[0].split("=", 1)[1]
        else:
            print("theme: --preset FAMILY[:VARIANT] takes no other argument but --dry-run", file=sys.stderr)
            return 2
        return apply_preset(preset, settings(), dry)
    if dry:
        print("theme: --dry-run only goes with --preset", file=sys.stderr)
        return 2
    cfg = settings()
    auto = bool(argv) and argv[0] == "--auto"
    keep = bool(argv) and argv[0] == "--palette"
    if auto:
        # the changer's step: never while locked (the screen is not seen, and the lock may hold the display)
        if session_locked():
            print("theme: locked, wallpaper not changed")
            return 0
        folder = cfg["dir"]
        now = on_screen(cfg["main"])
        wall = next_wallpaper(folder, now) if cfg["order"] == "name" else random_wallpaper(folder, now)
        if not wall:
            print(f"theme: no images in {folder}", file=sys.stderr)
            return 1
    else:
        wall = on_screen(cfg["main"]) if keep else (argv[0] if argv else None)
    # absolute, so a file name starting with "-" never reaches magick or awww as an option
    wall = os.path.abspath(os.path.expanduser(wall)) if wall else None
    # --palette is for the wallpaper on screen; a random one would not match it
    if keep and not wall:
        print("theme: no wallpaper on screen", file=sys.stderr)
        return 1
    if not wall:
        wall = random_wallpaper(cfg["dir"], on_screen(cfg["main"]))
    if not wall:
        print(f"theme: no images in {cfg['dir']}", file=sys.stderr)
        return 1
    # checked before anything runs: a wrong path must not blank the wallpaper first
    if not os.path.isfile(wall):
        print(f"theme: no such file: {wall}", file=sys.stderr)
        return 1

    # wallpaper first, so the screen changes at once; the palette follows a moment later
    # (awww-daemon runs from autostart; the wallpaper picker and SUPER+SHIFT+W call this script)
    daemon = wallpaper_daemon()
    if not keep and daemon:
        subprocess.run([daemon, "img", wall, "-t", "fade", "--transition-duration", "0.6",
                        "--transition-fps", "60"])

    # a community theme keeps its colours when the wallpaper changes: render it again (the templates may
    # have changed) and leave matugen alone; --palette is the way back to matugen's colours
    if cfg["preset"] and not keep:
        print(f"wallpaper: {wall}")
        return apply_preset(cfg["preset"], cfg, False)

    src = seed_source(wall)
    if not src:
        print(f"theme: no colours read from {wall}", file=sys.stderr)
        return 1
    seed = fold_cool(src) if cfg["cool"] else src.upper()

    print(f"wallpaper: {wall}")
    print(f"source: {src} -> seed: {seed} ({cfg['scheme']}, {cfg['mode']}, contrast {cfg['contrast']})")
    return subprocess.run(["matugen", "--type", cfg["scheme"], "--mode", cfg["mode"],
                           f"--contrast={cfg['contrast']}", "color", "hex", seed]).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
