#!/usr/bin/env python3
"""Keep installation-specific MAC addresses for built-in Ethernet devices."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile


MAC = "/soc/ethernet@15100000"
PORTS = {f"mac{i}": f"{MAC}/mac@{i}" for i in range(3)}
PORTS.update({f"lan{i}": f"{MAC}/mdio-bus/switch@16/ports/port@{i}" for i in range(1, 5)})
PORTS["lan5"] = "/soc/switch@15020000/ports/port@0"
PORTS["lan6"] = f"{MAC}/mdio-bus/switch@16/ports/port@13"


def atomic_write(path: Path, text: str, mode: int) -> None:
    if path.is_file() and path.read_text() == text:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as out:
            os.fchmod(out.fileno(), mode)
            out.write(text)
            out.flush()
            os.fsync(out.fileno())
        os.replace(name, path)
        fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        Path(name).unlink(missing_ok=True)


def validate(state: dict) -> dict:
    if state.get("version") != 1 or set(state.get("addresses", {})) != set(PORTS):
        raise ValueError("Unexpected MAC state; preserve the file for recovery")
    addresses = state["addresses"]
    for value in addresses.values():
        if not isinstance(value, str) or not re.fullmatch(r"(?:[0-9a-f]{2}:){5}[0-9a-f]{2}", value):
            raise ValueError("Invalid stored MAC address")
        if int(value[:2], 16) & 3 != 2:
            raise ValueError("Stored MAC must be locally administered and unicast")
    if len(set(addresses.values())) != len(addresses):
        raise ValueError("Stored MAC addresses must be unique")
    return addresses


def prepare(root: Path) -> dict:
    directory = root / "var/lib/r4pro8x"
    directory.mkdir(parents=True, mode=0o700, exist_ok=True)
    with (directory / "mac-addresses.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = directory / "mac-addresses.json"
        if path.exists():
            addresses = validate(json.loads(path.read_text()))
        else:
            addresses = {}
            while len(addresses) < len(PORTS):
                value = bytearray(secrets.token_bytes(6))
                value[0] = (value[0] & 0xfc) | 2
                address = ":".join(f"{byte:02x}" for byte in value)
                if address not in addresses.values():
                    addresses[list(PORTS)[len(addresses)]] = address
            state = {"version": 1, "addresses": addresses}
            validate(state)
            atomic_write(path, json.dumps(state, indent=2) + "\n", 0o600)
        for name, node in PORTS.items():
            text = (
                "# Generated from /var/lib/r4pro8x/mac-addresses.json.\n"
                f"[Match]\nProperty=OF_FULLNAME={node}\n\n"
                "[Link]\nNamePolicy=keep kernel\nMACAddressPolicy=none\n"
                f"MACAddress={addresses[name]}\n"
            )
            atomic_write(root / f"etc/systemd/network/10-r4pro8x-mac-{name}.link", text, 0o644)
    return addresses


def check_board() -> None:
    release = Path("/etc/armbian-release").read_text().splitlines()
    if not any(line.split("=", 1)[-1].strip("\"'") == "bananapir4pro8x"
               for line in release if line.startswith("BOARD=")):
        raise ValueError("MAC application requires the R4 Pro 8X board")


def apply(addresses: dict) -> None:
    by_node = {node: name for name, node in PORTS.items()}
    devices = {}
    base = Path("/sys/firmware/devicetree/base")
    for device in Path("/sys/class/net").iterdir():
        node = device / "of_node"
        if not node.exists():
            continue
        path = "/" + str(node.resolve().relative_to(base))
        if path in by_node:
            key = by_node[path]
            if key in devices:
                raise ValueError("Multiple Ethernet devices share one MAC identity")
            devices[key] = device
    if not devices:
        raise ValueError("No built-in Ethernet devices found")
    subprocess.run(["udevadm", "wait", "--initialized=yes", "--timeout=30",
                    *[str(device) for device in devices.values()]], check=True)
    for device in devices.values():
        if int((device / "flags").read_text(), 16) & 1:
            raise ValueError(f"{device.name} is already up; apply MAC addresses before networking")
    subprocess.run(["udevadm", "control", "--reload"], check=True)
    for key in PORTS:
        if key in devices:
            device = devices[key]
            subprocess.run(["ip", "link", "set", "dev", device.name,
                            "address", addresses[key]], check=True)
            if (device / "address").read_text().strip() != addresses[key]:
                raise ValueError(f"MAC verification failed for {device.name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("generate", "apply"))
    parser.add_argument("--root", type=Path, default=Path("/"))
    args = parser.parse_args()
    root = args.root.resolve()
    if args.action == "apply" and root != Path("/"):
        parser.error("Apply requires the running root filesystem")
    if root == Path("/"):
        check_board()
    addresses = prepare(root)
    if args.action == "apply":
        apply(addresses)
    print(f"Prepared {len(addresses)} persistent built-in Ethernet MAC addresses")
