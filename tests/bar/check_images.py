"""Checks the run of bar/local-images.sh: prints one PASS or FAIL line per check, exits 1 on any FAIL.

check_images.py RUN_FOLDER ICON_NAME
Reads the harness's RESULT line from qs.log and the request counter's log (hits).
"""
import json
import sys
from pathlib import Path

D, ICON = Path(sys.argv[1]), sys.argv[2]
fails = 0


def check(ok, what, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or not detail else f": {detail}"))
    fails += 0 if ok else 1


log = (D / "qs.log").read_text(errors="replace") if (D / "qs.log").exists() else ""
line = next((ln for ln in log.splitlines() if "RESULT {" in ln), None)
if line is None:
    check(False, "the harness reported", "no RESULT line; the end of qs.log:\n" + "\n".join(log.splitlines()[-15:]))
    sys.exit(1)
res = json.loads(line[line.index("RESULT {") + 7:])
hits = [h for h in (D / "hits").read_text().splitlines() if h] if (D / "hits").exists() else []

# the method can see a fetch at all: the control image was requested
check("/control.png" in hits, "the control image was fetched (a fetch would be seen)", f"hits: {hits}")
others = [h for h in hits if h != "/control.png"]
check(not others, "no notification or tray image was fetched from the network", f"requests: {others}")

bad = [u for u in res["units"] if u[1] != u[2]]
check(not bad, f"{len(res['units'])} source rules (only local, names and paths made local)",
      "; ".join(f"{w}: got {g!r}, want {e!r}" for w, g, e in bad))

pic = "file://" + str(D / "pic.png")
name = "image://icon/" + ICON
want = {
    "remote app icon": [],
    "remote image png": [],
    "remote https ico": [],
    "file url with host": [],
    "theme name": [name],
    "local path": [pic],
    "missing image falls back": ["file:///nonexistent/sleepyshell-test.png", name],
    "remote image, local app icon": [name],
    "unknown theme name": [],
    "local file url image": [pic],
}
cards = {c["summary"]: c for c in res["cards"]}
check(set(cards) == set(want), "all ten notifications arrived", f"got {sorted(cards)}")
for summary, sources in want.items():
    c = cards.get(summary)
    if c is None:
        continue
    shown = sources[1] if summary == "missing image falls back" else (sources[0] if sources else "")
    ok = c["sources"] == sources and c["card"] == shown and c["toast"] == shown
    what = "shows the bell (no image, no checkerboard)" if not shown else f"shows {shown.split('/')[-1]}"
    check(ok, f"notification '{summary}' {what}",
          f"sources {c['sources']} (want {sources}), card {c['card']!r}, toast {c['toast']!r}, image {c['image']!r}, appIcon {c['appIcon']!r}")

trays = {t["id"]: t for t in res["tray"]}
check(set(trays) == {"remote-name", "remote-path", "theme-name"}, "the three tray items arrived", f"got {sorted(trays)}")
t = trays.get("remote-name")
if t:
    check(t["raw"].startswith("image://icon/") and t["src"] == t["raw"],
          "tray icon named by a URL stays an icon-theme lookup (local)", f"{t}")
t = trays.get("remote-path")
if t:
    check(t["src"] == "", "tray icon in a folder given as a URL is not loaded", f"{t}")
t = trays.get("theme-name")
if t:
    check(t["src"] == name, "tray icon from the theme still shows", f"{t}")

sys.exit(1 if fails else 0)
