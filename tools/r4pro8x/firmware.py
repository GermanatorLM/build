#!/usr/bin/env python3
"""Install the locked firmware files and their license texts."""
import hashlib
import json
from pathlib import Path
import sys
import urllib.request


def install(root: Path) -> None:
    lock = Path(__file__).resolve().parents[2] / "config/optional/boards/bananapir4pro8x/sources.lock.json"
    manifest = json.loads(lock.read_text())
    for entry in manifest["firmware"]:
        relative = Path(entry["destination"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Invalid firmware destination")
        with urllib.request.urlopen(entry["url"], timeout=120) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError(f"Firmware checksum mismatch: {relative}")
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o644)
    target = root / "usr/share/r4pro8x/firmware-manifest.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(manifest["firmware"], indent=2) + "\n")


if __name__ == "__main__":
    install(Path(sys.argv[1]).resolve())
