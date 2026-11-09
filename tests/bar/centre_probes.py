"""Probes and helpers shared by the centre island's tests (centre-one-shape.test.py, centre-cards.test.py): the driver
code that reads the island's outline and content, the settings rows, and the launch with the stand-in Caps Lock LED
that flashes the volume peek. Not a test itself (the runner takes only *.test.py / *.test.sh)."""
import json
import time

from ui import Shell, Input, check, recording_gaps, RUN

DRAWING = ("QQuickImage", "QQuickCanvasItem")   # besides Shapes and Rectangles, found by their properties
# the drawing items of the centre island, outside its content: [type, element types of each ShapePath]
PROBE = """(function () {
  const c = Popouts.byName["clock"][0];
  const content = [c.leftItem, c.rightItem, c.peek].concat(Array.from(c.content || [])).filter(x => x);
  // a slot card's content is content too (its panel and fill are not: they count)
  for (const n in Popouts.byName) for (const d of Popouts.byName[n]) if (d.panel && d.content) Array.from(d.content).forEach(x => x && content.push(x));
  // a source hidden from the window and used as a path's fill draws only through that path
  const fills = [];
  const findFills = it => { for (let i = 0; i < (it.data ? it.data.length : 0); i++) { const d = it.data[i];
      if (String(d).startsWith("QQuickShapePath") && d.fillItem && d.fillItem.hideSource && d.fillItem.sourceItem) fills.push(d.fillItem.sourceItem); }
    for (let i = 0; i < it.children.length; i++) findFills(it.children[i]); };
  findFills(c.contentItem);
  const inContent = it => { for (let p = it; p; p = p.parent) if (content.indexOf(p) >= 0) return true; return false; };
  // inside a fill source only its backdrop (a Rectangle as big as the source) is exempt: every other drawing item
  // there still counts
  const backdrop = it => fills.indexOf(it.parent) >= 0 && it.border !== undefined && it.radius !== undefined
                         && it.width === it.parent.width && it.height === it.parent.height;
  const out = [];
  const walk = it => {
    if (inContent(it)) return;
    // by what an item is, not its type name: a QML type built on a Shape or a Rectangle has its own name
    const t = String(it).split("(")[0];
    const kind = it.rendererType !== undefined && it.containsMode !== undefined ? "Shape"
               : it.border !== undefined && it.radius !== undefined ? "Rectangle"   // (gradient reads undefined when unset)
               : %s.indexOf(t) >= 0 ? t.replace("QQuick", "") : null;
    if (it.visible && it.width > 0 && it.height > 0 && kind && !backdrop(it)) {
      let sig = kind;
      if (kind === "Shape") {
        const paths = [];
        for (let i = 0; i < it.data.length; i++)
          if (String(it.data[i]).startsWith("QQuickShapePath")) {
            const els = [];
            for (let k = 0; k < it.data[i].pathElements.length; k++) els.push(String(it.data[i].pathElements[k]).split("(")[0].replace("QQuickPath", "").charAt(0));
            paths.push(els.join(""));
          }
        sig += "[" + paths.join("|") + "]";
      }
      out.push(sig);
    }
    for (let i = 0; i < it.children.length; i++) walk(it.children[i]);
  };
  walk(c.contentItem);
  // where the content is on screen: the clock text, the widgets beside it, the control centre and its columns
  let clock = null;
  const find = it => { if (!clock && String(it).startsWith("QQuickText") && it.text === c.title) clock = it; for (let i = 0; i < it.children.length && !clock; i++) find(it.children[i]); };
  find(c.contentItem);
  const at = it => { if (!it) return null; const p = it.mapToItem(null, 0, 0); return [p.x, p.y]; };
  const body = Array.from(c.content || []).find(x => x && typeof x.mapToItem === "function") || null;
  return { sig: out.join(" "), pos: { clock: at(clock), left: c.leftItem && c.leftItem.visible ? at(c.leftItem) : null,
           right: c.rightItem && c.rightItem.visible ? at(c.rightItem) : null, body: at(body),
           leftCol: at(c.leftSide), midCol: at(c.middleItem), rightCol: at(c.rightSide) } };
})()""" % json.dumps(list(DRAWING))

# at rest, every shown content item lies inside the outline: points every 4 px along its edges, mapped into the
# outline Shape, must be inside its fill (Shape.contains, geometry, never pixels). Points sit 0.37 px in from the edge:
# contains() miscounts a point exactly on a horizontal edge's y.
INSIDE = """(function () {
  const c = Popouts.byName["clock"][0];
  let shape = null;
  const findShape = it => { if (shape) return; if (it.visible && it.rendererType !== undefined && it.containsMode !== undefined) { shape = it; return; }
    for (let i = 0; i < it.children.length; i++) findShape(it.children[i]); };
  findShape(c.contentItem);
  if (!shape) return { error: "no outline shape" };
  const seen = it => { let o = 1; for (let p = it; p; p = p.parent) { if (!p.visible) return false; o *= p.opacity; } return o > 0.01; };
  let clock = null;
  const find = it => { if (!clock && String(it).startsWith("QQuickText") && it.text === c.title) clock = it; for (let i = 0; i < it.children.length && !clock; i++) find(it.children[i]); };
  find(c.contentItem);
  const items = { clock: clock, left: c.leftItem, right: c.rightItem, peek: c.peek, leftCol: c.leftSide, midCol: c.middleItem, rightCol: c.rightSide };
  const out = {};
  for (const k in items) {
    const it = items[k];
    if (!it || !seen(it) || it.width <= 0 || it.height <= 0) continue;
    const e = 0.37, n = Math.max(2, Math.ceil(it.width / 4)), m = Math.max(2, Math.ceil(it.height / 4)), pts = [];
    for (let i = 0; i <= n; i++) { const x = e + (it.width - 2 * e) * i / n; pts.push([x, e], [x, it.height - e]); }
    for (let j = 0; j <= m; j++) { const y = e + (it.height - 2 * e) * j / m; pts.push([e, y], [it.width - e, y]); }
    let bad = 0, first = null;
    for (const p of pts) { const q = it.mapToItem(shape, p[0], p[1]); if (!shape.contains(Qt.point(q.x, q.y))) { bad++; if (!first) first = [Math.round(q.x), Math.round(q.y)]; } }
    out[k] = bad ? bad + " of " + pts.length + " edge points outside, first at " + first : "inside";
  }
  return out;
})()"""

# The outline at the clock part, read from the Shape's own geometry (contains, boundingRect): the bottom under the
# clock, the left and right edges at the clock text's bottom (binary search to 0.05 px), and the bounding box
# [x, width, height]. Points sit off the whole and half pixel (contains() miscounts a point exactly on an edge).
CLOCKPART = """(function () {
  const c = Popouts.byName["clock"][0];
  let shape = null;
  const findShape = it => { if (shape) return; if (it.visible && it.rendererType !== undefined && it.containsMode !== undefined) { shape = it; return; }
    for (let i = 0; i < it.children.length; i++) findShape(it.children[i]); };
  findShape(c.contentItem);
  let clock = null;
  const find = it => { if (!clock && String(it).startsWith("QQuickText") && it.text === c.title) clock = it; for (let i = 0; i < it.children.length && !clock; i++) find(it.children[i]); };
  find(c.contentItem);
  const p = clock.mapToItem(shape, clock.width / 2, clock.height);
  const x = p.x + 0.2917, y = p.y + 2.3719;
  const at = (a, b) => shape.contains(Qt.point(a, b));
  const edge = (inside, outside, probe) => { let a = inside, b = outside; while (Math.abs(b - a) > 0.05) { const m = (a + b) / 2; if (probe(m)) a = m; else b = m; } return a; };
  const bottom = edge(1.3719, shape.height + 1, v => at(x, v));
  const left = edge(x, -1, v => at(v, y));
  const right = edge(x, shape.width + 1, v => at(v, y));
  const b = shape.boundingRect;
  return [bottom, left, right, b.x, b.width, b.height];
})()"""
NAMES = ["bottom under the clock", "left edge at the clock", "right edge at the clock", "box left", "box width",
         "box height"]
GROWS = [1, -1, 1, -1, 1, 1]   # the direction each value may move while the island opens


def shrinks(rows):
    """Frames where the outline at the clock part moved against its opening direction (more than the search's
    0.05 px), as 'name: a -> b at frame n'."""
    out = []
    for a, b in zip(rows, rows[1:]):
        for k, sign in enumerate(GROWS):
            if (b[2][k] - a[2][k]) * sign < -0.06:
                out.append(f"{NAMES[k]}: {a[2][k]:.2f} -> {b[2][k]:.2f} at frame {b[0]}")
    return out


def steps(rows):
    """The largest frame-to-frame move of each value."""
    return [max((abs(b[2][k] - a[2][k]) for a, b in zip(rows, rows[1:])), default=0) for k in range(len(NAMES))]


# A slot's card (its IslandDropdown, opened by `toggle <name>`): where it is drawn and whether its content lies inside
# the centre island's one outline. NAME is the dropdown's Popouts name; the one whose anchor is a centre slot is used.
CARD = """(function () {
  const c = Popouts.byName["clock"][0];
  const d = (Popouts.byName["NAME"] || []).find(x => x.anchorItem && (x.anchorItem === c.leftItem || x.anchorItem === c.rightItem)) || null;
  if (!d) return { error: "no NAME dropdown in a centre slot" };
  let shape = null;
  const findShape = it => { if (shape) return; if (it.visible && it.rendererType !== undefined && it.containsMode !== undefined) { shape = it; return; }
    for (let i = 0; i < it.children.length; i++) findShape(it.children[i]); };
  findShape(c.contentItem);
  const under = (it, anc) => { for (let p = it; p; p = p.parent) if (p === anc) return true; return false; };
  const inCentre = under(d.panel, c.contentItem);
  // what the bar's own drop layer draws (visible children with a size)
  const barDraws = [];
  const bl = c.bar.dropLayer;
  for (let i = 0; i < bl.children.length; i++) { const k = bl.children[i]; if (k.visible && k.width > 0 && k.height > 0) barDraws.push(String(k).split("(")[0]); }
  // the side it hangs on, on screen: the card's centre against the clock's
  let clock = null;
  const find = it => { if (!clock && String(it).startsWith("QQuickText") && it.text === c.title) clock = it; for (let i = 0; i < it.children.length && !clock; i++) find(it.children[i]); };
  find(c.contentItem);
  const px = d.panel.mapToItem(null, d.panel.width / 2, 0).x + (inCentre ? c.margins.left : 0);
  const cx = clock.mapToItem(null, clock.width / 2, 0).x + c.margins.left;
  // its content's edge points, inside the outline (only meaningful in the centre's window)
  const outside = [];
  if (inCentre)
    for (const it of Array.from(d.content || [])) {
      if (!it || typeof it.mapToItem !== "function" || !it.visible || it.width <= 0 || it.height <= 0) continue;
      const e = 0.37, n = Math.max(2, Math.ceil(it.width / 4)), m = Math.max(2, Math.ceil(it.height / 4));
      let bad = 0;
      for (let i = 0; i <= n; i++) for (const y of [e, it.height - e]) { const q = it.mapToItem(shape, e + (it.width - 2 * e) * i / n, y); if (!shape.contains(Qt.point(q.x, q.y))) bad++; }
      for (let j = 0; j <= m; j++) for (const x of [e, it.width - e]) { const q = it.mapToItem(shape, x, e + (it.height - 2 * e) * j / m); if (!shape.contains(Qt.point(q.x, q.y))) bad++; }
      if (bad) outside.push(String(it).split("(")[0] + ": " + bad + " edge points");
    }
  return { open: d.open, current: Popouts.current === d, inCentre: inCentre, barDraws: barDraws,
           slot: d.anchorItem === c.leftItem ? "left" : "right", hangs: px < cx ? "left" : "right", outside: outside };
})()"""

TOML = RUN / "s/sleepysettings.toml"


def toml(row):
    """The run copy's settings file for a row {section: {key: value}}, over the tests' defaults (the islands' clock
    at 800 ms, the peek held 3 s)."""
    secs = {"sleepybar": {"islandAnimMs": 800, "peekMs": 3000}}
    for sec, kv in row.items():
        secs.setdefault(sec, {}).update(kv)
    lines = []
    for sec, kv in secs.items():
        lines.append(f"[{sec}]")
        for k, v in kv.items():
            lines.append(f"{k} = {json.dumps(v)}" if not isinstance(v, bool) else f"{k} = {'true' if v else 'false'}")
    return "\n".join(lines) + "\n"


# the volume peek row is shown the way a key press shows it: the stand-in Caps Lock LED changes
LED = RUN / "leds/input3::capslock/brightness"


def launch(tree):
    """The shell on the test screen with the stand-in Caps Lock LED, past the 2 s the peek is held back after start."""
    LED.parent.mkdir(parents=True)
    LED.write_text("0\n")
    s = Shell.launch(tree, "shell.qml", env={"SLEEPYSHELL_TEST_LEDS": str(RUN / "leds")})
    time.sleep(2.5)
    return s


def press_key():
    """A Caps Lock press, which flashes the peek row."""
    LED.write_text("1\n" if LED.read_text() == "0\n" else "0\n")


def centre_x(s):
    """The middle of the centre island's clock on screen (hovering there opens the island)."""
    return s.js("""(function () {
      const c = Popouts.byName["clock"][0];
      let clock = null;
      const find = it => { if (!clock && String(it).startsWith("QQuickText") && it.text === c.title) clock = it; for (let i = 0; i < it.children.length && !clock; i++) find(it.children[i]); };
      find(c.contentItem);
      return c.margins.left + clock.mapToItem(null, clock.width / 2, 0).x;
    })()""")


def closed_at_rest(s):
    Input.move(200, 1300)
    s.wait(lambda: s.js("Popouts.byName['clock'][0].progress") == 0, 4)
    time.sleep(0.4)


def record(s, label, moves):
    """Record the clock part on every frame while the pointer makes `moves` [(x, y, seconds after)]."""
    s.record_start(CLOCKPART, "Popouts.byName['clock'][0]", "progress")
    for x, y, wait in moves:
        Input.move(x, y)
        time.sleep(wait)
    rows = s.record_stop()
    gaps = recording_gaps(rows)
    check(not gaps, f"{label}: the recording has every frame and every change", "; ".join(gaps[:4]))
    return rows
