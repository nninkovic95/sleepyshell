import QtQuick
import qs

// Window-wide hover tip for InfoTip icons. Fill the window with it and put it above the pages;
// InfoTip calls show() on hover and hide() on leave. Takes no input, so it never blocks clicks.
Item {
    id: tip
    property Item anchor: null
    property string text: ""
    property bool warn: false
    // shown only while the item it describes can still be hovered (so a tip never stays over
    // another tab): an anchor that is hidden (its tab was left, a card folded) hides the tip and lets it go, so it does
    // not come back with the tab. The window also calls dismiss() when a tab changes, a dialog or picker opens,
    // Escape is pressed, the window is hidden or loses the focus, and a list scrolls.
    visible: anchor !== null && anchor.visible
    // above the leave dialog (z 30): its file chips have a tip too
    z: 40

    function show(item, t, w) {
        text = t;
        warn = w;
        anchor = item;
        const p = item.mapToItem(tip, item.width / 2, item.height + 6);
        box.x = Math.max(8, Math.min(p.x - 18, tip.width - box.width - 8));
        // below the icon, or above it when there is no room
        box.y = p.y + box.height + 8 > tip.height ? item.mapToItem(tip, 0, 0).y - box.height - 6 : p.y;
    }

    function dismiss() {
        anchor = null;
    }

    Connections {
        target: tip.anchor
        ignoreUnknownSignals: true
        function onVisibleChanged() {
            if (tip.anchor && !tip.anchor.visible)
                tip.anchor = null;
        }
    }

    function hide(item) {
        if (anchor === item)
            anchor = null;
    }

    Rectangle {
        id: box
        width: Math.min(340, label.implicitWidth + 24)
        height: label.implicitHeight + 16
        radius: Theme.radiusMd
        color: Theme.containerHigh
        border.width: 1
        border.color: Qt.alpha(tip.warn ? Theme.urgentFg : Theme.primary, 0.35)

        Text {
            id: label
            x: 12
            y: 8
            width: Math.min(implicitWidth, 316)
            wrapMode: Text.WordWrap
            text: tip.text
            textFormat: Text.StyledText
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
            lineHeight: 1.15
            color: Theme.fg
        }
    }
}
