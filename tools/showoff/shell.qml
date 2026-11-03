import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// showoff: demo tools kept out of sleepyshell, for recording the shell.
//   - screen recorder (Recorder.qml): SUPER + SHIFT + R, a red "REC m:ss" pill while it records
//   - click rings and a shortcuts popup (InputOverlay.qml): SUPER + SHIFT + K, a "KEYS" pill while on;
//     Hyprland reports the shortcuts and clicks itself (showoff.lua), nothing reads the keyboard
// The pills sit under sleepyshell's left island; a click on one stops that tool.
// Run on demand: ~/.config/quickshell/showoff/showoff.sh <record|keys> starts this instance if needed and
// sends the action over IPC (`qs -c showoff ipc call showoff <action>`).
ShellRoot {
    id: shellRoot

    // matugen's colours, the same file sleepyshell themes itself from, so the pills match the bar
    property color urgent: "#93000a"
    property color urgentFg: "#ffdad6"
    property color panel: "#2f353e"
    property color fg: "#dde3ee"
    property color primary: "#9dcaff"
    property color error: "#ffb4ab"
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                const take = (key, prop) => {
                    if (typeof c[key] === "string" && c[key].startsWith("#"))
                        shellRoot[prop] = c[key];
                };
                take("error_container", "urgent");
                take("on_error_container", "urgentFg");
                take("surface_container_highest", "panel");
                take("on_surface", "fg");
                take("primary", "primary");
                take("error", "error");
            } catch (e) {
                console.warn("showoff: colours not read: " + e);
            }
        }
    }

    Recorder {
        id: recorder
    }

    InputOverlay {
        id: input
        fill: shellRoot.panel
        text: shellRoot.fg
        leftRing: shellRoot.primary
        rightRing: shellRoot.error
    }

    IpcHandler {
        target: "showoff"

        // start or stop a screen recording
        function record(): void {
            recorder.toggle();
        }

        // switch the click rings and the pressed-keys popup on or off
        function keys(): void {
            input.toggle();
        }
    }

    // ---- the pills: top left, just under sleepyshell's left island ----
    PanelWindow {
        visible: recorder.recording || input.on
        color: "transparent"
        anchors.top: true
        anchors.left: true
        // the bar's islands are 46 px tall; 6 px gap below them
        margins.top: 52
        margins.left: 12
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: pills.implicitWidth
        implicitHeight: pills.implicitHeight
        WlrLayershell.namespace: "showoff-pills"
        WlrLayershell.layer: WlrLayer.Overlay

        Row {
            id: pills
            spacing: 8

            Pill {
                visible: recorder.recording
                label: "REC  " + shellRoot.clock(recorder.elapsed)
                pulse: true
                bg: shellRoot.urgent
                fg: shellRoot.urgentFg
                onClicked: recorder.stop()
            }
            Pill {
                visible: input.on
                label: "KEYS"
                bg: shellRoot.panel
                fg: shellRoot.fg
                onClicked: input.on = false
            }
        }
    }

    component Pill: Rectangle {
        id: pill
        property string label: ""
        property bool pulse: false
        property color bg
        property color fg
        signal clicked
        width: pillRow.implicitWidth + 24
        height: 30
        radius: height / 2
        color: pill.bg

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 8

            // a pulsing dot on the recording pill: it is live
            Rectangle {
                visible: pill.pulse
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                color: pill.fg
                SequentialAnimation on opacity {
                    running: pill.pulse && pill.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 600 }
                    NumberAnimation { to: 1; duration: 600 }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                color: pill.fg
                font.pixelSize: 14
                font.bold: true
            }
        }

        // a click stops that tool, as its keybind again does
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }

    // m:ss, and h:mm:ss from an hour on
    function clock(s) {
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60;
        const two = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + two(m) + ":" + two(sec) : m + ":" + two(sec);
    }
}
