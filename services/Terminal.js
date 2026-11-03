.pragma library

// How each terminal emulator is told to run a program: the argument list that starts `argv` inside `term`.
// One copy for the shell (DefaultApps) and a second Quickshell config that reuses this file through a link
// (Quickshell imports nothing from outside a config's own folder). opts: {cls: window class / app id,
// title: window title} where the terminal has such options.
function command(term, argv, opts) {
    const cls = opts?.cls ?? "";
    const title = opts?.title ?? "";
    const a = [term];
    switch (term) {
    case "foot":
        if (cls) a.push("--app-id", cls);
        if (title) a.push("--title", title);
        break;
    case "alacritty":
        if (cls) a.push("--class", cls);
        if (title) a.push("--title", title);
        a.push("-e");
        break;
    case "wezterm":
        a.push("start");
        if (cls) a.push("--class", cls);
        a.push("--");
        break;
    case "ghostty":
        if (cls) a.push("--class=" + cls);
        if (title) a.push("--title=" + title);
        a.push("-e");
        break;
    case "konsole":
        if (title) a.push("-p", "tabtitle=" + title);
        a.push("-e");
        break;
    case "gnome-terminal":
        if (cls) a.push("--class=" + cls);
        if (title) a.push("--title=" + title);
        a.push("--");
        break;
    case "xterm":
        if (cls) a.push("-class", cls);
        if (title) a.push("-T", title);
        a.push("-e");
        break;
    default: // kitty, and the unknown: `-e` is the most common spelling
        if (term === "kitty") {
            if (cls) a.push("--class", cls);
            if (title) a.push("--title", title);
        }
        a.push("-e");
    }
    return a.concat(argv);
}
