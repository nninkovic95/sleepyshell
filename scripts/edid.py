#!/usr/bin/env python3
"""Reads what a monitor's EDID says about HDR, for the Display tab. Read only, standard library only.

  edid.py hdr [--root DIR] [OUTPUT...]    one JSON object: { "<output>": { "hdr": bool, "pq": bool, "hlg": bool, "maxNits": number|null } }
                                          for each named output (all connectors found when none is named)

The EDID is /sys/class/drm/card*-<OUTPUT>/edid (DIR replaces /sys/class/drm; the test kit points it at fixtures). HDR is advertised by the
CTA-861 extension block (tag 0x02): its data block collection holds, as an extended block (tag 7) with extended tag 6, the "HDR static
metadata data block": its first payload byte lists the supported EOTFs, bit 0 traditional SDR gamma, bit 1 traditional HDR gamma, bit 2 SMPTE
ST 2084 (PQ, what HDR10 uses), bit 3 hybrid log-gamma (CTA-861-G, section 7.5.13). `hdr` is true when the PQ bit is set. An output whose file
cannot be read, is shorter than one block or does not start with the EDID header is reported as { "hdr": false, "error": "..." }.
"""
import glob
import json
import os
import re
import sys

HEADER = bytes([0, 255, 255, 255, 255, 255, 255, 0])


def parse(data):
    """{hdr, pq, hlg, maxNits} of one EDID (bytes); raises ValueError when it is not one."""
    if len(data) < 128 or data[:8] != HEADER:
        raise ValueError("not an EDID")
    res = {"hdr": False, "pq": False, "hlg": False, "maxNits": None}
    n_ext = data[126]
    for b in range(1, n_ext + 1):
        blk = data[128 * b:128 * (b + 1)]
        if len(blk) < 128 or blk[0] != 0x02:  # CTA-861 extension
            continue
        end = blk[2]  # where the detailed timings start: the data blocks lie in 4..end
        i = 4
        while i < min(end, 127):
            tag, length = blk[i] >> 5, blk[i] & 0x1F
            body = blk[i + 1:i + 1 + length]
            if tag == 7 and length >= 3 and body[0] == 6:  # extended tag 6: HDR static metadata
                eotf = body[1]
                res["pq"] = bool(eotf & 0b100)
                res["hlg"] = bool(eotf & 0b1000)
                if length >= 4 and body[3] > 0:
                    # body: [extended tag 6, EOTFs, static metadata types, desired content max luminance, max frame-average, min]
                    # max luminance: 50 * 2^(code / 32) cd/m2
                    res["maxNits"] = round(50 * 2 ** (body[3] / 32))
            i += 1 + length
    res["hdr"] = res["pq"]
    return res


def find(root, output):
    return sorted(glob.glob(os.path.join(root, "card*-" + output, "edid")))


def main(argv):
    if not argv or argv[0] != "hdr":
        print(__doc__.strip(), file=sys.stderr)
        return 2
    args = argv[1:]
    root = os.environ.get("EDID_ROOT") or "/sys/class/drm"
    if "--root" in args:
        i = args.index("--root")
        root = args[i + 1]
        args = args[:i] + args[i + 2:]
    names = [a for a in args if re.fullmatch(r"[A-Za-z0-9._-]+", a)]
    if not names:
        names = sorted({re.sub(r"^card\d+-", "", os.path.basename(os.path.dirname(p))) for p in glob.glob(os.path.join(root, "card*-*", "edid"))})
    out = {}
    for name in names:
        files = find(root, name)
        if not files:
            out[name] = {"hdr": False, "error": "no EDID file"}
            continue
        try:
            with open(files[0], "rb") as f:
                out[name] = parse(f.read(128 * 8))
        except (OSError, ValueError) as e:
            out[name] = {"hdr": False, "error": str(e)}
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
