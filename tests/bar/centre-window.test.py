"""bar/centre-window.test.py: the centre island's window keeps its size and place, and takes the pointer only where the
island is drawn.

Tier 4 (cosmetic). On Hyprland a layer surface that is resized and moved in one change shows an old frame at the new
place for a frame or two, so a size change of the island (a corner roundness change, measured) made the closed island
shake. The island's window therefore spans the screen and never changes its width or left edge: the island is drawn
centred inside it, and every change of its size is a redraw. The kit's compositor applies such a change cleanly either
way, so the test checks the cause, the window's geometry, and not the flicker itself.

A window as wide as the screen must not take the pointer where the island is not drawn: over the side islands the
bar gets it, and over the gaps between the islands the centre island does not (it opens on hover), closed and open;
the input region it hands the compositor covers only the drawn island. And where a compositor keeps the pointer with
the window across all of it once it has entered (Hyprland does), the island still goes by where it is drawn: beside
it, the closed island does not open and the open one closes. Probes shared with the other centre tests are in
centre_probes.py."""
import json
import sys
import time
from pathlib import Path

from ui import Input, check, done
# the probes shared with the other centre tests sit beside this test (the runner puts only the kit's ui on the path)
sys.path.insert(0, str(Path(sys.argv[0]).resolve().parent))
from centre_probes import TOML, toml, launch, centre_x, closed_at_rest

# per frame: the window's width and left edge, the clock's left edge on screen, the outline's width
GEO = """(function () {
  const c = Popouts.byName["clock"][0];
  let clock = null;
  const find = it => { if (!clock && String(it).startsWith("QQuickText") && it.text === c.title) clock = it; for (let i = 0; i < it.children.length && !clock; i++) find(it.children[i]); };
  find(c.contentItem);
  let shape = null;
  const findShape = it => { if (shape) return; if (it.visible && it.rendererType !== undefined && it.containsMode !== undefined) { shape = it; return; }
    for (let i = 0; i < it.children.length; i++) findShape(it.children[i]); };
  findShape(c.contentItem);
  const r = v => Math.round(v * 100) / 100;
  return [c.width, c.margins.left, r(c.margins.left + clock.mapToItem(null, 0, 0).x), r(shape.boundingRect.width)];
})()"""

# Where the pointer goes: over each side island (the bar's islands, found by the host contract's `attach`) the middle
# of a hover area of one of its widgets, so the bar can say it has the pointer; and the middle of each gap between a
# side island and the centre island's outline. On screen.
PLACES = """(function () {
  const c = Popouts.byName["clock"][0];
  let shape = null;
  const findShape = it => { if (shape) return; if (it.visible && it.rendererType !== undefined && it.containsMode !== undefined) { shape = it; return; }
    for (let i = 0; i < it.children.length; i++) findShape(it.children[i]); };
  findShape(c.contentItem);
  const b = shape.boundingRect;
  const L = c.margins.left + shape.mapToItem(null, b.x, 0).x, R = L + b.width;
  const items = sleepytestDriver.scan().items.filter(e => e.win.info.type === "Sleepybar");
  const shown = it => { for (let p = it; p; p = p.parent) if (!p.visible) return false; return true; };
  const under = (it, anc) => { for (let p = it.parent; p; p = p.parent) if (p === anc) return true; return false; };
  const sides = [];
  for (const e of items) {
    const o = e.obj;
    if (o.attach === undefined || !shown(o) || o.width <= 0) continue;
    const p = o.mapToItem(null, 0, 0);
    const area = items.map(f => f.obj).find(m => m.hoverEnabled === true && m.containsMouse !== undefined && m.enabled
                                                && shown(m) && m.width >= 8 && m.height >= 8 && under(m, o));
    const t = area ? area.mapToItem(null, area.width / 2, area.height / 2) : null;
    sides.push({ attach: o.attach, x0: p.x, x1: p.x + o.width, target: t ? [t.x, t.y] : null });
  }
  return { L: L, R: R, sides: sides };
})()"""

# how many of the bar's hover areas have the pointer
BAR_HOVER = """(function () {
  let n = 0;
  for (const e of sleepytestDriver.scan().items) {
    const o = e.obj;
    if (e.win.info.type === "Sleepybar" && o.containsMouse === true && o.hoverEnabled === true) n++;
  }
  return n;
})()"""

OPEN = "Popouts.byName['clock'][0].open"

s = launch(sys.argv[1])
TOML.write_text(toml({"sleepybar": {"corners": "default"}}))
check(s.wait(lambda: s.js("Theme.islandRadius") == 14, 5), "the standard corners are loaded (island radius 14)")
closed_at_rest(s)

# ---- a corner roundness change while closed ----
s.record_start(GEO, "Theme", "islandRadius")
time.sleep(0.3)   # some frames before the first change, so the recording holds the state before it
for preset, radius in (("sharp", 7), ("round", 20), ("default", 14)):
    TOML.write_text(toml({"sleepybar": {"corners": preset}}))
    check(s.wait(lambda: s.js("Theme.islandRadius") == radius, 5), f"corners {preset}: the island radius is {radius}")
    time.sleep(0.6)
rows = s.record_stop()
skipped = [f"{a[0]} -> {b[0]}" for a, b in zip(rows, rows[1:]) if b[0] - a[0] != 1]
seen = [b[1] - a[1] for a, b in zip(rows, rows[1:]) if b[1] != a[1]]
check(len(rows) > 60 and not skipped and rows[0][1] == 0 and seen == [1, 1, 1],
      f"corner changes: the recording has every frame and sees each change on a frame of its own ({len(rows)} frames)",
      f"skipped {skipped[:3]}, changes per frame {seen}")
window = sorted({tuple(r[2][:2]) for r in rows})
check(len(window) == 1, "corner changes: the window keeps its width and left edge", json.dumps(window))
clock = sorted({r[2][2] for r in rows})
check(len(clock) == 1, "corner changes: the clock stays still on screen", json.dumps(clock))
widths = [r[2][3] for r in rows]
steps = [w for i, w in enumerate(widths) if i == 0 or w != widths[i - 1]]
check(len(steps) >= 4 and len(set(steps)) >= 3 and steps[0] == steps[-1],
      "corner changes: the outline takes each new corner size and ends where it began", json.dumps(steps))

# ---- the pointer where the island is not drawn ----
places = s.js(PLACES)
sides = {p["attach"]: p for p in places.get("sides", [])} if isinstance(places, dict) else {}
if check("topLeft" in sides and "topRight" in sides and sides["topLeft"]["target"] and sides["topRight"]["target"],
         "the left and right islands are found, each with a widget's hover area", json.dumps(places)[:300]):
    left, right = sides["topLeft"], sides["topRight"]
    over = {"left island": tuple(left["target"]), "right island": tuple(right["target"])}
    gaps = {"gap left of the centre": ((left["x1"] + places["L"]) / 2, 6),
            "gap right of the centre": ((places["R"] + right["x0"]) / 2, 6)}
    check(places["L"] - left["x1"] > 40 and right["x0"] - places["R"] > 40, "closed, there are gaps beside the centre island",
          json.dumps([left["x1"], places["L"], places["R"], right["x0"]]))
    for name, (x, y) in {**over, **gaps}.items():
        Input.move(round(x), round(y))
        time.sleep(0.6)
        bar = s.js(BAR_HOVER) > 0 if name in over else True
        check(bar and s.js(OPEN) is False,
              f"closed, pointer over the {name}: " + ("the bar has it, " if name in over else "") + "the centre island stays closed",
              json.dumps([round(x), round(y), s.js(BAR_HOVER), s.js(OPEN)]))
    cx = centre_x(s)
    close_s = s.js("Settings.hoverCloseMs") / 1000 + 1.5
    for name, (x, y) in {**over, **gaps}.items():
        Input.move(round(cx), 12)
        if not check(s.wait(lambda: s.js("Popouts.byName['clock'][0].progress") == 1, 3), f"open, before the {name}: hovering the clock opens the island"):
            continue
        # open, the island is wider: a gap point is taken again from the open outline
        if name in gaps:
            now = s.js(PLACES)
            x = (left["x1"] + now["L"]) / 2 if "left" in name else (now["R"] + right["x0"]) / 2
        Input.move(round(x), round(y))
        closed = s.wait(lambda: s.js(OPEN) is False, close_s)
        bar = s.js(BAR_HOVER) > 0 if name in over else True
        check(closed and bar, f"open, pointer moved over the {name}: " + ("the bar has it and " if name in over else "")
              + "the island closes as left", json.dumps([round(x), round(y), s.js(BAR_HOVER), s.js(OPEN)]))
    Input.move(200, 1300)
    closed_at_rest(s)

# ---- the input region the window hands the compositor: only the island ----
# Every rectangle of the window's input region (Region: its own rectangle, if any, and its child regions) lies within
# the drawn island's bounding box, closed and open, so the pointer and clicks beside the island go past it.
REGION = """(function () {
  const c = Popouts.byName["clock"][0];
  let shape = null;
  const findShape = it => { if (shape) return; if (it.visible && it.rendererType !== undefined && it.containsMode !== undefined) { shape = it; return; }
    for (let i = 0; i < it.children.length; i++) findShape(it.children[i]); };
  findShape(c.contentItem);
  const b = shape.boundingRect, box = [Math.floor(b.x) - 1, Math.ceil(b.x + b.width) + 1, Math.ceil(b.height) + 1];
  const rects = [];
  const add = r => { if (r.width > 0 && r.height > 0) rects.push([r.x, r.x + r.width, r.y + r.height]); };
  add(c.mask);
  for (const r of c.mask.regions) add(r);
  const out = rects.filter(r => r[0] < box[0] || r[1] > box[1] || r[2] > box[2]);
  return { box: box, rects: rects.length, outside: out };
})()"""
for state in ("closed", "open"):
    if state == "open":
        Input.move(round(centre_x(s)), 12)
        s.wait(lambda: s.js("Popouts.byName['clock'][0].progress") == 1, 3)
    got = s.js(REGION)
    check(isinstance(got, dict) and got["rects"] >= 1 and not got["outside"],
          f"{state}: the window's input region covers only the drawn island", json.dumps(got)[:300])
Input.move(200, 1300)
closed_at_rest(s)

# ---- a compositor that keeps the pointer with the window across all of it ----
# Hyprland gives a window the pointer only where its input region is, but then keeps sending it there anywhere in the
# window (measured: positions far beside the island, "left" only at the window's bottom edge). The kit's compositor
# does not, so the test widens the input region to the whole window, which has the same effect, and checks that the
# island still goes by where it is drawn. (Last in the test: the region stays widened.)
WIDEN = """(function () {
  const c = Popouts.byName["clock"][0];
  c.mask = Qt.createQmlObject("import Quickshell; Region { width: " + c.width + "; height: " + c.height + " }", c, "sleepytestWideMask");
  return [c.mask.width, c.mask.height];
})()"""
if "topLeft" in sides:
    widened = s.js(WIDEN)
    check(isinstance(widened, list) and widened[0] > 2000, "the input region is widened to the whole window", json.dumps(widened))
    gap = (round((sides["topLeft"]["x1"] + places["L"]) / 2), 6)
    Input.move(*gap)
    time.sleep(0.8)
    check(s.js(OPEN) is False, "pointer kept by the window, closed: resting beside the island does not open it",
          json.dumps(gap))
    Input.move(round(centre_x(s)), 12)
    if check(s.wait(lambda: s.js("Popouts.byName['clock'][0].progress") == 1, 3), "pointer kept by the window: hovering the clock opens the island"):
        now = s.js(PLACES)
        gap = (round((sides["topLeft"]["x1"] + now["L"]) / 2), 6)
        Input.move(*gap)
        closed = s.wait(lambda: s.js(OPEN) is False, s.js("Settings.hoverCloseMs") / 1000 + 1.0)
        check(closed, "pointer kept by the window, open: moving off the island beside it closes it within the hover-close delay",
              json.dumps(gap))
    Input.move(200, 1300)

env_errors = ("pipewire", "quickshell.network", "Network will not work")
errs = [e for e in s.errors() if not any(x in e for x in env_errors)]
check(not errs, "no QML errors", "; ".join(errs[:3]))
s.stop()
done()
