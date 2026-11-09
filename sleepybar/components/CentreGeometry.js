.pragma library

// The centre island's size rules (GrowingIsland.qml), as plain arithmetic over what its content measures, the
// settings and the theme, so the rules read in one place, apart from the island's state, surface and input. Every
// position is in the island window's coordinates, the island centred in it: the content is placed there once and
// never moves, and the outline (IslandShape.qml) grows around it.

// The closed and open sizes and where the header and the panel body sit.
//   m: windowW (the island window's width), headerW (the header row), clockH (the clock column), bodyW / bodyH (the
//      panel body), sideDepth (the deeper side column), uneven (a middle column hangs deeper than the sides), stepped
//      (Settings.centreStep with a widget beside the clock), pad, barH, radius, stepFillet, stepCorner
function sizes(m) {
    // Closed, the island fits a two-line header (clock and date, 5 px above and below). Stepped, the clock part
    // reaches at least stepCorner + stepFillet below the sides, so the step has room for its corners and fillets.
    const startH = Math.max(m.barH, Math.ceil(m.clockH) + 10, m.stepped ? m.barH + m.stepCorner + m.stepFillet : 0);
    const fullW = Math.max(m.headerW + 2 * m.radius, m.bodyW + 2 * m.pad);
    // the body starts 4 px under the closed header
    const fullH = startH + 4 + m.bodyH + m.pad;
    return {
        startH: startH,
        fullW: fullW,
        fullH: fullH,
        // Open, the side columns end higher than the middle one, both where the deeper of the two does, not each at
        // its own depth; without a middle column the open panel is one plain rectangle.
        sideH: m.uneven ? Math.min(fullH, startH + 4 + m.sideDepth + m.pad) : fullH,
        headerX: Math.round((m.windowW - m.headerW) / 2),
        colX: Math.round((m.windowW - fullW) / 2) + m.pad
    };
}

// The outline's two skylines (IslandShape.qml), the clock part's centre and where an open card sits.
//   s: sizes(); m: headerW, clockX / clockW (the clock box in the header), centreW / baseH (the clock part, wider and
//   deeper while the volume peek shows), left / right (a widget shows on that side), step (Settings.centreStep),
//   middle ({ x, width } of the middle column in the body, or null), card ({ side: "left" | "right", width, height }
//   of a slot's dropdown, or null), pad, barH, radius, stepFillet, stepCorner
function skylines(s, m) {
    const clockMid = s.headerX + m.clockX + m.clockW / 2;
    // Closed: the island reaches `radius` beyond the header; the clock part is centreW wide and baseH deep; the sides
    // are bar-high when stepped, as deep as the clock part when not. A side without a widget has no column: the clock
    // part reaches that edge, which the peek widens past the header.
    const lo = clockMid - m.centreW / 2, hi = clockMid + m.centreW / 2;
    const l = m.left ? s.headerX - m.radius : Math.min(s.headerX - m.radius, lo);
    const r = m.right ? s.headerX + m.headerW + m.radius : Math.max(s.headerX + m.headerW + m.radius, hi);
    const c0 = m.left ? lo : l, c1 = m.right ? hi : r;
    const side = m.step ? m.barH : m.baseH;
    // A card hangs flush under its slot, from that side's bottom, its inner edge on the clock part's: its side
    // widens outward only (never narrower than the island) and reaches the card's bottom; the clock stays put.
    const card = m.card ?? null, onL = card !== null && card.side === "left", onR = card !== null && card.side === "right";
    const cardX = onL ? c0 - card.width : c1;
    const L0 = onL ? Math.min(l, cardX) : l, R0 = onR ? Math.max(r, c1 + card.width) : r;
    const dL = onL ? side + card.height : m.left ? side : m.baseH, dR = onR ? side + card.height : m.right ? side : m.baseH;
    // Open: the panel's three columns, the middle one 6 px into the gaps beside it (past the column dividers) and the
    // only one at the full depth; without a middle column all three are.
    const L = s.colX - m.pad, R = L + s.fullW;
    const m0 = m.middle ? s.colX + m.middle.x - 6 : c0, m1 = m.middle ? s.colX + m.middle.x + m.middle.width + 6 : c1;
    return {
        clockMid: clockMid,
        cardX: cardX,
        cardY: side,
        closed: {
            fillet: m.stepFillet,
            corner: m.stepCorner,
            cols: [{ x0: L0, x1: c0, d: dL }, { x0: c0, x1: c1, d: m.baseH }, { x0: c1, x1: R0, d: dR }]
        },
        open: {
            fillet: m.radius,
            corner: m.radius,
            cols: [{ x0: L, x1: m0, d: s.sideH }, { x0: m0, x1: m1, d: s.fullH }, { x0: m1, x1: R, d: s.sideH }]
        }
    };
}
