#!/usr/bin/env python3
"""Default applications for Sleepysettings' Apps tab (services/DefaultApps.qml).

  defaultapps.py scan
      Prints one JSON object: for each category (web browser, file manager, ...) the current default
      (`xdg-mime query default <type>`) and the installed applications that say they handle it.
  defaultapps.py apply <category>=<desktop file> [...]
      Sets the defaults with `xdg-mime default <desktop file> <types...>` (the web browser also with
      `xdg-settings set default-web-browser`). Prints {"ok": bool, "errors": [...]}.
  defaultapps.py webmail <service> [mailto:...]
      Opens a new message of a web mail service (WEBMAIL) for the link, or the service's start page
      without one, in the default browser through `xdg-open`.

Why a script: Quickshell 0.3.2's DesktopEntry has no MimeType property, so the candidates come from the
desktop-file-utils caches (mimeinfo.cache in every applications folder) and the user's mimeapps.list,
and each .desktop file is read for its name, icon and Exec line. Python standard library only; the
only things it starts are xdg-mime, xdg-settings and xdg-open, as argument arrays (nothing goes through
a shell). Honours XDG_DATA_HOME, XDG_DATA_DIRS, XDG_CONFIG_HOME and PATH, so a test can fake all of them.

Web mail: a website cannot be a mailto: handler on its own, so the mail category also offers the services
in WEBMAIL. Applying one writes a hidden .desktop file (WEBMAIL_PREFIX<service>.desktop in the user's
applications folder) whose Exec line runs `webmail` above, then makes it the default like any other app.
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.parse

# id, label, the types a default is written to (`types` plus every cached type that starts with a
# `prefix`), and the one type whose default and handlers are shown (`probe`)
CATEGORIES = [
    {"id": "browser", "label": "Web browser", "probe": "x-scheme-handler/https",
     "types": ["x-scheme-handler/http", "x-scheme-handler/https", "text/html"]},
    {"id": "files", "label": "File manager", "probe": "inode/directory", "types": ["inode/directory"]},
    {"id": "editor", "label": "Text editor", "probe": "text/plain", "types": ["text/plain"]},
    {"id": "image", "label": "Image viewer", "probe": "image/png", "prefix": ["image/"],
     "types": ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/svg+xml", "image/tiff"]},
    {"id": "video", "label": "Video player", "probe": "video/mp4", "prefix": ["video/"],
     "types": ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/mpeg", "video/x-msvideo"]},
    {"id": "audio", "label": "Music player", "probe": "audio/mpeg", "prefix": ["audio/"],
     "types": ["audio/mpeg", "audio/flac", "audio/ogg", "audio/mp4", "audio/x-wav", "audio/x-opus+ogg"]},
    {"id": "pdf", "label": "PDF viewer", "probe": "application/pdf", "types": ["application/pdf"]},
    {"id": "mail", "label": "Mail", "probe": "x-scheme-handler/mailto", "types": ["x-scheme-handler/mailto"]},
]

# web mail services for the mail category: the compose page takes the whole mailto: link percent-encoded after
# it (the URL each service registers as a browser's own mailto handler), `home` opens when there is no link
WEBMAIL = {
    "gmail": {"name": "Gmail (web)", "compose": "https://mail.google.com/mail/?extsrc=mailto&url=",
              "home": "https://mail.google.com/"},
    "outlook": {"name": "Outlook (web)", "compose": "https://outlook.live.com/mail/0/deeplink/compose?mailtouri=",
                "home": "https://outlook.live.com/mail/"},
    "proton": {"name": "Proton Mail (web)", "compose": "https://mail.proton.me/inbox/#mailto=",
               "home": "https://mail.proton.me/"},
}
WEBMAIL_PREFIX = "sleepyshell-webmail-"
WEBMAIL_ICON = "internet-mail"


def env_dirs(name, default):
    return [d for d in (os.environ.get(name) or default).split(":") if d]


def data_dirs():
    home = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return [home] + env_dirs("XDG_DATA_DIRS", "/usr/local/share:/usr/share")


def config_home():
    return os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")


def mimeapps_path():
    return os.path.join(config_home(), "mimeapps.list")


def read_ini(path):
    """{section: [(key, value)]}, comments and blank lines dropped; {} when unreadable."""
    out, sec = {}, None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    sec = line[1:-1]
                    out.setdefault(sec, [])
                elif sec is not None and "=" in line:
                    k, v = line.split("=", 1)
                    out[sec].append((k.strip(), v.strip()))
    except OSError:
        return {}
    return out


def handlers():
    """{mime type: [desktop ids]} from every mimeinfo.cache and the user's added associations."""
    out = {}
    for d in data_dirs():
        for k, v in read_ini(os.path.join(d, "applications", "mimeinfo.cache")).get("MIME Cache", []):
            for app in v.split(";"):
                if app and app not in out.setdefault(k, []):
                    out[k].append(app)
    ini = read_ini(mimeapps_path())
    for k, v in ini.get("Added Associations", []):
        for app in v.split(";"):
            if app and app not in out.setdefault(k, []):
                out[k].insert(0, app)
    return out


def find_desktop(desktop_id):
    for d in data_dirs():
        p = os.path.join(d, "applications", desktop_id)
        if os.path.isfile(p):
            return p
    return None


def read_desktop(desktop_id):
    """{id, name, icon, exec, terminal, hidden, installed} of an application, None when there is no such file."""
    p = find_desktop(desktop_id)
    if p is None:
        return None
    entry = dict(read_ini(p).get("Desktop Entry", []))
    tryexec = entry.get("TryExec", "")
    installed = tryexec == "" or shutil.which(tryexec) is not None
    return {
        "id": desktop_id,
        "name": entry.get("Name") or desktop_id.removesuffix(".desktop"),
        "icon": entry.get("Icon", ""),
        "exec": entry.get("Exec", ""),
        "terminal": entry.get("Terminal", "").lower() == "true",
        "hidden": entry.get("NoDisplay", "").lower() == "true" or entry.get("Hidden", "").lower() == "true",
        "installed": installed,
    }


def xdg_default(mime):
    try:
        r = subprocess.run(["xdg-mime", "query", "default", mime], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout.strip() if r.returncode == 0 else ""


def expand_types(cat, cache):
    types = list(cat["types"])
    for pre in cat.get("prefix", []):
        for t in sorted(cache):
            if t.startswith(pre) and t not in types:
                types.append(t)
    return types


def scan():
    cache = handlers()
    cats = []
    for cat in CATEGORIES:
        current = xdg_default(cat["probe"])
        ids = list(cache.get(cat["probe"], []))
        if current and current not in ids:
            ids.insert(0, current)
        cands = []
        for i in ids:
            info = read_desktop(i)
            if info is None or not info["installed"]:
                continue
            # a hidden entry (NoDisplay) is offered only while it is the current default
            if info["hidden"] and i != current:
                continue
            cands.append({k: info[k] for k in ("id", "name", "icon", "exec", "terminal")})
        if cat["id"] == "mail":
            # offered whether or not their file exists yet; Apply writes it
            for service, svc in WEBMAIL.items():
                wid = WEBMAIL_PREFIX + service + ".desktop"
                if not any(c["id"] == wid for c in cands):
                    cands.append({"id": wid, "name": svc["name"], "icon": WEBMAIL_ICON, "exec": "", "terminal": False})
        cats.append({"id": cat["id"], "label": cat["label"], "probe": cat["probe"], "types": expand_types(cat, cache),
                     "current": current, "candidates": cands})
    return {"categories": cats, "mimeapps": mimeapps_path(), "hasSettings": shutil.which("xdg-settings") is not None}


def apply(pairs):
    cache = handlers()
    cats = {c["id"]: c for c in CATEGORIES}
    errors = []
    for pair in pairs:
        cid, _, desktop = pair.partition("=")
        if cid not in cats or not desktop.endswith(".desktop") or "/" in desktop:
            errors.append("refused: " + pair)
            continue
        service = webmail_service(desktop)
        if cid == "mail" and service:
            try:
                write_webmail(service)
            except OSError as e:
                errors.append("could not write " + desktop + ": " + str(e))
                continue
        cmds = [["xdg-mime", "default", desktop] + expand_types(cats[cid], cache)]
        if cid == "browser":
            cmds.append(["xdg-settings", "set", "default-web-browser", desktop])
        for cmd in cmds:
            try:
                r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
                if r.returncode != 0:
                    errors.append(cmd[0] + " failed for " + desktop + ": " + (r.stderr.strip() or str(r.returncode)))
            except (OSError, subprocess.SubprocessError) as e:
                errors.append(cmd[0] + ": " + str(e))
    return {"ok": not errors, "errors": errors}


def webmail_service(desktop_id):
    """The WEBMAIL key a desktop id names, None for any other id."""
    if desktop_id.startswith(WEBMAIL_PREFIX) and desktop_id.endswith(".desktop"):
        service = desktop_id[len(WEBMAIL_PREFIX):-len(".desktop")]
        if service in WEBMAIL:
            return service
    return None


def exec_arg(arg):
    """One argument of a .desktop Exec line, quoted and escaped as the Desktop Entry spec asks."""
    arg = arg.replace("%", "%%")
    if arg and not any(c in arg for c in " \t\n\"'\\><~|&;$*?#()`"):
        return arg
    return '"' + "".join("\\" + c if c in '"`$\\' else c for c in arg) + '"'


def write_webmail(service):
    """Writes (or rewrites, so it follows the shell if it moved) the hidden .desktop file of a web mail service."""
    folder = os.path.join(data_dirs()[0], "applications")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, WEBMAIL_PREFIX + service + ".desktop")
    argv = ["python3", os.path.abspath(__file__), "webmail", service]
    text = ("[Desktop Entry]\n"
            "# Written by Sleepysettings (Apps, Mail); choosing the service there again rewrites it.\n"
            "Type=Application\n"
            "Name=" + WEBMAIL[service]["name"] + "\n"
            "Icon=" + WEBMAIL_ICON + "\n"
            "Exec=" + " ".join(exec_arg(a) for a in argv) + " %u\n"
            "MimeType=x-scheme-handler/mailto;\n"
            "Terminal=false\n"
            # a mailto: handler, not an app to start from a launcher
            "NoDisplay=true\n")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def webmail(service, link):
    svc = WEBMAIL.get(service)
    if svc is None:
        sys.stderr.write("unknown web mail service: " + service + "\n")
        return 2
    if link and not link.lower().startswith("mailto:"):
        sys.stderr.write("not a mailto: link: " + link + "\n")
        return 2
    url = svc["compose"] + urllib.parse.quote(link, safe="") if link else svc["home"]
    # not waited for: xdg-open stays until the browser exits when it has to start it
    subprocess.Popen(["xdg-open", url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    return 0


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "scan":
        json.dump(scan(), sys.stdout, ensure_ascii=False)
    elif len(sys.argv) >= 2 and sys.argv[1] == "apply":
        res = apply(sys.argv[2:])
        json.dump(res, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0 if res["ok"] else 1
    elif len(sys.argv) in (3, 4) and sys.argv[1] == "webmail":
        return webmail(sys.argv[2], sys.argv[3] if len(sys.argv) == 4 else "")
    else:
        sys.stderr.write(__doc__)
        return 2
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
