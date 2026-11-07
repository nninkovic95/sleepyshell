import QtQuick
import qs
import qs.services
import qs.sleepybar.components

// A screen recording runs (services/Recording.qml): shown only then. Information only; the recorder is started and
// stopped by its own shortcut.
BarIndicator {
    objectName: "recordingIndicator"
    shown: Recording.on
    cp: 0xF044A
    // red, larger than the other indicators and blinking, unlike the state indicators in the accent colour: a
    // recording must not go unnoticed
    tint: Theme.recording
    // about 1.3 times the bar icon, rounded to an even pixel size: an odd one put its centre half a pixel off the
    // line of the buttons beside it
    glyphScale: 2 * Math.round(Theme.barIconSize * 1.3 / 2) / Theme.barIconSize
    blink: true
}
