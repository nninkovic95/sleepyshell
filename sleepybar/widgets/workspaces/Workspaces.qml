import QtQuick
import Quickshell.Hyprland
import qs
import qs.components
import qs.services
import qs.sleepybar.components

// Numbered workspaces of this screen's monitor, drawn as dots, with a circular highlight. Workspaces 1 to Settings.workspaces
// (5 by default) are always shown,
// whether or not Hyprland has created them yet (a click on a missing one creates and focuses it);
// workspaces above 5 appear while they exist. Special workspaces (negative ids, e.g. special:magic)
// are not listed; while one is open on this monitor a glyph pill shows its name and toggles it.
// One accent disc sits behind the dots and slides to the active workspace, stretching into a
// pill on the way. `active` (active on its own monitor) is used rather than `focused` (active and
// monitor focused), so a second monitor keeps its disc when it is not the focused one.
Item {
    id: root
    required property var bar
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(bar.screen)
    property Item focusedItem: null

    readonly property var persistent: Array.from({
        length: Settings.workspaces
    }, (_, i) => i + 1)
    readonly property int disc: 22   // highlight and hover disc diameter, also a slot's width
    readonly property int dot: 10
    // circles, or rounded squares: the corners
    // come from the radius tokens, so the Sharp / Standard / Rounded preset applies. The sliding marker
    // and the hover backing take radiusSm; a dot, a ring and the wave's shadow sit inside the 22 px slot
    // with the concentric radius (Theme.nested, never below radiusXs). Sizes, spacing and the slide are the same.
    // A third shape, a rounded equilateral triangle pointing up: the dot 13 px on a
    // side (about the area of the 10 px circle), the marker 22 px, the same corner tokens; the marker keeps
    // its size while it slides (its centre follows the stretching edges), and the slide, sizes and spacing
    // are the same.
    // A fourth, "number": the workspace's number in the bar font, tabular (the font is
    // monospaced, so the island does not jump), at the size of the dots; the cell is the usual 22 px and
    // widens only as far as "10" needs. Occupied: the text colour, empty: muted, active: the accent
    // marker (a rounded rectangle, corners from radiusSm) behind it with the number in the accent foreground.
    // ---- BEGIN toml custom ----: any other value is a glyph of the user's own (one or two characters, validated in the
    // settings window), drawn on each dot exactly like the numbers; a hand-written empty or longer value reads as a circle
    readonly property string customGlyph: {
        const v = String(Settings.workspaceShape);
        return !["circle", "square", "triangle", "number"].includes(v) && v.trim() !== "" && Array.from(v).length <= 2 ? v.trim() : "";
    }
    readonly property string shape: customGlyph !== "" ? "number" : ["square", "triangle", "number"].includes(Settings.workspaceShape) ? Settings.workspaceShape : "circle"
    // ---- END toml custom ----
    readonly property bool square: root.shape === "square"
    readonly property bool triangle: root.shape === "triangle"
    readonly property bool number: root.shape === "number"
    readonly property real markerRadius: square || number ? Math.min(Theme.radiusSm, disc / 2) : disc / 2
    // capped at 30 % of the dot, or the standard preset (radiusXs 4 on a 10 px dot) looked like a circle
    readonly property real dotRadius: square ? Math.min(Theme.nested(markerRadius, (disc - dot) / 2), dot * 0.3) : dot / 2
    readonly property real dotSide: 13

    // Hyprland's activespecial event does not refresh the monitor objects on its own
    readonly property string special: {
        const n = root.monitor?.lastIpcObject?.specialWorkspace?.name ?? "";
        return n.startsWith("special:") ? n.slice(8) : n;
    }

    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (e.name === "activespecial")
                Hyprland.refreshMonitors();
        }
    }

    implicitWidth: row.implicitWidth
    // full island height: the dots and the disc are centred in it, unlike the top-glued text buttons
    implicitHeight: Theme.barHeight

    // The disc stretches toward the target: its leading edge moves in 200 ms, the trailing one in
    // 300 ms (a plain slide moved both edges in lockstep). The first placement is not animated.
    property real edgeL: 0
    property real edgeR: 0

    function slideTo(l, r) {
        slide.stop();
        if (edgeR <= edgeL) {
            edgeL = l;
            edgeR = r;
            return;
        }
        const toRight = l >= edgeL;
        // the wave setting slows the slide so the dots it passes have time to lift
        const k = Settings.workspaceWave ? 650 / 300 : 1;
        animL.duration = Math.round((toRight ? 300 : 200) * k);
        animR.duration = Math.round((toRight ? 200 : 300) * k);
        animL.to = l;
        animR.to = r;
        slide.start();
    }

    function follow() {
        if (focusedItem)
            slideTo(focusedItem.x, focusedItem.x + focusedItem.width);
    }

    onFocusedItemChanged: follow()
    // A dot that claims the disc while the bar is still being built does so before these handlers
    // run, so after a fresh start the disc stayed at 0..0; place it once the
    // component is complete.
    Component.onCompleted: Qt.callLater(follow)

    Connections {
        target: root.focusedItem
        function onXChanged() {
            root.follow();
        }
        function onWidthChanged() {
            root.follow();
        }
    }

    // the wave's strength: up while the disc slides, eased back down when it stops, so the dot it
    // lands on settles instead of dropping (the dots' Lifts follow the disc frame by frame)
    property real wave: 0
    // 1 while the disc is a slot or more from where it is going, falling to 0 as it arrives: the
    // dot it lands on lifts only briefly (the disc slows down on top of it)
    readonly property real arrive: Math.min(1, Math.abs((edgeL + edgeR) / 2 - (animL.to + animR.to) / 2) / disc)
    Behavior on wave {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: slide
        onStarted: root.wave = 1
        onStopped: root.wave = 0
        NumberAnimation {
            id: animL
            target: root
            property: "edgeL"
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            id: animR
            target: root
            property: "edgeR"
            easing.type: Easing.OutCubic
        }
    }

    // the sliding accent disc (a pill while its two edges travel at different speeds)
    Rectangle {
        visible: !root.triangle && root.focusedItem !== null && root.focusedItem.isFocused
        x: root.edgeL
        width: Math.max(0, root.edgeR - root.edgeL)
        height: root.disc
        radius: root.markerRadius
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.accent
        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
    }

    // the triangle marker: the same slide, but it keeps its shape (a stretched triangle would be a wide one)
    ShapeMark {
        visible: root.triangle && root.focusedItem !== null && root.focusedItem.isFocused
        kind: "triangle"
        x: (root.edgeL + root.edgeR) / 2 - width / 2
        width: root.disc
        height: root.disc
        anchors.verticalCenter: parent.verticalCenter
        fill: Theme.accent
        cornerRadius: Theme.radiusXs
    }

    // Two Repeaters share one delegate so the dots stay the same objects across workspace changes
    // (the sliding disc follows `focusedItem`, which a rebuilt delegate would reset).
    Component {
        id: wsDot

        Item {
            id: btn
            // a workspace id (persistent slot) or the HyprlandWorkspace itself (above 5)
            required property var modelData
            readonly property bool slot: typeof modelData === "number"
            readonly property int wsId: slot ? modelData : modelData.id
            readonly property HyprlandWorkspace ws: slot ? (Hyprland.workspaces.values.find(w => w.id === modelData) ?? null) : modelData
            readonly property bool onThisMonitor: !root.monitor || !ws || ws.monitor === root.monitor
            // not `&& onThisMonitor`: when `ws` changes, this binding could run before onThisMonitor did, and a workspace that just appeared
            // as the active one of ANOTHER monitor briefly counted as focused here, took the disc and left it on a hidden dot (only visible
            // with two monitors)
            readonly property bool isFocused: (ws?.active ?? false) && (!root.monitor || !ws || ws.monitor === root.monitor)
            readonly property bool urgent: ws?.urgent ?? false
            // a workspace with windows is a solid dot, an empty one a ring
            readonly property bool occupied: (ws?.toplevels?.values?.length ?? 0) > 0
            readonly property bool hovered: mouse.containsMouse
            visible: onThisMonitor && (slot || wsId > root.persistent.length)
            width: root.number ? Math.max(root.disc, numText.implicitWidth + 8) : root.disc
            height: Theme.barHeight

            // only a shown dot may own the sliding disc: the second Repeater also builds hidden
            // dots for workspaces 1 to 5, and a hidden item (never laid out, x 0) would park the
            // disc on the first slot
            readonly property bool claims: isFocused && visible
            onClaimsChanged: {
                if (claims)
                    root.focusedItem = this;
            }
            Component.onCompleted: {
                if (claims)
                    root.focusedItem = this;
            }

            // urgent fill, or a faint disc under the pointer (not on the active one: the accent disc is there)
            Rectangle {
                visible: !root.triangle
                anchors.centerIn: parent
                width: btn.width
                height: root.disc
                radius: root.markerRadius
                color: btn.urgent ? Theme.urgent : btn.hovered && !btn.isFocused ? Theme.hoverBg : "transparent"
                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }
            }

            ShapeMark {
                visible: root.triangle
                anchors.centerIn: parent
                width: root.disc
                height: root.disc
                kind: "triangle"
                cornerRadius: Theme.radiusXs
                fill: btn.urgent ? Theme.urgent : btn.hovered && !btn.isFocused ? Theme.hoverBg : "transparent"
            }

            // the triangle: filled when occupied, an outline (the same stroke as the ring) when empty
            ShapeMark {
                id: triShape
                visible: root.triangle
                anchors.centerIn: parent
                width: root.dotSide
                height: root.dotSide
                kind: "triangle"
                cornerRadius: Theme.radiusXs
                fill: btn.occupied ? dotShape.tone : "transparent"
                stroke: dotShape.tone
                strokeWidth: btn.occupied ? 0 : 2
            }

            // the number: occupied in the text colour, empty muted, active in the accent foreground on the marker
            Text {
                id: numText
                visible: root.number
                anchors.centerIn: parent
                text: root.customGlyph !== "" ? root.customGlyph : btn.wsId
                font.family: Theme.font
                font.pixelSize: Theme.barFontSize
                font.weight: Font.Medium
                color: btn.urgent ? Theme.urgentFg : btn.isFocused ? Theme.accentFg : btn.occupied ? Theme.fg : Theme.fgMuted
                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }

            Rectangle {
                id: dotShape
                visible: !root.triangle && !root.number
                readonly property color tone: btn.urgent ? Theme.urgentFg : btn.isFocused ? Theme.accentFg : Theme.fg
                anchors.centerIn: parent
                width: root.dot
                height: root.dot
                radius: root.dotRadius
                color: btn.occupied ? tone : "transparent"
                border.width: btn.occupied ? 0 : 2
                border.color: tone
                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }

            // Wave: a dot lifts while the sliding disc passes it, driven by the
            // disc's live centre, not by the mouse. btn.x and edgeL/edgeR share the Row's space
            // (the Row sits at x 0 in root). Scale leaves x/width alone, so follow() is unaffected.
            Lift {
                shape: root.triangle ? triShape : dotShape
                radius: root.triangle ? 2 : root.dotRadius
                peak: Theme.dotLiftScale
                maxPx: 1000
                eased: false
                level: Settings.workspaceWave && !root.number ? root.wave * Math.max(0, 1 - Math.abs(btn.x + btn.width / 2 - (root.edgeL + root.edgeR) / 2) / (root.disc * 1.5)) * (btn === root.focusedItem ? root.arrive : 1) : 0
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Hyprland runs the Lua config, so dispatch strings are Lua, not "workspace N"
                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + btn.wsId + " })")
                // a tilt-wheel or horizontal scroll event has y == 0; it must not count as "down"
                onWheel: w => {
                    if (w.angleDelta.y !== 0)
                        Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + (w.angleDelta.y > 0 ? "e-1" : "e+1") + "\" })");
                }
            }
        }
    }

    Row {
        id: row
        spacing: Theme.gap

        Repeater {
            model: root.persistent
            delegate: wsDot
        }

        Repeater {
            model: Hyprland.workspaces
            delegate: wsDot
        }

        // the open special workspace (scratchpad); click hides it again
        BarButton {
            visible: root.special !== ""
            glyph: 0xF0328
            text: root.special
            glyphFirst: true
            hpad: 6
            fg: Theme.primary
            onClicked: Hyprland.dispatch("hl.dsp.workspace.toggle_special(\"" + root.special + "\")")
        }
    }
}
