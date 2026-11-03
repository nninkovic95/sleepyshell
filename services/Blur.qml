pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Hyprland's blur strength from the settings (`blurStrength`, Bar tab), set at run time with
// `hyprctl eval 'hl.config({ decoration = { blur = {...} } })'`.
//
// Hyprland has one blur for everything: the shell's translucent islands and dropdowns, and every
// see-through window (a window with an opacity below 1). This setting changes it for all of them.
//   config  Hyprland's own value (decoration.blur in its config), untouched; the default, so a new user's
//           Hyprland look does not change
//   off     no blur
//   light / medium / strong   size 3 / 6 / 10, passes 1 / 2 / 3
//
// A run-time value lasts until Hyprland reloads its config, which puts the config's value back, so the
// `configreloaded` event applies the choice again. Going back to "config" after another choice asks
// Hyprland to reload its config (`hyprctl reload config-only`: monitors are left alone) rather than
// guessing the config's value: a value read from Hyprland after a shell restart could be this
// service's own earlier choice.
//
// The choice is read live (Settings.live), so picking one in the settings window shows it at once and
// leaving without Apply puts the applied one back.
Singleton {
    id: root

    readonly property string choice: Settings.blurStrength
    readonly property var presets: ({
            off: "enabled = false",
            light: "enabled = true, size = 3, passes = 1",
            medium: "enabled = true, size = 6, passes = 2",
            strong: "enabled = true, size = 10, passes = 3"
        })

    // a preset is in force at run time (kept over a hot reload of the shell), so "config" must reload
    PersistentProperties {
        id: persist
        reloadableId: "blur"
        property bool overridden: false
    }

    onChoiceChanged: root.apply()
    Component.onCompleted: root.apply()

    function apply() {
        if (!Deps.has("hyprctl"))
            return;
        const p = root.presets[root.choice];
        if (p !== undefined) {
            persist.overridden = true;
            Quickshell.execDetached(["hyprctl", "eval", "hl.config({ decoration = { blur = { " + p + " } } })"]);
        } else if (persist.overridden) {
            persist.overridden = false;
            Quickshell.execDetached(["hyprctl", "reload", "config-only"]);
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(e) {
            // the reload put the config's blur back: apply a preset again (nothing to do for "config")
            if (e.name === "configreloaded" && root.presets[root.choice] !== undefined)
                root.apply();
        }
    }
}
