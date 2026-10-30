import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services

// The calendar's content: month grid and the selected day's events, without a window around it and without
// a surface of its own (the window paints the fill; Hyprland draws border, rounding and shadow), so
// CalendarPopup.qml (a floating toplevel window) stays thin and a test window can show the same
// thing 1:1.
//
// Size follows the screen (screenW, screenH): about 30 % of the width and 44 % of the height, at least
// 600 x 520, at most 900 x 760 (760 x 634 on a 2560 x 1440 screen). Wide layout (inner width of 660 px or
// more): the grid on the left, the selected day on the right (date, event list, the two buttons). Narrower:
// the day's block goes under the grid, and cells too short for titles (under 58 px) show only their dots.
// A day cell shows its number, up to three calendar-coloured dots, and (when the cell is tall enough)
// up to two event titles as chips, "+N more" for the rest.
//
// Keys (handleKey, called by Keys.onPressed): arrows move the selection by a day or a week (the month
// follows), PgUp / PgDn change the month, Home goes to today, Enter moves into the day's events (Up / Down
// pick one, Enter opens khal, Esc or Left goes back to the grid), Esc closes. The wheel over the grid
// changes the month.
// Hover follows CLAUDE.md's holder pattern: the Lift sits in a background child of each day cell and the
// number and chips stay siblings at scale 1, so they are never blurred.
Item {
    id: root

    signal closeRequested
    signal openKhal

    property int screenW: 2560
    property int screenH: 1440

    // the size the window opens at; the window may be resized (the layout follows width and height)
    readonly property int defaultW: Math.max(600, Math.min(900, Math.round(root.screenW * 0.3)))
    readonly property int defaultH: Math.max(520, Math.min(760, Math.round(root.screenH * 0.44)))
    readonly property int minW: 600
    readonly property int minH: 520
    width: root.defaultW
    height: root.defaultH

    readonly property int pad: 24
    readonly property int gap: 24
    readonly property int innerW: root.width - 2 * root.pad
    readonly property int innerH: root.height - 2 * root.pad
    readonly property bool wide: root.innerW >= 660
    readonly property int sideMin: 236
    readonly property int headH: 40
    readonly property int wdH: 24
    // under the grid in the narrow layout: date line, list, buttons and the gaps between
    readonly property int belowH: 196

    readonly property int cellW: root.wide ? Math.min(80, Math.floor((root.innerW - root.gap - root.sideMin) / 7)) : Math.floor(root.innerW / 7)
    readonly property int cellH: Math.max(34, Math.min(92, Math.floor((root.innerH - root.headH - root.wdH - 8 - (root.wide ? 0 : root.belowH)) / 6)))
    readonly property int gridW: 7 * root.cellW
    readonly property bool showTitles: root.cellH >= 58
    // title lines that fit under the number (14 px each, at most three counting the "+N more" line)
    readonly property int cap: root.showTitles ? Math.max(0, Math.min(3, Math.floor((root.cellH - 28) / 15))) : 0

    property var today: Calendar.day(2000, 0, 1)
    property var selected: today
    property var shown: Calendar.day(2000, 0, 1)      // the 1st of the month on show
    property bool eventFocus: false
    property int evIndex: 0
    property bool ready: false

    // the first of the 42 days drawn: back from the 1st to khal's first weekday
    readonly property var gridStart: {
        const first = root.shown;
        const monOffset = (first.getDay() + 6) % 7;
        return Calendar.addDays(first, -((monOffset - Calendar.firstWeekday + 7) % 7));
    }
    readonly property var dayEvents: Calendar.eventsOn(root.selected)
    readonly property bool khalOk: Deps.has("ikhal") && Deps.has(Settings.defaultTerminal)
    readonly property var weekdays: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    onGridStartChanged: if (root.ready)
        root.request()

    function request() {
        Calendar.setRange(root.gridStart, Calendar.addDays(root.gridStart, 41));
    }

    function monthOf(d) {
        return Calendar.day(d.getFullYear(), d.getMonth(), 1);
    }

    function dayOf(d) {
        return Calendar.day(d.getFullYear(), d.getMonth(), d.getDate());
    }

    // fresh state each time the popup opens: today selected, its month shown, the data re-read
    function reset() {
        root.today = root.dayOf(new Date());
        root.selected = root.today;
        root.shown = root.monthOf(root.today);
        root.eventFocus = false;
        root.ready = true;
        root.request();
    }

    function goToday() {
        root.today = root.dayOf(new Date());
        root.select(root.today);
    }

    // select a day; the shown month follows it
    function select(d) {
        root.eventFocus = false;
        root.selected = d;
        const m = root.monthOf(d);
        if (m.getTime() !== root.shown.getTime())
            root.shown = m;
    }

    // a month ahead or back, keeping the day number where the month is long enough
    function shiftMonth(n) {
        const s = root.selected;
        const first = Calendar.day(root.shown.getFullYear(), root.shown.getMonth() + n, 1);
        const dim = Calendar.day(first.getFullYear(), first.getMonth() + 1, 0).getDate();
        root.eventFocus = false;
        root.shown = first;
        root.selected = Calendar.day(first.getFullYear(), first.getMonth(), Math.min(s.getDate(), dim));
    }

    // what a day cell prints under its number: [{t: title, c: colour}] and a last {more: N} line.
    // Up to two titles; with room for a third line the rest become "+N more", with room for two the
    // second title is given up for it, and with one line only a count is left.
    function chips(evs, cap) {
        const n = evs.length;
        const out = [];
        if (n === 0 || cap <= 0)
            return out;
        const one = e => ({ t: e.title, c: e.color });
        if (n <= 2 && n <= cap) {
            evs.forEach(e => out.push(one(e)));
        } else if (cap >= 3) {
            out.push(one(evs[0]), one(evs[1]), { more: n - 2 });
        } else if (cap === 2) {
            out.push(one(evs[0]), { more: n - 1 });
        } else {
            out.push({ more: n, all: true });
        }
        return out;
    }

    function handleKey(key, mods) {
        if (root.eventFocus) {
            if (key === Qt.Key_Down)
                root.evIndex = Math.min(root.dayEvents.length - 1, root.evIndex + 1);
            else if (key === Qt.Key_Up)
                root.evIndex = Math.max(0, root.evIndex - 1);
            else if (key === Qt.Key_Return || key === Qt.Key_Enter)
                root.openKhal();
            else if (key === Qt.Key_Escape || key === Qt.Key_Left || key === Qt.Key_Backspace)
                root.eventFocus = false;
            else
                return false;
            return true;
        }
        const s = root.selected;
        switch (key) {
        case Qt.Key_Left:
            root.select(Calendar.addDays(s, -1));
            return true;
        case Qt.Key_Right:
            root.select(Calendar.addDays(s, 1));
            return true;
        case Qt.Key_Up:
            root.select(Calendar.addDays(s, -7));
            return true;
        case Qt.Key_Down:
            root.select(Calendar.addDays(s, 7));
            return true;
        case Qt.Key_PageUp:
            root.shiftMonth(-1);
            return true;
        case Qt.Key_PageDown:
            root.shiftMonth(1);
            return true;
        case Qt.Key_Home:
            root.goToday();
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (root.dayEvents.length > 0) {
                root.evIndex = 0;
                root.eventFocus = true;
            }
            return true;
        case Qt.Key_Escape:
            root.closeRequested();
            return true;
        }
        return false;
    }

    // the day number changes at midnight while the panel stays open
    Timer {
        interval: 60000
        repeat: true
        running: root.ready
        onTriggered: {
            const t = root.dayOf(new Date());
            if (t.getTime() !== root.today.getTime())
                root.today = t;
        }
    }

    focus: true
    Keys.onPressed: e => e.accepted = root.handleKey(e.key, e.modifiers)

    Item {
        id: body
        x: root.pad
        y: root.pad
        width: root.innerW
        height: root.innerH

        // month and year, previous / next, Today
        RowLayout {
            id: head
            x: root.wide ? 0 : Math.round((root.innerW - root.gridW) / 2)
            width: root.gridW
            height: root.headH
            spacing: 4

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                text: Calendar.monthsLong[root.shown.getMonth()] + " " + root.shown.getFullYear()
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 9
                font.bold: true
                color: Theme.fg
            }

            BarButton {
                glyph: 0xF0141
                glued: false
                onClicked: root.shiftMonth(-1)
            }

            BarButton {
                glyph: 0xF0142
                glued: false
                onClicked: root.shiftMonth(1)
            }

            BarButton {
                text: "Today"
                glued: false
                onClicked: root.goToday()
            }
        }

        Row {
            id: weekRow
            x: head.x
            y: root.headH + 4
            Repeater {
                model: 7

                Text {
                    required property int index
                    width: root.cellW
                    height: root.wdH
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdays[(index + Calendar.firstWeekday) % 7]
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.fgMuted
                }
            }
        }

        // 6 weeks of 7 days
        Item {
            id: grid
            x: head.x
            y: root.headH + 4 + root.wdH
            width: root.gridW
            height: 6 * root.cellH
            property real wheelAcc: 0

            Repeater {
                model: 42

                Item {
                    id: cell
                    required property int index
                    readonly property var date: Calendar.addDays(root.gridStart, cell.index)
                    readonly property bool inMonth: cell.date.getMonth() === root.shown.getMonth()
                    readonly property bool isToday: cell.date.getTime() === root.today.getTime()
                    readonly property bool isSel: cell.date.getTime() === root.selected.getTime()
                    readonly property var dots: Calendar.dotColours(cell.date)
                    readonly property var lines: root.chips(Calendar.eventsOn(cell.date), root.cap)

                    x: (cell.index % 7) * root.cellW
                    y: Math.floor(cell.index / 7) * root.cellH
                    width: root.cellW
                    height: root.cellH
                    // above its neighbours while lifted, so the shadow is not covered
                    z: surface.z

                    Item {
                        anchors.fill: parent
                        anchors.margins: 1

                        Rectangle {
                            id: surface
                            anchors.fill: parent
                            radius: Theme.radiusMd
                            color: cell.isSel ? Theme.accent : mouse.containsMouse ? Theme.hoverBg : "transparent"
                            border.width: cell.isToday ? 2 : 0
                            border.color: Theme.primary

                            Lift {
                                radius: surface.radius
                                pointer: mouse
                                level: mouse.containsMouse ? 1 : 0
                            }
                        }
                    }

                    Text {
                        x: root.showTitles ? 8 : 0
                        y: root.showTitles ? 5 : 3
                        width: root.showTitles ? implicitWidth : parent.width
                        height: root.showTitles ? implicitHeight : root.cellH - 14
                        horizontalAlignment: root.showTitles ? Text.AlignLeft : Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: cell.date.getDate()
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + (root.showTitles ? 2 : 0)
                        font.bold: cell.isToday || cell.isSel
                        color: cell.isSel ? Theme.accentFg : cell.inMonth ? Theme.fg : Qt.alpha(Theme.fg, 0.35)
                    }

                    // one dot per calendar with events that day, at most three: top right beside the
                    // number when titles are shown, else under it
                    Row {
                        x: root.showTitles ? parent.width - width - 8 : Math.round((parent.width - width) / 2)
                        y: root.showTitles ? 11 : root.cellH - 11
                        spacing: 3

                        Repeater {
                            model: cell.dots

                            Rectangle {
                                required property var modelData
                                width: 6
                                height: 6
                                radius: 3
                                color: modelData !== "" ? modelData : Theme.primary
                                opacity: cell.inMonth ? 1 : 0.5
                            }
                        }
                    }

                    Column {
                        x: 5
                        y: 26
                        width: parent.width - 10
                        spacing: 1
                        visible: root.showTitles
                        opacity: cell.inMonth ? 1 : 0.45

                        Repeater {
                            model: cell.lines

                            Rectangle {
                                id: chip
                                required property var modelData
                                width: parent.width
                                height: 14
                                radius: 3
                                color: chip.modelData.more !== undefined ? "transparent" : Qt.alpha(chip.modelData.c !== "" ? chip.modelData.c : Theme.primary, cell.isSel ? 0.45 : 0.28)

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 3
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: chip.modelData.more === undefined ? chip.modelData.t : chip.modelData.all ? chip.modelData.more + " events" : "+" + chip.modelData.more + " more"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 3
                                    color: cell.isSel ? Theme.accentFg : chip.modelData.more === undefined ? Theme.fg : Theme.fgMuted
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.select(cell.date)
                    }
                }
            }

            // a notch is 120; touchpads send many small steps, so they add up to one month per notch
            WheelHandler {
                onWheel: event => {
                    grid.wheelAcc += event.angleDelta.y;
                    if (Math.abs(grid.wheelAcc) >= 120) {
                        root.shiftMonth(grid.wheelAcc > 0 ? -1 : 1);
                        grid.wheelAcc = 0;
                    }
                }
            }
        }

        // hairline between the grid and the day's block, in the wide layout
        Rectangle {
            visible: root.wide
            x: root.gridW + Math.round(root.gap / 2)
            y: 0
            width: 1
            height: parent.height
            color: Theme.hoverBg
        }

        // the selected day: on the right, or under the grid when the panel is narrow
        ColumnLayout {
            id: side
            x: root.wide ? root.gridW + root.gap : head.x
            y: root.wide ? 0 : grid.y + grid.height + 10
            width: root.wide ? root.innerW - root.gridW - root.gap : root.gridW
            height: root.wide ? root.innerH : root.innerH - y
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: Qt.formatDate(root.selected, "dddd d MMMM")
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + (root.wide ? 4 : 1)
                    font.bold: true
                    color: Theme.fg
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: !Calendar.available || Calendar.reason !== "" ? "" : Calendar.loading ? "Loading…" : Calendar.error !== "" ? Calendar.error : root.dayEvents.length === 0 ? "" : root.dayEvents.length === 1 ? "1 event" : root.dayEvents.length + " events"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.fgMuted
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: !Calendar.available || Calendar.reason !== "" || root.dayEvents.length === 0
                    text: !Calendar.available || Calendar.reason !== "" ? Calendar.reason : "No events"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    color: Theme.fgMuted
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    spacing: 4
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    visible: Calendar.available && Calendar.reason === ""
                    model: root.dayEvents

                    Connections {
                        target: root
                        function onEvIndexChanged() {
                            if (root.eventFocus)
                                list.positionViewAtIndex(root.evIndex, ListView.Contain);
                        }
                        function onEventFocusChanged() {
                            if (root.eventFocus)
                                list.positionViewAtIndex(root.evIndex, ListView.Contain);
                        }
                    }

                    delegate: Item {
                        id: ev
                        required property var modelData
                        required property int index
                        readonly property bool focused: root.eventFocus && root.evIndex === ev.index
                        // narrow list (a column beside the grid): time above the title; wide list: time to the left
                        readonly property bool stacked: list.width < 380
                        width: list.width
                        height: Math.max(40, info.implicitHeight + 14)

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSm
                            color: ev.focused ? Theme.hoverBg : Theme.tileBg
                            border.width: ev.focused ? 1 : 0
                            border.color: Theme.primary
                        }

                        Rectangle {
                            x: 7
                            y: 7
                            width: 3
                            height: parent.height - 14
                            radius: 1.5
                            color: ev.modelData.color !== "" ? ev.modelData.color : Theme.primary
                        }

                        Text {
                            visible: !ev.stacked
                            x: 18
                            y: 7
                            width: 96
                            elide: Text.ElideRight
                            text: Calendar.timeLabel(ev.modelData, Calendar.key(root.selected))
                            textFormat: Text.PlainText
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                            color: Theme.fgMuted
                            lineHeight: 1.1
                        }

                        Column {
                            id: info
                            x: ev.stacked ? 18 : 120
                            y: 7
                            width: parent.width - x - 8

                            Text {
                                visible: ev.stacked
                                width: parent.width
                                elide: Text.ElideRight
                                text: Calendar.timeLabel(ev.modelData, Calendar.key(root.selected))
                                textFormat: Text.PlainText
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 2
                                color: Theme.fgMuted
                            }

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: ev.modelData.title
                                textFormat: Text.PlainText
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize
                                color: Theme.fg
                            }

                            Text {
                                width: parent.width
                                visible: ev.modelData.location !== ""
                                elide: Text.ElideRight
                                text: ev.modelData.location
                                textFormat: Text.PlainText
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 2
                                color: Theme.fgMuted
                            }
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 1 : 2
                rowSpacing: 6
                columnSpacing: 6

                BarButton {
                    Layout.fillWidth: true
                    glyph: 0xF00F3
                    text: "New event"
                    glyphFirst: true
                    glued: false
                    bg: Theme.tileBg
                    enabled: root.khalOk
                    opacity: root.khalOk ? 1 : 0.5
                    onClicked: root.openKhal()
                }

                BarButton {
                    Layout.fillWidth: true
                    glyph: 0xF00ED
                    text: "Open in khal"
                    glyphFirst: true
                    glued: false
                    bg: Theme.tileBg
                    enabled: root.khalOk
                    opacity: root.khalOk ? 1 : 0.5
                    onClicked: root.openKhal()
                }
            }
        }
    }
}
