import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs
import qs.components

// In-window file and folder chooser for the settings window (the wallpaper folder on the Theme tab, the Select… buttons of
// the Config tab). Not Qt's FolderDialog and FileDialog: with no Qt platform theme set for the shell they fall back to Qt's own
// unthemed dialogs, and the GTK ones through the portal would need the shell's whole Qt environment changed,
// so every Select… uses this one. Fill the window with it.
// open(path, fn): folder mode (as before), fn(chosen folder) on "Use this folder".
// openFile(path, fn, { title, filters: ["*.lua"] }): file mode, files and folders are listed, `filters` hide the other
// files (folders always stay), a click on a folder goes into it, a click on a file selects it, a double click or Enter picks it.
// Both: the path bar is editable (Enter goes there), Home and up buttons, a "Show hidden" switch (off: dot files and folders
// are left out), Escape (the window's shortcut) or a click outside cancels.
// A "New folder" button next to Up and Home opens a name field at the top of the
// list (Enter creates it with `mkdir -p -- <folder>/<name>` and goes into it, Escape cancels; a name that is empty, has a "/" or is "."
// or ".." is refused with a line that says so). In file mode a writable target (the file may not exist yet: the idle, monitors and custom
// keybinds files) passes `newFile: true` and `fileName`: a "File name" field at the bottom, filled with the default name, and Select
// takes an existing file or a new name in the folder shown. A read-only target (colors.json, extra keybind files) keeps "existing files
// only". For a writable target a "New file" button beside "New folder" opens the same inline
// name field for a file (Enter creates it at once, empty, with `touch -- <folder>/<name>`, and selects it; a name that is empty, has a
// slash or is a folder is refused with a line that says so), and Select with a new name creates the file right away too, so the Config
// tab does not say "Not found" afterwards.
Item {
    id: fb
    property string path: Quickshell.env("HOME")
    property var onChosen: null
    // "folder" or "file"
    property string mode: "folder"
    property string title: "Wallpaper folder"
    property var filters: []
    property bool showHidden: false
    // the window's Tooltip (the New folder button's tip)
    property var tip: null
    // the file chosen in file mode ("" for none)
    property string selected: ""
    // file mode for a file that may not exist yet: the name field, filled with `fileName` to start with
    property bool newFile: false
    // the name field at the top of the list is open ("folder", "file", or "" for closed), and why the last name or mkdir was refused
    property string createKind: ""
    readonly property bool creating: fb.createKind !== ""
    property string createError: ""
    // the name of the file the browser would pick in the folder shown (the field, or the selected file)
    readonly property string pickName: fb.newFile ? nameBox.text.trim() : ""
    // the name is a file already in the folder shown (or a folder: -1), else 0
    function kindOfName(n) {
        const l = fb.names();
        return l.includes(n) ? 1 : l.includes(n + "/") ? -1 : 0;
    }
    function validName(n) {
        return n !== "" && n !== "." && n !== ".." && !n.includes("/") && !n.includes("\0");
    }
    readonly property bool canPick: fb.mode !== "file" || (fb.newFile ? fb.validName(fb.pickName) : fb.selected !== "")
    // what the list shows now: file names (folders first), for the tests
    function names() {
        const out = [];
        for (let i = 0; i < listModel.count; i++)
            out.push(listModel.get(i, "fileName") + (listModel.get(i, "fileIsDir") ? "/" : ""));
        return out;
    }
    visible: false
    z: 30

    function open(start, fn) {
        fb.show("folder", start, fn, { title: "Wallpaper folder" });
    }

    function openFile(start, fn, opts) {
        fb.show("file", start, fn, opts ?? {});
    }

    function show(mode, start, fn, opts) {
        fb.mode = mode;
        fb.title = opts.title ?? (mode === "file" ? "Choose a file" : "Choose a folder");
        fb.filters = opts.filters ?? [];
        fb.selected = "";
        fb.newFile = mode === "file" && opts.newFile === true;
        nameBox.text = fb.newFile ? (opts.fileName ?? "") : "";
        fb.cancelCreate();
        fb.path = start !== "" ? start : Quickshell.env("HOME");
        fb.onChosen = fn;
        fb.visible = true;
    }

    function close() {
        fb.visible = false;
        fb.onChosen = null;
        fb.cancelCreate();
        pathBox.input.focus = false;
    }

    // Escape (the window's shortcut): the open name field first, then the browser
    function cancelOrClose() {
        if (fb.creating)
            fb.cancelCreate();
        else
            fb.close();
    }

    // ---- a new folder, a new file ----
    function startCreate(kind) {
        fb.createError = "";
        fb.createKind = kind === "file" && fb.newFile ? "file" : "folder";
        folderBox.text = "";
        folderBox.input.forceActiveFocus();
    }

    function cancelCreate() {
        fb.createKind = "";
        fb.createError = "";
        folderBox.text = "";
        folderBox.input.focus = false;
    }

    // Enter in the name field
    function createEntry() {
        return fb.createKind === "file" ? fb.createFile(folderBox.text.trim(), "select") : fb.createFolder();
    }

    // make the file `n` in the folder shown, then "select" it in the list or go on to "pick" it. A file that is there is left alone.
    function createFile(n, then) {
        if (n === "") {
            fb.createError = "Type a name for the file.";
            return false;
        }
        if (!fb.validName(n)) {
            fb.createError = n.includes("/") ? "A file name cannot contain a slash." : "\"" + n + "\" is not a usable file name.";
            return false;
        }
        if (fb.kindOfName(n) < 0) {
            fb.createError = "\"" + n + "\" is a folder here.";
            return false;
        }
        fb.createError = "";
        mkf.target = (fb.path === "/" ? "" : fb.path) + "/" + n;
        mkf.then = then;
        mkf.command = ["touch", "--", mkf.target];
        mkf.running = true;
        return true;
    }

    Process {
        id: mkf
        property string target: ""
        property string then: "select"
        onExited: code => {
            if (code !== 0) {
                fb.createError = "Could not create the file here (is the folder writable?).";
                return;
            }
            const full = mkf.target;
            fb.cancelCreate();
            fb.selected = full;
            nameBox.text = full.slice(full.lastIndexOf("/") + 1);
            if (mkf.then === "pick")
                fb.finish(full);
        }
    }

    function createFolder() {
        const n = folderBox.text.trim();
        if (n === "") {
            fb.createError = "Type a name for the folder.";
            return false;
        }
        if (!fb.validName(n)) {
            fb.createError = n.includes("/") ? "A folder name cannot contain a slash." : "\"" + n + "\" is not a usable folder name.";
            return false;
        }
        fb.createError = "";
        if (fb.kindOfName(n) > 0) {
            fb.createError = "\"" + n + "\" is a file here.";
            return false;
        }
        mk.target = (fb.path === "/" ? "" : fb.path) + "/" + n;
        mk.command = ["mkdir", "-p", "--", mk.target];
        mk.running = true;
        return true;
    }

    Process {
        id: mk
        property string target: ""
        onExited: code => {
            if (code === 0) {
                fb.cancelCreate();
                fb.go(mk.target);
            } else {
                fb.createError = "Could not create the folder here (is it writable?).";
            }
        }
    }

    function up() {
        if (fb.path === "/")
            return;
        const i = fb.path.lastIndexOf("/");
        fb.go(i <= 0 ? "/" : fb.path.slice(0, i));
    }

    function go(p) {
        fb.path = p;
        fb.selected = "";
    }

    // pick what is chosen: the selected file (file mode), or the folder shown (folder mode); false when nothing can be picked
    function pick() {
        if (!fb.canPick)
            return false;
        // a new name: the file is made now, and chosen once it is there (a failure stays in the browser and says why)
        if (fb.mode === "file" && fb.newFile && fb.kindOfName(fb.pickName) <= 0)
            return fb.kindOfName(fb.pickName) < 0 ? false : fb.createFile(fb.pickName, "pick");
        fb.finish(fb.mode === "file" ? (fb.newFile ? (fb.path === "/" ? "" : fb.path) + "/" + fb.pickName : fb.selected) : fb.path);
        return true;
    }

    function finish(chosen) {
        const fn = fb.onChosen;
        fb.close();
        if (fn)
            fn(chosen);
    }

    // Enter picks, unless the path bar has the focus (it goes to the typed folder instead)
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: fb.visible && !pathBox.input.activeFocus
        onActivated: fb.pick()
    }

    // dims the window and closes on a click outside the card
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.surface, 0.7)

        MouseArea {
            anchors.fill: parent
            onClicked: fb.close()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(560, fb.width - 40)
        height: Math.min(500, fb.height - 40)
        radius: Theme.radiusXl
        color: Theme.containerHigh
        border.width: 1
        border.color: Theme.trackBg

        // swallow clicks on the card itself
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            Text {
                objectName: "browserTitle"
                text: fb.title
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 1
                font.weight: Font.Medium
                color: Theme.fg
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                BarButton {
                    objectName: "browserUp"
                    glyph: 0xF005D
                    glued: false
                    hpad: 6
                    bg: Theme.tileBg
                    opacity: fb.path === "/" ? 0.4 : 1
                    onClicked: fb.up()
                }

                BarButton {
                    objectName: "browserHome"
                    glyph: 0xF02DC
                    glued: false
                    hpad: 6
                    bg: Theme.tileBg
                    onClicked: fb.go(Quickshell.env("HOME"))
                }

                BarButton {
                    id: newFolderBtn
                    objectName: "browserNewFolder"
                    glyph: 0xF0257
                    glued: false
                    hpad: 6
                    bg: fb.createKind === "folder" ? Theme.hoverBg : Theme.tileBg
                    onClicked: fb.createKind === "folder" ? fb.cancelCreate() : fb.startCreate("folder")
                    onHoveredChanged: {
                        if (!fb.tip)
                            return;
                        if (hovered)
                            fb.tip.show(newFolderBtn, "New folder here", false);
                        else
                            fb.tip.hide(newFolderBtn);
                    }
                }

                // a new file, for a target that may not exist yet
                BarButton {
                    id: newFileBtn
                    objectName: "browserNewFile"
                    visible: fb.newFile
                    glyph: 0xF0752
                    glued: false
                    hpad: 6
                    bg: fb.createKind === "file" ? Theme.hoverBg : Theme.tileBg
                    onClicked: fb.createKind === "file" ? fb.cancelCreate() : fb.startCreate("file")
                    onHoveredChanged: {
                        if (!fb.tip)
                            return;
                        if (hovered)
                            fb.tip.show(newFileBtn, "New file here", false);
                        else
                            fb.tip.hide(newFileBtn);
                    }
                }

                // the path: type a folder and press Enter to go there
                TextBox {
                    id: pathBox
                    objectName: "browserPath"
                    placeholder: "Folder"
                    onAccepted: {
                        const t = pathBox.text.trim().replace(/^~(?=\/|$)/, Quickshell.env("HOME")).replace(/(.)\/+$/, "$1");
                        if (t !== "")
                            fb.go(t);
                        pathBox.input.focus = false;
                    }
                }

                // follows the folder shown, unless it is being typed in
                Binding {
                    target: pathBox
                    property: "text"
                    value: fb.path.replace(Quickshell.env("HOME"), "~")
                    when: !pathBox.input.activeFocus
                    restoreMode: Binding.RestoreNone
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusMd
                color: Theme.tileBg

                // the new folder's name, at the top of the list: Enter creates, Escape cancels
                Item {
                    id: newRow
                    visible: fb.creating
                    x: 4
                    y: 4
                    width: parent.width - 8
                    height: fb.creating ? (fb.createError !== "" ? 54 : 34) : 0

                    TextBox {
                        id: folderBox
                        objectName: "browserFolderName"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 30
                        placeholder: fb.createKind === "file" ? "New file name" : "New folder name"
                        onAccepted: fb.createEntry()
                        onEscaped: fb.cancelCreate()
                    }

                    Text {
                        objectName: "browserFolderError"
                        visible: fb.createError !== ""
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 4
                        y: 32
                        elide: Text.ElideRight
                        text: fb.createError
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                        color: Theme.urgentFg
                    }
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.margins: 4
                    anchors.topMargin: 4 + newRow.height
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: FolderListModel {
                        id: listModel
                        folder: "file://" + fb.path
                        showFiles: fb.mode === "file"
                        showDirs: true
                        showDirsFirst: true
                        showDotAndDotDot: false
                        showHidden: fb.showHidden
                        caseSensitive: false
                        nameFilters: fb.filters.length > 0 ? fb.filters : ["*"]
                        sortField: FolderListModel.Name
                    }

                    delegate: MenuItem {
                        required property string fileName
                        required property string filePath
                        required property bool fileIsDir
                        width: ListView.view.width
                        icon: fileIsDir ? 0xF024B : 0xF0214
                        label: fileName
                        selected: !fileIsDir && fb.selected === filePath
                        onClicked: {
                            if (fileIsDir) {
                                fb.go(filePath);
                            } else {
                                fb.selected = filePath;
                                // a chosen file's name goes into the name field, which is what Select takes
                                if (fb.newFile)
                                    nameBox.text = fileName;
                            }
                        }
                        onDoubleClicked: {
                            if (!fileIsDir) {
                                fb.selected = filePath;
                                if (fb.newFile)
                                    nameBox.text = fileName;
                                fb.pick();
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: fb.mode === "file" ? "No files or folders here" : "No folders here"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.fgMuted
                }
            }

            // a file that may not exist yet (a writable target): its name, taken from here or typed
            RowLayout {
                Layout.fillWidth: true
                visible: fb.newFile
                spacing: 8

                Text {
                    text: "File name"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.fgMuted
                }

                TextBox {
                    id: nameBox
                    objectName: "browserFileName"
                    placeholder: "File name"
                    onAccepted: fb.pick()
                }
            }

            Text {
                objectName: "browserNameHint"
                Layout.fillWidth: true
                visible: fb.newFile && text !== ""
                wrapMode: Text.WordWrap
                text: fb.pickName === "" ? "Type a file name, or click a file." : !fb.validName(fb.pickName) ? "A file name has no slash and is not . or .." : fb.kindOfName(fb.pickName) < 0 ? "That name is a folder here." : fb.createError !== "" ? fb.createError : ""
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
                color: fb.pickName !== "" && !fb.validName(fb.pickName) ? Theme.urgentFg : Theme.fgMuted
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Toggle {
                    objectName: "browserHidden"
                    checked: fb.showHidden
                    onClicked: fb.showHidden = !fb.showHidden
                }

                Text {
                    text: "Show hidden"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.fgMuted
                }

                Text {
                    objectName: "browserFilter"
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    visible: fb.mode === "file" && fb.filters.length > 0
                    text: "Files: " + fb.filters.join(", ")
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.fgMuted
                }

                Item {
                    Layout.fillWidth: !(fb.mode === "file" && fb.filters.length > 0)
                }

                BarButton {
                    objectName: "browserCancel"
                    text: "Cancel"
                    glued: false
                    onClicked: fb.close()
                }

                BarButton {
                    objectName: "browserPick"
                    text: fb.mode === "file" ? "Select" : "Use this folder"
                    glued: false
                    bg: Theme.accent
                    fg: Theme.accentFg
                    enabled: fb.canPick
                    opacity: enabled ? 1 : 0.4
                    onClicked: fb.pick()
                }
            }
        }
    }
}
