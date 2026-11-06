import QtQuick
import qs.services
import qs.sleepybar.components

// The keybind overlay is on (services/InputShow.qml): shown only then, so it is never on unnoticed. Information only;
// the overlay is switched by its shortcut (Keybinds tab, Shell shortcuts).
BarIndicator {
    objectName: "keysIndicator"
    shown: InputShow.keysOn
    cp: 0xF0C09  // a K in an outlined box
}
