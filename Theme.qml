pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Palette and geometry shared by every bar component.
// matugen writes colors.json from ~/.config/matugen/templates/quickshell/colors.json;
// the FileView below re-reads it whenever it changes, so a theme run recolours the bar live.
// The sizes the user can change (bar height, opacity, font and icon size, icon nudge) come from
// the Settings singleton (settings.json, edited in the settings panel) and also apply live.
Singleton {
    id: root

    // the colours file matugen writes; the Config tab can point it elsewhere (pathColors, applied)
    // (the default until Settings has loaded: at start-up the key read as undefined for a moment)
    readonly property string colorsPath: Settings.pathColors || Quickshell.env("HOME") + "/.local/state/quickshell/colors.json"

    // Defaults are a rendered matugen palette; colors.json overrides them.
    property color surface: "#0d141c"
    property color container: "#1a2028"
    property color containerHigh: "#242a33"
    property color containerHighest: "#2f353e"
    property color fg: "#dde3ee"
    property color accent: "#00497b"        // primary_container
    property color accentFg: "#d0e4ff"      // on_primary_container
    property color urgent: "#93000a"        // error_container
    property color urgentFg: "#ffdad6"      // on_error_container
    property color primary: "#9dcaff"       // slider fills, active list rows

    // derived tones for interactive surfaces (light overlays read on the frosted islands;
    // container_high did not, it is darker than the island fill)
    readonly property color hoverBg: Qt.alpha(fg, 0.12)
    readonly property color tileBg: Qt.alpha(fg, 0.07)
    readonly property color trackBg: Qt.alpha(fg, 0.18)
    readonly property color fgMuted: Qt.alpha(fg, 0.65)
    readonly property color popupBg: Qt.alpha(container, 0.9)
    // the lock screen's cover while the system goes to sleep: true black whatever the palette, so the screen looks off
    readonly property color blackout: "#000000"

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: Settings.fontSize

    // Icons are Nerd Font glyphs drawn by Glyph.qml at their own size in a fixed cell, so they are
    // one optical size and line up beside the 13 px figures instead of shrinking into the text.
    // The Propo face gives a glyph its natural advance (the plain face pads every icon to two cells).
    readonly property string iconFont: "JetBrainsMono Nerd Font Propo"
    readonly property int iconSize: Settings.iconSize
    // the readouts on the bar itself (right island, workspace cue) have their own sizes, so they can
    // be larger than the text in dropdowns and the settings window
    readonly property int barFontSize: Settings.barFontSize
    readonly property int barIconSize: Settings.barIconSize
    readonly property int iconCell: 20       // minimum glyph width, so readouts and list columns do not shift per icon
    readonly property int iconNudge: Settings.iconNudge   // vertical offset of bar icons in px, tune by eye (negative = up)

    // Islands are carved into the screen edge: the left and right ones sit in the top corners,
    // the centre one hangs from the top. marginBottom leaves room for the 10 px side fillets.
    readonly property int barHeight: Settings.barHeight
    readonly property int marginTop: 0
    readonly property int marginSide: 0
    // Corner radii: fixed numbers in three presets, picked by the `corners`
    // setting (Bar tab, Look), NOT derived from matugen's corner_radius any more (that token still
    // drives Hyprland and the other apps). One scale for the whole shell:
    //   radiusXl  islands, panels, popups, dialogs, toasts (= islandRadius)
    //   radiusLg  group boxes and lists
    //   radiusMd  cards, tiles and rows 34-52 px tall
    //   radiusSm  fields and rows up to 30 px tall (= buttonRadius)
    //   radiusXs  keycaps and chips
    //   radiusXxl the session menu's full-screen panel (outside the scale, its cards are nested)
    // Pills, discs and tracks are `height / 2`, never a token.
    readonly property var cornerSets: ({
            sharp: { xxl: 18, xl: 7, lg: 5, md: 4, sm: 3, xs: 2 },
            "default": { xxl: 36, xl: 14, lg: 10, md: 8, sm: 6, xs: 4 },
            round: { xxl: 50, xl: 20, lg: 14, md: 11, sm: 8, xs: 6 }
        })
    // ---- BEGIN toml custom ----: `corners` may also be a number, the island radius in pixels (2 to 30), and the other
    // radii scale with it from the Standard set (14 : 10 : 8 : 6 : 4 : 36)
    readonly property var cornerSet: {
        const c = String(Settings.corners);
        if (/^[0-9]+$/.test(c)) {
            const xl = Math.max(2, Math.min(30, parseInt(c, 10)));
            const f = xl / 14;
            const part = n => Math.max(2, Math.round(n * f));
            return { xxl: Math.round(36 * f), xl: xl, lg: part(10), md: part(8), sm: part(6), xs: part(4) };
        }
        return cornerSets[c] ?? cornerSets["default"];
    }
    // ---- END toml custom ----
    readonly property int radiusXxl: cornerSet.xxl
    readonly property int radiusXl: cornerSet.xl
    readonly property int radiusLg: cornerSet.lg
    readonly property int radiusMd: cornerSet.md
    readonly property int radiusSm: cornerSet.sm
    readonly property int radiusXs: cornerSet.xs
    // the concentric radius of a surface set `inset` px inside one with radius `outer`, never
    // below radiusXs
    function nested(outer, inset) {
        return Math.max(radiusXs, outer - inset);
    }

    // ---- Islands: one rule set for all three, for their corners and for what sits inside them.
    // SideIsland, GrowingIsland and IslandDropdown take their shape, padding and
    // motion from this block only, never from a literal, so the side islands, the centre island and
    // every dropdown meet at seams and move on one clock.
    //
    // Shape. ONE value for the island corners, the four fillets, the centre island's outline and
    // its margins, and the dropdown fillet and panel: they meet at seams, so none of them may take a
    // radius from anywhere else.
    readonly property int islandRadius: radiusXl
    // The closed centre island is stepped: its sides are bar-high, the clock part reaches deeper.
    // stepFillet is the small inverted fillet where the two meet, stepCorner the clock part's own
    // bottom corners. Opening grows both to islandRadius, so the open panel (sides shorter, middle
    // deeper) mirrors the closed step. A step needs stepCorner + stepFillet of depth below the sides.
    readonly property int stepFillet: radiusSm
    readonly property int stepCorner: radiusLg
    // Inside. The content padding of an open panel (control centre, dropdowns), and the side
    // islands' padding around their widgets (Left island and Right island tabs).
    readonly property int panelPad: 12
    readonly property int leftIslandPad: Settings.leftPadding
    readonly property int rightIslandPad: Settings.rightPadding
    // Motion (Bar tab, Islands). One duration for every island: the centre's growth, a side
    // island's extension and its dropdown's growth. "standard" is the curves the islands had
    // before the setting: the centre grows in-out, a side island and its dropdown slide out.
    readonly property int islandMs: Settings.islandAnimMs
    readonly property int islandEaseGrow: ({ smooth: Easing.InOutSine, snappy: Easing.OutQuint, linear: Easing.Linear })[Settings.islandEasing] ?? Easing.InOutCubic
    readonly property int islandEaseSlide: ({ smooth: Easing.InOutSine, snappy: Easing.OutQuint, linear: Easing.Linear })[Settings.islandEasing] ?? Easing.OutCubic

    readonly property int marginBottom: islandRadius + 2
    readonly property int reserved: marginTop + barHeight + marginBottom   // bar window height (room for the side fillets)
    readonly property int exclusive: barHeight + 2                            // space actually kept free of windows
    // buttons hang from the island's top edge (square top corners), 4 px short of its bottom
    readonly property int buttonHeight: barHeight - 4
    readonly property int buttonRadius: radiusSm
    readonly property int filletSmall: radiusXs     // inverted corners on widget highlights
    readonly property int gap: 6
    // right-island highlights float this far inside the island, with the nested corner radius
    readonly property int insetPad: 4
    readonly property int insetRadius: nested(radiusXl, insetPad)

    // hover lift (components/Lift.qml): scale on hover, capped in px so wide rows grow only a
    // little; the workspace dots lift harder, a 10 px dot at 1.05 would not show
    readonly property real liftScale: 1.05
    readonly property int liftMaxPx: 6
    readonly property real dotLiftScale: 1.7     // a stronger lift than other items, so the small dots read clearly

    // island fill: a lighter container tone at low alpha, so the frosted blur behind it
    // reads against the dark wallpaper (surface at 0.72 was indistinguishable from it)
    readonly property real barOpacity: Settings.barOpacity
    readonly property color barBg: Qt.alpha(containerHighest, barOpacity)

    function apply(json) {
        const c = JSON.parse(json);
        const map = {
            surface: "surface",
            surface_container: "container",
            surface_container_high: "containerHigh",
            surface_container_highest: "containerHighest",
            on_surface: "fg",
            primary_container: "accent",
            on_primary_container: "accentFg",
            error_container: "urgent",
            on_error_container: "urgentFg",
            primary: "primary"
        };
        for (const key in map) {
            const v = c[key];
            if (typeof v === "string" && v.startsWith("#"))
                root[map[key]] = v;
        }
    }

    FileView {
        path: root.colorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.apply(text());
            } catch (e) {
                console.warn("Theme: could not parse " + root.colorsPath + ": " + e);
            }
        }
    }
}
