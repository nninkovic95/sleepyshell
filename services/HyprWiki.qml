pragma Singleton
import Quickshell

// The Hyprland wiki pages Sleepysettings links to (an "Open Hyprland wiki" link beside every file problem
// that Hyprland itself decides). The one table of addresses: each was fetched and documents the Lua config of
// Hyprland 0.55 and later (wiki.hypr.land; hypridle's page still shows its own .conf format, which hypridle keeps).
// A page that cannot be confirmed does not go in this table.
Singleton {
    id: root

    readonly property var urls: ({
            // hl.monitor({ ... })
            monitors: "https://wiki.hypr.land/Configuring/Basics/Monitors/",
            // hl.bind(...), hl.dsp.*
            binds: "https://wiki.hypr.land/Configuring/Basics/Binds/",
            // the config's structure: hyprland.lua, require() of other files, hl.config({ ... })
            lua: "https://wiki.hypr.land/Configuring/Start/",
            // hypridle.conf
            hypridle: "https://wiki.hypr.land/Hypr-Ecosystem/hypridle/"
        })

    function has(key) {
        return root.urls[key] !== undefined;
    }

    // the wiki page for a file's kind ("" when none)
    function url(key) {
        return root.urls[key] ?? "";
    }

    // opens the page in the desktop's browser; the one place that starts it
    function open(key) {
        const u = root.url(key);
        if (u !== "")
            Quickshell.execDetached(["xdg-open", u]);
    }
}
