pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// Network state through Quickshell's NetworkManager backend (no nmcli polling).
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

    // Interface of the connection in use, for the speed readout (wired wins, as in `label`).
    // Empty when nothing is connected; NetSpeed then falls back to the first interface with traffic.
    readonly property string iface: (wiredUp ? wired : wifiUp ? wifi : null)?.name ?? ""

    // connected networks disconnect; saved or open ones connect directly (a network that
    // needsPassword is handled by WifiList before it gets here)
    function join(n) {
        if (n.connected)
            n.disconnect();
        else
            n.connect();
    }
}
