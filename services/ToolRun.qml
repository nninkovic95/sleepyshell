pragma Singleton
import QtQuick
import Quickshell

// Running the user's own control-centre tools. A custom tool is
// { id, label, icon, kind, value, terminal } (Settings.customTools):
//   app      value is a desktop entry id (the DesktopEntries list); launching runs the entry itself
//   command  value is a shell command; `terminal` runs it in the terminal chosen in the Apps tab (DefaultApps.terminalShell)
//   link     value is an address; the desktop opener (`openerProgram` below) opens it
// Every launch ends in one of the two lines marked "launch" below, which the test kit's sandbox replaces with a log line.
// A tool whose program is missing is greyed out in the control centre and in the editor with "Needs ..." (needs()); the first
// word of a command is asked of Deps (Deps.want), like the editor named in programs.lua.
Singleton {
    id: root

    // the desktop's opener, which runs a link tool (Deps probes it; the test kit splits the literal)
    readonly property string openerProgram: "xdg-open"

    // the terminal that runs a command tool with "Run in terminal": the Apps tab's choice
    readonly property string terminalProgram: DefaultApps.terminal

    function terminalCommand(cmd) {
        return DefaultApps.terminalShell(cmd);
    }

    // the command line of a command or link tool, null for an app (which the desktop entry launches)
    function argv(tool) {
        if (!tool)
            return null;
        if (tool.kind === "link")
            return [root.openerProgram, String(tool.value)];
        if (tool.kind === "command")
            return tool.terminal ? root.terminalCommand(String(tool.value)) : ["sh", "-c", String(tool.value)];
        return null;
    }

    // the first word of a command, which has to exist as a program
    function firstWord(cmd) {
        const m = String(cmd).trim().match(/^(?:\w+=\S*\s+)*([^\s;&|<>()]+)/);
        return m ? m[1] : "";
    }

    // the programs a tool runs (for Deps)
    function programs(tool) {
        if (!tool)
            return [];
        if (tool.kind === "link")
            return [root.openerProgram];
        if (tool.kind === "command") {
            const w = root.firstWord(tool.value);
            return (tool.terminal ? [root.terminalProgram] : []).concat(w !== "" && !w.includes("/") ? [w] : []);
        }
        return [];
    }

    // ask Deps about the programs of these tools (a name it does not know counts as missing until it has been asked)
    function want(tools) {
        for (const t of tools)
            for (const p of root.programs(t))
                Deps.want(p);
    }

    function entry(id) {
        return DesktopEntries.byId(String(id)) ?? null;
    }

    // "" when the tool can run, else "Needs ... (not installed)"
    function needs(tool) {
        if (!tool)
            return "";
        if (tool.kind === "app")
            return root.entry(tool.value) ? "" : "Not found: " + tool.value;
        if (String(tool.value).trim() === "")
            return "Needs a " + (tool.kind === "link" ? "link" : "command");
        // a command's program is the user's own (Deps.want makes it an app): "Not found: btop", no hint to install anything
        return Deps.needs(root.programs(tool));
    }

    function run(tool) {
        if (!tool || root.needs(tool) !== "")
            return;
        if (tool.kind === "app") {
            const e = root.entry(tool.value);
            if (e)
                e.execute(); // launch
            return;
        }
        const a = root.argv(tool);
        if (a)
            Quickshell.execDetached(a); // launch
    }
}
