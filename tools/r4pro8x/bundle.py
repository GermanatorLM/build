#!/usr/bin/env python3
"""Collect private build outputs, source records, and checksums."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main(source: Path, bundle: Path) -> None:
    source = source.resolve()
    bundle = bundle.resolve()
    bundle.mkdir(parents=True, exist_ok=True)
    for directory in ("images", "debs", "logs"):
        path = source / "output" / directory
        if path.exists():
            shutil.copytree(path, bundle / directory, dirs_exist_ok=True)
    records = []
    for gitdir in sorted((source / "cache/sources").glob("**/.git")):
        path = gitdir.parent
        result = subprocess.run(["git", "-C", str(path), "rev-parse", "--verify", "HEAD"], text=True, capture_output=True)
        if result.returncode:
            continue
        sha = result.stdout.strip()
        records.append({"path": str(path.relative_to(source)), "revision": sha})
    collector_sha = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    build_sha = os.environ.get("SOURCE_COMMIT", collector_sha)
    (bundle / "build-manifest.json").write_text(json.dumps({"build_commit": build_sha, "collector_commit": collector_sha, "source_cache_checkouts": records}, indent=2) + "\n")
    shutil.copy(source / "config/optional/boards/bananapir4pro8x/sources.lock.json", bundle)
    shutil.copytree(source / "patch/kernel/archive/bananapir4pro8x-7.3", bundle / "kernel-patches", dirs_exist_ok=True)
    sums = []
    for path in sorted(bundle.rglob("*")):
        if path.is_file() and path.name != "SHA256SUMS":
            with path.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            sums.append(f"{digest}  {path.relative_to(bundle)}\n")
    (bundle / "SHA256SUMS").write_text("".join(sums))


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
