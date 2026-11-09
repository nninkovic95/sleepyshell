"""Cosmetic smoke (the network list's rate is wrong, or jumps with the traffic): the dropdown shows the most the connected
Wi-Fi network can carry at its signal, worked out from NetworkManager's scan list
(`nmcli -t -f IN-USE,FREQ,BANDWIDTH,RATE,SIGNAL device wifi list`), not the card's rate of the moment. The sandbox has
no NetworkManager, so the service's own functions are given scan lines:
  - only the connected network counts;
  - a strong 20 MHz 2.4 GHz network gets its full rate, a 5 GHz one at -75 dBm on 80 MHz a middle step (a real card
    hears about 10 dB better than the standard's worst case), one below every step none."""
import sys
from ui import Shell, check, done

s = Shell.launch(sys.argv[1], "shell.qml", name="bar")
scan = " :2437 MHz:20 MHz:65 Mbit/s:90\\n*:2462 MHz:20 MHz:130 Mbit/s:60\\n :5220 MHz:80 MHz:1170 Mbit/s:80"
full = s.js(f"(Math.round(Net.connectedRate('{scan}')))")
check(full == 130, "the connected 2.4 GHz network at -60 dBm gets its full 130 Mbit/s, the others are ignored", f"{full}")
low = s.js("(Math.round(Net.connectedRate('*:5220 MHz:80 MHz:1170 Mbit/s:45')))")
check(low == 281, "a 5 GHz network at -75 dBm on 80 MHz gets MCS 3 (281 of 1170 Mbit/s), not the bare table's lowest step", f"{low}")
none = s.js("(Net.connectedRate('*:5220 MHz:80 MHz:1170 Mbit/s:30'))")
check(none == 0, "below every step the rate is unknown, and the row hides", f"{none}")
errs = [e for e in s.errors() if not any(x in e for x in ("pipewire", "quickshell.network", "Network will not work"))]
check(not errs, "no QML errors", "; ".join(errs[:3]))
done()
