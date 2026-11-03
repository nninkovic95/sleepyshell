import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// One settings row: the label (FieldLabel, with an optional "!" tip) in a fixed column, then the
// control, then a reset button. Children declared in a SettingRow go into the control slot,
// left-aligned; one that should take the rest of the row sets Layout.fillWidth. `hint` is a
// muted line under the control, `error` replaces it in the urgent colour. NumberRow, SwitchRow,
// ChoiceRow, ComboRow and FieldRow are SettingRows bound to a Settings `key`; the Display tab
// uses it bare. A keyed row marks an unapplied change (a bar left of the label) and shows the
// reset button while its value is not the default; the button stages the default, so Apply is
// still needed. The settings search (TabPage.query) dims rows it does not find. `requires` names
// programs the row needs (services/Deps.qml): while one is missing the row is greyed out, its
// control disabled, and the hint line says "Needs ... (not installed)" instead of anything running.
RowLayout {
    id: row
    property string label: ""
    property string info: ""
    property bool warn: false
    property var tooltip: null      // null: the page's
    property string hint: ""
    // a short muted description under the label, in the label column (the Config tab's file rows: the description
    // belongs to the name, not to the path); the control then centres against the two lines
    property string describe: ""
    property string error: ""
    // the Settings key this row edits; "" for a row that edits something else
    property string key: ""
    // how a value of this row reads, for the reset button's tip
    property var format: v => String(v)
    // more words the settings search finds this row by
    property string tags: ""
    // the label column's width: the page's (TabPage.labelCol, sized for the longest label on the
    // tab, at least 180); a PairRow sets its own for the rows it holds
    readonly property bool paired: row.parent !== null && row.parent.isPairGrid === true
    property int labelWidth: row.page ? row.page.labelCol : 180
    // what the row would like, for the PairRow and the page to size columns from: the label with its
    // badge, the control, the revert arrow and its gap
    readonly property real labelNeed: lbl.natural
    readonly property real controlNeed: slot.implicitWidth
    readonly property real resetNeed: reset.implicitWidth + row.spacing
    // programs this row needs; missing ones grey it out (Deps.needs gives the message)
    property var requires: []
    // lit up for a moment: "Configure in Config" points at the row that fixes a file problem (FilesTab.reveal)
    property bool flash: false
    readonly property string needsText: Deps.needs(row.requires)
    readonly property bool available: row.needsText === ""
    default property alias controls: slot.data
    // items under the control and its hint line (a file notice under a row)
    property alias below: belowCol.data

    // the TabPage this row is on (its tooltip and search query), up the parent chain
    readonly property var page: {
        let p = row.parent;
        while (p && p.isTabPage !== true)
            p = p.parent;
        return p ?? null;
    }
    readonly property var tip: row.tooltip ?? (row.page ? row.page.tooltip : null)
    readonly property bool keyed: row.key !== "" && Settings.schema[row.key] !== undefined
    // a row that edits something other than a Settings key (the Display tab's monitor draft, the monitor's live DDC values) says
    // by itself when it has an unapplied change (`changedMark`) and when its revert arrow shows (`canRevert`); the arrow then emits
    // `revertRequested()` and its tip says `revertText` (what the arrow goes back to)
    property bool changedMark: false
    property bool canRevert: false
    property string revertText: ""
    signal revertRequested()
    readonly property bool staged: (row.keyed && Settings.pending.hasOwnProperty(row.key)) || row.changedMark
    readonly property bool resettable: row.keyed ? Settings.get(row.key) !== Settings.schema[row.key].def : row.canRevert
    // more words the search finds the row by: its options (ChoiceRow, ComboRow set them)
    property string extraSearch: ""
    // the card the row is on: a hit on its title is a hit on every row of it
    readonly property string sectionTitle: {
        let p = row.parent;
        while (p && !(p.title !== undefined && p.rows !== undefined))
            p = p.parent;
        return p ? (p.indexTitle ?? p.title) : "";
    }
    // label, tip, tags, the description line, option labels and the section's title, folded (Settings.norm)
    readonly property string searchText: Settings.norm(row.label + " " + row.info.replace(/<[^>]*>/g, "") + " " + row.tags + " " + row.hint + " " + row.describe + " " + row.extraSearch + " " + row.sectionTitle)
    readonly property bool searchHit: !row.page || row.page.query === "" || Settings.searchMatch(row.searchText, row.page.query)

    Layout.fillWidth: true
    spacing: 10

    // a row outside a PairRow tells the page how wide its label wants to be
    onLabelNeedChanged: {
        if (row.page && !row.paired)
            row.page.reportLabel(row, row.labelNeed);
    }
    Component.onCompleted: {
        if (row.page && !row.paired)
            row.page.reportLabel(row, row.labelNeed);
    }
    Component.onDestruction: {
        if (row.page)
            row.page.forgetLabel(row);
    }

    opacity: (enabled ? 1 : 0.5) * (row.available ? 1 : 0.5) * (searchHit ? 1 : 0.3)
    Behavior on opacity {
        NumberAnimation {
            duration: 120
        }
    }

    // the light behind a row that was pointed at. A layout child that takes no room (no width, the row's spacing taken back, no
    // height), under the row's own parts; QtQuick.Layouts has no "ignore"
    Item {
        Layout.preferredWidth: 0
        Layout.maximumWidth: 0
        Layout.preferredHeight: 0
        Layout.rightMargin: -row.spacing
        Layout.alignment: Qt.AlignTop
        z: -1

        Rectangle {
            objectName: "rowFlash"
            x: -8
            y: -4
            width: row.width + 16
            height: row.height + 8
            radius: Theme.radiusMd
            color: Qt.alpha(Theme.accent, 0.28)
            opacity: row.flash ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 350
                }
            }
        }
    }

    ColumnLayout {
        Layout.alignment: Qt.AlignTop
        // a nested layout would otherwise take its share of the spare width
        Layout.fillWidth: false
        Layout.minimumWidth: row.labelWidth
        Layout.preferredWidth: row.labelWidth
        Layout.maximumWidth: row.labelWidth
        spacing: 0

        FieldLabel {
            id: lbl
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            text: row.label
            info: row.info
            warn: row.warn
            marked: row.staged
            tooltip: row.tip
        }

        SmallText {
            objectName: "rowDescribe"
            visible: row.describe !== ""
            text: row.describe
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: row.describe !== "" ? Qt.AlignVCenter : Qt.AlignTop
        spacing: 4

        RowLayout {
            id: slot
            enabled: row.available
            Layout.fillWidth: true
            Layout.minimumHeight: 30
            spacing: 6
        }

        SmallText {
            visible: text !== ""
            text: row.needsText !== "" ? row.needsText : row.error !== "" ? row.error : row.hint
            color: row.needsText === "" && row.error !== "" ? Theme.urgentFg : Theme.fgMuted
        }

        ColumnLayout {
            id: belowCol
            Layout.fillWidth: true
            spacing: 4
        }
    }

    // keeps its room when hidden, so every row's control ends at the same x
    BarButton {
        id: reset
        Layout.alignment: row.describe !== "" ? Qt.AlignVCenter : Qt.AlignTop
        Layout.topMargin: row.describe !== "" ? 0 : (30 - implicitHeight) / 2
        glyph: 0xF054C
        hpad: 4
        glued: false
        fg: Theme.fgMuted
        hoverFg: Theme.fg
        opacity: row.resettable ? 1 : 0
        enabled: row.resettable && row.available
        onClicked: {
            if (row.keyed)
                Settings.stage(row.key, Settings.schema[row.key].def);
            else
                row.revertRequested();
        }
        onHoveredChanged: {
            if (!row.tip || !(row.keyed || row.revertText !== ""))
                return;
            if (hovered)
                row.tip.show(reset, row.keyed ? "Back to the default, <b>" + String(row.format(Settings.schema[row.key].def)).replace(/</g, "&lt;") + "</b>. Nothing changes until Apply." : row.revertText, false);
            else
                row.tip.hide(reset);
        }
    }
}
