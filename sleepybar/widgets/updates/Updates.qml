import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.services
import qs.sleepybar.components

// Pending package updates (repo + AUR) from scripts/checkupdates.sh, checked at start and every
// Settings.updateMinutes minutes (default 30). Click: dropdown with the list; "Update now" opens kitty with scripts/update.sh (a big
// "UPDATER" banner so the sudo password prompt does not sit in a bare window, then paru -Syu);
// right click: re-check. It needs pacman, paru and fakeroot (scripts/checkupdates.sh); without them
// (services/Deps.qml) it never checks, and the dropdown says what is missing.
BarButton {
    id: root
    required property var bar
    property int repo: 0
    property int aur: 0
    property var packages: []
    property bool checking: false
    property bool failed: false
    readonly property int total: repo + aur
    // only on the bar while there is something to update; the right island's
    // Loader follows `shown`, and the checks keep running while it is hidden
    readonly property bool shown: total > 0
    readonly property var requires: ["pacman", "paru", "fakeroot"]
    readonly property string needsText: Deps.needs(root.requires)
    inset: true

    glyph: checking ? 0xF0453 : 0xF03D6
    text: total > 0 ? String(total) : ""
    // a lone glyph (nothing pending) would be a narrow sliver
    minWidth: Theme.buttonHeight
    // urgent tint when the last check failed, muted when nothing is pending
    fg: failed ? Theme.urgentFg : total > 0 ? Theme.fg : Theme.fgMuted
    bg: pop.open ? Theme.hoverBg : "transparent"
    onClicked: button => {
        if (button === Qt.RightButton)
            root.check();
        else
            pop.toggle();
    }

    function check() {
        if (root.needsText !== "")
            return;
        if (!checker.running) {
            checking = true;
            checker.running = true;
        }
    }

    function parse(out) {
        // a failed run (offline, database lock) prints nothing; keep the last good counts
        if (!out.includes("REPO "))
            return;
        const pkgs = [];
        let r = 0, a = 0;
        for (const line of out.split("\n")) {
            if (line.startsWith("REPO "))
                r = parseInt(line.slice(5)) || 0;
            else if (line.startsWith("AUR "))
                a = parseInt(line.slice(4)) || 0;
            else if (line.startsWith("PKG "))
                pkgs.push(line.slice(4));
        }
        repo = r;
        aur = a;
        packages = pkgs;
    }

    Process {
        id: checker
        command: [Quickshell.shellPath("scripts/checkupdates.sh")]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: (code, status) => {
            root.checking = false;
            root.failed = code !== 0;
        }
    }

    Process {
        id: upgrade
        command: DefaultApps.terminalCommand([Quickshell.shellPath("scripts/update.sh")], {
            cls: "bar-update",
            title: "System update"
        })
        onExited: root.check()
    }

    Timer {
        interval: Settings.updateMinutes * 60 * 1000
        repeat: true
        running: true
        onTriggered: root.check()
    }

    Timer {
        interval: 20000
        running: true
        onTriggered: root.check()
    }

    IslandDropdown {
        id: pop
        name: "updates"
        fixedWidth: 380
        anchorItem: root
        bar: root.bar

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 4
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: root.needsText !== "" ? root.needsText : root.checking ? "Checking…" : root.failed ? "Check failed" : root.total === 0 ? "System is up to date" : root.total + " updates  (" + root.repo + " repo, " + root.aur + " AUR)"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
                color: Theme.fg
            }

            BarButton {
                glyph: 0xF0453
                hpad: 6
                glued: false
                opacity: root.needsText === "" ? 1 : 0.5
                onClicked: root.check()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 4
            implicitHeight: 1
            color: Theme.containerHighest
        }

        Repeater {
            model: root.packages.slice(0, 30)

            Text {
                required property string modelData
                Layout.leftMargin: 10
                textFormat: Text.PlainText   // a package name from pacman or paru, never markup
                text: modelData
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                color: Theme.fg
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }
        }

        Text {
            visible: root.packages.length > 30
            Layout.leftMargin: 10
            text: "… and " + (root.packages.length - 30) + " more"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            color: Theme.fgMuted
        }

        Rectangle {
            visible: root.total > 0
            Layout.fillWidth: true
            Layout.margins: 4
            implicitHeight: 1
            color: Theme.containerHighest
        }

        MenuItem {
            visible: root.total > 0
            icon: 0xF06B0
            label: "Update now"
            requires: root.requires
            onClicked: {
                pop.open = false;
                upgrade.running = true;
            }
        }
    }
}
