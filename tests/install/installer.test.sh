#!/bin/bash
# install/installer.test.sh [TREE]: install.sh asks before it changes anything of the user's, installs what was picked
# and records it, and refuses the systems it is not for.
#
# Tier 1 (a user's files changed without asking) and tier 2 (a broken desktop after an install). In one sandbox, each
# scenario in a world of its own (inner.sh, scenarios.sh): a fresh home with the kit's fixture Hyprland config, a copy
# of the clone (TREE plus the repository's install.sh and tools/install.py), and a PATH in which pacman, sudo, paru,
# systemctl, hyprctl, git, makepkg, qs and awww are stand-ins (stub.py) that log and install nothing. matugen and
# ImageMagick are the real ones, so the theme run is real. Checks: the refusals (not Arch, no Hyprland, Hyprland 0.54,
# hyprland.conf only) change nothing; a fresh install with paru built from the AUR sets up every file, records every
# package, service and file, and starts the shell; a second run changes nothing; every "no" to a file of the user's
# leaves it byte for byte; --dry-run changes nothing; AUR packages without a helper never reach any helper; a file edited
# after its question is not written over; a taken key is left out and reported; a failed pacman stops the setup; the
# full-screen interface answers keys and gives the terminal back.
# INSTALL_SH names another install.sh to test (a copy with a bug, to see the checks catch it).
# Prints PASS or FAIL per check; exits 1 on any FAIL.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../common/env.sh"
TREE=$(readlink -f "${1:-$LIVE}")
REPO=$(cd "$KIT/.." && pwd)
NAME=installer-$$
D=$RUN/$NAME
mkdir -p "$D"
trap 'bash "$KIT/common/cleanup.sh" "$D" >/dev/null' EXIT

python3 -I "$KIT/common/guard.py" snapshot "$NAME" >/dev/null
copy_tree "$TREE" "$D/clone-src"
rm -f "$D"/clone-src/sleepysettings.toml* "$D"/clone-src/settings.json*
mkdir -p "$D/clone-src/tools"
cp "${INSTALL_SH:-$REPO/install.sh}" "$D/clone-src/install.sh"
cp "$REPO/tools/install.py" "$D/clone-src/tools/"

SCENARIOS=(refuse_os refuse_nohypr refuse_old refuse_conf derivative nopython fresh declines dryrun aur_declined changed
    taken pacman_fails interrupted dotfiles existing xdg polkit_keep polkit_use font_ok font_bad tui)
timeout 600 bash "$KIT/common/sandbox.sh" "$D" bash "$KIT/install/inner.sh" "$D" "${SCENARIOS[@]}"

python3 -I - "$D" <<'CHECK_INSTALLER_PY'
import json, re, sys, tomllib
from pathlib import Path
D = Path(sys.argv[1])
fails = 0
def check(ok, what, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or not detail else ": " + str(detail)[:600]))
    fails += 0 if ok else 1
def read(p):
    try:
        return Path(p).read_text()
    except OSError:
        return ""
def rc(w):
    return read(D / w / "rc").strip()
def out(w, name="out.txt"):
    return read(D / w / name)
def calls(w, name="stub/calls.log"):
    return read(D / w / name)
def snap(w, tag):
    return read(D / w / f"snap-{tag}")
def changed(w, a, b):
    """the lines that differ between two snapshots"""
    x, y = set(snap(w, a).splitlines()), set(snap(w, b).splitlines())
    return sorted(x ^ y)
def manifest(w):
    rows = []
    for line in read(D / w / "home/.local/state/sleepyshell/install/manifest.tsv").splitlines():
        if line and not line.startswith("#"):
            rows.append(line.split("\t"))
    return rows
H = lambda w: D / w / "home"
NO_INSTALL = re.compile(r"^(ROOT )?(pacman -S |paru -S |yay -S |makepkg|git clone|systemctl (--user )?enable|sudo )", re.M)

# ---- refusals: before any question, nothing changed, nothing installed
for w, words in [("refuse_os", "Arch Linux and Arch-based distributions"), ("refuse_nohypr", "No Hyprland session"),
                 ("refuse_old", "This is Hyprland 0.54.2"), ("refuse_conf", "still " )]:
    o = out(w)
    check(rc(w) == "1" and words in o, f"{w}: refused with a plain message", o)
    check(changed(w, "before", "after") == [] and not NO_INSTALL.search(calls(w)), f"{w}: nothing changed or installed",
          changed(w, "before", "after") or calls(w))
check("hyprland.conf" in out("refuse_conf") and "Lua" in out("refuse_conf"), "refuse_conf: names hyprland.conf and the Lua config",
      out("refuse_conf"))
check("for Hyprland only" in out("refuse_nohypr"), "refuse_nohypr: says Sleepy Shell is for Hyprland", out("refuse_nohypr"))
check(rc("derivative") == "1" and "== Welcome ==" in out("derivative") and "CachyOS" in out("derivative")
      and changed("derivative", "before", "after") == [], "derivative: an Arch-based system passes; quitting changes nothing",
      out("derivative")[-800:])
check(rc("nopython") == "1" and "== Python 3 ==" in out("nopython") and changed("nopython", "before", "after") == []
      and "pacman -S" not in calls("nopython"), "nopython: asks to install Python; quitting changes nothing",
      out("nopython")[-800:])

# ---- a fresh install
w = "fresh"
o1, c1 = out(w, "out-1.txt"), calls(w, "calls-1.log")
h = H(w)
check("Sleepy Shell is installed." in o1 and "Failed" not in o1, "fresh: finished without a failed step", o1[-2500:])
repo_line = next((l for l in c1.splitlines() if l.startswith("ROOT pacman -S")), "")
for p in ["quickshell", "ttf-jetbrains-mono-nerd", "polkit", "matugen", "imagemagick", "awww", "hypridle",
          "hyprshot", "wl-clipboard", "upower", "kitty", "git", "base-devel"]:
    check(f" {p}" in repo_line, f"fresh: {p} installed from the repositories", repo_line)
check(repo_line != "" and not re.search(r" (walker|elephant|elephant-clipboard|pwvucontrol|paru)( |$)", repo_line),
      "fresh: no AUR package is passed to pacman", repo_line)
check("git clone --depth 1 https://aur.archlinux.org/paru-bin.git" in c1 and "makepkg -si --needed" in c1,
      "fresh: paru built from the AUR after the yes", c1)
aur_line = next((l for l in c1.splitlines() if l.startswith("paru -S")), "")
check(all(p in aur_line.split() for p in ["walker", "elephant", "elephant-clipboard", "pwvucontrol"]) and " paru " not in aur_line + " ",
      "fresh: the AUR packages through paru", aur_line)
link = h / ".config/quickshell/sleepyshell"
check(link.is_symlink() and link.resolve() == (D / w / "clone").resolve(), "fresh: the shell folder links to the clone")
defaults = read(D / w / "clone/data/default-settings.toml")
check(defaults != "" and read(D / w / "clone/sleepysettings.toml") == defaults, "fresh: the default settings are in place")
mod = read(h / ".config/hypr/modules/sleepyshell.lua")
check(mod.startswith("-- Sleepy Shell: written by its installer") and 'hl.exec_cmd("qs -c sleepyshell")' in mod
      and "SUPER + ESCAPE" in mod and "SUPER + L" in mod and "Caps_Lock" in mod and 'require("modules.sleepybinds")' in mod
      and 'hl.bind("Print", hl.dsp.exec_cmd("hyprshot -m region"))' in mod,
      "fresh: the module starts the shell, binds its keys and loads the Keybinds tab's file", mod)
hl = read(h / ".config/hypr/hyprland.lua")
check(hl.count('require("modules.sleepyshell")') == 1, "fresh: one require line in hyprland.lua", hl)
baks = sorted((h / ".config/hypr").glob("hyprland.lua.bak-*"))
check(len(baks) == 1 and read(baks[0]) + 'require("modules.sleepyshell")\n' == hl,
      "fresh: hyprland.lua is its copy plus that line, nothing else", [str(b) for b in baks])
binds = read(h / ".config/hypr/modules/sleepybinds.lua")
check(binds.startswith("-- Keybinds added in Sleepysettings") and 'hl.bind("SUPER + slash", hl.dsp.event("sleepyshell:keybinds"))' in binds,
      "fresh: the Keybinds tab's file has its header and the Keybinds window's key", binds)
idle = read(h / ".config/hypr/hypridle.conf")
check("sleepylock" in idle or "sleepyshell" in idle, "fresh: hypridle.conf made by idle.py", idle[:300])
try:
    mt = tomllib.loads(read(h / ".config/matugen/config.toml"))
    t = mt["templates"]["sleepyshell"]
    ok = t["output_path"] == "~/.local/state/quickshell/colors.json" and t["input_path"].endswith("templates/quickshell/colors.json")
except Exception as e:
    ok, mt = False, e
check(ok, "fresh: matugen's config has the bar's colours template", mt)
try:
    col = json.loads(read(h / ".local/state/quickshell/colors.json"))
    ok = all(re.fullmatch(r"#[0-9a-fA-F]{6}", col.get(k, "")) for k in ["surface", "primary_container", "on_surface", "error_container"])
except ValueError as e:
    ok, col = False, e
check(ok, "fresh: the theme run made the bar's colours (real matugen)", col)
check(re.search(r"^awww img /\S+ ", c1, re.M) is not None, "fresh: the theme run set a wallpaper", c1)
check("qs -c sleepyshell -d" in c1, "fresh: the shell was started", c1)
check("ROOT systemctl enable --now NetworkManager.service" in c1 and "systemctl --user enable --now hypridle.service" in c1
      and "bluetooth.service" not in "".join(l for l in c1.splitlines() if "enable" in l)
      and "power-profiles-daemon.service" not in "".join(l for l in c1.splitlines() if "enable" in l),
      "fresh: only the services that got a yes were enabled", c1)
check("sudo sh -c set -C; printf \"i2c-dev\\n\" > \"$1\" sh " in c1 and "modules-load.d/i2c-dev.conf" in c1,
      "fresh: i2c-dev's file written through sudo after the yes", c1)
check("sudo systemctl enable --now bluetooth.service" in o1 and "sudo systemctl enable --now power-profiles-daemon.service" in o1,
      "fresh: the report gives the command for every service left off", o1[-2500:])
m = manifest(w)
kinds = {(r[1], r[2]) for r in m}
for path in [".config/quickshell/sleepyshell", "clone/sleepysettings.toml", ".config/hypr/modules/sleepyshell.lua",
             ".config/hypr/modules/sleepybinds.lua", ".config/hypr/hypridle.conf", ".config/matugen/config.toml",
             ".local/state/quickshell/colors.json"]:
    full = str(D / w / path) if path.startswith("clone/") else str(h / path)
    check(("created", full) in kinds or ("link", full) in kinds, f"fresh: the record has {path}", m)
check(any(r[1] == "changed" and r[2] == str(h / ".config/hypr/hyprland.lua") and Path(r[3]).exists() for r in m),
      "fresh: the record has hyprland.lua with its copy", m)
pk = {r[2]: (r[3], r[4]) for r in m if r[1] == "package"}
check(pk.get("quickshell") == ("explicit", "repo") and pk.get("qt6-declarative") == ("dependency", "repo")
      and pk.get("walker") == ("explicit", "aur") and pk.get("paru-bin") == ("explicit", "aur") and "bash" not in pk,
      "fresh: the record has each new package, explicit or a dependency, repo or AUR, and nothing that was there", pk)
check({("service", "system", "NetworkManager.service"), ("service", "user", "hypridle.service")} <= {tuple(r[1:4]) for r in m},
      "fresh: the record has the enabled services", m)
check(any(r[1] == "root-created" and r[2].endswith("modules-load.d/i2c-dev.conf") for r in m), "fresh: the record has the i2c-dev file", m)
check(list((h / ".local/state/sleepyshell/install").glob("report-*.txt")) != [], "fresh: the report is kept")
# a second run over the result
o2, c2 = out(w, "out-2.txt"), calls(w)
check(rc(w) == "0" and "Nothing to install" in o2 and "== Your file" not in o2, "fresh, again: nothing to install and no file question",
      o2[-2500:])
check(changed(w, "after", "again") == [] or all("/.local/state/" in l or "/.cache/" in l for l in changed(w, "after", "again")),
      "fresh, again: no file changed but the installer's own record", changed(w, "after", "again"))
check(not NO_INSTALL.search(c2), "fresh, again: nothing installed or enabled", c2)
runs = {r[0] for r in manifest(w)}
check(len(runs) == 1, "fresh, again: the record gained nothing", runs)

o3 = out(w)
check("was written by this installer and changed since" in o3 and read(h / ".config/hypr/modules/sleepyshell.lua") == read(D / w / "module-edited"),
      "fresh, third run: an edited module is replaced only after a question (no: kept as edited)", o3[-2000:])

# ---- stopped right after pacman
w = "interrupted"
pk = {r[2] for r in manifest(w) if r[1] == "package"}
check(rc(w) == "130" and {"quickshell", "qt6-declarative"} <= pk, "interrupted: the packages installed before Ctrl+C are recorded",
      (rc(w), pk, out(w)[-600:]))
check(not (H(w) / ".config/quickshell/sleepyshell").exists(), "interrupted: nothing after the stop was done")

# ---- a require line already there, its module missing
w = "dotfiles"
o = out(w)
check("== Your file: hyprland.lua" not in o and read(H(w) / ".config/hypr/hyprland.lua") == read(D / w / "hyprland.orig")
      and not any(r[1] == "changed" and r[2].endswith("hyprland.lua") for r in manifest(w))
      and read(H(w) / ".config/hypr/modules/sleepyshell.lua").startswith("-- Sleepy Shell: written by its installer"),
      "dotfiles: the module is made; hyprland.lua is not asked about, changed or recorded", o[-1500:])

# ---- every no to a file of the user's
w = "declines"
check(rc(w) == "0" or "Sleepy Shell is installed" in out(w), "declines: the run finished", out(w)[-1500:])
check(changed(w, "before", "quit") == [], "declines: quitting at the shell folder question changed nothing", changed(w, "before", "quit"))
diff = changed(w, "before", "after")
kept = [".config/hypr/hyprland.lua", ".config/matugen/config.toml", ".config/kitty/kitty.conf", ".config/hypr/modules/binds.lua"]
moved_bad = [l for l in diff if any(l.endswith(" home/" + k) for k in kept)]
check(moved_bad == [], "declines: hyprland.lua, binds.lua, the matugen config and kitty.conf are byte for byte the same", moved_bad)
old = list((H(w) / ".config/quickshell").glob("sleepyshell.bak-*"))
check(len(old) == 1 and read(old[0] / "shell.qml") == "// someone else's shell\n", "declines: the old shell folder was moved aside whole")
check((H(w) / ".config/quickshell/sleepyshell").is_symlink(), "declines: the link took its place after the yes")
o = out(w)
check('require("modules.sleepyshell")' in o.split("== Finished ==")[-1], "declines: the report gives the require line to add", o[-2500:])
check(not re.search(r"systemctl (--user )?enable", calls(w)), "declines: no service enabled", calls(w))
check("theme.py" not in calls(w) and "awww img" not in calls(w), "declines: the theme did not run", calls(w))

# ---- existing files, yes to each
w = "existing"
o, c, h, m = out(w), calls(w), H(w), manifest(w)
bk = lambda path: next((r[3] for r in m if r[1] == "changed" and r[2] == str(h / path)), "")
mod = read(h / ".config/hypr/modules/sleepyshell.lua")
check("== Your file: sleepyshell.lua" in o and mod.startswith("-- Sleepy Shell: written by its installer")
      and read(bk(".config/hypr/modules/sleepyshell.lua")) == read(D / w / "orig-sleepyshell.lua"),
      "existing: a foreign sleepyshell.lua is replaced after the yes, its copy recorded", (bk(".config/hypr/modules/sleepyshell.lua"), o[-1500:]))
mt = read(h / ".config/matugen/config.toml")
try:
    tm = tomllib.loads(mt)["templates"]
    ok = "kitty" in tm and "sleepyshell" in tm and mt.startswith(read(D / w / "orig-config.toml"))
except ValueError as e:
    ok, tm = False, e
check(ok and read(bk(".config/matugen/config.toml")) == read(D / w / "orig-config.toml"),
      "existing: the matugen config keeps its own lines, gains the template, its copy recorded", (tm, bk(".config/matugen/config.toml")))
kitty = read(h / ".config/kitty/kitty.conf")
check(re.fullmatch(r"background #[0-9a-fA-F]{6}\n", kitty) is not None and kitty != read(D / w / "orig-kitty.conf")
      and read(bk(".config/kitty/kitty.conf")) == read(D / w / "orig-kitty.conf"),
      "existing: the theme run rewrites kitty.conf after copying it, the copy recorded", (kitty, bk(".config/kitty/kitty.conf")))
question = o.split("== First theme run", 1)[-1].split("Every file", 1)[0]
check("rewrite" in question and "kitty.conf" in question, "existing: the theme question names kitty.conf as rewritten", question)
check("runs commands of its own" in o and "kitty" in o.split("runs commands of its own")[1][:200], "existing: the hook is named in the question", o[-2500:])
check("Service: NetworkManager" not in o and "iwd manages your network" in o, "existing: NetworkManager not offered beside iwd, and said why", o[-2500:])
check("Service: power-profiles-daemon" not in o and "tlp manages power" in o, "existing: power-profiles-daemon not offered beside TLP, and said why", o[-2500:])
check(not re.search(r"systemctl (--user )?enable", c), "existing: no service enabled", c)

# ---- XDG_CONFIG_HOME elsewhere
w = "xdg"
o = out(w)
check("== First theme run" not in o and "XDG_CONFIG_HOME is not ~/.config" in o and "theme.py" not in calls(w)
      and "awww img" not in calls(w), "xdg: no theme run offered, and the report says why", o[-1500:])
check((H(w) / "xdgconf/quickshell/sleepyshell").is_symlink() and (H(w) / "xdgconf/hypr/modules/sleepyshell.lua").exists(),
      "xdg: the link and the module go under XDG_CONFIG_HOME", o[-800:])

# ---- another polkit agent
w = "polkit_keep"
o = out(w)
check("== Password prompt ==" in o and "hyprpolkitagent.service, a service of your user" in o, "polkit_keep: the other agent is found and asked about", o[-2500:])
check(re.search(r"^polkitAgent = false$", read(D / w / "clone/sleepysettings.toml"), re.M) is not None
      and "disable" not in calls(w), "polkit_keep: kept; the shell's prompt is off in the new settings and the service untouched",
      calls(w)[-800:])
check("Password prompts are answered by hyprpolkitagent" in o.split("== Finished ==")[-1], "polkit_keep: the report names the agent that answers", o[-1500:])
w = "polkit_use"
o, m = out(w), manifest(w)
check("systemctl --user disable --now hyprpolkitagent.service" in calls(w) and ["service-disabled", "user", "hyprpolkitagent.service"] in [r[1:4] for r in m]
      and re.search(r"^polkitAgent = true$", read(D / w / "clone/sleepysettings.toml"), re.M) is not None,
      "polkit_use: the other agent's service is disabled and recorded, the shell's prompt stays on", (calls(w)[-800:], m[-6:]))
check("Password prompts are answered by Sleepy Shell" in o.split("== Finished ==")[-1], "polkit_use: the report says the shell answers", o[-1500:])
check(re.search(r'^defaultTerminal = "myterm"$', read(D / w / "clone/sleepysettings.toml"), re.M) is not None and "Terminal for Update now" in o,
      "polkit_use: without kitty the new settings name $TERMINAL as the shell's terminal", o[-1500:])

# ---- the clocks' font
w = "font_ok"
fdir = H(w) / ".local/share/fonts"
names = ["3270-Regular.ttf", "3270SemiCondensed-Regular.ttf", "3270Condensed-Regular.ttf"]
check(all(read(fdir / n) == f"stand-in for {n}\n" for n in names) and not (fdir / "README.md").exists()
      and all(["created", str(fdir / n)] in [r[1:3] for r in manifest(w)] for n in names),
      "font_ok: the three font files of the checked archive are installed and recorded, nothing else of it", out(w)[-1500:])
check("The clocks' font IBM 3270" in out(w).split("== Summary ==", 1)[-1], "font_ok: the summary names the download", out(w)[-2500:])
w = "font_bad"
check(not any((H(w) / ".local/share/fonts" / n).exists() for n in names) and "not the expected one" in out(w) and rc(w) == "1",
      "font_bad: an archive with another SHA-256 installs nothing, and the run says so", out(w)[-1500:])
w = "fresh"
check("Installed the clocks' font IBM 3270" in out(w, "out-1.txt") and "The clocks' font" not in out(w, "out-2.txt").split("== Summary ==", 1)[-1].split("Install /", 1)[0],
      "fresh: the clocks' font is installed once and not downloaded again on the next run", out(w, "out-2.txt")[-1500:])

# ---- dry run
w = "dryrun"
check(rc(w) == "0" and "Dry run: nothing was installed or changed." in out(w), "dryrun: stops after the summary", out(w)[-800:])
check(changed(w, "before", "after") == [] and not NO_INSTALL.search(calls(w)), "dryrun: nothing changed or installed",
      changed(w, "before", "after") or calls(w))

# ---- AUR declined
w = "aur_declined"
c = calls(w)
check(not re.search(r"^(paru|yay|makepkg|git clone)", c, re.M) and not re.search(r"pacman -S .*\b(walker|elephant|pwvucontrol|paru)\b", c),
      "aur_declined: no AUR package reaches pacman or a helper", c)
check("The AUR packages (paru walker elephant elephant-clipboard pwvucontrol)" in out(w), "aur_declined: the report lists them",
      out(w)[-1500:])

# ---- a file edited after its question
w = "changed"
hl = read(H(w) / ".config/hypr/hyprland.lua")
check('require("modules.sleepyshell")' not in hl and hl.endswith("-- edited while the installer ran\n")
      and hl == read(D / w / "hyprland.orig") + "-- edited while the installer ran\n",
      "changed: hyprland.lua edited meanwhile is left as the user left it", hl)
check("changed after you were asked" in out(w) and rc(w) == "1", "changed: the report says so, and the run fails", out(w)[-1500:])

# ---- a taken key and a bar the config starts
w = "taken"
mod = read(H(w) / ".config/hypr/modules/sleepyshell.lua")
check("SUPER + L" not in mod and "SUPER + ESCAPE" in mod, "taken: the taken key is left out of the module", mod)
o = out(w)
check("SUPER + L is already bound" in o and "waybar" in o and "another bar" in o, "taken: both are reported", o[-2500:])

# ---- pacman fails
w = "pacman_fails"
o = out(w)
check(rc(w) == "1" and "Failed" in o, "pacman_fails: the run fails and says so", o[-1500:])
d = [l for l in changed(w, "before", "after") if "/.local/state/sleepyshell/" not in l]
check(d == [], "pacman_fails: without the shell's packages nothing else was set up", d)

# ---- the full-screen interface
w = "tui"
t = read(D / w / "drive.txt")
check(rc(w) == "0", "tui: every screen came", t[-2000:])
check("PICKER" in t and "[ ] Wallpaper theming" in t, "tui: Space unticks a part in the picker", t[-2000:])
check("WRAPPED yes" in t, "tui: a package line longer than the screen wraps in the picker", read(D / w / "frames.txt")[-3000:])
check("SCREEN Summary" in t and "[ Install ]" in t and "Cancel" in t and "matugen" not in t.split("SUMMARY", 1)[-1].split("Services")[0],
      "tui: the summary shows the choice, without the unticked part's packages", t[-2000:])
check("SCREEN Cancelled" in t and "EXIT 1" in t, "tui: cancel at the summary ends the run", t[-800:])
check("RESTORED yes" in t, "tui: the terminal's screen and cursor are given back", t[-400:])
check(changed(w, "before", "after") == [] and not NO_INSTALL.search(calls(w)), "tui: nothing changed or installed",
      changed(w, "before", "after") or calls(w))
sys.exit(1 if fails else 0)
CHECK_INSTALLER_PY
res=$?
# a failed run keeps what each scenario printed and wrote (not the PATH folders or the clones) for a look afterwards
if [ "$res" != 0 ]; then
    mkdir -p "$KIT/jobs/failed/$NAME"
    tar -C "$D" --exclude='./*/bin' --exclude=./bin-base --exclude=./clone-src --exclude='./*/clone/[!s]*' -cf - . |
        tar -C "$KIT/jobs/failed/$NAME" -xf -
    echo "kept: $KIT/jobs/failed/$NAME"
fi
python3 -I "$KIT/common/guard.py" verify "$NAME" && echo "PASS guard: no real file changed" || { echo "FAIL guard: a real file changed"; res=1; }
exit $res
