#!/usr/bin/env python3
"""Install the locked firmware files and their license texts."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import urllib.request


def firmware_bytes(entry: dict, cache: Path) -> bytes:
    cached = cache / entry["sha256"]
    if cached.exists():
        data = cached.read_bytes()
    else:
        with urllib.request.urlopen(entry["url"], timeout=120) as response:
            data = response.read()
    if hashlib.sha256(data).hexdigest() != entry["sha256"]:
        raise ValueError(f"Firmware checksum mismatch: {entry['destination']}")
    if not cached.exists():
        with tempfile.TemporaryDirectory(prefix="download-", dir=cache) as temporary:
            downloaded = Path(temporary) / "firmware"
            downloaded.write_bytes(data)
            downloaded.replace(cached)
    return data


def install(root: Path) -> None:
    source = Path(__file__).resolve().parents[2]
    lock = source / "config/optional/boards/bananapir4pro8x/sources.lock.json"
    cache = source / "cache/download/r4pro8x-firmware"
    cache.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(lock.read_text())
    for entry in manifest["firmware"]:
        relative = Path(entry["destination"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Invalid firmware destination")
        data = firmware_bytes(entry, cache)
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o644)
    target = root / "usr/share/r4pro8x/firmware-manifest.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(manifest["firmware"], indent=2) + "\n")


if __name__ == "__main__":
    install(Path(sys.argv[1]).resolve())
