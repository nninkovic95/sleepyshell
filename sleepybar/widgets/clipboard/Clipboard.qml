import QtQuick
import Quickshell
import qs.components
import qs.services

// Clipboard history through walker, an optional app of the user's (walker and its elephant service are
// not part of the shell): the button is left off the right island while walker is not installed.
BarButton {
    inset: true
    glyph: 0xF014D
    readonly property bool shown: Deps.has("walker")
    onClicked: Quickshell.execDetached(["walker", "-m", "clipboard"])
}
