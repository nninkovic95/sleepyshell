"""bar/centre-cards.test.py: a widget's card in the centre island's slots is one deeper part of the island's outline.

Tier 4 (cosmetic) and tier 3 (a card that will not open or close): `toggle audio` / `toggle sysinfo` open the card of
whichever slot holds that widget, drawn by the centre island as part of its one outline (not by the bar, not as a
floating card), with its content inside the outline. A click on the clock hands a card over to the control centre in
one morph. A card in a hidden slot is refused with one line in the shell log. The volume peek row needs the same room
beside the clock as a card, so it waits while a card is open. Settings rows are written to the run copy's settings
file, which the shell reloads; the probes are shared with centre-one-shape.test.py (centre_probes.py)."""
import json
import sys
import time
from pathlib import Path

from ui import Input, check, done, recording_gaps
# the probes shared with centre-one-shape.test.py sit beside this test (the runner puts only the kit's ui on the path)
sys.path.insert(0, str(Path(sys.argv[0]).resolve().parent))
from centre_probes import (PROBE, CLOCKPART, CARD, TOML, toml, launch, press_key, centre_x, closed_at_rest, record,
                           shrinks, steps)

ENV_ERRORS = ("pipewire", "quickshell.network", "Network will not work")   # the sandbox has neither service
s = launch(sys.argv[1])
cx = centre_x(s)

# a plain hover opening on the islands' 800 ms clock: its largest frame step is the measure for "without a jump"
TOML.write_text(toml({}))
s.wait(lambda: s.js("Settings.islandAnimMs") == 800, 5)
closed_at_rest(s)
plain = record(s, "a plain opening", [(cx, 12, 1.4)])
closed_at_rest(s)

# Cards: `toggle audio` / `toggle sysinfo` open the card of whichever slot holds that widget, under that slot, drawn by
# the centre island as one deeper part of its one outline (not by the bar, not as a floating card), its content inside
# the outline, the outline only growing while it opens; a second toggle closes it.
for layout, left in (("CPU/memory left", "sysinfo"), ("audio left", "audio")):
    TOML.write_text(toml({"sleepybar": {"islandAnimMs": 260}, "centre-island": {"centreLeft": left}}))
    # (code for the driver never starts with "[": `qs ipc call` splits such an argument; wrapped in a function)
    loaded = s.wait(lambda: s.js("(function () { return [Settings.islandAnimMs, Settings.centreLeft]; })()") == [260, left], 5)
    check(loaded, f"[cards, {layout}] the settings row is loaded")
    closed_at_rest(s)
    for name in ("audio", "sysinfo"):
        tag = f"card {name}, {layout}"
        # (the island's progress does not move for a card, so this recording is read frame by frame, not checked for
        # one change per frame)
        s.record_start(CLOCKPART, "Popouts.byName['clock'][0]", "progress")
        s.call("sleepybar", "toggle", name)
        time.sleep(0.9)
        rows = s.record_stop()
        got = s.js(CARD.replace("NAME", name))
        if not check(isinstance(got, dict) and "error" not in got and got["open"] and got["current"],
                     f"[{tag}] the toggle opens it", json.dumps(got)[:300]):
            continue
        check(got["inCentre"] and not got["barDraws"], f"[{tag}] the centre island draws it; the bar draws nothing",
              json.dumps({"inCentre": got["inCentre"], "barDraws": got["barDraws"]}))
        check(got["hangs"] == got["slot"] == ("left" if name == left else "right"),
              f"[{tag}] it hangs under the slot that holds {name}", json.dumps({"slot": got["slot"], "hangs": got["hangs"]}))
        check(got["inCentre"] and not got["outside"], f"[{tag}] its content lies inside the outline", "; ".join(got["outside"][:3]))
        sig = s.js(PROBE)["sig"]
        check(sig.startswith("Shape[") and " " not in sig and "|" not in sig, f"[{tag}] the island is one shape with one path", sig)
        moved = len({tuple(round(v, 1) for v in r[2]) for r in rows})
        bad = shrinks(rows) if moved > 1 else ["the outline did not move"]
        check(not bad, f"[{tag}] the outline grows to take the card, and only grows ({len(rows)} frames)", "; ".join(bad[:3]))
        s.call("sleepybar", "toggle", name)
        closed = s.wait(lambda: s.js(f"(Popouts.byName['{name}'] || []).every(d => !d.open)") is True, 2)
        check(closed, f"[{tag}] a second toggle closes it")
        time.sleep(0.6)

# Handover: with a card open, a click on the clock opens the control centre and the card closes; the outline goes
# from the card's shape to the panel's in one morph, without a jump. A card deeper than the panel's side column
# (audio: 340 against 302) eases up into it on the way, so the card column's depth is held to "no frame step above
# 1.5 x the opening's largest", not to "only grows".
HANDOVER = """(function () {
  const c = Popouts.byName["clock"][0];
  let shape = null;
  const findShape = it => { if (shape) return; if (it.visible && it.rendererType !== undefined && it.containsMode !== undefined) { shape = it; return; }
    for (let i = 0; i < it.children.length; i++) findShape(it.children[i]); };
  findShape(c.contentItem);
  const x = XPOS + 0.2917;
  let a = 1.3719, b = shape.height + 1;
  while (b - a > 0.05) { const m = (a + b) / 2; if (shape.contains(Qt.point(x, m))) a = m; else b = m; }
  return [a, shape.boundingRect.width, shape.boundingRect.height];
})()"""
TOML.write_text(toml({"sleepybar": {"islandAnimMs": 800}}))
s.wait(lambda: s.js("Settings.islandAnimMs") == 800, 5)
for name in ("audio", "sysinfo"):
    closed_at_rest(s)
    s.call("sleepybar", "toggle", name)
    time.sleep(1.2)
    at = s.js(f"""(function () {{ const c = Popouts.byName["clock"][0];
      const d = (Popouts.byName["{name}"] || []).find(x => x.open) || null; if (!d) return null;
      let clock = null;
      const find = it => {{ if (!clock && String(it).startsWith("QQuickText") && it.text === c.title) clock = it; for (let i = 0; i < it.children.length && !clock; i++) find(it.children[i]); }};
      find(c.contentItem);
      const p = d.panel.mapToItem(null, d.panel.width / 2, 0), q = clock.mapToItem(null, clock.width / 2, clock.height / 2);
      return [p.x, c.margins.left + q.x, q.y]; }})()""")
    if not check(at is not None, f"[handover {name}] the card is open before the click"):
        continue
    s.record_start(HANDOVER.replace("XPOS", str(at[0])), "Popouts.byName['clock'][0]", "progress")
    Input.click(round(at[1]), round(at[2]))
    time.sleep(1.4)
    rows = s.record_stop()
    gaps = recording_gaps(rows)
    check(not gaps, f"[handover {name}] the recording has every frame and every change", "; ".join(gaps[:3]))
    now = s.js(f"(function () {{ return [Popouts.byName['clock'][0].open, (Popouts.byName['{name}'] || []).some(d => d.open)]; }})()")
    check(now == [True, False], f"[handover {name}] the control centre is open and the card closed", json.dumps(now))
    sig = s.js(PROBE)["sig"]
    check(sig.startswith("Shape[") and " " not in sig, f"[handover {name}] one shape at the end", sig)
    depth = [r[2][0] for r in rows]
    dsteps = [abs(b - a) for a, b in zip(depth, depth[1:])]
    print(f"INFO handover {name}: card column depth {depth[0]:.1f} -> {depth[-1]:.1f}, lowest {min(depth):.1f}, "
          f"largest frame step {max(dsteps):.1f} px")
    lim = 1.5 * steps(plain)[0] + 1
    check(max(dsteps) <= lim,
          f"[handover {name}] the card's column moves into the panel's without a jump ({len(rows)} frames)",
          f"largest step {max(dsteps):.1f} px, limit {lim:.1f}")
closed_at_rest(s)

# A card in a hidden slot has nothing to hang from, so it is refused: the toggle opens nothing (no dropdown open,
# nothing current), the outline does not change, and the shell log gets exactly one line saying so; nothing else.
for name, key in (("audio", "centreAudio"), ("sysinfo", "centreSysinfo")):
    TOML.write_text(toml({"sleepybar": {"islandAnimMs": 260}, "centre-island": {key: False}}))
    s.wait(lambda: s.js(f"Settings.{key}") is False, 5)
    closed_at_rest(s)
    before_box = s.js(CLOCKPART)
    lines_before = len(s.log.read_text(errors="replace").splitlines())
    s.call("sleepybar", "toggle", name)
    time.sleep(0.8)
    opened = s.js(f"(function () {{ return [(Popouts.byName['{name}'] || []).some(d => d.open), Popouts.current !== null]; }})()")
    check(opened == [False, False], f"[hidden {name}] the toggle opens nothing", json.dumps(opened))
    after_box = s.js(CLOCKPART)
    check(all(abs(a - b) < 0.06 for a, b in zip(before_box, after_box)), f"[hidden {name}] the outline does not change",
          json.dumps([before_box, after_box]))
    new = s.log.read_text(errors="replace").splitlines()[lines_before:]
    said = [ln for ln in new if name in ln and "hidden" in ln]
    check(len(said) == 1, f"[hidden {name}] the shell log says so in exactly one line", json.dumps(said[:3])[:300])

# The volume peek row and a card need the same room beside the clock, so while a card is open the island shows no
# peek row and its outline does not move for one. A peek still within its time when the card closes shows then, for
# the rest of its time: it ends when it would have ended, not a full time after the card closed. (Caps Lock's peek is
# held back by neither card, so it serves for both.)
TOML.write_text(toml({"sleepybar": {"islandAnimMs": 260}}))
s.wait(lambda: s.js("(function () { return [Settings.islandAnimMs, Settings.centreSysinfo, Settings.centreAudio]; })()") == [260, True, True], 5)
# [a peek is within its time, the peek row is drawn (its effective visibility: the row's slot hides it)]
PEEK = "(function () { return [OsdState.shown, Popouts.byName['clock'][0].peek.visible]; })()"
for name in ("sysinfo", "audio"):
    tag = f"peek with the {name} card"
    closed_at_rest(s)
    s.wait(lambda: s.js("OsdState.shown") is False, 5)
    s.call("sleepybar", "toggle", name)
    time.sleep(0.5)
    box = s.js(CLOCKPART)
    press_key()
    pressed = time.monotonic()
    time.sleep(0.6)
    if not check(s.js(PEEK)[0] is True, f"[{tag}] a key press starts a peek"):
        continue
    check(s.js(PEEK)[1] is False, f"[{tag}] no peek row while the card is open")
    now = s.js(CLOCKPART)
    check(all(abs(a - b) < 0.06 for a, b in zip(box, now)), f"[{tag}] the outline does not move", json.dumps([box, now]))
    got = s.js(CARD.replace("NAME", name))
    check(got.get("open") is True and not got.get("outside"), f"[{tag}] the card's content still lies inside the outline",
          json.dumps(got)[:300])
    time.sleep(max(0, pressed + 1.5 - time.monotonic()))
    s.call("sleepybar", "toggle", name)
    closed = time.monotonic()
    check(s.wait(lambda: s.js(PEEK)[1] is True, 1), f"[{tag}] closing the card shows the peek still within its time")
    s.wait(lambda: s.js(PEEK)[1] is False, 6)
    ended = time.monotonic()
    # the LED is read every 150 ms: a peek ends 3.0-3.2 s after the press, plus the polling here
    check(2.9 < ended - pressed < 3.6, f"[{tag}] the peek ends when its own time is up",
          f"{ended - pressed:.2f} s after the key press (peekMs 3 s), {ended - closed:.2f} s after the card closed")

# The flat outline (centreStep off) deepens as a whole for the peek. A card opened while the peek shows makes the peek
# row give way and hangs where the island ends without it, its content inside the outline.
TOML.write_text(toml({"sleepybar": {"islandAnimMs": 260}, "centre-island": {"centreStep": False}}))
s.wait(lambda: s.js("Settings.centreStep") is False, 5)
closed_at_rest(s)
s.wait(lambda: s.js("OsdState.shown") is False, 5)
press_key()
if check(s.wait(lambda: s.js(PEEK)[1] is True, 2), "[flat, card during the peek] a key press shows the peek row"):
    time.sleep(0.4)   # the outline grows for the peek
    s.call("sleepybar", "toggle", "sysinfo")
    time.sleep(0.6)
    got = s.js(CARD.replace("NAME", "sysinfo"))
    check(got.get("open") is True and s.js(PEEK)[1] is False, "[flat, card during the peek] the card opens and the peek row gives way",
          json.dumps(got)[:200])
    check(got.get("open") is True and not got.get("outside"), "[flat, card during the peek] its content lies inside the outline",
          json.dumps(got.get("outside"))[:300])
    s.call("sleepybar", "toggle", "sysinfo")
    s.wait(lambda: s.js("(Popouts.byName['sysinfo'] || []).every(d => !d.open)") is True, 2)
s.wait(lambda: s.js("OsdState.shown") is False, 5)

# A card whose widget goes away while it is open (swapping centreLeft makes both slots' widgets anew) leaves nothing
# behind: no popup is current, the outline is no deeper than the closed island (its bounding box ends at the bottom
# under the clock, the closed island's deepest part), the shell log gets no error, and hovering the clock opens the
# island again.
def nothing_left():
    """[no popup is current, the outline's depth, the depth under the clock]"""
    box = s.js(CLOCKPART)
    return [s.js("Popouts.current === null"), round(box[5], 2), round(box[0], 2)]


def left_nothing(got):
    return got[0] is True and got[1] <= got[2] + 0.1


def new_errors(since):
    """The shell log's errors (as the kit counts them, Shell.errors) after the first `since`, without the sandbox's."""
    return [e for e in s.errors()[since:] if not any(x in e for x in ENV_ERRORS)]


for gone, keep in (("sysinfo", "audio"), ("audio", "sysinfo")):
    tag = f"{gone} card, its widget made anew"
    TOML.write_text(toml({"sleepybar": {"islandAnimMs": 260}, "centre-island": {"centreLeft": gone}}))
    s.wait(lambda: s.js("(function () { return [Settings.centreLeft, Settings.centreStep]; })()") == [gone, True], 5)
    closed_at_rest(s)
    s.call("sleepybar", "toggle", gone)
    time.sleep(0.6)
    if not check(s.js(CARD.replace("NAME", gone)).get("open") is True, f"[{tag}] the card is open before the swap"):
        continue
    errs_before = len(s.errors())
    TOML.write_text(toml({"sleepybar": {"islandAnimMs": 260}, "centre-island": {"centreLeft": keep}}))
    s.wait(lambda: s.js("Settings.centreLeft") == keep, 5)
    time.sleep(0.6)
    got = nothing_left()
    check(left_nothing(got), f"[{tag}] nothing is left of the card", json.dumps(got))
    bad = new_errors(errs_before)
    check(not bad, f"[{tag}] the shell log gets no error", "; ".join(bad[:2])[:300])
    Input.move(cx, 12)
    check(s.wait(lambda: s.js("Popouts.byName['clock'][0].open") is True, 2), f"[{tag}] hovering the clock opens the island")
    closed_at_rest(s)

# A card whose slot is hidden while it is open (centreSysinfo / centreAudio turned off) has nothing left to hang from,
# so it closes, and nothing is left of it.
for name, key in (("sysinfo", "centreSysinfo"), ("audio", "centreAudio")):
    tag = f"{name} card, its slot hidden"
    TOML.write_text(toml({"sleepybar": {"islandAnimMs": 260}}))
    s.wait(lambda: s.js(f"Settings.{key}") is True, 5)
    closed_at_rest(s)
    s.call("sleepybar", "toggle", name)
    time.sleep(0.6)
    if not check(s.js(CARD.replace("NAME", name)).get("open") is True, f"[{tag}] the card is open before the slot hides"):
        continue
    TOML.write_text(toml({"sleepybar": {"islandAnimMs": 260}, "centre-island": {key: False}}))
    s.wait(lambda: s.js(f"Settings.{key}") is False, 5)
    time.sleep(0.6)
    shut = s.js(f"(function () {{ return (Popouts.byName['{name}'] || []).every(d => !d.open); }})()")
    got = nothing_left()
    check(shut is True and left_nothing(got), f"[{tag}] the card closes and nothing is left of it",
          json.dumps({"closed": shut, "current none, depth, under the clock": got}))
TOML.write_text(toml({"sleepybar": {"islandAnimMs": 260}}))
s.wait(lambda: s.js("(function () { return [Settings.centreSysinfo, Settings.centreAudio]; })()") == [True, True], 5)

# Two cards in a row: opening the other slot's card while one is open closes the first and hangs the second under its
# own slot, its content inside; the outline ends up the same as with the second card opened alone.
closed_at_rest(s)
s.call("sleepybar", "toggle", "audio")
time.sleep(0.6)
alone = s.js(CLOCKPART)
s.call("sleepybar", "toggle", "audio")
s.wait(lambda: s.js("(Popouts.byName['audio'] || []).every(d => !d.open)") is True, 2)
time.sleep(0.6)
s.call("sleepybar", "toggle", "sysinfo")
time.sleep(0.6)
s.call("sleepybar", "toggle", "audio")
time.sleep(0.6)
got = s.js(CARD.replace("NAME", "audio"))
first = s.js("(Popouts.byName['sysinfo'] || []).some(d => d.open)")
check(isinstance(got, dict) and got.get("open") is True and got.get("current") is True and first is False
      and got.get("hangs") == got.get("slot"), "[two cards in a row] the second opens under its own slot and the first closes",
      json.dumps({"second": got, "first open": first})[:300])
check(got.get("open") is True and not got.get("outside"), "[two cards in a row] the second card's content lies inside the outline",
      json.dumps(got.get("outside"))[:300])
now = s.js(CLOCKPART)
check(all(abs(a - b) < 0.06 for a, b in zip(alone, now)), "[two cards in a row] the outline is the same as with that card alone",
      json.dumps([alone, now]))
s.call("sleepybar", "toggle", "audio")
s.wait(lambda: s.js("(Popouts.byName['audio'] || []).every(d => !d.open)") is True, 2)

# A reload with a card open (a file of the shell changed on disk) tears the card down with everything else: the shell
# log gets no error, and the island comes back closed with no card.
closed_at_rest(s)
s.call("sleepybar", "toggle", "sysinfo")
time.sleep(0.6)
if check(s.js(CARD.replace("NAME", "sysinfo")).get("open") is True, "[reload] the card is open before the reload"):
    errs_before = len(s.errors())
    loads = s.log.read_text(errors="replace").count("Configuration Loaded")
    # an edit saved to the run copy (a touch alone, with the same content, does not reload)
    edited = Path(sys.argv[1]) / "sleepybar/Sleepybar.qml"
    edited.write_text(edited.read_text() + "\n// changed on disk\n")
    reloaded = s.wait(lambda: s.log.read_text(errors="replace").count("Configuration Loaded") > loads, 15)
    if check(reloaded, "[reload] an edit to the bar's file reloads the shell"):
        time.sleep(1.5)
        bad = new_errors(errs_before)
        check(not bad, "[reload] the shell log gets no error", "; ".join(bad[:2])[:300])
        back = s.wait(lambda: left_nothing(nothing_left()), 5)
        check(back, "[reload] the island comes back closed with no card", json.dumps(nothing_left()))

errs = [e for e in s.errors() if not any(x in e for x in ENV_ERRORS)]
check(not errs, "no QML errors", "; ".join(errs[:3]))
s.stop()
done()
