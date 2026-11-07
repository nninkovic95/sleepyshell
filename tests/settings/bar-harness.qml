// Harness of tests/settings/*.sh, copied into the root of the tree under test: the bar's end of the settings socket
// (the tree's real services/SettingsServer.qml, which writes sleepysettings.toml for the window's commits) without
// the rest of the bar, run offscreen. Logs "SOCK <path>" once the socket's path is known; runs until stopped.
import QtQuick
import Quickshell
import qs.services

Scope {
    SettingsServer {}

    Timer {
        running: Settings.socketPath !== ""
        interval: 50
        onTriggered: console.log("SOCK " + Settings.socketPath)
    }
}
