import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs
import qs.components
import qs.services
import qs.sleepybar.components

// Wi-Fi networks of the default adapter. Scans while `scanning` is true (bind it to the popup's visibility).
// Clicking an unknown PSK network opens a password row under it (`pending`). The window hosting the
// list must hold keyboard focus while `typing` is true (IslandDropdown / GrowingIsland `wantsKeyboard`).
ColumnLayout {
    id: root
    property bool scanning: false
    property var pending: null       // the WifiNetwork whose password is being typed
    property string error: ""
    readonly property bool typing: pending !== null
    readonly property int maxRows: 8
    readonly property var shown: Net.wifiEnabled ? Net.networks.slice(0, maxRows) : []
    spacing: 2

    onScanningChanged: {
        Net.setScanning(scanning);
        // closing the popup (or leaving this list) drops a half-typed password
        if (!scanning)
            pending = null;
    }
    Component.onCompleted: Net.setScanning(scanning)
    onPendingChanged: error = ""
    // a scan can drop the network, or the sort can push it below the visible rows
    onShownChanged: {
        if (pending !== null && shown.indexOf(pending) < 0)
            pending = null;
    }

    function activate(n) {
        if (pending === n)
            pending = null;
        else if (Net.needsPassword(n))
            pending = n;
        else {
            pending = null;
            Net.join(n);
        }
    }

    function submit(psk) {
        if (pending === null)
            return;
        error = "";
        pending.connectWithPsk(psk);
    }

    // NoSecrets is what NetworkManager reports when the supplied key is rejected; the other
    // ConnectionFailReason values (supplicant failure, timeout, network lost) are not password errors
    Connections {
        target: root.pending
        function onConnectedChanged() {
            if (root.pending !== null && root.pending.connected)
                root.pending = null;
        }
        function onConnectionFailed(reason) {
            root.error = reason === ConnectionFailReason.NoSecrets ? "Wrong password" : "Could not connect";
        }
    }

    Text {
        visible: !Net.wifi || !Net.wifiEnabled || Net.networks.length === 0
        Layout.margins: 8
        text: !Net.wifi ? "No Wi-Fi adapter" : !Net.wifiEnabled ? "Wi-Fi is off" : "Scanning…"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fgMuted
    }

    Repeater {
        // ScriptModel diffs by object, so a re-sorted list moves rows instead of rebuilding them
        // all (a plain JS array made every signal tick recreate the rows under the pointer)
        model: ScriptModel {
            values: root.shown
        }

        ColumnLayout {
            id: row
            required property var modelData
            // why the last connect of this network failed, in the sub line until the next attempt.
            // Failures were only shown for the password row, so a saved network with a stale
            // password (NoSecrets) failed with no sign at all (review 3, F10).
            property string failure: ""
            Layout.fillWidth: true
            spacing: 2

            Connections {
                target: row.modelData
                function onConnectionFailed(reason) {
                    if (root.pending === row.modelData)
                        return;
                    row.failure = reason === ConnectionFailReason.NoSecrets && row.modelData.known ? "Saved password rejected, right-click to forget" : "Could not connect";
                }
                function onStateChangingChanged() {
                    if (row.modelData.stateChanging)
                        row.failure = "";
                }
            }

            DeviceRow {
                icon: Net.strengthGlyph(modelData.signalStrength)
                title: modelData.name
                sub: row.failure !== "" ? row.failure : (modelData.connected ? "Connected" : modelData.known ? "Saved" : "") + (Net.secured(modelData) ? (modelData.connected || modelData.known ? "  " : "") + String.fromCodePoint(0xF033E) : "")
                active: modelData.connected
                busy: modelData.stateChanging
                onClicked: root.activate(modelData)
                onSecondary: {
                    if (modelData.known)
                        modelData.forget();
                }
            }

            WifiPassword {
                Layout.fillWidth: true
                open: root.pending === modelData
                name: modelData.name
                error: root.error
                busy: modelData.stateChanging
                onSubmitted: psk => root.submit(psk)
                onCancelled: root.pending = null
            }
        }
    }

    Text {
        visible: Net.wifiEnabled && Net.networks.length > root.maxRows
        Layout.margins: 8
        text: "+" + (Net.networks.length - root.maxRows) + " more"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fgMuted
    }
}
