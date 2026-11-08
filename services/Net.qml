pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Network state through Quickshell's NetworkManager backend; NetworkManager is asked directly only for the Wi-Fi
// link rate, and only while the network dropdown is open.
Singleton {
    id: root

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired) ?? null
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wiredUp: wired?.connected ?? false
    readonly property bool wifiUp: wifi?.connected ?? false
    readonly property bool online: wiredUp || wifiUp
    readonly property var active: wifi ? (wifi.networks.values.find(n => n.connected) ?? null) : null
    readonly property real strength: active?.signalStrength ?? 0

    // NetworkManager's own internet check, so the shell sends no requests of its own. Unknown (the
    // check is turned off in NetworkManager) counts as online: no warning without a real result.
    // None and Limited both mean a link without internet while a device is connected.
    readonly property bool portal: online && Networking.connectivity === NetworkConnectivity.Portal
    readonly property bool noInternet: online && (portal || Networking.connectivity === NetworkConnectivity.Limited || Networking.connectivity === NetworkConnectivity.None)

    readonly property string label: (wiredUp ? "Wired" : wifiUp ? (active?.name ?? "Wi-Fi") : !wifi ? "No Wi-Fi adapter" : wifiEnabled ? "Not connected" : "Wi-Fi off") + (portal ? " · Sign-in needed" : noInternet ? " · No internet" : "")

    // connected first, then saved, then by signal in three coarse bands (a raw strength sort
    // reordered the rows on every scan tick, under the pointer), then by name
    function band(s) {
        return s > 0.66 ? 2 : s > 0.33 ? 1 : 0;
    }
    readonly property var networks: wifi ? wifi.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (band(b.signalStrength) - band(a.signalStrength)) || a.name.localeCompare(b.name)) : []

    function strengthGlyph(s) {
        return s > 0.8 ? 0xF0928 : s > 0.55 ? 0xF0925 : s > 0.3 ? 0xF0922 : 0xF091F;
    }

    function glyph() {
        if (wiredUp)
            return noInternet ? 0xF0202 : 0xF0200;
        if (!wifi || !wifiEnabled)
            return 0xF092D;
        if (!wifiUp)
            return 0xF092F;
        // without internet, the same strength with a "!": each strength glyph's alert variant is the next codepoint
        return strengthGlyph(strength) + (noInternet ? 1 : 0);
    }

    function setWifi(on) {
        Networking.wifiEnabled = on;
    }

    function setScanning(on) {
        if (wifi)
            wifi.scannerEnabled = on;
    }

    function secured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }

    // An unknown PSK network needs a password first (WifiList shows the prompt and calls
    // connectWithPsk). Quickshell's connectWithPsk accepts only these three security types, so an
    // unknown EAP or WEP network cannot be joined from the bar at all: join() just tries connect().
    function needsPassword(n) {
        return !n.connected && !n.known && (n.security === WifiSecurityType.Wpa2Psk || n.security === WifiSecurityType.WpaPsk || n.security === WifiSecurityType.Sae);
    }

    // The most the connection can carry now, in Mbit/s (0 when unknown): a cable's negotiated speed, or the rate the
    // Wi-Fi card and the access point settled on for the current signal (it drops as the signal weakens). Wired wins,
    // as in `label`. Quickshell gives the speed only for wired devices, so the Wi-Fi rate is NetworkManager's own
    // (Device.Wireless.Bitrate, in Kbit/s), read only while something shows it: rateWatchers counts the viewers.
    property int rateWatchers: 0
    property real wifiRate: 0
    readonly property real linkRate: wiredUp ? (wired?.linkSpeed ?? 0) : wifiUp ? wifiRate : 0

    Process {
        id: rateProc
        command: ["sh", "-c", 'p=$(nmcli -g GENERAL.DBUS-PATH device show "$1") && gdbus call --system --dest org.freedesktop.NetworkManager --object-path "$p" --method org.freedesktop.DBus.Properties.Get org.freedesktop.NetworkManager.Device.Wireless Bitrate', "sh", root.wifi?.name ?? ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /uint32 (\d+)/.exec(text);
                root.wifiRate = m ? parseInt(m[1], 10) / 1000 : 0;
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.rateWatchers > 0 && root.wifiUp && !root.wiredUp
        onTriggered: {
            if (!rateProc.running)
                rateProc.running = true;
        }
    }

    // connected networks disconnect; saved or open ones connect directly (a network that
    // needsPassword is handled by WifiList before it gets here)
    function join(n) {
        if (n.connected)
            n.disconnect();
        else
            n.connect();
    }
}
