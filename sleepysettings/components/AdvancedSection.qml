import QtQuick
import QtQuick.Layouts
import qs
import qs.services

// The "Advanced" fold that ends a tab: a CollapseHeader
// (chevron and title, plus the accent count pill only while a setting inside is unapplied) and, under it, a
// card of the rare rows. At most one per tab and always the last Section; collapsed by default.
// Rows are declared inside as in a Section and keep their normal widgets. A closed fold does not lose a
// row: the rows stay in the tree, so the sidebar search finds and counts them (TabPage.countHits), and a
// hit opens the fold (for as long as the search lasts; clearing it puts the remembered state back).
// Open or closed is remembered per tab in sleepysettings.toml (`advancedOpen`, saved at once by Settings.setNow,
// no Apply: it is a choice about the window, like "Show unavailable tabs"). The tab registers the fold as
// `advanced`, which the tests use.
ColumnLayout {
    id: adv
    objectName: "advancedSection"
    default property alias rows: card.rows
    // the pill: unapplied rows inside; a tab with its own draft (Display) sets this itself
    property int pending: adv.countStaged(card)
    readonly property string title: "Advanced"

    readonly property var page: {
        let p = adv.parent;
        while (p && p.isTabPage !== true)
            p = p.parent;
        return p ?? null;
    }
    readonly property string tabKey: adv.page ? adv.page.key : ""
    // the remembered state, from sleepysettings.toml
    readonly property bool remembered: Settings.advancedOpen.split(",").includes(adv.tabKey)
    // what is drawn: the remembered state, or open because the search found a row inside
    property bool expanded: false
    readonly property string query: adv.page ? adv.page.query : ""
    // how many rows inside the search finds; counted after the rows have taken the new query (a binding on it looped)
    property int hits: 0
    function recount() {
        adv.hits = adv.query === "" || !adv.page ? 0 : adv.page.countHits(card);
    }

    Layout.fillWidth: true
    spacing: 6

    function countStaged(item) {
        let n = 0;
        const kids = item.children;
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i];
            if (c.searchOff === true)
                continue;
            if (c.staged !== undefined)
                n += c.staged ? 1 : 0;
            else
                n += adv.countStaged(c);
        }
        return n;
    }

    // the header's click: draw the other state, and remember it unless a search is holding the fold open
    function toggle() {
        adv.expanded = !adv.expanded;
        if (adv.query !== "")
            return;
        const keys = Settings.advancedOpen.split(",").filter(k => k !== "" && k !== adv.tabKey);
        if (adv.expanded)
            keys.push(adv.tabKey);
        Settings.setNow("advancedOpen", keys.join(","));
    }

    onRememberedChanged: if (adv.query === "")
        adv.expanded = adv.remembered
    onQueryChanged: {
        if (adv.query === "")
            adv.expanded = adv.remembered;
        Qt.callLater(adv.recount);
    }
    onHitsChanged: if (adv.hits > 0)
        adv.expanded = true
    Component.onCompleted: {
        adv.expanded = adv.remembered;
        if (adv.page)
            adv.page.advanced = adv;
    }

    CollapseHeader {
        objectName: "advancedHeader"
        title: adv.title
        open: adv.expanded
        pending: adv.pending
        onToggled: adv.toggle()
    }

    // `indexTitle`: a row's search text includes it, so "advanced" finds the folded rows
    Section {
        id: card
        visible: adv.expanded
        indexTitle: adv.title
    }
}
