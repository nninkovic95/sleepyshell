#!/usr/bin/env python3
"""The Theme tab's Appearance section: icon theme, interface font, GNOME's light/dark preference and the folder-colour overlay.
Python standard library only; every answer is one JSON object on stdout.

  appearance.py state                  what the desktop uses now (gsettings) and which programs are installed
  appearance.py icons                  installed icon themes, each with nine sample icons resolved from THAT theme's own files
  appearance.py fonts                  font families (fc-list)
  appearance.py apply KEY,KEY,... [--color-scheme dark|light]
                                       apply the settings keys that changed (iconTheme, folderColours, gtkFont, gtkFontSize;
                                       colorScheme sets GNOME's color-scheme to the mode after --color-scheme); values come
                                       from settings.json
  appearance.py folders-state          the folder icons' matugen templates: are they in the matugen config, is the overlay there
  appearance.py folders-snippet        the [templates.*] lines the matugen config needs for the folder icons, printed
  appearance.py folders-setup          add those lines to the matugen config (backup kept, atomic, idempotent)
  appearance.py folders-preview --primary #RRGGBB --on #RRGGBB
                                       five of the folder icons drawn in those colours into the cache folder (the Theme tab's
                                       "with matched folder colours" preview, before anything is applied)

Apply: icons = gsettings icon-theme; font = gsettings font-name; colorScheme = gsettings color-scheme
('prefer-dark' or 'prefer-light', the Theme tab's Light or dark). The mouse pointer is not set here: it comes from the
matugen tokens that the Hyprland config is rendered from. This script never writes a Hyprland file.

"Match folder colours to the theme" is an overlay icon theme, ~/.local/share/icons/Sleepytheme-Folders, whose
index.theme says Inherits=<the chosen icon theme> and whose scalable/places folder holds the flat folder icons that
matugen (or theme.py --preset) renders from ../templates/folders. With the option on, gsettings icon-theme is the
overlay; off, it is the chosen theme itself.

Every outside program is a name in BIN, which APPEARANCE_GSETTINGS and APPEARANCE_FCLIST can point
elsewhere (the test kit's fakes); HOME can point at a test folder, APPEARANCE_ICON_DIRS (colon separated) replaces
the three icon folders and APPEARANCE_CACHE the cache folder.
"""
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import theme  # noqa: E402  (the one reader of the settings file: theme.raw_settings)

BIN = {
    "gsettings": os.environ.get("APPEARANCE_GSETTINGS", "gsettings"),
    "fc-list": os.environ.get("APPEARANCE_FCLIST", "fc-list"),
}
SCHEMA = "org.gnome.desktop.interface"
OVERLAY = "Sleepytheme-Folders"
SHELL = Path(__file__).resolve().parent.parent
FOLDER_TEMPLATES = Path(os.environ.get("APPEARANCE_TEMPLATES") or SHELL / "templates" / "folders")
# the folder icons the Theme tab compares with and without the matched colours
FOLDER_SAMPLES = ["folder", "user-home", "folder-download", "folder-documents", "folder-music"]
SAMPLES = ["folder", "user-home", "folder-download", "text-x-generic", "image-x-generic", "utilities-terminal",
           "web-browser", "preferences-system", "user-trash"]
MARK_BEGIN = "# >>> sleepyshell folder icons (Theme tab, Match folder colours to the theme)"
MARK_END = "# <<< sleepyshell folder icons"


def home():
    return Path(os.environ.get("HOME") or Path.home())


def icon_dirs():
    env = os.environ.get("APPEARANCE_ICON_DIRS")
    if env is not None:
        return [Path(p) for p in env.split(":") if p]
    # the order GTK looks in: the user's folders first, then the system's
    return [home() / ".icons", home() / ".local/share/icons", Path("/usr/share/icons")]


def cache_dir():
    return Path(os.environ.get("APPEARANCE_CACHE") or (Path(os.environ.get("XDG_CACHE_HOME") or home() / ".cache") / "sleepyshell"))


def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False))
    return code


def run(name, *args):
    """(returncode, stdout) of one of the outside programs; (127, "") when it is not there."""
    try:
        p = subprocess.run([BIN[name], *args], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return 127, ""
    return p.returncode, p.stdout


def have(name):
    return shutil.which(BIN[name]) is not None


# ---- index.theme ----

def parse_index(path):
    """{section: {key: value}} of an index.theme, {} when unreadable."""
    sections, cur = {}, None
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line[0] in "#;":
            continue
        if line.startswith("[") and line.endswith("]"):
            cur = sections.setdefault(line[1:-1], {})
        elif "=" in line and cur is not None:
            k, _, v = line.partition("=")
            cur.setdefault(k.strip(), v.strip())
    return sections


def theme_dirs(tid):
    """Every folder that holds the theme `tid`, in lookup order."""
    return [d / tid for d in icon_dirs() if (d / tid).is_dir()]


def theme_index(tid):
    for d in theme_dirs(tid):
        idx = parse_index(d / "index.theme")
        if idx:
            return idx.get("Icon Theme", {})
    return {}


def csv(v):
    return [x.strip() for x in (v or "").split(",") if x.strip()]


# ---- icons: lookups the way GTK does them ----

class IconTheme:
    def __init__(self, tid):
        self.id = tid
        self.index = theme_index(tid)
        self.dirs = []
        for sec in csv(self.index.get("Directories")) + csv(self.index.get("ScaledDirectories")):
            self.dirs.append(sec)
        self.sections = {}
        for d in theme_dirs(tid):
            for k, v in parse_index(d / "index.theme").items():
                self.sections.setdefault(k, v)

    def spec(self, sub):
        s = self.sections.get(sub, {})
        try:
            size = int(s.get("Size", "0"))
        except ValueError:
            size = 0
        return size, s.get("Type", "Threshold")


def chain(tid, seen=None):
    seen = seen if seen is not None else []
    if tid in seen or len(seen) > 12:
        return seen
    seen.append(tid)
    for p in csv(theme_index(tid).get("Inherits")):
        chain(p, seen)
    return seen


_THEMES = {}


def load_theme(tid):
    if tid not in _THEMES:
        _THEMES[tid] = IconTheme(tid)
    return _THEMES[tid]


def find_icon(tid, name, target=48):
    """The file GTK would draw for `name` at about `target` px: walking the theme, then what it inherits, then hicolor;
    in a theme a scalable (svg) file first, else the largest size not above `target` (else the smallest above)."""
    order = chain(tid)
    if "hicolor" not in order:
        order.append("hicolor")
    for t in order:
        th = load_theme(t)
        cands = []
        for base in theme_dirs(t):
            for sub in th.dirs:
                size, typ = th.spec(sub)
                for ext in ("svg", "png"):
                    f = base / sub / f"{name}.{ext}"
                    if f.is_file():
                        cands.append((ext == "svg" or typ == "Scalable", size or target, f))
                        break
        if not cands:
            continue
        svg = [c for c in cands if c[0] and c[2].suffix == ".svg"]
        pool = svg or cands
        within = [c for c in pool if c[1] <= target]
        pick = max(within, key=lambda c: c[1]) if within else min(pool, key=lambda c: c[1])
        return pick[2]
    return None


def icon_themes():
    found = {}
    for d in icon_dirs():
        try:
            subs = sorted(d.iterdir())
        except OSError:
            continue
        for t in subs:
            if t.name in found or t.name in ("hicolor", OVERLAY) or not t.is_dir():
                continue
            idx = parse_index(t / "index.theme").get("Icon Theme", {})
            if not idx.get("Directories") or idx.get("Hidden", "").lower() == "true":
                continue
            found[t.name] = {"id": t.name, "name": idx.get("Name") or t.name, "path": str(t)}
    res = sorted(found.values(), key=lambda x: x["name"].lower())
    for t in res:
        t["samples"] = []
        for n in SAMPLES:
            f = find_icon(t["id"], n)
            t["samples"].append({"name": n, "path": str(f) if f else ""})
        t["folders"] = []
        for n in FOLDER_SAMPLES:
            f = find_icon(t["id"], n)
            t["folders"].append({"name": n, "path": str(f) if f else ""})
    return res


# ---- gsettings ----

def gget(key):
    rc, text = run("gsettings", "get", SCHEMA, key)
    return text.strip().strip("'") if rc == 0 else ""


def gset(key, value, did, errors):
    rc, _ = run("gsettings", "set", SCHEMA, key, str(value))
    (did if rc == 0 else errors).append(f"gsettings {key} {value}" if rc == 0 else f"gsettings set {key} failed")


def split_font(spec):
    m = re.match(r"^(.*?)\s+(\d+(?:\.\d+)?)$", spec.strip())
    if not m:
        return spec.strip(), 0
    n = float(m.group(2))
    return m.group(1), int(n) if n.is_integer() else n


def cmd_state(_a):
    name, size = split_font(gget("font-name"))
    icon = gget("icon-theme")
    base = icon
    if icon == OVERLAY:
        base = theme_index(OVERLAY).get("Inherits", "").split(",")[0] or icon
    return out({
        "available": {"gsettings": have("gsettings"), "fontList": have("fc-list")},
        "iconTheme": icon, "iconBase": base, "overlayOn": icon == OVERLAY,
        "font": name, "fontSize": size, "colorScheme": gget("color-scheme"),
    })


def cmd_fonts(_a):
    rc, text = run("fc-list", ":", "family")
    names = set()
    for line in text.splitlines():
        first = line.split(",")[0].strip()
        if first and not first.startswith("."):
            names.add(first)
    return out({"ok": rc == 0, "fonts": sorted(names, key=str.lower)})


def write_atomic_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix="." + path.name + ".")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def write_overlay(base):
    """~/.local/share/icons/Sleepytheme-Folders/index.theme, rewritten only when the base theme changed."""
    d = home() / ".local/share/icons" / OVERLAY
    idx = d / "index.theme"
    text = ("[Icon Theme]\nName=Sleepytheme Folders\nComment=Folder icons in the colours of the shell's theme (sleepyshell)\n"
            f"Inherits={base}\nDirectories=scalable/places\n\n[scalable/places]\nSize=64\nMinSize=16\nMaxSize=512\n"
            "Context=Places\nType=Scalable\n")
    (d / "scalable" / "places").mkdir(parents=True, exist_ok=True)
    try:
        if idx.read_text() == text:
            return False
    except OSError:
        pass
    write_atomic_text(idx, text)
    return True


def cmd_apply(a):
    keys = set(csv(a[0])) if a else set()
    mode = a[a.index("--color-scheme") + 1] if "--color-scheme" in a[:-1] else ""
    s = theme.raw_settings()
    did, errors = [], []
    # Light or dark: GNOME's own preference, so GTK 4 / libadwaita apps and the portal follow the theme (only these two values are ever set)
    if "colorScheme" in keys:
        if mode in ("dark", "light"):
            gset("color-scheme", "prefer-" + mode, did, errors)
        else:
            errors.append("color-scheme needs dark or light")
    # icons, and the overlay for the folder colours
    if keys & {"iconTheme", "folderColours"}:
        icons = {t["id"] for t in icon_themes_ids()}
        base = str(s.get("iconTheme") or "")
        if not base:
            base = gget("icon-theme")
            if base == OVERLAY:
                base = theme_index(OVERLAY).get("Inherits", "").split(",")[0]
        if base not in icons:
            errors.append(f"icon theme {base!r} is not installed")
        else:
            use = base
            if s.get("folderColours") is True:
                if write_overlay(base):
                    did.append(f"{OVERLAY} (index.theme)")
                use = OVERLAY
            gset("icon-theme", use, did, errors)
    # font
    if keys & {"gtkFont", "gtkFontSize"}:
        cur, cur_size = split_font(gget("font-name"))
        name = str(s.get("gtkFont") or "") or cur
        size = s.get("gtkFontSize") if "gtkFontSize" in keys else cur_size
        if not isinstance(size, (int, float)) or isinstance(size, bool) or not (6 <= size <= 48):
            size = cur_size or 11
        if not name or re.search(r"[\x00-\x1f]", name):
            errors.append("the interface font name is empty or has control characters")
        else:
            gset("font-name", f"{name} {int(size) if float(size).is_integer() else size}", did, errors)
    return out({"ok": not errors, "did": did, "errors": errors}, 0 if not errors else 1)


def icon_themes_ids():
    """Installed icon theme ids without resolving their samples."""
    res = []
    for d in icon_dirs():
        try:
            subs = sorted(d.iterdir())
        except OSError:
            continue
        for t in subs:
            idx = parse_index(t / "index.theme").get("Icon Theme", {})
            if t.is_dir() and idx.get("Directories") and t.name not in (OVERLAY,):
                res.append({"id": t.name})
    return res


# ---- the folder icons' matugen templates ----

def template_names():
    return sorted(p.stem for p in FOLDER_TEMPLATES.glob("*.svg")) if FOLDER_TEMPLATES.is_dir() else []


def tilde(p):
    s = str(p)
    h = str(home())
    return "~" + s[len(h):] if s == h or s.startswith(h + "/") else s


def snippet():
    lines = [MARK_BEGIN]
    for n in template_names():
        lines += [f"[templates.sleepy_folder_{n.replace('-', '_')}]",
                  f'input_path = "{tilde(FOLDER_TEMPLATES / (n + ".svg"))}"',
                  f'output_path = "~/.local/share/icons/{OVERLAY}/scalable/places/{n}.svg"', ""]
    lines.append(MARK_END)
    return "\n".join(lines) + "\n"


def configured_templates():
    try:
        conf = theme.tomllib.loads(theme.MATUGEN_CONFIG.read_text())
    except (OSError, ValueError):
        return None
    have_in = set()
    for t in conf.get("templates", {}).values():
        if isinstance(t, dict) and "input_path" in t:
            have_in.add(os.path.normpath(os.path.expanduser(t["input_path"])))
    return have_in


def cmd_folders_state(_a):
    names = template_names()
    have_in = configured_templates()
    missing = [n for n in names if have_in is None or os.path.normpath(str(FOLDER_TEMPLATES / (n + ".svg"))) not in have_in]
    idx = theme_index(OVERLAY)
    return out({"sample": "\n".join(snippet().splitlines()[1:4]), "count": len(names), "templates": names, "configReadable": have_in is not None, "config": str(theme.MATUGEN_CONFIG),
                "missing": missing, "configured": bool(names) and not missing,
                "overlay": bool(idx), "overlayBase": (idx.get("Inherits") or "").split(",")[0]})


def cmd_folders_snippet(_a):
    sys.stdout.write(snippet())
    return 0


def cmd_folders_setup(_a):
    path = theme.MATUGEN_CONFIG
    names = template_names()
    if not names:
        return out({"ok": False, "error": "the folder icon templates are missing from the shell's templates folder"}, 1)
    try:
        old = path.read_text()
        theme.tomllib.loads(old)
    except OSError as e:
        return out({"ok": False, "error": f"cannot read the matugen config: {e}"}, 1)
    except ValueError as e:
        return out({"ok": False, "error": f"the matugen config is not valid TOML, left alone: {e}"}, 1)
    block = snippet()
    if MARK_BEGIN in old and MARK_END in old:
        i = old.index(MARK_BEGIN)
        j = old.index(MARK_END, i) + len(MARK_END)
        new = old[:i] + block.rstrip("\n") + old[j:]
        if not new.endswith("\n"):
            new += "\n"
    else:
        new = old + ("" if old.endswith("\n") or not old else "\n") + "\n" + block
    if new == old:
        return out({"ok": True, "changed": False, "backup": ""})
    try:
        theme.tomllib.loads(new)
    except ValueError as e:
        return out({"ok": False, "error": f"the result would not be valid TOML, nothing written: {e}"}, 1)
    backup = path.with_name(path.name + ".bak-" + datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S"))
    try:
        shutil.copy2(path, backup)
        write_atomic_text(path, new)
    except OSError as e:
        return out({"ok": False, "error": f"cannot write the matugen config: {e}"}, 1)
    return out({"ok": True, "changed": True, "backup": str(backup)})


PREVIEW_NAMES = ["folder", "user-home", "folder-download", "folder-documents", "folder-music"]
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def cmd_folders_preview(a):
    opts = dict(zip(a[0::2], a[1::2]))
    prim, on = opts.get("--primary", ""), opts.get("--on", "")
    if not HEX.match(prim) or not HEX.match(on):
        return out({"ok": False, "error": "--primary and --on need colours like #RRGGBB"}, 1)
    d = cache_dir() / "folders" / (prim[1:].lower() + "-" + on[1:].lower())
    res = {}
    for n in PREVIEW_NAMES:
        src = FOLDER_TEMPLATES / (n + ".svg")
        try:
            text = src.read_text()
        except OSError:
            continue
        text = theme.PLACEHOLDER.sub(lambda m: prim if m.group(1) == "primary" else on if m.group(1) == "on_primary" else m.group(0), text)
        dest = d / (n + ".svg")
        try:
            if not dest.is_file() or dest.read_text() != text:
                write_atomic_text(dest, text)
        except OSError:
            continue
        res[n] = str(dest)
    return out({"ok": bool(res), "icons": res})


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    cmd, rest = argv[0], argv[1:]
    table = {
        "state": cmd_state,
        "icons": lambda a: out({"icons": icon_themes()}),
        "fonts": cmd_fonts,
        "apply": cmd_apply,
        "folders-state": cmd_folders_state,
        "folders-snippet": cmd_folders_snippet,
        "folders-setup": cmd_folders_setup,
        "folders-preview": cmd_folders_preview,
    }
    if cmd not in table:
        print(f"appearance: unknown command {cmd!r}", file=sys.stderr)
        return 2
    return table[cmd](rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
