import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services

// Base of every settings tab: what the window's sidebar, title row and shared Apply bar read.
// A tab that stages Settings keys names its `group` (a Settings.groups key) and gets dirty,
// Apply and Discard from it (Reset to defaults is in the Config tab). A tab with its own draft (Display, Keybinds) leaves group
// empty, binds `dirty` and handles applying() and discarding(). applying() runs before the group
// is committed, so a tab can still see what is about to change (Theme).
ColumnLayout {
    id: page
    // SettingRows find their page by this, up the parent chain
    readonly property bool isTabPage: true
    // sidebar entry
    property string key: ""
    property string label: ""
    // extra words the sidebar search finds the tab by, besides its name (the Apps tab: "workspace")
    property string tags: ""
    property int icon: 0
    // the window's overlays (Sleepysettings passes them in; rows reach the tooltip through the page)
    property var tooltip: null
    property var picker: null
    property var folders: null
    property var confirm: null
    // the tool editor dialog (the Centre island tab)
    property var toolDialog: null
    // the sidebar search in lower case, "" when not searching; rows it does not find dim
    property string query: ""
    // how many rows on this tab the search finds (a tab with its own list counts that instead)
    property int hits: page.query === "" ? 0 : page.countHits(page)

    // the label column of this tab's rows: the longest label of any row outside a PairRow, between
    // 180 and labelMax px (a row reports its label; a label past the cap is cut and shows in a tooltip)
    // (a tab with long labels raises it: the Theme tab's two long switch names)
    property int labelMax: 250
    property int labelCol: 180
    property var labelNeeds: null
    function reportLabel(row, need) {
        if (!page.labelNeeds)
            page.labelNeeds = new Map();
        page.labelNeeds.set(row, need);
        page.recomputeLabelCol();
    }
    function forgetLabel(row) {
        if (page.labelNeeds) {
            page.labelNeeds.delete(row);
            page.recomputeLabelCol();
        }
    }
    function recomputeLabelCol() {
        let m = 180;
        page.labelNeeds.forEach(v => {
            m = Math.max(m, v);
        });
        page.labelCol = Math.min(page.labelMax, Math.ceil(m + 4));
    }

    // the tab's Advanced fold (AdvancedSection registers itself), null when the tab has none
    property var advanced: null

    property string group: ""
    // keys of other groups that rows on this tab edit too (the Config tab edits the Theme tab's wallpaperDir)
    property var extraKeys: []
    // true: the sidebar draws the entry greyed, but it still opens (the Power tab on a machine with no
    // battery and no backlight; it is not hidden)
    property bool dimmed: false
    // programs the whole tab needs (services/Deps.qml): while one is missing the page is greyed out and
    // disabled under a line that says what is missing, and the sidebar hides the tab unless
    // "Show unavailable tabs" is on
    property var requires: []
    readonly property string needsText: Deps.needs(page.requires)
    // files the whole tab depends on (FileChecks ids): while one is missing, read-only or not loaded by Hyprland the tab's
    // content is greyed out under a notice that says why (FileNotice); the Apply bar and the sidebar stay as they are
    property var fileIds: []
    readonly property string fileText: FileChecks.needs(page.fileIds)
    // the tab cannot work here: nothing to work on (dimmed) or programs missing
    readonly property bool unavailable: page.dimmed || page.needsText !== ""
    readonly property var keys: (page.group !== "" ? Settings.groups[page.group] : []).concat(page.extraKeys)
    readonly property int changes: page.keys.filter(k => Settings.pending.hasOwnProperty(k)).length
    property bool dirty: page.changes > 0
    property bool busy: false
    property string dirtyText: page.changes === 1 ? "1 unapplied change" : page.changes > 1 ? page.changes + " unapplied changes" : "Unapplied changes"
    // a keep-or-revert countdown runs (Display): the Apply bar shows Revert and Keep, and leaving
    // the tab asks Keep or Revert, since the change would otherwise revert unseen
    property bool pending: false
    property string pendingText: ""
    // Apply from the leave dialog stays on this tab (Display: Apply starts the countdown, whose
    // buttons the tab must show) instead of going where the user was heading
    property bool applyStays: false
    // what Apply does, shown in the Apply bar while nothing is pending
    property string note: "Apply saves to " + Settings.tilde(Settings.path)
    // the files Apply modifies, as the Apply bar lists them (~ for home), and a line for what it
    // runs afterwards; a tab that writes elsewhere sets these
    property var files: page.group !== "" ? [Settings.tilde(Settings.path)] : []
    property string afterNote: ""

    signal applying()
    signal discarding()
    signal keeping()
    signal reverting()

    // rows (anything with searchText and searchHit) under `item` that the search finds
    function countHits(item) {
        let n = 0;
        const kids = item.children;
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i];
            // a group that does not exist here (the on-battery idle set on a desktop) sets searchOff: its rows are not counted
            if (c.searchOff === true)
                continue;
            if (c.searchText !== undefined)
                n += c.searchHit ? 1 : 0;
            else
                n += page.countHits(c);
        }
        return n;
    }

    function apply() {
        page.applying();
        if (page.keys.length > 0)
            Settings.commit(page.keys);
    }

    function discard() {
        page.discarding();
        if (page.keys.length > 0)
            Settings.drop(page.keys);
    }

    function keep() {
        page.keeping();
    }

    function revert() {
        page.reverting();
    }

    // the stack's width also while hidden: StackLayout sizes only the open page, and a hidden one
    // at its implicit width (131 px) wrapped its hints so tall that the window, which is as tall
    // as the tallest page, grew by 200 px
    width: parent ? parent.width : implicitWidth
    spacing: 8
    enabled: page.needsText === ""
    opacity: page.needsText === "" ? 1 : 0.5

    // the tab's own rows go in `body`, so a file problem can grey them without greying the notice and its buttons
    default property alias content: body.data

    SmallText {
        visible: page.needsText !== ""
        text: page.needsText
        color: Theme.urgentFg
    }

    FileNotice {
        ids: page.fileIds
        tooltip: page.tooltip
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: page.spacing
        enabled: page.fileText === ""
        opacity: page.fileText === "" ? 1 : 0.5
    }
}
