import QtQuick
import qs.services
import qs.sleepybar.components

// The click circles are on (services/InputShow.qml): shown only then, so they are never on unnoticed. Information
// only; the circles are switched by their shortcut (Keybinds tab, Shell shortcuts).
BarIndicator {
    objectName: "clicksIndicator"
    shown: InputShow.clicksOn
    cp: 0xF0CFE  // an outlined pointer with click rays
}
