import QtQuick
import QtQuick.Layouts
import qs.services
import "Customs.js" as Customs
import qs.sleepysettings.components

// Settings tab: the centre island (clock, items beside it, control centre with its quick-setting tiles and tools; formats and timings
// in Advanced). The volume popup and Caps Lock rows are on the Bar tab's "Popups and indicators".
TabPage {
    id: tab
    key: "centre"
    label: "Centre island"
    icon: 0xF0150
    group: "centre"

    // "" for a usable Qt time format, else why not: every unquoted letter must be a time code
    // (h H m s z t a A, or ap AP) and there must be hours or minutes; Qt prints any other letter
    // as is, so "HH:MM" showed "14:MM"
    function timeFormatError(f) {
        if (f.trim() === "")
            return "Enter a format, e.g. HH:mm.";
        let quoted = false, clock = false;
        for (let i = 0; i < f.length; i++) {
            const c = f[i];
            if (c === "'") {
                quoted = !quoted;
                continue;
            }
            if (quoted || !/[A-Za-z]/.test(c))
                continue;
            if ((c === "a" && f[i + 1] === "p") || (c === "A" && f[i + 1] === "P")) {
                i++;
                continue;
            }
            if (!"hHmsztaA".includes(c))
                return "\"" + c + "\" is not a time code. Use H or h, m, s, z, t, AP or ap; put other text in single quotes.";
            if ("hHm".includes(c))
                clock = true;
        }
        if (quoted)
            return "A single quote is not closed.";
        if (!clock)
            return "Include hours (H or h) or minutes (m).";
        return "";
    }

    // sections follow the declutter plan; the rare rows are in Advanced
    Section {
        title: "Clock"

        NumberRow {
            label: "Clock text size"
            key: "clockSize"
            suffix: " px"
            tags: "clock"
        }
        SwitchRow {
            label: "Date under the clock"
            key: "showDate"
        }
    }

    Section {
        title: "Next to the clock"

        PairRow {
            SwitchRow {
                label: "Show CPU and memory"
                key: "centreSysinfo"
                tags: "sysinfo ram"
            }
            SwitchRow {
                label: "Show audio"
                key: "centreAudio"
                tags: "volume sound"
            }
        }
        // only meaningful while both are shown
        ChoiceRow {
            label: "Item left of the clock"
            key: "centreLeft"
            enabled: Settings.get("centreSysinfo") && Settings.get("centreAudio")
            info: "Which of the two sits left of the clock; the other goes right."
            tags: "order swap side sysinfo audio"
            options: [["sysinfo", "CPU and memory"], ["audio", "Audio"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
        }
    }

    // the island's outline, closed and open; the open shape mirrors the closed one
    Section {
        title: "Shape"

        PairRow {
            SwitchRow {
                label: "Stepped island"
                key: "centreStep"
                info: "The closed island is stepped: the clock part reaches lower than the widgets beside it. Off, it is one flat shape."
                tags: "step outline clock island shape"
            }
            SwitchRow {
                label: "Uneven panel"
                key: "centreUneven"
                info: "In the open control centre the middle column hangs lower than the two side columns. Off, the panel is one rectangle."
                tags: "middle column hangs lower outline control centre shape"
            }
        }
    }

    // the control centre's quick-setting tiles and its tools grid, each drawn as the grid is: two to a row, in this order
    // Power is last in the tools and fixed. The Right island tab keeps the rows
    // (OrderList). The tools grid also adds the user's own tools (the "+ Add tool" tile and the dialog behind it, ToolEditor).
    Section {
        title: "Control centre"

        SwitchRow {
            label: "Open control centre on hover"
            key: "hoverOpen"
            tags: "control centre"
        }
        Heading {
            text: "Quick settings"
        }
        ToolsGridEditor {
            kind: "tiles"
            orderKey: "tilesOrder"
            hiddenKey: "tilesHidden"
            query: tab.query
            noun: "quick setting tile control centre wifi bluetooth"
            tooltip: tab.tooltip
        }
        Heading {
            text: "Tools"
        }
        ToolsGridEditor {
            kind: "tools"
            orderKey: "toolsOrder"
            hiddenKey: "toolsHidden"
            query: tab.query
            noun: "tool control centre"
            tooltip: tab.tooltip
            onAddRequested: tab.toolDialog.openAdd()
            onEditRequested: name => tab.toolDialog.openEdit(name)
        }
    }

    AdvancedSection {
        ComboRow {
            label: "Clock font"
            key: "clockFont"
            picker: tab.picker
            info: "The clock's typeface. Pick one of the fonts offered, or Custom… for any other installed font: IBM 3270 is an old IBM terminal face, CPMono a geometric mono, 0xProto a rounded coding font."
            tags: "clock typeface"
            options: [["IBM 3270", "IBM 3270 (terminal)"], ["CPMono_v07", "CPMono"], ["0xProto Nerd Font", "0xProto"], ["JetBrainsMono Nerd Font", "JetBrains Mono"]].map(p => ({
                        value: p[0],
                        label: p[1]
                    }))
            // ---- BEGIN toml custom ----: any installed family (Qt.fontFamilies), found by typing part of its name
            custom: ({
                    placeholder: "Type part of a font name",
                    toText: v => String(v),
                    seed: v => "",
                    parse: t => {
                        const q = t.trim().toLowerCase();
                        const hit = Qt.fontFamilies().find(f => f.toLowerCase() === q);
                        return hit !== undefined ? { ok: true, value: hit } : { ok: false, error: "That font isn't installed. Pick one of the names below." };
                    },
                    suggest: t => {
                        const q = t.trim().toLowerCase();
                        const all = Qt.fontFamilies();
                        return (q === "" ? all.filter(f => /mono/i.test(f)) : all.filter(f => f.toLowerCase().includes(q))).slice(0, 8);
                    },
                    describe: v => String(v)
                })
            // ---- END toml custom ----
        }
        ComboRow {
            label: "Clock time format"
            key: "clockFormat"
            picker: tab.picker
            info: "How the time reads. Custom… takes a Qt time format: HH:mm, or HH:mm:ss for seconds (the clock then ticks every second)."
            tags: "clock seconds 12 hour 24 hour am pm"
            options: [["HH:mm", "24 hour"], ["HH:mm:ss", "24 hour with seconds"], ["h:mm AP", "12 hour"], ["h:mm:ss AP", "12 hour with seconds"]].map(p => ({
                        value: p[0],
                        label: p[1] + " (" + Qt.formatDateTime(new Date(), p[0]) + ")"
                    }))
            // ---- BEGIN toml custom ---- (the preview is live: it follows what is typed)
            custom: ({
                    placeholder: "A Qt time format, such as HH:mm",
                    toText: v => String(v),
                    seed: v => String(v),
                    parse: t => {
                        const e = tab.timeFormatError(t);
                        return e === "" ? { ok: true, value: t } : { ok: false, error: e };
                    },
                    preview: (t, now) => t.trim() === "" ? "" : "Preview: " + Qt.formatDateTime(now, t),
                    describe: v => String(v)
                })
            // ---- END toml custom ----
        }
        ComboRow {
            label: "Clock date format"
            key: "dateFormat"
            picker: tab.picker
            enabled: Settings.get("showDate")
            info: "How the date under the clock reads. Custom… takes a Qt date format, e.g. ddd d MMM, or dddd for the full weekday. Used while the date under the clock is on."
            tags: "clock date"
            options: [["ddd d MMM", "Short"], ["dddd d MMMM", "Long"], ["d MMM yyyy", "With year"], ["yyyy-MM-dd", "Numbers"]].map(p => ({
                        value: p[0],
                        label: p[1] + " (" + Qt.formatDateTime(new Date(), p[0]) + ")"
                    }))
            // ---- BEGIN toml custom ----
            custom: ({
                    placeholder: "A Qt date format, such as ddd d MMM",
                    toText: v => String(v),
                    seed: v => String(v),
                    parse: t => Customs.format(t),
                    preview: (t, now) => t.trim() === "" ? "" : "Preview: " + Qt.formatDateTime(now, t),
                    describe: v => String(v)
                })
            // ---- END toml custom ----
        }
        NumberRow {
            label: "Close delay after hover"
            key: "hoverCloseMs"
            enabled: Settings.get("hoverOpen")
            suffix: " ms"
            info: "How long the control centre stays open after the pointer leaves it. Used while opening on hover is on."
            tags: "hover close delay control centre"
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
