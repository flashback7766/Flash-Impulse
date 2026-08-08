#!/usr/bin/env python3
"""
What each connected display actually claims it can do, read from its EDID.

The compositor is no help here: `hyprctl monitors -j` reports what a monitor is
currently *doing* and nothing about what it is *capable* of — no VRR flag, no
supported bit depths, no HDR. So the settings page had to offer every option to
every screen and let the user find out by trying.

Everything below is a positive claim from the display or nothing at all. There
is deliberately no inference: a monitor that does not publish the AMD FreeSync
block is reported as "did not say", not as "no VRR", because plenty of working
setups are missing blocks they ought to have. The caller marks those rather than
hiding them, so a display that under-reports never costs the user a feature that
would have worked.

Prints JSON on stdout, keyed by connector name:

  {"HDMI-A-1": {"bitDepth": 8|null, "hdr": true|false|null,
                "vrr": true|null, "vrrMin": 48, "vrrMax": 144}}

null means the display did not say. Always exits 0 with a parseable object; the
page treats a missing entry the same as an all-null one.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys


def parse(text):
    caps = {"bitDepth": None, "hdr": None, "vrr": None, "vrrMin": None, "vrrMax": None}

    m = re.search(r"^\s*Bits per primary color channel:\s*(\d+)", text, re.M)
    if m:
        caps["bitDepth"] = int(m.group(1))

    # The AMD FreeSync vendor block is the one unambiguous statement of VRR
    # support in an EDID. Its range is what the panel will actually hold sync
    # across, which is worth showing next to the toggle.
    amd = re.search(r"Vendor-Specific Data Block \(AMD\), OUI 00-00-1A:(.*?)(?=\n\s*(?:Vendor-Specific|Checksum|[A-Z][a-z]+ Data Block))",
                    text, re.S)
    if amd:
        caps["vrr"] = True
        lo = re.search(r"Minimum Refresh Rate:\s*(\d+)", amd.group(1))
        hi = re.search(r"Maximum Refresh Rate:\s*(\d+)", amd.group(1))
        if lo:
            caps["vrrMin"] = int(lo.group(1))
        if hi:
            caps["vrrMax"] = int(hi.group(1))

    # A display that supports HDR says so in the CTA HDR Static Metadata block.
    if re.search(r"HDR Static Metadata Data Block", text) or re.search(r"Supported EOTF", text):
        caps["hdr"] = True

    return caps


def main():
    if not shutil.which("edid-decode"):
        print(json.dumps({}))
        return 0

    out = {}
    for path in sorted(glob.glob("/sys/class/drm/card*-*/edid")):
        conn_dir = os.path.basename(os.path.dirname(path))
        # "card1-HDMI-A-1" -> "HDMI-A-1", matching the names Hyprland uses.
        name = conn_dir.split("-", 1)[1] if "-" in conn_dir else conn_dir
        status_path = os.path.join(os.path.dirname(path), "status")
        try:
            with open(status_path) as fh:
                if fh.read().strip() != "connected":
                    continue
        except OSError:
            continue
        try:
            # Read rather than stat: sysfs binary attributes report a size of 0
            # whether or not they have contents, so getsize() rejects every
            # connector including the connected ones.
            with open(path, "rb") as fh:
                if not fh.read(128):
                    continue
            res = subprocess.run(["edid-decode", path], capture_output=True,
                                 text=True, timeout=10)
        except Exception:
            continue
        # edid-decode exits non-zero on EDIDs it considers non-conformant while
        # still printing everything useful, so its output is used regardless.
        if res.stdout:
            out[name] = parse(res.stdout)

    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
