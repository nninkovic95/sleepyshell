import QtQuick
import qs.services
import qs.sleepybar.components

// Caps Lock on the right island: shown only while it is on (services/CapsLock.qml watches the LED). Information only;
// the OSD flashes the change itself (OsdState).
BarIndicator {
    shown: CapsLock.on
    cp: 0xF0632  // the Caps Lock symbol (an arrow over a bar)
    // it fills more of its box than the other icons: at 5/6 it is drawn as tall as they are (14 px at the default size)
    glyphScale: 5 / 6
}
