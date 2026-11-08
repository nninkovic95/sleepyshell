pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Network state through Quickshell's NetworkManager backend; NetworkManager's scan list is read directly only for
// the Wi-Fi link rate, and only while the network dropdown is open.
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

    // The most the connection can carry at its signal, in Mbit/s (0 when unknown): a cable's negotiated speed, or for
    // Wi-Fi the connected network's maximum scaled to its signal (estimate()). Not the card's own rate: that changes
    // per packet with the traffic (seen 144 and 43 Mbit/s at the same signal). Wired wins, as in `label`. Quickshell
    // has no width or maximum rate per network, so NetworkManager's scan list is read, only while something shows
    // the rate: rateWatchers counts the viewers.
    property int rateWatchers: 0
    property real wifiRate: 0
    readonly property real linkRate: wiredUp ? (wired?.linkSpeed ?? 0) : wifiUp ? wifiRate : 0

    // 802.11ax minimum receiver sensitivity per MCS at 20 MHz (dBm), each doubling of the channel width needing 3 dB
    // more, and each MCS's rate (one stream, 20 MHz) to scale a network's maximum by. The table is the standard's worst
    // case: a real card hears about cardMargin dB better (at -72 dBm on 80 MHz one ran MCS 4-5, 432-576 Mbit/s, where
    // the bare table allowed only MCS 0)
    readonly property int cardMargin: 10
    readonly property var mcsSens: [-82, -79, -77, -74, -70, -66, -65, -64, -59, -57, -54, -52]
    readonly property var mcsRate: [8.6, 17.2, 25.8, 34.4, 51.6, 68.8, 77.4, 86, 103.2, 114.7, 129, 143.4]

    // max: the network's maximum in Mbit/s, width: channel width in MHz, pct: NetworkManager's signal percentage
    function estimate(max, width, pct) {
        // NetworkManager maps -90..-20 dBm onto 30..100 %
        const dbm = pct - 120 + cardMargin;
        const doublings = Math.log2(Math.max(1, width / 20));
        // the network's top step from its maximum per 20 MHz (two streams): HT ends at MCS 7, VHT at 9, HE at 11
        const per20 = max / Math.pow(2, doublings);
        const top = per20 <= 150 ? 7 : per20 <= 200 ? 9 : 11;
        let step = -1;
        for (let k = 0; k <= top; k++) {
            if (dbm >= mcsSens[k] + 3 * doublings)
                step = k;
        }
        return step < 0 ? 0 : max * mcsRate[step] / mcsRate[top];
    }

    // text: `nmcli -t -f IN-USE,FREQ,BANDWIDTH,RATE,SIGNAL device wifi list`; the connected network's estimate
    function connectedRate(text) {
        for (const line of text.split("\n")) {
            const f = line.split(":");
            if (f.length >= 5 && f[0] === "*")
                return estimate(parseInt(f[3], 10), parseInt(f[2], 10) || 20, parseInt(f[4], 10));
        }
        return 0;
    }

    Process {
        id: rateProc
        command: ["nmcli", "-t", "-f", "IN-USE,FREQ,BANDWIDTH,RATE,SIGNAL", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            onStreamFinished: root.wifiRate = root.connectedRate(text)
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
