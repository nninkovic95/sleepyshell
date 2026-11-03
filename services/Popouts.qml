pragma Singleton
import Quickshell
import Quickshell.Hyprland

// Tracks the one open dropdown so opening another closes it, and a name registry for
// `qs ipc call sleepybar toggle <name>` (clock, audio, network, privacy, wallpaper).
// Every screen has its own set of surfaces, so a name maps to a list and toggle picks the one
// on the focused monitor; surfaces unregister when their screen goes away.
Singleton {
    property var current: null
    property var byName: ({})

    function register(name, p) {
        const l = byName[name] ?? [];
        l.push(p);
        byName[name] = l;
    }

    function unregister(name, p) {
        const l = byName[name];
        if (l)
            byName[name] = l.filter(x => x !== p);
        if (current === p)
            current = null;
    }

    function toggle(name) {
        const l = byName[name] ?? [];
        if (l.length === 0)
            return;
        const mon = Hyprland.focusedMonitor;
        const p = l.find(x => mon && x.bar && x.bar.screen && x.bar.screen.name === mon.name) ?? l[0];
        p.open = !p.open;
    }

    function opened(p) {
        if (current && current !== p)
            current.open = false;
        current = p;
    }

    function closed(p) {
        if (current === p)
            current = null;
    }
}
