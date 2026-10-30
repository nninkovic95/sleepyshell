import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services
import qs.sleepybar.components

// Bell with the number of waiting notifications; click: dropdown with the list (the bar is the
// notification daemon, see services/Notifs.qml). Only on the bar while something is waiting
// (the rule for right-island widgets that matter sometimes, like the updater).
BarButton {
    id: root
    required property var bar
    readonly property bool shown: Notifs.count > 0
    inset: true

    glyph: Notifs.dnd ? 0xF009B : 0xF009A
    text: String(Notifs.count)
    fg: Notifs.dnd ? Theme.fgMuted : Theme.fg
    bg: pop.open ? Theme.hoverBg : "transparent"
    onClicked: pop.toggle()

    // the button leaves the bar at zero; do not leave the dropdown hanging
    Connections {
        target: Notifs
        function onCountChanged() {
            if (Notifs.count === 0)
                pop.open = false;
        }
    }

    // Clear all's beat: every tick (30 ms) the next card from the top is offered its turn (Notifs.swipeOne);
    // it takes it only when it is in view, else the beat waits for the list to move it up. Sent on a
    // fixed beat regardless, cards came up out of view: some slid in late, the last few were dropped
    // unseen at once. If nothing takes a turn for about 2.5 s, the rest go.
    property var swept: []
    property int idleBeats: 0
    // a card starts 100 ms after the one before it, every card alike: on a quick beat the cards
    // already on screen left as a group before the list moved up, and only the later ones went one
    // by one
    property real lastStart: 0
    readonly property var listOrder: Settings.notifOrder === "oldest" ? Notifs.list.slice().reverse() : Notifs.list
    Timer {
        id: sweep
        running: Notifs.clearing
        repeat: true
        triggeredOnStart: true
        interval: 30
        onRunningChanged: {
            if (running) {
                root.swept = [];
                root.idleBeats = 0;
            }
        }
        onTriggered: {
            if (Date.now() - root.lastStart < 100)
                return;
            const next = root.listOrder.find(n => !root.swept.includes(n));
            if (!next)
                return;
            Notifs.swipeOne(next);
            if (Notifs.swipeWasTaken(next.id)) {
                root.swept = root.swept.concat([next]);
                root.idleBeats = 0;
                root.lastStart = Date.now();
            } else if (++root.idleBeats * sweep.interval > 2500) {
                Notifs.clearAll();
            }
        }
    }

    // closed in the middle of a Clear all: the cards are gone, so clear the rest at once
    Connections {
        target: pop
        function onOpenChanged() {
            if (!pop.open && Notifs.clearing)
                Notifs.clearAll();
        }
    }

    IslandDropdown {
        id: pop
        name: "notifications"
        fixedWidth: 420
        anchorItem: root
        bar: root.bar

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 4
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "Notifications"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 2
                font.bold: true
                color: Theme.fg
            }

            Text {
                text: "Do not disturb"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                color: Theme.fgMuted
            }

            Toggle {
                checked: Notifs.dnd
                onClicked: Notifs.toggleDnd()
            }

            BarButton {
                text: "Clear all"
                hpad: 8
                glued: false
                // the cards swipe out one by one, including the ones the list creates as it scrolls
                onClicked: Notifs.startClear()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 4
            implicitHeight: 1
            color: Theme.containerHighest
        }

        // room around the cards for their hover lift and tilt: the list clips, and a card scaled to
        // its full width lost its rounded corners at the clip edge
        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight + topMargin + bottomMargin, 460)
            visible: Notifs.count > 0
            clip: true
            spacing: 6
            leftMargin: Theme.liftMaxPx
            rightMargin: Theme.liftMaxPx
            topMargin: Theme.liftMaxPx
            bottomMargin: Theme.liftMaxPx
            // Settings' "List order"
            // a ScriptModel, not the array itself: a new array rebuilt every card on each change,
            // which cut the Clear all swipes short and skipped the displaced transition
            model: ScriptModel {
                values: root.listOrder
            }

            // the cards below close the gap smoothly as one leaves (Clear all, a dismissed card)
            displaced: Transition {
                NumberAnimation {
                    property: "y"
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            delegate: NotifCard {
                required property var modelData
                required property int index
                width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
                swipeIndex: index
                notif: modelData
                onActivated: pop.open = false
            }
        }

        Text {
            visible: Notifs.count === 0
            Layout.leftMargin: 10
            text: "No notifications"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            color: Theme.fgMuted
        }
    }
}
