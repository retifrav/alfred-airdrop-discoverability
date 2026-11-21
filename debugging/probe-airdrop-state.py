"""Prints what each source tried so far says about the AirDrop, Bluetooth and Wi-Fi state, and how long it takes.

That is how the Script Filter's source of the current discoverability level was chosen, see
.claude/notes/airdrop-state.md. It changes no settings and clicks nothing.

Device addresses and names are left out, except in the dump of the whole com.apple.sharingd domain at the end
(there to find keys that change between states), which holds account and device identifiers. So write the
output to an ignored location such as _stuff/ and never commit it.

Usage, on the Mac from the repository root, once per state that is to be compared:

    mkdir -p ./_stuff
    python3 ./debugging/probe-airdrop-state.py > ./_stuff/probe-bt-off.txt
"""

import json
import re
import subprocess
import time


def run(args):
    start = time.monotonic()
    try:
        result = subprocess.run(
            args, check=False, capture_output=True, text=True, timeout=60
        )
        out, code, err = result.stdout, result.returncode, result.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as ex:
        out, code, err = "", None, str(ex)
    return out, code, err, (time.monotonic() - start) * 1000


def report(lines, title, args, extract):
    out, code, err, ms = run(args)
    try:
        value = extract(out) if code == 0 else None
    except Exception as ex:  # noqa: BLE001 - a probe reports whatever went wrong instead of stopping
        value = f"extraction failed: {ex!r}"
    lines.append(f"## {title}")
    lines.append(f"command: {' '.join(args)}")
    lines.append(f"exit code: {code}, {ms:.0f} ms")
    if err:
        lines.append(f"stderr: {err[:300]}")
    lines.append(f"value: {value}")
    lines.append("")
    return out if code == 0 else None


def bluetoothControllerFields(out):
    # only the controller's state-like fields, never its address or the paired devices
    found = {}

    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k.startswith("controller_") and any(
                    w in k for w in ("state", "power", "discoverable")
                ):
                    found[k] = v
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(json.loads(out))
    return found


def ioregBluetoothPowerKeys(out):
    # keys mentioning both Bluetooth and power, with their values cut short
    pattern = re.compile(
        r'"([^"]*(?:bluetooth|BT)[^"]*power[^"]*|[^"]*power[^"]*(?:bluetooth|BT)[^"]*)" = (.*)',
        re.IGNORECASE,
    )
    found = {}
    for line in out.splitlines():
        match = pattern.search(line)
        if match:
            found.setdefault(match.group(1), set()).add(match.group(2)[:80])
    return {k: sorted(v) for k, v in found.items()}


def wifiDevice(out):
    match = re.search(r"Hardware Port: Wi-Fi\s*\nDevice: (\S+)", out)
    return match.group(1) if match else None


def main():
    lines = [f"# AirDrop state probe, {time.strftime('%Y-%m-%d %H:%M:%S')}", ""]
    report(
        lines,
        "AirDrop level (sharingd)",
        ["defaults", "read", "com.apple.sharingd", "DiscoverableMode"],
        str.strip,
    )
    report(
        lines,
        "Bluetooth power (preferences)",
        [
            "defaults",
            "read",
            "/Library/Preferences/com.apple.Bluetooth",
            "ControllerPowerState",
        ],
        str.strip,
    )
    report(
        lines,
        "Bluetooth controller (system_profiler)",
        ["system_profiler", "SPBluetoothDataType", "-json"],
        bluetoothControllerFields,
    )
    report(
        lines,
        "Bluetooth power keys (ioreg)",
        ["ioreg", "-l", "-w0"],
        ioregBluetoothPowerKeys,
    )
    ports = report(
        lines,
        "Wi-Fi device (networksetup)",
        ["networksetup", "-listallhardwareports"],
        wifiDevice,
    )
    device = wifiDevice(ports) if ports else None
    if device:
        report(
            lines,
            "Wi-Fi power (networksetup)",
            ["networksetup", "-getairportpower", device],
            str.strip,
        )
    sharingd = report(
        lines,
        "whole sharingd domain (dump below)",
        ["defaults", "read", "com.apple.sharingd"],
        lambda out: f"{len(out.splitlines())} lines",
    )
    lines.append("## com.apple.sharingd")
    lines.append(sharingd or "")

    print("\n".join(lines))


if __name__ == "__main__":
    main()
