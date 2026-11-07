#!/usr/bin/python3 -I
"""Stand-ins for the programs install.sh runs, for tests/install/installer.test.sh (linked under each name).

Every call is logged to $STUB_DIR/calls.log as one line "name arg arg ...". Nothing real is ever installed, enabled or
started: the package database is three files in $STUB_DIR (installed: "name explicit|dependency repo|aur" lines; repo:
the names the repositories have), the running units are $STUB_DIR/active. Behaviour per name:

  pacman      -T PKG...      prints the ones not installed (exit 127 when any)
              -Si PKG        exit 0 when the repositories have it
              -Qq / -Qqe P / -Qqm P   installed names / P is explicit / P is from the AUR
              -S --needed P...        only "as root" (through the sudo stand-in): adds them; quickshell brings
                                      qt6-declarative as a dependency. $STUB_DIR/interrupt-after-pacman sends the
                                      installer SIGINT afterwards (Ctrl+C). $STUB_DIR/pacman-fail makes it fail; the path in
                                      $STUB_DIR/touch-during-pacman gets a line appended (a file edited meanwhile)
  sudo        logs, then runs pacman and systemctl stand-ins as root; anything else is only logged
  paru, yay   -S --needed P...  adds them from the AUR
  git         clone URL DIR      makes DIR
  makepkg     -si               installs paru-bin and links paru into $STUB_BIN
  systemctl   [--user] is-active [--quiet] UNIT   by $STUB_DIR/active ("user:UNIT" for --user);
              [--user] enable --now UNIT          adds it there; anything else exit 0
  hyprctl     version -j        Hyprland $STUB_HYPR_VER (default 0.57.1)
  qs          -c sleepyshell -d   a process whose command line is "qs -c sleepyshell -d" (it waits on a pipe), so
                                  install.sh sees the shell running; its pid in $STUB_DIR/qs.pid (inner.sh stops it when
                                  the scenario ends, so the next world starts without a shell)
  others      logged, exit 0
"""
import json
import os
import sys
from pathlib import Path

name = os.path.basename(sys.argv[0])
args = sys.argv[1:]
D = Path(os.environ["STUB_DIR"])
with open(D / "calls.log", "a") as f:
    f.write(" ".join([("ROOT " if os.environ.get("STUB_ROOT") else "") + name] + args) + "\n")


def read_db():
    db = {}
    p = D / "installed"
    if p.exists():
        for line in p.read_text().split("\n"):
            parts = line.split()
            if parts:
                db[parts[0]] = (parts[1], parts[2])
    return db


def write_db(db):
    (D / "installed").write_text("".join(f"{k} {v[0]} {v[1]}\n" for k, v in sorted(db.items())))


def repo():
    p = D / "repo"
    return set(p.read_text().split()) if p.exists() else set()


def add(pkgs, src):
    db = read_db()
    for p in pkgs:
        if p not in db:
            db[p] = ("explicit", src)
            if p == "quickshell":
                db.setdefault("qt6-declarative", ("dependency", "repo"))
    write_db(db)


def active():
    p = D / "active"
    return set(p.read_text().split()) if p.exists() else set()


if name == "pacman":
    db = read_db()
    flags = [a for a in args if a.startswith("-")]
    pkgs = [a for a in args if not a.startswith("-")]
    if "-T" in flags:
        # what another package provides, as pacman knows it (paru-bin provides paru)
        provides = {"paru": "paru-bin"}
        miss = [p for p in pkgs if p not in db and provides.get(p) not in db]
        print("\n".join(miss)) if miss else None
        sys.exit(127 if miss else 0)
    if "-Si" in flags:
        sys.exit(0 if pkgs and pkgs[0] in repo() else 1)
    if "-Qq" in flags:
        if not pkgs:
            print("\n".join(sorted(db)))
            sys.exit(0)
        sys.exit(0 if pkgs[0] in db else 1)
    if "-Qqe" in flags:
        sys.exit(0 if pkgs and db.get(pkgs[0], ("",))[0] == "explicit" else 1)
    if "-Qqm" in flags:
        sys.exit(0 if pkgs and db.get(pkgs[0], ("", ""))[1] == "aur" else 1)
    if "-S" in flags:
        if not os.environ.get("STUB_ROOT"):
            print("error: you cannot perform this operation unless you are root.", file=sys.stderr)
            sys.exit(1)
        if (D / "pacman-fail").exists():
            print("error: failed to commit transaction (stand-in)", file=sys.stderr)
            sys.exit(1)
        t = D / "touch-during-pacman"
        if t.exists():
            with open(t.read_text().strip(), "a") as f:
                f.write("-- edited while the installer ran\n")
        bad = [p for p in pkgs if p not in repo()]
        if bad:
            print("error: target not found: " + bad[0], file=sys.stderr)
            sys.exit(1)
        add(pkgs, "repo")
        # a user pressing Ctrl+C right after pacman: the installer (sudo's parent, sudo being exec'd) gets SIGINT
        if (D / "interrupt-after-pacman").exists():
            import signal
            os.kill(os.getppid(), signal.SIGINT)
        sys.exit(0)
    sys.exit(0)

if name == "sudo":
    if args and args[0] in ("pacman", "systemctl"):
        env = dict(os.environ, STUB_ROOT="1")
        os.execve(str(Path(os.environ["STUB_BIN"]) / args[0]), args, env)
    sys.stdin.close()
    sys.exit(0)

if name in ("paru", "yay"):
    if "-S" in args:
        add([a for a in args if not a.startswith("-")], "aur")
    sys.exit(0)

if name == "git":
    if args[:1] == ["clone"]:
        Path(args[-1]).mkdir(parents=True, exist_ok=True)
    sys.exit(0)

if name == "makepkg":
    add(["paru-bin"], "aur")
    link = Path(os.environ["STUB_BIN"]) / "paru"
    if not link.exists():
        link.symlink_to(Path(__file__).resolve())
    sys.exit(0)

if name == "systemctl":
    user = "--user" in args
    rest = [a for a in args if a not in ("--user", "--quiet", "--now")]
    if rest[:1] == ["is-active"]:
        unit = rest[1]
        sys.exit(0 if (("user:" if user else "") + unit) in active() or unit.removesuffix(".service") in active() else 3)
    if rest[:1] == ["enable"] and len(rest) > 1:
        (D / "active").write_text("\n".join(sorted(active() | {("user:" if user else "") + rest[1]})) + "\n")
    sys.exit(0)

if name == "hyprctl":
    if args[:1] == ["version"]:
        v = os.environ.get("STUB_HYPR_VER", "0.57.1")
        print(json.dumps({"branch": "v" + v, "version": v, "tag": "v" + v}, indent=4))
    else:
        print("{}")
    sys.exit(0)

if name == "qs":
    if args == ["-c", "sleepyshell", "-d"]:
        fifo = D / "qs.fifo"
        if not fifo.exists():
            os.mkfifo(fifo)
        (D / "qs.pid").write_text(str(os.getpid()))
        fd = os.open(fifo, os.O_RDWR)
        os.dup2(fd, 0)
        os.execv("/usr/bin/cat", ["qs -c sleepyshell -d"])
    sys.exit(0)

sys.exit(0)
