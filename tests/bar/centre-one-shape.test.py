"""bar/centre-one-shape.test.py: the centre island is drawn as one shape in every state.

Tier 4 (cosmetic), kept because it is a standing requirement of the shell (each island is one single shape): a
second drawing that swaps in while the island moves, or at rest, shows as a seam, a jump of the outline or a corner
drawn as its own piece (a fallback drawing while it opens, or a rectangle plus separate corner pieces at rest).

Also, the island grows around its content: the clock, the widgets beside it and the control centre never move on
screen while it opens or closes (two separately rounded centrings flip it by a pixel every frame). At rest (closed,
open, and closed with the volume peek row) every shown content item lies inside the outline: a geometry check
(Shape.contains), never pixels.

Every frame of a hover open and close is recorded (the driver's frame recorder; a skipped frame or a missed change
fails the check, never passes it). On every frame exactly one visible drawing item may draw the island: one Shape
with one ShapePath, with the same path elements on every frame. The island's content (the widgets beside the clock,
the volume peek and the control centre) is not part of the outline and is not counted. Settings rows are written to
the run copy's settings file, which the shell reloads. A slot's card is checked in centre-cards.test.py; the probes
both use are in centre_probes.py."""
import json
import sys
import time
from pathlib import Path

from ui import Input, check, done, recording_gaps
# the probes shared with centre-cards.test.py sit beside this test (the runner puts only the kit's ui on the path)
sys.path.insert(0, str(Path(sys.argv[0]).resolve().parent))
from centre_probes import (PROBE, INSIDE, NAMES, TOML, toml, launch, press_key, centre_x, closed_at_rest, record,
                           shrinks, steps)

# The content is drawn as the outline's fill and nowhere else: the one path's fillItem is a texture provider that
# draws its source live, at a real size, with the source hidden from the window, and the source holds the clock, the
# widgets beside it, the peek row and the control centre. This is what lets LIFTED count content under the source as
# cut to the outline. Returns the problems found.
FILL = """(function () {
  const c = Popouts.byName["clock"][0];
  let shape = null;
  const findShape = it => { if (shape) return; if (it.visible && it.rendererType !== undefined && it.containsMode !== undefined) { shape = it; return; }
    for (let i = 0; i < it.children.length; i++) findShape(it.children[i]); };
  findShape(c.contentItem);
  if (!shape) return ["no outline shape"];
  let fill = null;
  for (let i = 0; i < shape.data.length; i++) if (String(shape.data[i]).startsWith("QQuickShapePath")) fill = shape.data[i].fillItem;
  if (!fill) return ["the path has no fillItem"];
  const out = [];
  if (fill.sourceItem === undefined || fill.hideSource !== true) out.push("the fill is not a hidden source (" + String(fill).split("(")[0] + ")");
  if (fill.live !== true) out.push("the fill does not follow its source (live off)");
  const src = fill.sourceItem;
  if (!src || src.width < shape.width || src.height < 1) out.push("the source does not cover the outline");
  let clock = null;
  const find = it => { if (!clock && String(it).startsWith("QQuickText") && it.text === c.title) clock = it; for (let i = 0; i < it.children.length && !clock; i++) find(it.children[i]); };
  find(c.contentItem);
  const under = it => { for (let p = it; p; p = p.parent) if (p === src) return true; return false; };
  const parts = { clock: clock, left: c.leftItem, right: c.rightItem, peek: c.peek, leftCol: c.leftSide, midCol: c.middleItem, rightCol: c.rightSide };
  for (const k in parts) if (parts[k] && !under(parts[k])) out.push(k + " is not in the fill source");
  return out;
})()"""

# While a tile, tool or slot widget is lifted by hover (Lift: scaled, maybe tilted, with a soft shadow), what it draws
# stays inside the outline: the lifted surface at its drawn size (mapToItem includes scale and transform) and its
# shadow, the RectangularShadow's rect grown by its live blur on every side and moved by its offset. A point that a
# clipping ancestor cuts off is not drawn; content drawn only through the outline's fill (its ShapePath.fillItem, a
# source hidden from the window) is cut to the outline. Returns the lifted count and the problems.
LIFTED = """(function () {
  const c = Popouts.byName["clock"][0];
  let shape = null;
  const findShape = it => { if (shape) return; if (it.visible && it.rendererType !== undefined && it.containsMode !== undefined) { shape = it; return; }
    for (let i = 0; i < it.children.length; i++) findShape(it.children[i]); };
  findShape(c.contentItem);
  if (!shape) return { error: "no outline shape" };
  let fill = null;
  for (let i = 0; i < shape.data.length; i++) if (String(shape.data[i]).startsWith("QQuickShapePath") && shape.data[i].fillItem) fill = shape.data[i].fillItem;
  const src = fill && fill.hideSource && fill.sourceItem ? fill.sourceItem : null;
  const under = (it, anc) => { for (let p = it; p; p = p.parent) if (p === anc) return true; return false; };
  const clips = it => { const out = []; for (let p = it.parent; p; p = p.parent) if (p.clip) out.push(p); return out; };
  const shown = it => { let o = 1; for (let p = it; p; p = p.parent) { if (!p.visible) return false; o *= p.opacity; } return o > 0.01; };
  const lifts = [];
  const walk = it => { if (it.peak !== undefined && it.maxPx !== undefined && it.area !== undefined && it.amount !== undefined) lifts.push(it);
    for (let i = 0; i < it.children.length; i++) walk(it.children[i]); };
  walk(c.contentItem);
  const problems = [];
  const test = (label, item, r) => {
    if (src && under(item, src)) return;
    const cl = clips(item);
    const e = 0.37, n = Math.max(2, Math.ceil(r.width / 4)), m = Math.max(2, Math.ceil(r.height / 4)), pts = [];
    for (let i = 0; i <= n; i++) { const x = r.x + e + (r.width - 2 * e) * i / n; pts.push([x, r.y + e], [x, r.y + r.height - e]); }
    for (let j = 0; j <= m; j++) { const y = r.y + e + (r.height - 2 * e) * j / m; pts.push([r.x + e, y], [r.x + r.width - e, y]); }
    let bad = 0, first = null;
    for (const p of pts) {
      if (cl.some(k => { const q = item.mapToItem(k, p[0], p[1]); return q.x < 0 || q.y < 0 || q.x > k.width || q.y > k.height; })) continue;
      const q = item.mapToItem(shape, p[0], p[1]);
      if (!shape.contains(Qt.point(q.x, q.y))) { bad++; if (!first) first = [Math.round(q.x), Math.round(q.y)]; }
    }
    if (bad) problems.push(label + ": " + bad + " of " + pts.length + " points outside, first at " + first);
  };
  let lifted = 0;
  for (const l of lifts) {
    if (l.amount <= 0.01 || !shown(l.target)) continue;
    lifted++;
    const p = l.target.mapToItem(null, 0, 0);
    const name = String(l.target).split("(")[0].replace(/_QMLTYPE_\\d+$/, "") + "@" + Math.round(p.x) + "," + Math.round(p.y);
    test(name + " lifted", l.target, l.area);
    let sh = null;
    const findSh = it => { if (sh) return; if (it.blur !== undefined && it.offset !== undefined && it.spread !== undefined) { sh = it; return; }
      for (let i = 0; i < it.children.length; i++) findSh(it.children[i]); };
    for (let i = 0; i < l.children.length; i++) findSh(l.children[i]);
    if (sh) test(name + " shadow", sh, Qt.rect(sh.offset.x - sh.blur, sh.offset.y - sh.blur, sh.width + 2 * sh.blur, sh.height + 2 * sh.blur));
  }
  return { lifted: lifted, problems: problems };
})()"""

# the hover sweep: every visible lifting item of the open island, by the centre of its surface on screen; an item
# whose own `lift` switch is off (a passive readout such as the audio levels) does not lift by design
TARGETS = """(function () {
  const c = Popouts.byName["clock"][0];
  const shown = it => { let o = 1; for (let p = it; p; p = p.parent) { if (!p.visible) return false; o *= p.opacity; } return o > 0.01; };
  const off = it => { for (let p = it.target, k = 0; p && k < 5; p = p.parent, k++) if (p.lift === false) return true; return false; };
  const out = [];
  const walk = it => { if (it.peak !== undefined && it.maxPx !== undefined && it.area !== undefined && it.amount !== undefined && shown(it.target)
                           && it.area.width > 0 && it.area.height > 0 && !off(it)) {
      const p = it.target.mapToItem(null, it.area.x + it.area.width / 2, it.area.y + it.area.height / 2);
      out.push([c.margins.left + p.x, c.margins.top + p.y]); }
    for (let i = 0; i < it.children.length; i++) walk(it.children[i]); };
  walk(c.contentItem);
  return out;
})()"""

ROWS = [
    ("default settings, 260 ms", {"sleepybar": {"islandAnimMs": 260}}),
    ("default settings", {}),
    ("uneven off", {"centre-island": {"centreUneven": False}}),
    ("step off", {"centre-island": {"centreStep": False}}),
    ("no widgets beside the clock", {"centre-island": {"centreSysinfo": False, "centreAudio": False}}),
    ("CPU/memory hidden", {"centre-island": {"centreSysinfo": False}}),
    ("audio hidden", {"centre-island": {"centreAudio": False}}),
]
s = launch(sys.argv[1])


def inside(label):
    got = s.js(INSIDE)
    out = {k: v for k, v in got.items() if v != "inside"} if isinstance(got, dict) else got
    check(isinstance(got, dict) and got and not out, f"{label}: the content lies inside the outline ({len(got) if isinstance(got, dict) else 0} items)",
          json.dumps(out))
cx = centre_x(s)
probe = s.js(PROBE)
if not check(isinstance(probe, dict) and "sig" in probe, "the probe reads the island", json.dumps(probe)[:400]):
    s.stop()
    done()

for name, row in ROWS:
    TOML.write_text(toml(row))
    want = {**{"centreUneven": True, "centreStep": True, "centreSysinfo": True, "centreAudio": True},
            **row.get("centre-island", {})}
    ms = row.get("sleepybar", {}).get("islandAnimMs", 800)
    ok = s.wait(lambda: s.js("(function () { return [Settings.centreUneven, Settings.centreStep, Settings.centreSysinfo, Settings.centreAudio, Settings.islandAnimMs, Settings.peekMs]; })()")
                == [want["centreUneven"], want["centreStep"], want["centreSysinfo"], want["centreAudio"], ms, 3000], 5)
    if not check(ok, f"[{name}] the settings row is loaded"):
        continue
    time.sleep(0.4)
    bad = s.js(FILL)
    check(bad == [], f"[{name}] the content is drawn as the outline's fill and nowhere else", json.dumps(bad))
    inside(f"[{name}] closed")
    for phase, point in (("open", (cx, 12)), ("close", (200, 1300))):
        s.record_start(PROBE, "Popouts.byName['clock'][0]", "progress")
        Input.move(*point)
        time.sleep(ms / 1000 + 0.6)
        rows = s.record_stop()
        gaps = recording_gaps(rows)
        check(not gaps, f"[{name}] {phase}: the recording has every frame and every change", "; ".join(gaps[:4]))
        sigs = [r[2]["sig"] for r in rows]
        kinds = sorted(set(sigs))
        one = all(isinstance(x, str) and x.startswith("Shape[") and " " not in x and "|" not in x for x in kinds)
        check(len(kinds) == 1 and one, f"[{name}] {phase}: one shape with one path on every frame ({len(rows)} frames)",
              " / ".join(f"{k} x{sigs.count(k)}" for k in kinds))
        # content still: the island grows around its content, which never moves on screen while it does
        moved = {}
        for key in rows[0][2]["pos"]:
            seen = [tuple(r[2]["pos"][key]) for r in rows if r[2]["pos"][key] is not None]
            if len(set(seen)) > 1:
                xs = [p[0] for p in seen]
                dxs = [b - a for a, b in zip(xs, xs[1:]) if b != a]
                rev = sum(1 for a, b in zip(dxs, dxs[1:]) if (a > 0) != (b > 0))
                moved[key] = f"{len(set(seen))} positions, {rev} reversals"
        check(not moved, f"[{name}] {phase}: the content stays still on screen while the island moves", json.dumps(moved))
        if phase == "open":
            inside(f"[{name}] open")
    press_key()
    shown = s.wait(lambda: s.js("(function () { const c = Popouts.byName['clock'][0]; return c.showPeek && c.peek.visible; })()") is True, 2)
    if check(shown, f"[{name}] a key press shows the volume peek row"):
        time.sleep(ms / 1000 + 0.3)   # the outline grows for the peek on the islands' clock
        inside(f"[{name}] closed with the volume peek")
    s.wait(lambda: s.js("OsdState.shown") is False, 5)
    time.sleep(0.4)

# input only where the island is drawn: closed and stepped, the empty corner under a side's bottom edge (inside the
# surface, outside the outline) lets the pointer through, so resting there does not open the island
TOML.write_text(toml({"sleepybar": {"islandAnimMs": 260}}))
s.wait(lambda: s.js("Settings.islandAnimMs") == 260, 5)
s.wait(lambda: s.js("Popouts.byName['clock'][0].progress") == 0, 3)
corner = s.js("""(function () {
  const c = Popouts.byName["clock"][0];
  let shape = null;
  const findShape = it => { if (shape) return; if (it.visible && it.rendererType !== undefined && it.containsMode !== undefined) { shape = it; return; }
    for (let i = 0; i < it.children.length; i++) findShape(it.children[i]); };
  findShape(c.contentItem);
  const side = c.leftItem && c.leftItem.visible ? c.leftItem : c.rightItem;
  const p = side.mapToItem(shape, side.width / 2, side.height);
  for (let y = Math.ceil(p.y) + 2; y < c.height - 2; y++)
    if (!shape.contains(Qt.point(p.x, y))) return [c.margins.left + Math.round(p.x), c.margins.top + y, c.height];
  return null;
})()""")
if check(corner is not None, "the closed, stepped island has an empty corner under a side inside its surface", json.dumps(corner)):
    Input.move(corner[0], corner[1] + 2)
    time.sleep(0.8)
    check(s.js("Popouts.byName['clock'][0].open") is False, "resting the pointer in that corner does not open the island",
          json.dumps(corner))
# hover sweep, default settings: each lifting item in turn, sampled through the lift's ease and at rest
Input.move(cx, 12)
opened = s.wait(lambda: s.js("Popouts.byName['clock'][0].progress") == 1, 3)
targets = s.js(TARGETS) if opened else []
if check(opened and len(targets) >= 5, f"hover sweep: the open island has lifting items to hover ({len(targets)})"):
    problems, missed = {}, []
    for x, y in targets:
        Input.move(round(x), round(y))
        most = 0
        for wait in (0.06, 0.06, 0.08, 0.25):
            time.sleep(wait)
            got = s.js(LIFTED)
            most = max(most, got.get("lifted", 0))
            if got.get("problems"):
                problems.setdefault(f"hovering {round(x)},{round(y)}", got["problems"][0])
        if most == 0:
            missed.append([round(x), round(y)])
    check(not missed, "hover sweep: every hovered item lifts", json.dumps(missed[:6]))
    check(not problems, f"hover sweep: lifted items and their shadows show only inside the outline, inside it or cut "
                        f"by the fill ({len(targets)} items)",
          f"{len(problems)} hovers: " + "; ".join(f"{k}: {v}" for k, v in list(problems.items())[:4]))
    # open, the empty corner under a shorter side column lets the pointer through too: resting there is leaving the
    # panel, which closes it after the hover-close delay
    under_side = s.js("""(function () {
      const c = Popouts.byName["clock"][0];
      let shape = null;
      const findShape = it => { if (shape) return; if (it.visible && it.rendererType !== undefined && it.containsMode !== undefined) { shape = it; return; }
        for (let i = 0; i < it.children.length; i++) findShape(it.children[i]); };
      findShape(c.contentItem);
      const side = c.leftSide;
      const p = side.mapToItem(shape, side.width / 2, side.height);
      for (let y = Math.ceil(p.y) + 2; y < c.height - 2; y++)
        if (!shape.contains(Qt.point(p.x, y))) return [c.margins.left + Math.round(p.x), c.margins.top + y, Settings.hoverCloseMs];
      return null;
    })()""")
    if check(under_side is not None, "the open island has an empty corner under a side column inside its surface",
             json.dumps(under_side)):
        Input.move(under_side[0], under_side[1] + 2)
        closed = s.wait(lambda: s.js("Popouts.byName['clock'][0].open") is False, under_side[2] / 1000 + 1.5)
        check(closed, "resting the pointer in that corner closes the open island", json.dumps(under_side))
Input.move(200, 1300)

# One clock: the outline only grows while the island opens, also when the volume peek shows at that moment (the
# peek's own shrink must not pull the clock part in), and a reversal halfway continues from where the outline is,
# never faster than an opening moves.
TOML.write_text(toml({}))
s.wait(lambda: s.js("Settings.islandAnimMs") == 800, 5)


closed_at_rest(s)
plain = record(s, "one clock, opening", [(cx, 12, 1.4)])
bad = shrinks(plain)
check(not bad, f"one clock, opening: the outline only grows ({len(plain)} frames)", "; ".join(bad[:4]))
# and it grows gradually, not in one jump: the bottom under the clock takes a new value on most frames of the motion
moving = len({round(r[2][0], 1) for r in plain})
check(moving >= 20, f"one clock, opening: the outline moves over many frames ({moving} distinct depths)")
closed_at_rest(s)
press_key()
if check(s.wait(lambda: s.js("Popouts.byName['clock'][0].showPeek") is True, 2), "one clock: a key press shows the volume peek"):
    time.sleep(0.6)
    peek = record(s, "one clock, opening during the peek", [(cx, 12, 1.4)])
    bad = shrinks(peek)
    check(not bad, f"one clock, opening while the volume peek shows: the outline only grows ({len(peek)} frames)",
          "; ".join(bad[:4]))
closed_at_rest(s)
s.wait(lambda: s.js("OsdState.shown") is False, 5)
# leaving starts the close after the hover-close delay: leave so the turn comes about halfway through the 800 ms
leave = max(0.05, 0.4 - s.js("Settings.hoverCloseMs") / 1000)
back = record(s, "one clock, reversing halfway", [(cx, 12, leave), (200, 1300, 1.6)])
check(len(back) > 10 and max(r[2][0] for r in back) < max(r[2][0] for r in plain) - 20,
      "one clock, reversing halfway: the island turned back before it was open", f"left after {leave:.2f} s")
limit, got = steps(plain), steps(back)
fast = [f"{NAMES[k]}: {got[k]:.1f} px in one frame (opening: {limit[k]:.1f})" for k in range(len(NAMES))
        if got[k] > 1.5 * limit[k] + 1]
check(not fast, "one clock, reversing halfway: the outline turns back without a jump", "; ".join(fast))
# it turns once: the bottom under the clock goes down, then up, never back and forth
ds = [b[2][0] - a[2][0] for a, b in zip(back, back[1:]) if abs(b[2][0] - a[2][0]) > 0.06]
turns = sum(1 for a, b in zip(ds, ds[1:]) if (a > 0) != (b > 0))
check(turns == 1, f"one clock, reversing halfway: the outline turns back exactly once ({turns} turns)")
closed_at_rest(s)


env_errors = ("pipewire", "quickshell.network", "Network will not work")
errs = [e for e in s.errors() if not any(x in e for x in env_errors)]
check(not errs, "no QML errors", "; ".join(errs[:3]))
s.stop()
done()
