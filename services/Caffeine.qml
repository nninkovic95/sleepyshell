pragma Singleton
import Quickshell

// "Keep awake" state; the IdleInhibitor that enforces it lives in Sleepybar.qml (it needs a window).
// Kept over a hot reload (review 4): as a plain property it reset to false on every QML save,
// which dropped the inhibitor with no sign on the bar.
Singleton {
    property alias on: persist.on

    PersistentProperties {
        id: persist
        reloadableId: "caffeine"
        property bool on: false
    }
}
