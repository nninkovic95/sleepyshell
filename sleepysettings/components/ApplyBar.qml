import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// The bar under the settings pages: what is pending on the open tab, Discard and Apply. One for
// the window (Sleepysettings binds it to the open TabPage); every tab has it, and nothing a tab changes takes effect before
// Apply. While a keep-or-revert countdown runs (Display) it turns accent and shows Revert and Keep.
// It is only there while something is pending (`shown`: unapplied changes, an apply at work or a
// countdown, on any tab): otherwise it fades and shrinks away and the page
// gets its room back. While it leaves it keeps showing what it showed (the latched v* values),
// so "No changes" does not flash up after an Apply.
// It is a
// card of the window's own family (the Section cards' surface and radiusLg, no outline), docked at
// the bottom of the page column and rising into place when it appears. One status row at the normal
// font size: an accent dot and the count at the left, Discard (a ghost button) and Apply (filled
// accent) at the right. Under it, one line per file the open tab's Apply will modify:
// a file glyph, the directory muted (cut in the middle when the line is too long) and the
// file name in the normal text colour (never cut), none of it smaller than fontSize - 1.
// `afterNote` is a last line for what Apply runs afterwards (Theme). The bar has room for two such
// lines on every tab, so the window keeps one size.
Rectangle {
    id: ab
    property bool dirty: false
    property bool busy: false
    property bool pending: false
    property string idleText: "No changes"
    property string dirtyText: "Unapplied changes"
    property string pendingText: ""
    // the files the open tab's Apply writes (paths, ~ for home), and what it runs after
    property var files: []
    property string afterNote: ""
    // the window's Tooltip, for the file chips ("Open in editor")
    property var tooltip: null
    // the bar is up; Sleepysettings sets it from all the tabs
    property bool shown: dirty || busy || pending
    // the layout's spacing above the bar, which a hidden bar takes back with a negative margin
    property int gap: 10
    // 8 margin, the status row (32), two lines of 20, 8 margin
    readonly property int fullHeight: 88
    // 0 hidden .. 1 shown
    property real reveal: shown ? 1 : 0
    // the room the bar does not take now; the window adds it to its height so it keeps its size
    readonly property real collapsed: (1 - reveal) * (fullHeight + gap)
    Behavior on reveal {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
    // what the bar looks like, held while it is leaving
    property bool vDirty: false
    property bool vBusy: false
    property bool vPending: false
    property string vIdleText: idleText
    property string vDirtyText: dirtyText
    property string vPendingText: pendingText
    property var vFiles: files
    property string vAfterNote: afterNote
    Binding { target: ab; property: "vDirty"; value: ab.dirty; when: ab.shown; restoreMode: Binding.RestoreNone }
    Binding { target: ab; property: "vBusy"; value: ab.busy; when: ab.shown; restoreMode: Binding.RestoreNone }
    Binding { target: ab; property: "vPending"; value: ab.pending; when: ab.shown; restoreMode: Binding.RestoreNone }
    Binding { target: ab; property: "vIdleText"; value: ab.idleText; when: ab.shown; restoreMode: Binding.RestoreNone }
    Binding { target: ab; property: "vDirtyText"; value: ab.dirtyText; when: ab.shown; restoreMode: Binding.RestoreNone }
    Binding { target: ab; property: "vPendingText"; value: ab.pendingText; when: ab.shown; restoreMode: Binding.RestoreNone }
    Binding { target: ab; property: "vFiles"; value: ab.files; when: ab.shown; restoreMode: Binding.RestoreNone }
    Binding { target: ab; property: "vAfterNote"; value: ab.afterNote; when: ab.shown; restoreMode: Binding.RestoreNone }

    signal apply()
    signal discard()
    signal keep()
    signal revert()

    Layout.fillWidth: true
    implicitHeight: fullHeight * reveal
    Layout.topMargin: -gap * (1 - reveal)
    // out of the layout once gone, so its spacing goes too
    visible: reveal > 0.001
    opacity: reveal
    clip: true
    // the Section cards' surface and radius; the keep-or-revert countdown turns it accent
    radius: Theme.radiusLg
    color: vPending ? Theme.accent : Theme.container

    // the content keeps its full height and hangs from the bottom edge, so while the bar grows
    // (or shrinks) it rises into place (and sinks away) instead of being unrolled from the top
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: ab.fullHeight

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 8

                // a dot in the accent colour: something is waiting for Apply (not an error, so not red)
                Rectangle {
                    visible: ab.vDirty && !ab.vPending
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: width / 2
                    color: Theme.primary
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: ab.vPending ? ab.vPendingText : ab.vBusy ? "Applying…" : ab.vDirty ? ab.vDirtyText : ab.vIdleText
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    color: ab.vPending ? Theme.accentFg : ab.vDirty ? Theme.fg : Theme.fgMuted
                }

                BarButton {
                    visible: ab.vPending
                    text: "Revert"
                    glued: false
                    hpad: 14
                    fg: Theme.accentFg
                    bg: Qt.alpha(Theme.accentFg, 0.08)
                    onClicked: ab.revert()
                }

                BarButton {
                    visible: ab.vPending
                    text: "Keep"
                    glued: false
                    hpad: 14
                    fg: Theme.accentFg
                    bg: Qt.alpha(Theme.accentFg, 0.2)
                    onClicked: ab.keep()
                }

                // a real button, same height and corners as Apply: the quiet one of the two
                BarButton {
                    visible: ab.vDirty && !ab.vBusy && !ab.vPending
                    text: "Discard"
                    glued: false
                    hpad: 14
                    bg: Qt.alpha(Theme.fg, 0.09)
                    onClicked: ab.discard()
                }

                BarButton {
                    visible: !ab.vPending
                    text: "Apply"
                    glued: false
                    hpad: 18
                    opacity: ab.vDirty && !ab.vBusy ? 1 : 0.4
                    bg: ab.vDirty ? Theme.accent : Qt.alpha(Theme.fg, 0.09)
                    fg: ab.vDirty ? Theme.accentFg : Theme.fg
                    onClicked: if (ab.dirty && !ab.busy) ab.apply()
                }
            }

            // one line per file: a file glyph, the directory (cut in the middle when long), the file name
            Repeater {
                model: ab.vFiles

                FileLine {
                    required property string modelData
                    path: modelData
                    tooltip: ab.tooltip
                    onAccent: ab.vPending
                }
            }

            // what runs after the write (the Theme tab)
            Text {
                visible: ab.vAfterNote !== ""
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: ab.vAfterNote
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                color: ab.vPending ? Theme.accentFg : Theme.fgMuted
            }
        }
    }
}
