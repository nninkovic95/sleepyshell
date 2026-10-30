import QtQuick
import QtQuick.Layouts
import qs

// Two compact settings rows side by side in a Section: spin fields, switches and other short controls that belong together. Declare exactly the
// two rows (SettingRow, NumberRow, SwitchRow, ...) inside. Sliders, text fields and lists stay full
// width, as plain rows. Each row keeps its own label, "!" tip, revert arrow, unapplied mark and
// search dimming, and counts as a row for the search (TabPage.countHits walks into it).
// Labels stay on one line: each column's label width is the longest label in
// that column over every PairRow of the Section, so the controls line up from pair to pair, and the
// columns are as wide as label, control and revert arrow need. The Section sees one item and draws
// one hairline above it; this item draws the one between its rows: a vertical line when they sit side
// by side, a horizontal one when they stack. They stack, in every pair of the Section together, when
// the page is narrower than `breakAt` (the window at its smallest, 784 px, has a 560 px page) or the
// two columns do not fit the card.
Item {
    id: pair
    readonly property bool isPairRow: true
    default property alias pairRows: grid.data
    property int breakAt: 700
    readonly property int gap: 10      // between label and control (SettingRow.spacing); resetNeed has its own
    readonly property var page: {
        let p = pair.parent;
        while (p && p.isTabPage !== true)
            p = p.parent;
        return p ?? null;
    }
    // the pairs of this Section, this one included
    readonly property var peers: (pair.parent ? Array.prototype.filter.call(pair.parent.children, c => c.isPairRow === true) : [pair])
    // the rows this pair holds, in column order
    readonly property var members: Array.prototype.filter.call(grid.children, c => c.labelNeed !== undefined)
    // the rows that take room: a hidden one leaves the other alone in its column
    readonly property var shown: Array.prototype.filter.call(grid.visibleChildren, c => c.height > 0 && c.label !== undefined)

    // the widest of `what` ("labelNeed", "controlNeed", "resetNeed") in column `col`, over the Section's pairs
    function widest(col, what) {
        let m = 0;
        for (const p of pair.peers) {
            const r = p.members[col];
            if (r)
                m = Math.max(m, r[what]);
        }
        return m;
    }
    // a column's label width, and what the whole column wants
    function labelOf(col) {
        return Math.ceil(pair.widest(col, "labelNeed")) + 4;
    }
    function columnNeed(col) {
        return pair.labelOf(col) + pair.gap + Math.ceil(pair.widest(col, "controlNeed")) + Math.ceil(pair.widest(col, "resetNeed"));
    }
    // the label width when stacked: the longest label of the whole Section's pairs, at least the page's
    function stackedLabel() {
        return Math.min(pair.page ? pair.page.labelMax : 250, Math.max(pair.page ? pair.page.labelCol : 180, pair.labelOf(0), pair.labelOf(1)));
    }

    readonly property bool fits: pair.columnNeed(0) + pair.columnNeed(1) + grid.columnSpacing <= pair.width
    readonly property bool narrow: (pair.page ? pair.page.width < pair.breakAt : false) || !pair.fits
    readonly property int columns: grid.columns

    Layout.fillWidth: true
    implicitHeight: grid.implicitHeight

    GridLayout {
        id: grid
        readonly property bool isPairGrid: true
        width: pair.width
        columns: pair.narrow ? 1 : 2
        columnSpacing: 25
        rowSpacing: 8
        uniformCellWidths: false
    }

    // the line between the two rows, 1 px, in the middle of the column gap
    Rectangle {
        visible: pair.shown.length === 2
        color: Qt.alpha(Theme.fg, 0.06)
        x: pair.narrow ? 0 : (pair.shown[0] ? pair.shown[0].x + pair.shown[0].width : 0) + (grid.columnSpacing - 1) / 2
        y: pair.narrow ? (pair.shown[1] ? pair.shown[1].y : 0) - grid.rowSpacing / 2 : 0
        width: pair.narrow ? pair.width : 1
        height: pair.narrow ? 1 : pair.height
    }

    // each row gets its column's label width and its share (the columns grow from what they need)
    Component.onCompleted: {
        const rows = pair.members;
        rows.forEach((c, i) => {
            c.labelWidth = Qt.binding(() => pair.narrow ? pair.stackedLabel() : pair.labelOf(i));
            c.Layout.preferredWidth = Qt.binding(() => pair.narrow ? pair.width : pair.columnNeed(i));
            // the shorter row of a line sits at the top, so the labels line up
            c.Layout.alignment = Qt.AlignTop | Qt.AlignLeft;
        });
    }
}
