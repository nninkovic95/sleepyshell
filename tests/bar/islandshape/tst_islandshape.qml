// Seam A: the centre island's outline (IslandShape.qml) on its own. Run by ../islandshape.test.sh, or from the
// repository root with `QT_QUICK_BACKEND=software qmltestrunner -platform offscreen -input tests/bar/islandshape`.
// Every row is a pair of skylines (the island closed and open, in surface coordinates) written out from a settings
// combination, with the sizes measured in the kit (the default look: 393 x 51 closed; the control
// centre 1022 x 329 under it, its middle column at 325 + 372, its sides 235 deep). Expected values come from those
// inputs and from Qt's own geometry (Shape.contains, boundingRect, Path.pointAtPercent), never from the component.
import QtQuick
import QtTest
import "../../../sleepybar/components"

Item {
    id: top
    width: 1400
    height: 600

    // what the island's content would be: a texture provider (a layered item), the size of the shape
    Rectangle {
        id: content
        anchors.fill: parent
        color: "red"
        layer.enabled: true
    }

    IslandShape {
        id: shape
        anchors.fill: parent
        from: top.row.from
        to: top.row.to
        t: 0
        radius: top.row.radius
        fillItem: content
    }

    property var row: build({ step: true, uneven: true, slots: "both", corners: "default", date: true, peek: false })

    // ---- rows: the island's closed and open skylines for one settings combination ----
    // Corner sets from Theme.qml (islandRadius = xl, step fillet = sm, step corner = lg); numbers 2 and 30 scale them.
    function corners(c) {
        const sets = { sharp: { xl: 7, lg: 5, sm: 3 }, "default": { xl: 14, lg: 10, sm: 6 }, round: { xl: 20, lg: 14, sm: 8 } };
        if (sets[c])
            return sets[c];
        const xl = c, f = xl / 14, part = n => Math.max(2, Math.round(n * f));
        return { xl: xl, lg: part(10), sm: part(6) };
    }

    function build(s) {
        const barH = 30, gap = 6, pad = 12, slotL = 126, slotR = 140, clockBox = 87, peekH = 18;
        const cs = corners(s.corners), r = cs.xl;
        const hasL = s.slots === "both" || s.slots === "left", hasR = s.slots === "both" || s.slots === "right";
        const header = (hasL ? slotL + gap : 0) + clockBox + (hasR ? gap + slotR : 0);
        const startW = header + 2 * r;
        const clockH = s.date ? 41 : 24;   // the clock column's height with and without the date line
        const stepDepth = s.step && (hasL || hasR) ? barH + cs.lg + cs.sm : 0;
        const startH = Math.max(barH, clockH + 10, stepDepth);
        const baseH = s.peek ? startH + peekH + 10 : startH;
        const fullW = Math.max(startW, 1022 + 2 * pad), fullH = startH + 4 + 329 + pad;
        const W = Math.ceil(fullW) + 2 * r;
        // closed: the header centred in the surface, the island r beyond it; a side without a widget has no column and
        // ends at the clock part, which the peek widens past the header
        const hx = Math.round((W - header) / 2);
        const centreW = s.peek ? Math.max(clockBox, 220) : clockBox;
        const clockMid = hx + (hasL ? slotL + gap : 0) + clockBox / 2;
        const L0 = hasL ? hx - r : Math.min(hx - r, clockMid - centreW / 2);
        const R0 = hasR ? hx + header + r : Math.max(hx + header + r, clockMid + centreW / 2);
        const c0 = hasL ? clockMid - centreW / 2 : L0, c1 = hasR ? clockMid + centreW / 2 : R0;
        const sideD = s.step ? barH : baseH;
        // an open card: its side widens outward only, to the card's width from the clock part, and reaches
        // the card's bottom, hanging from that side's bottom
        const card = s.card ?? null, onL = card !== null && card.side === "left", onR = card !== null && card.side === "right";
        const from = { fillet: cs.sm, corner: cs.lg, cols: [
            { x0: onL ? Math.min(L0, c0 - card.w) : L0, x1: c0, d: onL ? sideD + card.h : hasL ? sideD : baseH },
            { x0: c0, x1: c1, d: baseH },
            { x0: c1, x1: onR ? Math.max(R0, c1 + card.w) : R0, d: onR ? sideD + card.h : hasR ? sideD : baseH }] };
        // open: the control centre's three columns, centred; with uneven off one plain rectangle
        const colX = Math.round((W - fullW) / 2) + pad;
        const L1 = colX - pad, R1 = L1 + fullW;
        const m0 = colX + 325 - 6, m1 = colX + 325 + 372 + 6;
        const sideH = s.uneven ? Math.min(fullH, startH + 4 + 235 + pad) : fullH;
        const to = { fillet: r, corner: r, cols: [{ x0: L1, x1: m0, d: sideH }, { x0: m0, x1: m1, d: fullH }, { x0: m1, x1: R1, d: sideH }] };
        const name = [s.step ? "step" : "flat", s.uneven ? "uneven" : "even", s.slots, "corners " + s.corners,
                      s.date ? "date" : "no date", s.peek ? "peek" : "no peek"].join(", ")
                     + (card ? ", " + card.side + " card " + card.w + "x" + card.h : "");
        return { name: name, radius: r, from: from, to: to };
    }

    // Pairwise rows over the settings: every value of each setting meets every value of every other setting at least
    // once. Built greedily from the full product in a fixed order, so the list is the same on every run.
    function rows() {
        const axes = { step: [true, false], uneven: [true, false], slots: ["both", "left", "right", "none"],
                       corners: ["default", "sharp", "round", 2, 30], date: [true, false], peek: [false, true] };
        const keys = Object.keys(axes);
        let combos = [{}];
        for (const k of keys)
            combos = [].concat.apply([], combos.map(c => axes[k].map(v => Object.assign({}, c, { [k]: v }))));
        const pair = (c, a, b) => a + "=" + c[a] + "|" + b + "=" + c[b];
        const need = new Set();
        for (const c of combos)
            for (let i = 0; i < keys.length; i++)
                for (let j = i + 1; j < keys.length; j++)
                    need.add(pair(c, keys[i], keys[j]));
        const picked = [];
        while (need.size > 0) {
            let best = null, bestN = 0;
            for (const c of combos) {
                let n = 0;
                for (let i = 0; i < keys.length; i++)
                    for (let j = i + 1; j < keys.length; j++)
                        if (need.has(pair(c, keys[i], keys[j])))
                            n++;
                if (n > bestN) {
                    best = c;
                    bestN = n;
                }
            }
            picked.push(best);
            for (let i = 0; i < keys.length; i++)
                for (let j = i + 1; j < keys.length; j++)
                    need.delete(pair(best, keys[i], keys[j]));
        }
        return picked.map(build);
    }

    // A card open under a slot, morphing into the open control centre (the handover), with the cards' measured sizes:
    // CPU and memory 324 x 90 on the left, audio 364 x 310 on the right; stepped and flat, at the corner extremes, and
    // a card next to the peek.
    function cardRows() {
        const sys = { side: "left", w: 324, h: 90 }, audio = { side: "right", w: 364, h: 310 };
        const base = { step: true, uneven: true, slots: "both", corners: "default", date: true, peek: false };
        return [{ card: sys }, { card: audio }, { card: sys, step: false }, { card: audio, step: false },
                { card: audio, corners: 2 }, { card: sys, corners: 30 }, { card: audio, corners: 30, uneven: false },
                { card: sys, peek: true }].map(c => build(Object.assign({}, base, c)));
    }

    // every row; `opening` only the rows that open from the closed island (no card)
    function rowData(opening) {
        return rows().concat(opening ? [] : cardRows()).map(r => ({ tag: r.name, row: r }));
    }

    TestCase {
        name: "IslandShape"
        when: windowShown

        function path() {
            for (let i = 0; i < shape.data.length; i++)
                if (String(shape.data[i]).startsWith("QQuickShapePath"))
                    return shape.data[i];
            return null;
        }

        function paths() {
            let n = 0;
            for (let i = 0; i < shape.data.length; i++)
                if (String(shape.data[i]).startsWith("QQuickShapePath"))
                    n++;
            return n;
        }

        function kinds() {
            const p = path(), els = [];
            for (let k = 0; k < p.pathElements.length; k++)
                els.push(String(p.pathElements[k]).split("(")[0]);
            return els.join(",");
        }

        // every number the path is drawn from: its start and each element's end point and radius
        function values() {
            const p = path(), out = [p.startX, p.startY];
            for (let k = 0; k < p.pathElements.length; k++) {
                const e = p.pathElements[k];
                out.push(e.x, e.y);
                if (e.radiusX !== undefined)
                    out.push(e.radiusX);
            }
            return out;
        }

        // the largest change any input of the row makes between closed and open
        function span(r) {
            let m = Math.abs(r.to.fillet - r.from.fillet);
            m = Math.max(m, Math.abs(r.to.corner - r.from.corner));
            for (let i = 0; i < 3; i++)
                for (const k of ["x0", "x1", "d"])
                    m = Math.max(m, Math.abs(r.to.cols[i][k] - r.from.cols[i][k]));
            return m;
        }

        function use(r) {
            top.row = r;
            shape.from = r.from;
            shape.to = r.to;
            shape.t = 0;
        }

        // 1. one ShapePath, with the same element types in the same order at every point of the morph and in every
        //    row: no second drawing ever swaps in
        function test_1_structure_data() {
            return top.rowData();
        }
        function test_1_structure(d) {
            use(d.row);
            compare(paths(), 1, "exactly one ShapePath");
            verify(path().fillItem === content, "the path is filled with the content");
            const first = kinds();
            compare(first, "QQuickPathLine,QQuickPathArc,QQuickPathLine,QQuickPathArc,QQuickPathLine,QQuickPathArc,QQuickPathLine,QQuickPathArc,QQuickPathLine,QQuickPathArc,QQuickPathLine,QQuickPathArc,QQuickPathLine,QQuickPathArc,QQuickPathLine,QQuickPathArc",
                    "the same 16 elements in every row");
            for (let i = 0; i <= 240; i++) {
                shape.t = i / 240;
                compare(paths(), 1, "exactly one ShapePath at t " + shape.t);
                compare(kinds(), first, "the same elements at t " + shape.t);
            }
        }

        // 2. smooth: between two neighbouring steps of 1/240, no number of the path moves more than twice the row's
        //    largest input change over 240 (a radius clamped by a moving step can move at most that fast) plus 0.01
        function test_2_smooth_data() {
            return top.rowData();
        }
        function test_2_smooth(d) {
            use(d.row);
            const limit = 2 * span(d.row) / 240 + 0.01;
            let prev = values();
            for (let i = 1; i <= 240; i++) {
                shape.t = i / 240;
                const now = values();
                for (let k = 0; k < now.length; k++)
                    verify(isFinite(now[k]), "a finite value " + k + " at t " + shape.t);
                for (let k = 0; k < now.length; k++)
                    if (Math.abs(now[k] - prev[k]) > limit)
                        fail("value " + k + " jumped " + (now[k] - prev[k]).toFixed(2) + " px at t " + shape.t.toFixed(4) + " (limit " + limit.toFixed(2) + ")");
                prev = now;
            }
        }

        // 3. only grows while it opens: a point inside the fill stays inside at every later step, and the bounding
        //    rectangle never gets smaller (a 12 x 8 px grid over the whole open island)
        function test_3_grows_data() {
            return top.rowData(true);
        }
        function test_3_grows(d) {
            use(d.row);
            const x0 = d.row.to.cols[0].x0 - d.row.radius - 2, x1 = d.row.to.cols[2].x1 + d.row.radius + 2;
            const y1 = Math.max(d.row.to.cols[0].d, d.row.to.cols[1].d, d.row.to.cols[2].d) + 2;
            // Off-grid offsets: Shape.contains miscounts a point whose y is exactly that of a horizontal edge (seen at
            // y 176.5 = a column's depth halfway through the morph), and the skylines' values are whole and half pixels.
            const pts = [];
            for (let x = x0 + 0.2917; x <= x1; x += 12)
                for (let y = 0.3719; y <= y1; y += 8)
                    pts.push(Qt.point(x, y));
            let inside = pts.map(p => shape.contains(p));
            let box = shape.boundingRect;
            for (let i = 1; i <= 240; i++) {
                shape.t = i / 240;
                for (let k = 0; k < pts.length; k++) {
                    const now = shape.contains(pts[k]);
                    if (inside[k] && !now)
                        fail("point " + pts[k].x + "," + pts[k].y + " left the fill at t " + shape.t.toFixed(4));
                    inside[k] = now;
                }
                const b = shape.boundingRect;
                verify(b.x <= box.x + 0.01 && b.y <= box.y + 0.01 && b.x + b.width >= box.x + box.width - 0.01
                       && b.y + b.height >= box.y + box.height - 0.01, "the bounding rectangle shrank at t " + shape.t.toFixed(4));
                box = b;
            }
        }

        // 4. never crosses itself: the outline sampled along its length (240 points) has no two edges that cross,
        //    every 8th step of the morph
        function test_4_simple_data() {
            return top.rowData();
        }
        function test_4_simple(d) {
            use(d.row);
            const p = path();
            const n = 240;
            const cross = (a, b, c, e) => {
                const o = (p1, p2, p3) => (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x);
                const d1 = o(c, e, a), d2 = o(c, e, b), d3 = o(a, b, c), d4 = o(a, b, e);
                return ((d1 > 1e-6 && d2 < -1e-6) || (d1 < -1e-6 && d2 > 1e-6)) && ((d3 > 1e-6 && d4 < -1e-6) || (d3 < -1e-6 && d4 > 1e-6));
            };
            for (let i = 0; i <= 240; i += 8) {
                shape.t = i / 240;
                const pts = [];
                for (let k = 0; k < n; k++)
                    pts.push(p.pointAtPercent(k / n));
                // the samples are real points that cover the outline (NaN or one repeated point never crosses)
                const xs = pts.map(q => q.x), ys = pts.map(q => q.y);
                verify(xs.every(isFinite) && ys.every(isFinite), "every sample is a finite point at t " + shape.t.toFixed(4));
                // within one sample spacing (the outline is at most 4 x (width + height) long: its steps add depth twice)
                const b = shape.boundingRect, gap = 4 * (b.width + b.height) / n;
                verify(Math.min.apply(null, xs) <= b.x + gap && Math.max.apply(null, xs) >= b.x + b.width - gap
                       && Math.max.apply(null, ys) >= b.y + b.height - gap, "the samples span the outline at t " + shape.t.toFixed(4));
                for (let a = 0; a < n; a++)
                    for (let b = a + 2; b < n; b++) {
                        if (a === 0 && b === n - 1)
                            continue;
                        if (cross(pts[a], pts[(a + 1) % n], pts[b], pts[(b + 1) % n]))
                            fail("edges " + a + " and " + b + " cross at t " + shape.t.toFixed(4));
                    }
            }
        }

        // 5. the right size at both ends: the bounding rectangle is the row's skyline (outer edges, plus the top
        //    fillets of `radius` toward the screen edge, from the top edge to the deepest column)
        function test_5_endpoints_data() {
            return top.rowData();
        }
        function test_5_endpoints(d) {
            use(d.row);
            for (const [t, sky] of [[0, d.row.from], [1, d.row.to]]) {
                shape.t = t;
                const b = shape.boundingRect, r = d.row.radius;
                const deepest = Math.max(sky.cols[0].d, sky.cols[1].d, sky.cols[2].d);
                fuzzyCompare(b.x, sky.cols[0].x0 - r, 0.01, "left edge at t " + t);
                fuzzyCompare(b.x + b.width, sky.cols[2].x1 + r, 0.01, "right edge at t " + t);
                fuzzyCompare(b.y, 0, 0.01, "top at t " + t);
                fuzzyCompare(b.y + b.height, deepest, 0.01, "bottom at t " + t);
            }
        }

        // 6. a new morph starts where the outline is: `current` (the skyline drawn right now, with its step radii) as
        //    the next `from`, at t 0, draws exactly the same path, from anywhere in the morph
        function test_6_resume_data() {
            return top.rowData();
        }
        function test_6_resume(d) {
            use(d.row);
            for (const t of [0, 0.1, 0.37, 0.5, 0.83, 1]) {
                shape.from = d.row.from;
                shape.t = t;
                const before = values(), now = shape.current;
                verify(now && now.cols && now.cols.length === 3, "the drawn skyline is readable at t " + t);
                shape.from = now;
                shape.t = 0;
                const after = values();
                compare(after.length, before.length, "the same path elements at t " + t);
                for (let k = 0; k < before.length; k++)
                    fuzzyCompare(after[k], before[k], 1e-6, "value " + k + " unchanged when resuming at t " + t);
            }
        }
    }
}
