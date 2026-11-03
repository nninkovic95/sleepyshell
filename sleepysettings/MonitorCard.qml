import QtQuick
import QtQuick.Layouts
import qs
import qs.components
import qs.services
import qs.sleepysettings.components

// One monitor on the Display tab, one card per monitor. The card is headed "HDMI-A-1 · model" with
// "Currently ..." on the right and holds the everyday rows: Resolution, Refresh rate, Interface scale, and, when the monitor answers over DDC/CI,
// Brightness and Contrast. Everything rarer is in the Advanced fold under the card: Input source and Colour preset (DDC), screen rotation, adaptive sync, 10-bit colour and HDR with its two SDR sliders. This replaces the old pair of cards ("Monitor: <model>"
// for DDC and one card per monitor for the mode) and the single Advanced fold at the end of the tab.
//
// Two kinds of rows: the monitor's draft (resolution ... HDR: staged in Displays.qml, written by Apply to monitors.lua, then the keep-or-revert countdown)
// and the live DDC values (a slider writes as it moves, nothing waits for Apply). Every row has the revert arrow of the other tabs, shown only
// while its value differs: for a draft row it goes back to what monitors.lua says now; for a DDC row to the value the monitor had when the tab
// was opened (MonitorCtl.baseline). While the monitor cannot be controlled over DDC the rows stay, greyed, under the setup guide (DdcGuide),
// which sits inside this card.
ColumnLayout {
    id: mc
    objectName: "monitorSection"
    // an entry of Displays.monitors
    required property var modelData
    // the Display tab (its picker and tooltip)
    required property var host
    readonly property string output: mc.modelData.name
    readonly property string out: mc.output
    // the EDID's model: characters that could read as markup are dropped (the heading is not plain text)
    readonly property string title: mc.output + (mc.modelData.model ? "  ·  " + mc.modelData.model.replace(/[<>&]/g, "") : "")

    // ---- the draft ----
    readonly property var d: Displays.draft[mc.output] ?? Displays.configured(mc.output)
    readonly property var c: Displays.configured(mc.output)
    readonly property bool editable: Displays.editable(mc.output)
    readonly property bool live: mc.editable && !Displays.pending
    // "2560x1440@143.86" -> resolution and rate; a mode word ("preferred") has no rate
    readonly property string res: mc.d.mode.split("@")[0]
    readonly property string rate: mc.d.mode.includes("@") ? mc.d.mode.split("@")[1] : ""
    readonly property string cRes: mc.c.mode.split("@")[0]
    readonly property string cRate: mc.c.mode.includes("@") ? mc.c.mode.split("@")[1] : ""
    readonly property var resolutions: {
        const out = [];
        for (const m of mc.modelData.modes) {
            const r = m.split("@")[0];
            if (!out.includes(r))
                out.push(r);
        }
        if (!out.includes(mc.res))
            out.unshift(mc.res);
        return out;
    }
    function ratesFor(r) {
        return mc.modelData.modes.filter(m => m.startsWith(r + "@")).map(m => m.split("@")[1]).sort((a, b) => Number(b) - Number(a));
    }
    function setMode(r, hz) {
        Displays.setDraft(mc.output, "mode", hz ? r + "@" + hz : r);
    }
    function setDraft(key, value) {
        Displays.setDraft(mc.output, key, value);
    }
    readonly property string revertWord: "Back to what the file says now. Nothing changes until Apply."

    // ---- DDC/CI ----
    // the Brightness.ddc entry of this output (it is replaced on every brightness reading, so the tab's Repeater is keyed on the names)
    readonly property var ddcInfo: Brightness.ddc.find(m => m.output === mc.output) ?? null
    readonly property bool hasDdc: mc.ddcInfo !== null
    readonly property string st: mc.hasDdc ? MonitorCtl.stateOf(mc.ddcInfo) : "none"
    readonly property bool usable: mc.st === "ok"
    readonly property bool guide: mc.st === "nomodule" || mc.st === "noaccess" || mc.st === "off"
    // "no module" and "no access" are the same fix for every monitor: the first monitor in that state shows the guide (its rule
    // covers the buses of all of them), the others point to it. "off" is a setting of each monitor's own menu, so each shows its own.
    readonly property bool shared: mc.st === "nomodule" || mc.st === "noaccess"
    readonly property var sameState: Brightness.ddc.filter(m => MonitorCtl.stateOf(m) === mc.st)
    readonly property bool leader: !mc.shared || mc.sameState.length === 0 || mc.sameState[0].output === mc.output
    // the HDR line this monitor's EDID does not back: the first block anywhere in the loaded Hyprland files that names this output with cm hdr
    readonly property var hdrEntry: HyprConfig.monitors.find(m => m.config && m.config.output === mc.output && (m.config.cm === "hdr" || m.config.cm === "hdredid")) ?? null
    readonly property bool hdrMismatch: mc.hdrEntry !== null && Displays.hdr[mc.output] !== undefined && !Displays.hdr[mc.output].error && !Displays.hasHdr(mc.output)
    readonly property string hdrFile: mc.hdrEntry ? Settings.tilde(mc.hdrEntry.file) : ""
    readonly property int hdrLine: mc.hdrEntry ? mc.hdrEntry.line : 0
    readonly property bool hdrInMonitorsFile: mc.hdrEntry !== null && mc.hdrEntry.file === Displays.path
    readonly property string ddcRevert: "Back to what the monitor had when you opened this tab."
    readonly property var b10: MonitorCtl.base(mc.out, 0x10)
    readonly property real level: Brightness.ddcLevel(mc.out)

    Layout.fillWidth: true
    spacing: 6

    Section {
        id: card
        title: mc.title
        indexTitle: mc.output
        requires: []

        headerItems: [
            InfoTip {
                visible: !mc.editable
                Layout.alignment: Qt.AlignVCenter
                warn: true
                tooltip: mc.host.tooltip
                text: "This monitor's block in monitors.lua has a nested table, so the tab leaves it alone. Edit it by hand."
            },
            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.topMargin: 8
                text: "Currently " + mc.modelData.running.replace("x", " × ").replace("@", " @ ") + " Hz"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
                color: Theme.fgMuted
            }
        ]

        DdcGuide {
            visible: mc.guide && mc.leader
            kind: mc.st
            buses: mc.shared ? mc.sameState.map(m => m.bus) : [mc.ddcInfo ? mc.ddcInfo.bus : -1]
        }

        SmallText {
            objectName: "guideSame"
            visible: mc.guide && !mc.leader
            text: mc.hasDdc ? "Same steps as for " + Brightness.ddcLabel(mc.sameState[0] ?? mc.ddcInfo).replace(/[<>&]/g, "") + " above." : ""
        }

        // a line in the Hyprland config that sets HDR for a monitor whose EDID says it has none: said here, with the file and line;
        // when the line is in monitors.lua itself, Remove it takes that one key out of this monitor's block (staged, written by Apply, with the same
        // backup and keep-or-revert countdown as every change here). In another file there is only the notice: the shell never edits those.
        RowLayout {
            objectName: "hdrNotice"
            visible: mc.hdrMismatch
            Layout.fillWidth: true
            spacing: 8

            SmallText {
                objectName: "hdrNoticeText"
                Layout.fillWidth: true
                text: mc.d.cm === "" ? "HDR will be taken out of " + mc.hdrFile + " (line " + mc.hdrLine + ") when you press Apply." : "HDR is set in " + mc.hdrFile + " (line " + mc.hdrLine + "), but this monitor doesn't report HDR support."
                color: mc.d.cm === "" ? Theme.fgMuted : Theme.urgentFg
            }

            BarButton {
                objectName: "hdrNoticeRemove"
                visible: mc.hdrInMonitorsFile && mc.d.cm !== ""
                enabled: mc.live
                text: "Remove it"
                glued: false
                bg: Theme.tileBg
                onClicked: Displays.removeCm(mc.output)
            }
        }

        SettingRow {
            objectName: "rowResolution"
            enabled: mc.live
            label: "Resolution"
            info: "Use the panel's native resolution (the largest one listed). After <b>Apply</b> you have 15 seconds to press <b>Keep</b>; if the screen goes blank, wait and it switches back."
            tags: "mode monitor screen"
            changedMark: mc.res !== mc.cRes
            canRevert: mc.res !== mc.cRes
            revertText: mc.revertWord
            onRevertRequested: Displays.revertKeys(mc.output, ["mode"])

            Combo {
                picker: mc.host.picker
                value: mc.res
                options: mc.resolutions.map(r => ({
                            value: r,
                            label: r.replace("x", " × ")
                        }))
                // a new resolution takes its highest refresh rate
                onPicked: v => mc.setMode(v, mc.ratesFor(v)[0] ?? "")
            }
        }

        SettingRow {
            objectName: "rowRefresh"
            enabled: mc.live && mc.rate !== ""
            label: "Refresh rate"
            info: "How many times a second the screen redraws. Pick the highest one for the resolution; picking a resolution already selects its highest rate."
            tags: "hz monitor screen"
            changedMark: mc.rate !== mc.cRate
            canRevert: mc.rate !== mc.cRate
            revertText: mc.revertWord
            onRevertRequested: mc.setMode(mc.res, mc.ratesFor(mc.res).includes(mc.cRate) ? mc.cRate : (mc.ratesFor(mc.res)[0] ?? ""))

            Combo {
                picker: mc.host.picker
                value: mc.rate
                options: {
                    const list = mc.ratesFor(mc.res);
                    if (mc.rate !== "" && !list.includes(mc.rate))
                        list.unshift(mc.rate);
                    return list.map(h => ({
                                value: h,
                                label: h + " Hz"
                            }));
                }
                onPicked: v => mc.setMode(mc.res, v)
            }
        }

        SettingRow {
            objectName: "rowScale"
            enabled: mc.live
            label: "Interface scale"
            info: "Makes everything larger. 1× suits a 27 to 32 inch 1440p screen; fractional steps (1.25×, 1.5×) can make some apps look soft."
            tags: "zoom hidpi monitor screen"
            changedMark: mc.d.scale !== mc.c.scale
            canRevert: mc.d.scale !== mc.c.scale
            revertText: mc.revertWord
            onRevertRequested: Displays.revertKeys(mc.output, ["scale"])

            Segmented {
                value: mc.d.scale
                options: [1, 1.25, 1.5, 1.75, 2].map(s => ({
                            value: s,
                            label: s + "×"
                        }))
                onPicked: v => mc.setDraft("scale", v)
            }
        }

        SettingRow {
            objectName: "rowBrightness"
            visible: mc.hasDdc && (!mc.usable || MonitorCtl.has(mc.out, 0x10))
            enabled: mc.usable
            requires: ["python3"]
            label: "Brightness"
            info: "How bright this monitor is. It changes while you drag and the monitor keeps it."
            tags: "backlight luminance ddc monitor screen"
            canRevert: mc.usable && !!mc.b10 && mc.level >= 0 && Math.abs(mc.level - mc.b10.current / mc.b10.max * 100) >= 1
            revertText: mc.ddcRevert
            onRevertRequested: MonitorCtl.revertToBase(mc.out, 0x10)

            VSlider {
                Layout.fillWidth: true
                value: Math.max(0, Brightness.ddcLevel(mc.out)) / 100
                onMoved: v => Brightness.setDdc(mc.out, v * 100)
            }
        }

        SettingRow {
            objectName: "rowContrast"
            visible: mc.hasDdc && (!mc.usable || MonitorCtl.has(mc.out, 0x12))
            enabled: mc.usable
            requires: ["python3"]
            label: "Contrast"
            info: "The gap between the darkest and the brightest parts of the picture. The monitor's own default is usually best."
            tags: "ddc monitor screen"
            canRevert: mc.usable && MonitorCtl.changedFromBase(mc.out, 0x12)
            revertText: mc.ddcRevert
            onRevertRequested: MonitorCtl.revertToBase(mc.out, 0x12)

            VSlider {
                Layout.fillWidth: true
                value: MonitorCtl.frac(mc.out, 0x12)
                onMoved: v => MonitorCtl.setFrac(mc.out, 0x12, v)
            }
        }
    }

    // the rarer rows of this monitor (the fold is remembered for the tab, so every monitor's fold opens and closes together)
    AdvancedSection {

        SettingRow {
            objectName: "rowInput"
            visible: mc.hasDdc && (!mc.usable || MonitorCtl.has(mc.out, 0x60))
            enabled: mc.usable
            requires: ["python3"]
            label: "Input source"
            info: "Which cable the monitor shows. If you pick one with nothing plugged in, this screen goes blank: press the monitor's own buttons to switch back."
            warn: true
            tags: "hdmi displayport dp cable source ddc monitor screen"
            canRevert: mc.usable && MonitorCtl.changedFromBase(mc.out, 0x60)
            revertText: mc.ddcRevert
            onRevertRequested: MonitorCtl.revertToBase(mc.out, 0x60)

            Combo {
                picker: mc.host.picker
                value: MonitorCtl.val(mc.out, 0x60)?.current
                options: MonitorCtl.allowedValues(mc.out, 0x60).map(v => ({
                            value: v,
                            label: MonitorCtl.inputLabel(v)
                        }))
                onPicked: v => MonitorCtl.setValue(mc.out, 0x60, v)
            }
        }

        SettingRow {
            objectName: "rowPreset"
            visible: mc.hasDdc && (!mc.usable || MonitorCtl.has(mc.out, 0x14))
            enabled: mc.usable
            requires: ["python3"]
            label: "Colour preset"
            info: "The monitor's own colour warmth. Custom uses the red, green and blue values saved in the monitor (set them in its own menu); 6500 K is the standard for photos, video and the web."
            tags: "temperature kelvin warm cool color colour ddc monitor screen"
            canRevert: mc.usable && MonitorCtl.changedFromBase(mc.out, 0x14)
            revertText: mc.ddcRevert
            onRevertRequested: MonitorCtl.revertToBase(mc.out, 0x14)

            Combo {
                picker: mc.host.picker
                value: MonitorCtl.val(mc.out, 0x14)?.current
                options: MonitorCtl.allowedValues(mc.out, 0x14).map(v => ({
                            value: v,
                            label: MonitorCtl.presetLabel(v, mc.out)
                        }))
                onPicked: v => MonitorCtl.setValue(mc.out, 0x14, v)
            }
        }

        SettingRow {
            objectName: "rowTransform"
            enabled: mc.live
            label: "Screen rotation"
            info: "Only for a monitor turned on its side or mounted upside down."
            tags: "transform portrait monitor screen"
            changedMark: mc.d.transform !== mc.c.transform
            canRevert: mc.d.transform !== mc.c.transform
            revertText: mc.revertWord
            onRevertRequested: Displays.revertKeys(mc.output, ["transform"])

            Segmented {
                value: mc.d.transform
                options: [0, 1, 2, 3].map(t => ({
                            value: t,
                            label: (t * 90) + "°"
                        }))
                onPicked: v => mc.setDraft("transform", v)
            }
        }

        SettingRow {
            objectName: "rowVrr"
            enabled: mc.live
            label: "Adaptive sync"
            info: "FreeSync / VRR: the screen follows a game's frame rate, so there is no tearing. <b>Fullscreen</b> is the safe choice; <b>Always</b> can make browsers and video flicker. Hyprland reports it " + (mc.modelData.vrrActive ? "<b>active</b> now." : "<b>inactive</b> now, expected with Fullscreen when no game is open.")
            tags: "vrr freesync gsync monitor screen"
            changedMark: mc.d.vrr !== mc.c.vrr
            canRevert: mc.d.vrr !== mc.c.vrr
            revertText: mc.revertWord
            onRevertRequested: Displays.revertKeys(mc.output, ["vrr"])

            Segmented {
                value: mc.d.vrr
                options: [[0, "Off"], [1, "Always"], [2, "Fullscreen"]].map(p => ({
                            value: p[0],
                            label: p[1]
                        }))
                onPicked: v => mc.setDraft("vrr", v)
            }
        }

        SettingRow {
            objectName: "rowBitdepth"
            enabled: mc.live
            label: "10-bit colour"
            info: "Smoother gradients, but the monitor, the cable and the refresh rate all have to support it. If colours look wrong or the screen goes black, let the change revert."
            tags: "bitdepth hdr color monitor screen"
            changedMark: mc.d.bitdepth !== mc.c.bitdepth
            canRevert: mc.d.bitdepth !== mc.c.bitdepth
            revertText: mc.revertWord
            onRevertRequested: Displays.revertKeys(mc.output, ["bitdepth"])

            Toggle {
                checked: mc.d.bitdepth === 10
                onClicked: mc.setDraft("bitdepth", mc.d.bitdepth === 10 ? 8 : 10)
            }
        }

        // HDR: works only for a monitor whose EDID says it can (scripts/edid.py), greyed with the reason otherwise; off by default, only here, never in the main card. Field names
        // and ranges: see the note on `draft` in services/Displays.qml (the Hyprland wiki's Monitors page).
        SettingRow {
            objectName: "rowHdr"
            // always there; greyed with the reason unless the EDID says the monitor can (a monitor that is already in HDR can still be switched off)
            enabled: mc.live && (Displays.hasHdr(mc.output) || Displays.hdrOn(mc.d))
            hint: Displays.hasHdr(mc.output) ? "" : Displays.hdrReason(mc.output)
            label: "HDR"
            info: "Turns on HDR for this monitor. Turn on the monitor's own HDR mode too if it has one. Normal windows can look dim at first: set them with SDR brightness below. On many monitors with basic HDR10 (no local dimming) the picture looks worse in HDR than without it; try it, and the countdown puts it back if you don't keep it."
            tags: "hdr high dynamic range color colour management cm monitor screen"
            changedMark: Displays.hdrOn(mc.d) !== Displays.hdrOn(mc.c)
            canRevert: Displays.hdrOn(mc.d) !== Displays.hdrOn(mc.c)
            revertText: mc.revertWord
            onRevertRequested: Displays.revertKeys(mc.output, Displays.hdrOn(mc.c) ? ["cm"] : ["cm", "bitdepth"])

            Toggle {
                checked: Displays.hdrOn(mc.d)
                onClicked: Displays.setHdr(mc.output, !Displays.hdrOn(mc.d))
            }
        }

        SettingRow {
            id: sdrB
            objectName: "rowSdrBrightness"
            visible: Displays.hdrOn(mc.d)
            enabled: mc.live
            label: "SDR brightness"
            info: "How bright normal (non-HDR) windows look while HDR is on. To set it: put a white page next to a photo you know, then raise this until white looks as bright as it did with HDR off, without greys turning grainy. Around 1.2 to 1.5 suits most monitors."
            tags: "hdr sdr brightness white level monitor screen"
            readonly property real min: 1
            readonly property real max: 2
            readonly property real step: 0.05
            changedMark: mc.d.sdrbrightness !== mc.c.sdrbrightness
            canRevert: mc.d.sdrbrightness !== mc.c.sdrbrightness
            revertText: mc.revertWord
            onRevertRequested: Displays.revertKeys(mc.output, ["sdrbrightness"])

            VSlider {
                Layout.fillWidth: true
                value: (Math.max(sdrB.min, Math.min(sdrB.max, mc.d.sdrbrightness)) - sdrB.min) / (sdrB.max - sdrB.min)
                wheelStep: sdrB.step / (sdrB.max - sdrB.min)
                text: Number(mc.d.sdrbrightness).toFixed(2)
                textWidth: 64
                parseTyped: t => {
                    const n = Number(t.replace(",", ".").trim());
                    return t === "" || isNaN(n) ? NaN : (Math.max(sdrB.min, Math.min(sdrB.max, n)) - sdrB.min) / (sdrB.max - sdrB.min);
                }
                onMoved: v => mc.setDraft("sdrbrightness", Number((Math.round((sdrB.min + v * (sdrB.max - sdrB.min)) / sdrB.step) * sdrB.step).toFixed(2)))
            }
        }

        SettingRow {
            id: sdrS
            objectName: "rowSdrSaturation"
            visible: Displays.hdrOn(mc.d)
            enabled: mc.live
            label: "SDR saturation"
            info: "How strong normal colours look while HDR is on. Leave it at 1 unless colours look pale; then raise it a little while looking at a familiar photo."
            tags: "hdr sdr saturation colour color monitor screen"
            readonly property real min: 0.5
            readonly property real max: 1.5
            readonly property real step: 0.05
            changedMark: mc.d.sdrsaturation !== mc.c.sdrsaturation
            canRevert: mc.d.sdrsaturation !== mc.c.sdrsaturation
            revertText: mc.revertWord
            onRevertRequested: Displays.revertKeys(mc.output, ["sdrsaturation"])

            VSlider {
                Layout.fillWidth: true
                value: (Math.max(sdrS.min, Math.min(sdrS.max, mc.d.sdrsaturation)) - sdrS.min) / (sdrS.max - sdrS.min)
                wheelStep: sdrS.step / (sdrS.max - sdrS.min)
                text: Number(mc.d.sdrsaturation).toFixed(2)
                textWidth: 64
                parseTyped: t => {
                    const n = Number(t.replace(",", ".").trim());
                    return t === "" || isNaN(n) ? NaN : (Math.max(sdrS.min, Math.min(sdrS.max, n)) - sdrS.min) / (sdrS.max - sdrS.min);
                }
                onMoved: v => mc.setDraft("sdrsaturation", Number((Math.round((sdrS.min + v * (sdrS.max - sdrS.min)) / sdrS.step) * sdrS.step).toFixed(2)))
            }
        }
    }
}
