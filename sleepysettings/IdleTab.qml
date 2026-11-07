import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.sleepysettings.components

// Settings tab: what happens when the machine sits idle: dim the screens,
// lock, suspend, and lock before any sleep, for the plugged-in set and (on a laptop) the on-battery set. The keys are staged like every tab; Apply saves them
// and then runs scripts/idle.py, which writes ~/.config/hypr/hypridle.conf from sleepysettings.toml and
// restarts hypridle.service if it is running. Same order as the Theme tab: the script reads the
// file, so it waits for Settings.committed (the keys are on disk) before it starts.
// A hypridle.conf the shell did not write (no idle.py header) is never replaced silently: Apply asks first,
// naming the file, and on yes idle.py --replace keeps a dated backup beside it; Cancel keeps the saved keys
// and leaves the file as it is.
// The minutes rows dim while their switch is off. A step that is not later than the one before it
// shows a red hint; Apply is not blocked (hypridle copes, the order is only odd).
TabPage {
    id: tab
    key: "idle"
    label: "Idle"
    icon: 0xF04B2
    group: "idle"
    // hypridle.conf is written by scripts/idle.py (python3) for hypridle; without them the tab is greyed out
    requires: ["hypridle", "python3"]
    // the folder of hypridle.conf must exist and the file be writable, else the tab greys out under a notice (FileChecks)
    fileIds: ["hypridle"]
    files: [Settings.tilde(Settings.path), Settings.tilde(FileChecks.idlePath)]
    busy: tab.running
    // the plugged-in set and (on a laptop) the on-battery set are both here
    note: "Apply saves and rewrites hypridle.conf"

    property bool running: false
    property bool awaitingCommit: false

    // the minutes of the step before this one that is switched on, 0 for none
    readonly property bool dimOn: Settings.get("idleDim")
    readonly property bool lockOn: Settings.get("idleLock")
    readonly property bool suspendOn: Settings.get("idleSuspend")
    readonly property int dimMin: Settings.get("idleDimMin")
    readonly property int lockMin: Settings.get("idleLockMin")
    readonly property int suspendMin: Settings.get("idleSuspendMin")
    readonly property int beforeLock: tab.dimOn ? tab.dimMin : 0
    readonly property int beforeSuspend: tab.lockOn ? tab.lockMin : tab.dimOn ? tab.dimMin : 0

    function orderHint(on, min, before, what) {
        return on && before > 0 && min <= before ? "Later than " + what + " (" + before + " min), or this step never comes first." : "";
    }

    // once the keys are in sleepysettings.toml (the bar writes the file; the script reads it): ask idle.py whether
    // the file is the shell's own, then write it, or ask before replacing someone else's
    function run() {
        ownership.running = true;
    }

    // one power source for what the question shows and what is written, read once per Apply
    property string source: "--ac"
    // why the last write did not happen, shown above the timers until the next Apply ("" for none)
    property string error: ""

    // replace: the user said yes to replacing info.path (and the file it leads to); idle.py writes nothing if the
    // file is another by then
    function write(replace, info) {
        const args = [tab.source];
        if (replace)
            args.push("--replace", "--expect", info.path, "--expect-target", info.target ?? "");
        runner.command = [Quickshell.shellPath("scripts/idle.py")].concat(args);
        tab.running = true;
        runner.running = true;
    }

    // idle.py's exit codes, in words
    function failure(code) {
        switch (code) {
        case 3:
            return "hypridle.conf wasn't changed: Sleepy Shell didn't write it. Apply again to be asked about replacing it.";
        case 4:
            return "hypridle.conf isn't set up yet: Create it in Config.";
        case 6:
            return "Nothing was written: the file to write changed after you confirmed. Apply again.";
        case 7:
            return "Nothing was written: the file is in a place Sleepy Shell doesn't write to (outside your home folder, or in a folder others can write).";
        case 8:
            return "Nothing was written: the lock that keeps two writes apart couldn't be used.";
        case 9:
            return "hypridle.conf wasn't changed: your settings file has a mistake. Fix the file, then Apply again.";
        }
        return "Writing hypridle.conf failed (exit " + code + ").";
    }

    // the file asked about, while the new content is fetched for the question
    property var asking: null

    function decide(info) {
        if (!info || info.owned) {
            tab.write(false, null);
            return;
        }
        // the dialog's Cancel runs nothing, so the tab is not busy while it asks
        tab.running = false;
        if (!tab.confirm) {
            console.warn("idle: " + info.path + " was not written by sleepyshell; it was left as it is");
            return;
        }
        // show what would replace it: the content first, then the question
        tab.asking = info;
        printer.running = true;
    }

    function askReplace(content) {
        const info = tab.asking;
        tab.asking = null;
        if (!info)
            return;
        // no content to show: no question, so nothing is replaced unseen
        if (content === "") {
            tab.error = "The new hypridle.conf couldn't be prepared, so nothing was replaced.";
            return;
        }
        const name = String(info.path).split("/").pop();
        tab.confirm.askLine("Replace " + name + "?", "Sleepy Shell did not write " + Settings.tilde(info.path) + ", so it may hold your own idle setup. Apply replaces all of it with the lines below; a backup is kept beside it (" + name + ".bak-<date-time>). Cancel keeps your settings saved and leaves the file as it is.", content, () => tab.write(true, info), "Replace");
    }

    Process {
        id: printer
        command: [Quickshell.shellPath("scripts/idle.py"), "--print", tab.source]
        stdout: StdioCollector {
            onStreamFinished: tab.askReplace(text.trim())
        }
    }

    Process {
        id: ownership
        command: [Quickshell.shellPath("scripts/idle.py"), "--owned"]
        stdout: StdioCollector {
            onStreamFinished: {
                let info = null;
                try {
                    info = JSON.parse(text);
                } catch (e) {
                    // no answer: treat the file as the user's, so nothing is replaced without a question
                    info = { path: FileChecks.idlePath, target: "", owned: false };
                }
                tab.decide(info);
            }
        }
    }

    onApplying: {
        // greyed out (hypridle or python3 missing, or the config file cannot be written): Apply only saves the keys, it runs nothing
        if (tab.needsText !== "" || tab.fileText !== "")
            return;
        // a settings file that does not parse: idle.py would write hypridle.conf from the defaults
        tab.error = Settings.brokenNote("hypridle.conf wasn't changed");
        if (tab.error !== "")
            return;
        tab.source = Battery.onBattery ? "--battery" : "--ac";
        tab.running = true;
        tab.awaitingCommit = true;
        ackWait.restart();
    }

    function afterCommit() {
        tab.awaitingCommit = false;
        ackWait.stop();
        tab.error = "";
        tab.run();
    }

    // idle.py reads the saved file, so it runs only once the bar said the keys are saved; if the bar went away
    // first they are still unapplied and nothing runs on the old file
    Connections {
        target: Settings
        function onCommitted(keys) {
            if (tab.awaitingCommit && keys.some(k => tab.keys.includes(k)))
                tab.afterCommit();
        }
        function onUnsaved(keys) {
            if (!tab.awaitingCommit || !keys.some(k => tab.keys.includes(k)))
                return;
            tab.awaitingCommit = false;
            ackWait.stop();
            tab.running = false;
            tab.error = "Your idle settings weren't saved: Sleepy Shell's bar stopped first. They're still unapplied; Apply again.";
        }
    }

    // no word from the bar in 15 s (it hangs): the tab stops being busy so the window can close, and still runs
    // idle.py if the answer comes later
    Timer {
        id: ackWait
        interval: 15000
        onTriggered: {
            if (!tab.awaitingCommit)
                return;
            console.warn("idle: no word from the bar that the idle settings were saved yet");
            tab.running = false;
            tab.error = "Still waiting for Sleepy Shell's bar to save your idle settings. hypridle.conf is updated once it has; keep this window open until then.";
        }
    }

    Process {
        id: runner
        onExited: code => {
            tab.running = false;
            tab.error = code === 0 ? "" : tab.failure(code);
            // a replaced file is the shell's now: the notices follow
            FileChecks.refresh();
        }
    }

    SmallText {
        visible: tab.error !== ""
        text: tab.error
        color: Theme.urgentFg
    }

    // each step's switch sits beside its minutes (PairRow). All the
    // idle timers are on this tab, the plugged-in set and (on a laptop) the on-battery set; labels do not repeat the
    // Section's title, which the search still finds through the row's section title
    Section {
        title: "Idle timers"

        PairRow {
            SwitchRow {
                label: "Dim screens when idle"
                key: "idleDim"
                info: "Darkens the screens with sleepyshell's own overlay after this long without input; any key or mouse movement clears it. Keep awake in the control centre pauses every idle step."
                tags: "idle screen dark brightness hypridle caffeine inhibitor plugged in (plugged in)"
            }
            NumberRow {
                label: "Dim after"
                key: "idleDimMin"
                suffix: " min"
                enabled: tab.dimOn
                tags: "dim idle timeout after (plugged in)"
            }
        }
        PairRow {
            SwitchRow {
                label: "Lock screen when idle"
                key: "idleLock"
                info: "Starts the lock screen after this long without input. Keep awake in the control centre pauses this step."
                tags: "idle hypridle caffeine inhibitor plugged in (plugged in)"
            }
            NumberRow {
                label: "Lock after"
                key: "idleLockMin"
                suffix: " min"
                enabled: tab.lockOn
                error: tab.orderHint(tab.lockOn, tab.lockMin, tab.beforeLock, "dimming")
                tags: "lock idle timeout after (plugged in)"
            }
        }
    }

    // the set used while on battery (moved here from the Power tab; same keys); only on a machine with a battery
    Section {
        title: "On battery"
        visible: Battery.present
        property bool searchOff: !Battery.present

        PairRow {
            SwitchRow {
                label: "Dim when idle"
                key: "idleBatDim"
                info: "The idle steps used while on battery, shorter by default. The plugged-in steps are in Idle timers."
                tags: "idle screen dark discharging dim screens (on battery)"
            }
            NumberRow {
                label: "Dim after"
                key: "idleBatDimMin"
                suffix: " min"
                enabled: Settings.get("idleBatDim")
                tags: "dim idle timeout battery (on battery)"
            }
        }
        PairRow {
            SwitchRow {
                label: "Lock when idle"
                key: "idleBatLock"
                tags: "idle discharging lock screen (on battery)"
            }
            NumberRow {
                label: "Lock after"
                key: "idleBatLockMin"
                suffix: " min"
                enabled: Settings.get("idleBatLock")
                tags: "lock idle timeout battery (on battery)"
            }
        }
    }

    AdvancedSection {
        PairRow {
            SwitchRow {
                label: Battery.present ? "Sleep when idle (plugged in)" : "Sleep when idle"
                key: "idleSuspend"
                info: "Puts the computer to sleep after this long without input. Off by default. Keep awake in the control centre pauses this step."
                tags: "sleep idle hypridle caffeine inhibitor plugged in"
            }
            NumberRow {
                label: Battery.present ? "Sleep after (plugged in)" : "Sleep after"
                key: "idleSuspendMin"
                suffix: " min"
                enabled: tab.suspendOn
                error: tab.orderHint(tab.suspendOn, tab.suspendMin, tab.beforeSuspend, tab.lockOn ? "locking" : "dimming")
                tags: "sleep idle timeout after"
            }
        }
        PairRow {
            visible: Battery.present
            property bool searchOff: !Battery.present

            SwitchRow {
                label: "Sleep when idle (on battery)"
                key: "idleBatSuspend"
                tags: "sleep idle discharging"
            }
            NumberRow {
                label: "Sleep after (on battery)"
                key: "idleBatSuspendMin"
                suffix: " min"
                enabled: Settings.get("idleBatSuspend")
                tags: "sleep idle timeout battery"
            }
        }
        SwitchRow {
            label: "Lock before sleep"
            key: "lockBeforeSleep"
            info: "Locks the screen just before the machine goes to sleep, however it got there (the Sleep step, the session menu, the lid or the power button), so it wakes to the lock screen."
            tags: "suspend lid hypridle sleep"
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
