import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components
import qs.services

// The buttons that go with a file problem (FileChecks.problem(id)), at most two (the button matches the fix):
// the one the problem names (`action`: Create, Open hyprland.lua, Configure in Config, Open settings file, Shuffle colours) and, where it
// helps, a second one: "Configure in Config" beside Create (the file may be in the wrong place), "Open Hyprland wiki" beside a read-only
// Hyprland file. A file that is not loaded by Hyprland gets only "Open hyprland.lua". Used by FileNotice (a card under a tab or
// section title, or the compact form under a row).
Flow {
    id: fa
    // FileChecks.problem(id), or null
    property var problem: null
    property var tooltip: null
    spacing: 6

    readonly property string kind: fa.problem ? fa.problem.kind : ""
    // the second button: Configure in Config next to Create, the wiki next to a read-only or uncreatable Hyprland file
    readonly property string second: fa.problem === null ? "" : fa.kind === "notLoaded" ? "openHypr" : fa.kind === "missing" && fa.problem.action === "create" && fa.problem.id !== "colors" ? "configure" : (fa.kind === "notWritable" || fa.kind === "noCreate") && fa.problem.wiki !== "" ? "wiki" : ""

    BarButton {
        id: mainBtn
        objectName: "fileAction"
        visible: fa.problem !== null && fa.problem.action !== ""
        text: fa.problem ? fa.problem.actionText : ""
        glyph: !fa.problem ? 0 : fa.problem.action === "create" ? 0xF0257 : fa.problem.action === "configure" ? 0xF107C : fa.problem.action === "shuffle" ? 0xF03D8 : fa.problem.action === "setup" ? 0xF0493 : 0xF11E7
        glyphFirst: true
        glued: false
        bg: fa.problem && fa.problem.action !== "configure" && fa.problem.action !== "openSettings" && fa.problem.action !== "openHypr" ? Theme.hoverBg : Theme.tileBg
        onClicked: FileChecks.act(fa.problem)
        onHoveredChanged: {
            if (!fa.tooltip || !fa.problem)
                return;
            if (hovered)
                fa.tooltip.show(mainBtn, fa.problem.action === "create" ? Settings.tilde(fa.problem.path) : fa.problem.action === "setup" ? "Adds " + fa.problem.requireLine + " to " + Settings.tilde(HyprConfig.main) + ", after you confirm" : fa.problem.action === "openSettings" ? Settings.tilde(Settings.path) : fa.problem.text, false);
            else
                fa.tooltip.hide(mainBtn);
        }
    }

    BarButton {
        objectName: "fileSecond"
        visible: fa.second !== ""
        text: fa.second === "wiki" ? "Open Hyprland wiki" : fa.second === "openHypr" ? "Open " + (HyprConfig.format === "conf" ? "hyprland.conf" : "hyprland.lua") : "Configure in Config"
        glyph: fa.second === "wiki" ? 0xF03CC : fa.second === "openHypr" ? 0xF11E7 : 0xF107C
        glyphFirst: true
        glued: false
        bg: Theme.tileBg
        onClicked: fa.second === "wiki" ? HyprWiki.open(fa.problem.wiki) : fa.second === "openHypr" ? FileChecks.act({ action: "openHypr", id: fa.problem.id }) : FileChecks.configureRequested(fa.problem.id)
    }
}
