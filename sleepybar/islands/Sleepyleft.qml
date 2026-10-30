import QtQuick
import qs
import qs.components
import qs.sleepybar.widgets.workspaces
import qs.sleepybar.components

// The left island: the workspace dots, in the screen's top-left corner. It lives in the bar
// window (Sleepybar.qml places it and gives it input); shape, padding and motion come from the island
// block of Theme.qml like every island's. Kept to workspaces only: no window title.
SideIsland {
    id: sleepyleft
    // the Bar window of this screen (the id is not `bar`: see Sleepybar.qml)
    required property var bar

    attach: "topLeft"
    padding: Theme.leftIslandPad

    Workspaces {
        bar: sleepyleft.bar
    }
}
