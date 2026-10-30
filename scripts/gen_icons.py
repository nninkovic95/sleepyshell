#!/usr/bin/env python3
"""Builds data/icons.json: the Material Design icons ("md-*" glyphs) of a Nerd Font, as [[codepoint, "name"], ...].

  gen_icons.py [FONT.ttf] [OUT.json]

Defaults: /usr/share/fonts/TTF/JetBrainsMonoNerdFontPropo-Regular.ttf (the face the shell draws icons with, Theme.iconFont)
and ../data/icons.json. The tool editor of Sleepysettings (sleepysettings/ToolEditor.qml) searches this list by name; QML cannot
read a font's glyph names, so they are read here once and the result is kept in the repo. Run it again after a font update.

Python standard library only: the font's `cmap` (codepoint -> glyph) and `post` (format 2.0: glyph -> name) tables are read
by hand. Writes only OUT. A Nerd Font names its Material icons "md-<name>"; the "md-" is dropped in the output.
"""
import json
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FONT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/usr/share/fonts/TTF/JetBrainsMonoNerdFontPropo-Regular.ttf")
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE.parent / "data" / "icons.json"


def tables(data):
    n = struct.unpack(">H", data[4:6])[0]
    out = {}
    for i in range(n):
        tag, _, off, length = struct.unpack(">4sIII", data[12 + 16 * i:28 + 16 * i])
        out[tag.decode("latin-1")] = data[off:off + length]
    return out


def cmap_unicode(t):
    """codepoint -> glyph id from the best Unicode subtable (format 12 preferred, else 4)."""
    n = struct.unpack(">H", t[2:4])[0]
    subs = []
    for i in range(n):
        pid, eid, off = struct.unpack(">HHI", t[4 + 8 * i:12 + 8 * i])
        fmt = struct.unpack(">H", t[off:off + 2])[0]
        if pid in (0, 3) and fmt in (4, 12):
            subs.append((fmt, off))
    if not subs:
        sys.exit("no Unicode cmap subtable (format 4 or 12) in " + str(FONT))
    fmt, off = max(subs)
    m = {}
    if fmt == 12:
        groups = struct.unpack(">I", t[off + 12:off + 16])[0]
        for g in range(groups):
            start, end, gid = struct.unpack(">III", t[off + 16 + 12 * g:off + 28 + 12 * g])
            for k in range(start, end + 1):
                m[k] = gid + k - start
        return m
    segx2 = struct.unpack(">H", t[off + 6:off + 8])[0]
    seg = segx2 // 2
    ends = struct.unpack(">%dH" % seg, t[off + 14:off + 14 + segx2])
    p = off + 16 + segx2
    starts = struct.unpack(">%dH" % seg, t[p:p + segx2])
    p += segx2
    deltas = struct.unpack(">%dh" % seg, t[p:p + segx2])
    p += segx2
    ro_at = p
    ranges = struct.unpack(">%dH" % seg, t[p:p + segx2])
    for s in range(seg):
        for c in range(starts[s], ends[s] + 1):
            if c == 0xFFFF:
                continue
            if ranges[s] == 0:
                gid = (c + deltas[s]) & 0xFFFF
            else:
                q = ro_at + 2 * s + ranges[s] + 2 * (c - starts[s])
                gid = struct.unpack(">H", t[q:q + 2])[0]
                if gid:
                    gid = (gid + deltas[s]) & 0xFFFF
            if gid:
                m[c] = gid
    return m


def post_names(t):
    """glyph id -> name from a format 2.0 post table."""
    fmt = struct.unpack(">I", t[0:4])[0]
    if fmt != 0x00020000:
        sys.exit("post table is not format 2.0, so the font has no glyph names: " + str(FONT))
    n = struct.unpack(">H", t[32:34])[0]
    idx = struct.unpack(">%dH" % n, t[34:34 + 2 * n])
    p = 34 + 2 * n
    extra = []
    while p < len(t):
        ln = t[p]
        extra.append(t[p + 1:p + 1 + ln].decode("latin-1"))
        p += 1 + ln
    return {g: extra[i - 258] for g, i in enumerate(idx) if i >= 258 and i - 258 < len(extra)}


def main():
    t = tables(FONT.read_bytes())
    cm = cmap_unicode(t["cmap"])
    names = post_names(t["post"])
    icons = []
    for cp in sorted(cm):
        nm = names.get(cm[cp], "")
        if nm.startswith("md-"):
            icons.append([cp, nm[3:]])
    if not icons:
        sys.exit("no md-* glyph names in " + str(FONT))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(icons, separators=(",", ":")) + "\n")
    print("%d icons -> %s" % (len(icons), OUT))


main()
