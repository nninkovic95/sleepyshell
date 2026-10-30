import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import "Customs.js" as Customs
import qs.sleepysettings.components

// Settings tab: the bar as a whole (sizes, look; the icon offset and tile hover sit in Advanced). The workspaces are on the Left
// island tab.
TabPage {
    id: tab
    key: "bar"
    label: "Sleepybar"
    icon: 0xF1513
    group: "bar"
    // the Caps Lock icon switch below is the Right island tab's eye toggle for the same widget: one key (rightHidden), both rows
    extraKeys: ["rightHidden"]

    // sections follow the declutter plan: sizes, the dropdown pair, the look, then
    // the rare rows in Advanced
    Section {
        title: "Bar"

        NumberRow {
            label: "Bar height"
            key: "barHeight"
            suffix: " px"
        }
        NumberRow {
            label: "Bar text size"
            key: "barFontSize"
            suffix: " px"
            tags: "font"
        }
        NumberRow {
            label: "Bar icon size"
            key: "barIconSize"
            suffix: " px"
            tags: "glyph"
        }
    }

    Section {
        title: "Dropdowns"

        PairRow {
            NumberRow {
                label: "Dropdown text size"
                key: "fontSize"
                suffix: " px"
                tags: "font panel popup"
            }
            NumberRow {
                label: "Dropdown icon size"
                key: "iconSize"
                suffix: " px"
                tags: "glyph panel popup"
            }
        }
    }

    Section {
        title: "Look"

        NumberRow {
            label: "Island opacity"
            key: "barOpacity"
            tags: "transparency blur"
        }

        ChoiceRow {
            label: "Corner roundness"
            key: "corners"
            tags: "corners radius rounded sharp round square"
            info: "How round the corners of the bar, its islands, dropdowns, buttons and fields are: sharper, the standard set, or rounder. This shapes the bar and its popups only. The corners of other windows come from your Hyprland and matugen config."
            options: [["sharp", "Sharp"], ["default", "Standard"], ["round", "Rounded"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
            // ---- BEGIN toml custom ----: the island corner radius in pixels; the other corners scale with it (Theme.cornerSet)
            custom: ({
                    placeholder: "Island corner radius in pixels, 2 to 30",
                    toText: v => /^[0-9]+$/.test(v) ? String(v) : "",
                    seed: v => String(({ sharp: 7, "default": 14, round: 20 })[v] ?? 14),
                    parse: t => Customs.integer(t, 2, 30, "pixels"),
                    describe: v => /^[0-9]+$/.test(v) ? "island corners " + v + " px, the other corners scale with them" : ({ sharp: "Sharp", "default": "Standard", round: "Rounded" })[v] ?? String(v)
                })
            // ---- END toml custom ----
        }
    }

    // how every island opens: one clock for the centre island, the side islands and their dropdowns
    Section {
        title: "Islands"

        NumberRow {
            label: "Open and close time"
            key: "islandAnimMs"
            suffix: " ms"
            info: "How long an island takes to open into its panel or dropdown, and to close again. 0 opens at once."
            tags: "animation speed duration island dropdown control centre expand"
        }
        ChoiceRow {
            label: "Motion"
            key: "islandEasing"
            info: "How the opening speeds up and slows down. Standard eases in and out; Smooth is gentler; Snappy starts fast and settles; Linear moves at one speed."
            tags: "animation easing curve island dropdown"
            options: [["standard", "Standard"], ["smooth", "Smooth"], ["snappy", "Snappy"], ["linear", "Linear"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
        }
    }

    // Caps Lock and the volume popup
    Section {
        title: "Popups and indicators"

        // the same switch as the eye of "Caps Lock indicator" in the Right island tab (rightHidden): one key, both rows stay in step
        SettingRow {
            label: "Caps Lock icon on the bar"
            info: "Shows or hides the Caps Lock icon on the bar. It is the same switch as in the Right island tab."
            tags: "capslock keyboard indicator right island widget"

            Toggle {
                objectName: "capsIconToggle"
                checked: Settings.stagedShown("rightHidden", "capslock")
                onClicked: Settings.stageShown("rightHidden", "capslock", !Settings.stagedShown("rightHidden", "capslock"))
            }
        }
        SwitchRow {
            label: "Show Caps Lock in the popup"
            key: "capsPeek"
            info: "Shows Caps Lock on or off under the clock when it is pressed (in a small bar at the bottom of the screen over a fullscreen window), like a volume change."
            tags: "capslock osd keyboard peek"
        }
        NumberRow {
            label: "Volume/Caps popup duration"
            key: "peekMs"
            suffix: " ms"
            info: "How long the clock island shows the volume, or Caps Lock, after it changes."
            tags: "volume osd caps peek shown for"
        }
    }

    AdvancedSection {
        NumberRow {
            label: "Bar icon vertical offset"
            key: "iconNudge"
            suffix: " px"
            tags: "nudge"
            info: "Moves the bar's icons up (negative) or down by a pixel or two, so they sit level with the text."
        }
        ChoiceRow {
            label: "Tile hover effect"
            key: "cardHover"
            tags: "card hover"
            info: "Affects the control-centre tiles, the session-menu buttons and the wallpaper thumbnails: they lift like every button, or also lean toward the pointer's edge."
            options: [["lift", "Lift"], ["tilt", "Lift and tilt"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
            // ---- BEGIN toml custom ----: the lean strength in percent of the standard tilt
            custom: ({
                    placeholder: "Lean strength in percent of the standard, 10 to 300",
                    toText: v => /^[0-9]+$/.test(v) ? String(v) : "",
                    seed: v => "100",
                    parse: t => Customs.integer(t, 10, 300, "percent"),
                    describe: v => v === "lift" ? "lift only" : v === "tilt" ? "lift and tilt, standard strength" : /^[0-9]+$/.test(v) ? "lift and tilt at " + v + " % of the standard strength" : String(v)
                })
            // ---- END toml custom ----
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
