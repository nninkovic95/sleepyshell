pragma Singleton

import QtQuick
import Quickshell

// Whether a screen recording runs, for the right island's indicator. The recorder is its own process and says so over
// the shell's IPC (`qs -c sleepyshell ipc call sleepybar recording true|false`, shell.qml); kept across a hot reload,
// so the indicator does not vanish while the recording goes on.
Singleton {
    property alias on: persist.on

    PersistentProperties {
        id: persist
        reloadableId: "recording"
        property bool on: false
    }
}
