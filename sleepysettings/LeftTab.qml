import QtQuick
import QtQuick.Layouts
import "Customs.js" as Customs
import qs.sleepysettings.components

// Settings tab: the left island, which holds the workspace dots. The keys keep the names they had on the Bar tab.
TabPage {
    id: tab
    key: "left"
    label: "Left island"
    icon: 0xF10AA
    group: "left"

    Section {
        title: "Workspaces"

        NumberRow {
            label: "Always-visible workspaces"
            key: "workspaces"
            tags: "always shown"
            info: "Workspaces 1 to this number always have a dot, used or not; higher ones show only while they exist."
        }
        ChoiceRow {
            label: "Workspace dot shape"
            key: "workspaceShape"
            info: "The workspace dots, the ring on empty ones and the sliding marker: circles, rounded squares, rounded triangles pointing up, or the workspace numbers; the corners of squares, triangles and the number marker follow the corner roundness setting."
            tags: "workspace circle square triangle number digits round shape dots"
            options: [["circle", "Circles"], ["square", "Squares"], ["triangle", "Triangles"], ["number", "Numbers"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
            // ---- BEGIN toml custom ----: a glyph of your own drawn on every dot, laid out like the numbers
            custom: ({
                    placeholder: "One or two characters, a letter, a symbol or an icon",
                    toText: v => ["circle", "square", "triangle", "number"].includes(v) ? "" : String(v),
                    seed: v => "",
                    parse: t => Customs.glyph(t),
                    describe: v => ({ circle: "Circles", square: "Squares", triangle: "Triangles", number: "Numbers" })[v] ?? "\u201C" + v + "\u201D on every dot"
                })
            // ---- END toml custom ----
        }
    }

    AdvancedSection {
        SwitchRow {
            label: "Workspace switch wave"
            key: "workspaceWave"
            info: "The active disc slides slower and the dots it passes lift."
            tags: "workspace animation wave when switching"
        }
        NumberRow {
            label: "Island padding"
            key: "leftPadding"
            suffix: " px"
            info: "Space between the left island's edges and the workspace dots."
            tags: "padding space margin island edge"
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
