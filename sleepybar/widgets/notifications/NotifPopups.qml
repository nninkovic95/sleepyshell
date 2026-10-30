import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs
import qs.services

// Toasts for new notifications at the top right, under the bar: newest on top or at the bottom and
// up to Settings.toastMax at once (the Notifications tab of the settings window).
// A layer surface on the overlay layer (namespace sleepyshell-popup, which has the blur rule); only
// the column takes input. Hidden while the notifications dropdown is open. Toasts time out into
// the list (Notifs.unpop); hovering one holds its timer.
PanelWindow {
    id: root
    required property var bar
    readonly property bool dropdownOpen: Popouts.current !== null && Popouts.current.name === "notifications"
    // Toasts are let in one at a time, oldest first, so several that arrive together stack one
    // after another instead of appearing at once. `admitted` is newest first like Notifs.popups; one that
    // leaves Notifs.popups (timed out, dismissed) leaves here at once.
    property var admitted: []
    // the newest Settings.toastMax (4 by default); "New toasts" puts the newest on top (default) or at the bottom
    readonly property bool newestOnTop: Settings.toastStack !== "bottom"
    readonly property int maxShown: Math.max(1, Settings.toastMax)
    // Critical toasts keep their place: the slots go to them first, then to the newest others.
    // `kept` stays in admitted order (newest first).
    // Toasts under the pointer are held too: they keep their slot ahead of newer normal ones.
    // Updated a tick later: a hover change can reshuffle `kept`, which destroys or creates cards,
    // whose hover changes again; done at once that was a binding loop on `kept`.
    property var held: []
    // the pointer on a compact row (below) holds the chain as well
    property bool compactHover: false
    readonly property bool frozen: held.length > 0 || compactHover
    // Arrivals while the chain is frozen join its far end as compact rows, oldest first, three at
    // most plus "+N more" ;
    // when the pointer leaves they come in as full toasts one by one.
    readonly property var waiting: Notifs.popups.filter(n => !admitted.includes(n))
    readonly property var compactList: frozen ? waiting.slice(0, 3).reverse() : []
    // arrivals past the three compact rows, split by urgency for the merged pill
    readonly property var compactOver: frozen ? waiting.slice(3) : []
    property var holdQueue: []
    function hold(n, on) {
        holdQueue = holdQueue.concat([[n, on]]);
        Qt.callLater(applyHolds);
    }
    function applyHolds() {
        let h = held;
        for (const [n, on] of holdQueue)
            h = on ? h.concat(h.includes(n) ? [] : [n]) : h.filter(x => x !== n);
        holdQueue = [];
        held = h.filter(n => Notifs.popups.includes(n));
    }
    readonly property var kept: {
        const crit = admitted.filter(n => n.urgency === NotificationUrgency.Critical).slice(0, maxShown);
        const hov = admitted.filter(n => held.includes(n) && !crit.includes(n)).slice(0, Math.max(0, maxShown - crit.length));
        const rest = admitted.filter(n => !crit.includes(n) && !hov.includes(n)).slice(0, Math.max(0, maxShown - crit.length - hov.length));
        return admitted.filter(n => crit.includes(n) || hov.includes(n) || rest.includes(n));
    }
    readonly property var shownList: newestOnTop ? kept : kept.slice().reverse()
    // critical toasts waiting past the limit; a pill says how many
    readonly property int criticalWaiting: admitted.filter(n => n.urgency === NotificationUrgency.Critical && !kept.includes(n)).length
    // One pill at the end of the chain for everything not on screen: "+3 more · 2 critical"
    // (one merged pill when normal and critical overflow meet, instead of two)
    readonly property int moreNormal: compactOver.filter(n => n.urgency !== NotificationUrgency.Critical).length
    readonly property int moreCritical: criticalWaiting + compactOver.filter(n => n.urgency === NotificationUrgency.Critical).length

    Connections {
        target: Notifs
        function onPopupsChanged() {
            root.admitted = root.admitted.filter(n => Notifs.popups.includes(n));
            root.held = root.held.filter(n => Notifs.popups.includes(n));
            if (Notifs.popups.some(n => !root.admitted.includes(n)) && !admit.running)
                admit.start();
        }
    }

    Timer {
        id: admit
        interval: 380
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // While a toast is under the pointer the stack holds still: a new arrival pushed the
            // hovered card from under the pointer, its hover ended and it timed out
            // (seen with notifications arriving mid-hover). They wait their turn.
            if (root.frozen)
                return;
            // A normal toast whose moment has passed goes to the list instead, without using up a
            // turn: after a reload of the bar the queue starts empty and re-admitted old toasts one
            // by one ahead of new ones.
            let waiting = Notifs.popups.filter(n => !root.admitted.includes(n));
            while (waiting.length > 0) {
                const next = waiting[waiting.length - 1];
                const age = Date.now() - (Notifs.times[next.id] ?? Date.now());
                if (next.urgency === NotificationUrgency.Critical || age <= 10000) {
                    root.admitted = [next, ...root.admitted];
                    root.trim();
                    return;
                }
                Notifs.unpop(next);
                waiting = waiting.slice(0, -1);
            }
            stop();
        }
    }

    // A toast pushed past the limit leaves the toast stack (it stays in the bell's list). Kept
    // waiting off screen it had no timer and came back much later, long after it was new.
    // Critical ones are never trimmed; past the limit they wait for a free slot (they have no
    // timeout anyway).
    function trim() {
        for (const n of admitted)
            if (!kept.includes(n) && n.urgency !== NotificationUrgency.Critical && !held.includes(n))
                Notifs.unpop(n);
    }
    onMaxShownChanged: trim()

    screen: bar.screen
    // only on the focused monitor (the main one when the focused one has no bar)
    visible: shownList.length > 0 && !dropdownOpen && MonitorPolicy.isToastScreen(bar.screen)
    color: "transparent"
    anchors.top: true
    anchors.right: true
    // the surface is `pad` larger on every side than the cards, so a hovered card's lift and
    // shadow are not cut off square at the window edge; the cards keep their
    // place 6 px under the bar and from the screen edge
    readonly property int pad: 12
    margins.top: Theme.exclusive + 6 - pad
    margins.right: 6 - pad
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 420 + 2 * pad
    implicitHeight: Math.max(1, stack.implicitHeight + 2 * pad)
    WlrLayershell.namespace: "sleepyshell-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {
        item: stack
    }

    // A Column with transitions, not a ColumnLayout with a per-card Translate: Lift owns each
    // card's transform (its tilt), so the Translate never moved and only the fade showed; and a
    // plain array model rebuilt every card on each change, so they all faded in again.
    // ScriptModel keeps the
    // cards that stay; a new one slides down from under the bar and the others glide down.
    Column {
        id: stack
        x: root.pad
        y: root.pad
        // the window's set width, not its live one: that reads 0 while the surface is hidden or
        // being shown again, and the merged pill centred itself off the left edge (logged x -88)
        width: root.implicitWidth - 2 * root.pad
        spacing: 6

        // about twice the first timings
        // a new toast comes down from under the bar when it goes on top, up into place when it
        // goes at the bottom
        add: Transition {
            NumberAnimation {
                property: "y"
                from: root.newestOnTop ? -60 : ViewTransition.destination.y + 40
                duration: 520
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: 400
            }
        }
        move: Transition {
            NumberAnimation {
                property: "y"
                duration: 500
                easing.type: Easing.OutCubic
            }
        }

        // the pill sits where the waiting (older) ones would be: above when the newest go at the
        // bottom, below when they go on top
        Repeater {
            model: ScriptModel {
                values: root.shownList
            }

            NotifCard {
                id: card
                required property var modelData
                width: stack.width
                // the toasts lean less again than the dropdown's cards
                tiltMax: 2
                notif: modelData
                color: Qt.alpha(Theme.containerHighest, 0.92)

                // expireTimeout is in milliseconds as the app sent it (`notify-send --expire-time=3000`
                // arrives as 3000; read as seconds, Hyprshot's 5000 kept its
                // toast up for 83 minutes); <= 0 means no time given, so 5 s. Critical ones stay
                // until dismissed.
                Timer {
                    interval: card.notif.expireTimeout > 0 ? card.notif.expireTimeout : 5000
                    // every toast's timer waits while any toast is hovered: one timing out above
                    // the hovered card moved it up the chain
                    running: !card.critical && !card.hovered && !root.frozen
                    onTriggered: Notifs.unpop(card.notif)
                }
                onHoveredChanged: root.hold(card.notif, hovered)

                onActivated: Notifs.unpop(card.notif)
            }
        }

        // compact arrivals; their own Column, so the stack's add transition (which flies a new
        // toast in from the top) does not apply to them
        Column {
            id: compactCol
            width: stack.width
            spacing: 4

            add: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 300
                }
            }

            Repeater {
                model: ScriptModel {
                    values: root.compactList
                }

                CompactToast {
                    required property var modelData
                    width: compactCol.width
                    notif: modelData
                    onHoveredChanged: root.compactHover = hovered
                    // a row clicked away under the pointer never reports the hover ending
                    // (only for a hovered row, and guarded: on a reload the window is gone first)
                    Component.onDestruction: {
                        if (!hovered)
                            return;
                        const w = root;
                        Qt.callLater(() => {
                            try {
                                w.compactHover = false;
                            } catch (e) {}
                        });
                    }
                }
            }

        }

        MorePill {
            visible: root.moreNormal + root.moreCritical > 0
            count: root.moreNormal
            criticalCount: root.moreCritical
            x: Math.round((stack.width - width) / 2)
        }
    }
}
