import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services

// Month calendar with khal's events. A normal floating toplevel window (xdg toplevel, class
// org.quickshell, title "Calendar"), like the settings window, so Hyprland's own window rules draw its
// border, rounding, shadow, blur and open / close animation and place it (the rule in windowrules.lua matches
// class and title). The window only paints the panel fill and keeps an inner padding (CalendarView's); the
// size it opens at is the view's default size for the focused monitor. Popouts bookkeeping with no bar
// (`bar: null`: Popouts.toggle falls back to this one instance).
// Closes on Escape, when the window loses focus (after a short grace), and when ikhal is launched.
// Opened by the control centre's Calendar tile, `sleepyshell:toggle:calendar` and
// `qs -c sleepyshell ipc call sleepybar toggle calendar`. The content, keys and look are in CalendarView.qml,
// the data in the Calendar service.
Scope {
    id: root
    property string name: "calendar"
    property bool open: false
    readonly property var bar: null     // no anchor bar; Popouts.toggle falls back to this one

    // the window has been the active one since it opened: only then does losing focus close it
    property bool focusSeen: false

    Component.onCompleted: Popouts.register(name, root)
    Component.onDestruction: Popouts.unregister(name, root)

    onOpenChanged: {
        if (open) {
            const mon = Hyprland.focusedMonitor;
            const scr = Quickshell.screens.find(s => mon && s.name === mon.name) ?? Quickshell.screens[0];
            view.screenW = scr.width;
            view.screenH = scr.height;
            root.focusSeen = false;
            Popouts.opened(root);
            Calendar.active = true;
            view.reset();
            raise.restart();
        } else {
            raise.stop();
            loseFocus.stop();
            Calendar.active = false;
            Popouts.closed(root);
        }
    }

    // both buttons: ikhal in the default terminal (DefaultApps).
    // The calendar closes first, on purpose, so the focus change to kitty is not what closes it.
    function launchKhal() {
        open = false;
        DefaultApps.runInTerminal(["ikhal"]);
    }

    // Hyprland focuses a new floating window by itself; this makes sure of it (and of the keyboard) once
    // the window is mapped
    Timer {
        id: raise
        interval: 120
        onTriggered: {
            if (!root.open)
                return;
            Hyprland.dispatch("hl.dsp.focus({ window = \"title:^(Calendar)$\" })");
            view.forceActiveFocus();
        }
    }

    // focus left the window: close after a short grace, unless it came back
    Timer {
        id: loseFocus
        interval: 150
        onTriggered: if (root.open && !win.contentItem.Window.active)
            root.open = false
    }

    FloatingWindow {
        id: win
        // the Hyprland float rule matches this title
        title: "Calendar"
        visible: root.open
        color: Theme.container
        implicitWidth: view.defaultW
        implicitHeight: view.defaultH
        minimumSize: Qt.size(view.minW, view.minH)

        onVisibleChanged: {
            if (visible)
                view.forceActiveFocus();
            else
                root.open = false;     // closed from outside (compositor kill)
        }

        // whole pixels, so the text stays sharp; fills the window, so a resize re-lays it out
        CalendarView {
            id: view
            width: win.width
            height: win.height
            Window.onActiveChanged: {
                if (Window.active) {
                    root.focusSeen = true;
                    loseFocus.stop();
                } else if (root.open && root.focusSeen) {
                    loseFocus.restart();
                }
            }
            onCloseRequested: root.open = false
            onOpenKhal: root.launchKhal()
        }
    }
}
