// Seam C: the centre island's size rules (sleepybar/components/CentreGeometry.js) on their own. Run with Seam A by
// ../islandshape.test.sh. Every expected number below is worked out by hand from the rules in the island's design
// (written next to each row), never by calling the module twice; the inputs are the kit's measured sizes (header
// row, clock column 41 px with the date, control centre body 1022 x 329, its middle column at 325 + 372, its sides
// 235 deep; bar 30, island radius 14, step fillet 6, corner 10, panel padding 12). The default row's open size,
// 1046 x 396, is also the size an earlier audit measured on the live shell. The rows place the island in a window as
// wide as the open island with its outer fillets (1046 + 2 x 14 = 1074), so it starts at the window's left edge;
// test_sizes_screen_wide places it in a window as wide as the screen, as the shell does.
import QtQuick
import QtTest
import "../../../sleepybar/components/CentreGeometry.js" as Geometry

TestCase {
    name: "CentreGeometry"

    readonly property var look: ({ pad: 12, barH: 30, radius: 14, stepFillet: 6, stepCorner: 10 })

    function sizes(m) {
        return Geometry.sizes(Object.assign({ windowW: 1074, clockH: 41, bodyW: 1022, bodyH: 329, sideDepth: 235 }, look, m));
    }
    function skylines(s, m) {
        return Geometry.skylines(s, Object.assign({ clockW: 87, middle: { x: 325, width: 372 } }, look, m));
    }
    function cols(sky) {
        return sky.cols.map(c => [c.x0, c.x1, c.d]);
    }

    // both widgets beside the clock, stepped, uneven: closed 30 / 51 / 30, open 302 / 396 / 302
    function test_sizes_default() {
        const s = sizes({ headerW: 400, uneven: true, stepped: true });
        compare(s.startH, 51, "closed height: max(bar 30, clock 41 + 10, step 30 + 10 + 6)");
        compare(s.fullW, 1046, "open width: max(header 400 + 2 x 14, body 1022 + 2 x 12)");
        compare(s.fullH, 396, "open height: 51 + 4 + 329 + 12");
        compare(s.sideH, 302, "open sides: 51 + 4 + 235 + 12");
        compare(s.headerX, 337, "header centred: (1074 - 400) / 2");
        compare(s.colX, 26, "body: (1074 - 1046) / 2 + 12");
    }

    // A window as wide as the screen (2560): the header and the body are centred on it, and a rounder corner (radius
    // 20, the Rounded set) moves neither, since the body still decides the open width (max(400 + 40, 1046) = 1046)
    function test_sizes_screen_wide() {
        const s = sizes({ windowW: 2560, headerW: 400, uneven: true, stepped: true });
        compare(s.headerX, 1080, "header centred: (2560 - 400) / 2");
        compare(s.colX, 769, "body: (2560 - 1046) / 2 + 12");
        const round = sizes({ windowW: 2560, headerW: 400, uneven: true, stepped: true, radius: 20, stepFillet: 8, stepCorner: 14 });
        compare([round.headerX, round.colX], [1080, 769], "radius 20: header and body stay");
    }

    function test_skylines_default() {
        const k = skylines(sizes({ headerW: 400, uneven: true, stepped: true }),
                           { headerW: 400, clockX: 140, centreW: 87, baseH: 51, left: true, right: true, step: true });
        compare(k.clockMid, 520.5, "clock centre: 337 + 140 + 87 / 2");
        // closed: the island 14 beyond the header (323..751), the clock part 87 wide (477..564), sides bar-high
        compare(cols(k.closed), [[323, 477, 30], [477, 564, 51], [564, 751, 30]]);
        compare([k.closed.fillet, k.closed.corner], [6, 10]);
        // open: the body 14..1060, the middle column 6 px into the gaps (26 + 325 - 6, 26 + 325 + 372 + 6)
        compare(cols(k.open), [[14, 345, 302], [345, 729, 396], [729, 1060, 302]]);
        compare([k.open.fillet, k.open.corner], [14, 14]);
    }

    // no widget on the left, the volume peek showing: the clock part is 220 wide and 51 + 18 + 10 deep, and the left
    // side has no column, so the island's left edge is the clock part's (397 + 43.5 - 110)
    function test_skylines_peek_no_left() {
        const s = sizes({ headerW: 280, uneven: true, stepped: true });
        compare(s.headerX, 397, "header centred: (1074 - 280) / 2");
        const k = skylines(s, { headerW: 280, clockX: 0, centreW: 220, baseH: 79, left: false, right: true, step: true });
        compare(cols(k.closed), [[330.5, 330.5, 79], [330.5, 550.5, 79], [550.5, 691, 30]]);
    }

    // step and uneven off, no middle column: closed sides as deep as the clock part, open one plain rectangle
    function test_flat_even() {
        const s = sizes({ headerW: 400, uneven: false, stepped: false });
        compare(s.startH, 51, "closed height: max(30, 51, no step)");
        compare(s.sideH, 396, "open sides at full depth");
        const k = skylines(s, { headerW: 400, clockX: 140, centreW: 87, baseH: 51, left: true, right: true, step: false,
                                middle: null });
        compare(cols(k.closed), [[323, 477, 51], [477, 564, 51], [564, 751, 51]]);
        compare(cols(k.open), [[14, 477, 396], [477, 564, 396], [564, 1060, 396]]);
    }

    // ---- a card under a slot: its side widens outward only, it hangs from that side ----

    // the left card, 324 wide and 200 deep: the left column reaches 324 left of the clock part (477 - 324) and
    // 30 + 200 deep; the clock part and the right side stay; the card's content sits at x 153, y 30
    function test_card_left() {
        const k = skylines(sizes({ headerW: 400, uneven: true, stepped: true }),
                           { headerW: 400, clockX: 140, centreW: 87, baseH: 51, left: true, right: true, step: true,
                             card: { side: "left", width: 324, height: 200 } });
        compare(cols(k.closed), [[153, 477, 230], [477, 564, 51], [564, 751, 30]]);
        compare([k.cardX, k.cardY], [153, 30]);
        compare(cols(k.open), [[14, 345, 302], [345, 729, 396], [729, 1060, 302]], "the open shape has no card");
    }

    // the right card, 364 wide and 250 deep: the right column reaches 564 + 364 and 30 + 250 deep
    function test_card_right() {
        const k = skylines(sizes({ headerW: 400, uneven: true, stepped: true }),
                           { headerW: 400, clockX: 140, centreW: 87, baseH: 51, left: true, right: true, step: true,
                             card: { side: "right", width: 364, height: 250 } });
        compare(cols(k.closed), [[323, 477, 30], [477, 564, 51], [564, 928, 280]]);
        compare([k.cardX, k.cardY], [564, 30]);
    }

    // a card narrower than its slot: the side keeps its width (never narrower than the island), only deeper; the
    // card still hangs flush with the clock part (477 - 100)
    function test_card_narrow() {
        const k = skylines(sizes({ headerW: 400, uneven: true, stepped: true }),
                           { headerW: 400, clockX: 140, centreW: 87, baseH: 51, left: true, right: true, step: true,
                             card: { side: "left", width: 100, height: 120 } });
        compare(cols(k.closed), [[323, 477, 150], [477, 564, 51], [564, 751, 30]]);
        compare([k.cardX, k.cardY], [377, 30]);
    }

    // step off: the sides are as deep as the clock part, so the card hangs from 51
    function test_card_flat() {
        const k = skylines(sizes({ headerW: 400, uneven: true, stepped: false }),
                           { headerW: 400, clockX: 140, centreW: 87, baseH: 51, left: true, right: true, step: false,
                             card: { side: "right", width: 364, height: 250 } });
        compare(cols(k.closed), [[323, 477, 51], [477, 564, 51], [564, 928, 301]]);
        compare([k.cardX, k.cardY], [564, 51]);
    }
}
