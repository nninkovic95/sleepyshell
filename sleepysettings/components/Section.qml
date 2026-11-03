import QtQuick
import QtQuick.Layouts
import qs
import qs.services

// A titled group of settings rows on a card. Rows
// declared inside go on the card, with a hairline between each two that are shown. Every card
// has the same inner margins, so labels, controls and reset buttons line up across cards.
// `requires` names programs the whole group needs (services/Deps.qml): while one is missing the
// card is greyed out and disabled and a line under the title says what is missing.
ColumnLayout {
    id: sec
    property string title: ""
    // what a row's search text includes of this card: the title unless the card says otherwise
    property string indexTitle: sec.title
    property var requires: []
    readonly property string needsText: Deps.needs(sec.requires)
    // files the card depends on (FileChecks ids): a notice under the title says what is wrong, and the card greys out
    // while one is missing, read-only or not loaded by Hyprland
    property var fileIds: []
    // the file notice as one short line with a link to the Config tab (the Keybinds tab)
    property bool briefNotice: false
    readonly property string fileText: FileChecks.needs(sec.fileIds)
    // the TabPage this card is on (its tooltip)
    readonly property var page: {
        let p = sec.parent;
        while (p && p.isTabPage !== true)
            p = p.parent;
        return p ?? null;
    }
    default property alias rows: body.data
    // a "!" tip right after the title (the Keybinds tab's built-in list says where it reads from)
    property string titleTip: ""
    // items at the right end of the title row (a button that acts on the whole card)
    property alias headerItems: headerRow.data
    Layout.fillWidth: true
    spacing: 6

    RowLayout {
        id: headerRow
        visible: sec.title !== ""
        Layout.fillWidth: true
        spacing: 8

        Heading {
            text: sec.title
            Layout.fillWidth: sec.titleTip === ""
        }

        InfoTip {
            visible: sec.titleTip !== ""
            Layout.topMargin: 8
            tooltip: sec.page ? sec.page.tooltip : null
            text: sec.titleTip
        }

        Item {
            visible: sec.titleTip !== ""
            Layout.fillWidth: true
        }
    }

    SmallText {
        visible: sec.needsText !== ""
        Layout.leftMargin: 2
        text: sec.needsText
    }

    FileNotice {
        ids: sec.fileIds
        brief: sec.briefNotice
        tooltip: sec.page ? sec.page.tooltip : null
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + 12
        radius: Theme.radiusLg
        color: Theme.container
        // the card's own switch, so a caller's `enabled` on the Section still works beside it
        enabled: sec.needsText === "" && sec.fileText === ""
        opacity: enabled ? 1 : 0.5

        ColumnLayout {
            id: body
            // the rows that take room (a Repeater is an item too, but has no size)
            readonly property var shown: Array.prototype.filter.call(visibleChildren, c => c.height > 0)
            x: 12
            y: 6
            width: parent.width - 24
            spacing: 8
        }

        Repeater {
            model: Math.max(0, body.shown.length - 1)

            Rectangle {
                required property int index
                x: 12
                // a delegate can re-evaluate once more after a row hides, before the model shrinks
                y: body.y + (body.shown[index + 1]?.y ?? 0) - body.spacing / 2
                width: parent.width - 24
                height: 1
                color: Qt.alpha(Theme.fg, 0.06)
            }
        }
    }
}
