import QtQuick
import qs.services
import qs.sleepybar.components

// A screen recording runs (services/Recording.qml): shown only then. Information only; the recorder is started and
// stopped by its own shortcut.
BarIndicator {
    objectName: "recordingIndicator"
    shown: Recording.on
    cp: 0xF044A
}
