#!/usr/bin/env python3
"""Apply R4 Pro userspace corrections to the board package."""
from pathlib import Path
import sys


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if new in text and old not in text:
        return
    if text.count(old) != 1:
        raise ValueError(f"Unexpected layout: {path}")
    path.write_text(text.replace(old, new))


def install(root: Path) -> None:
    optimize = root / "usr/lib/armbian/armbian-hardware-optimization"
    replace_once(
        optimize,
        'grep -q "${GOVERNOR}" "${Cluster}/scaling_available_governors"',
        '[[ -n "${GOVERNOR}" ]] && '
        'grep -qwF -- "${GOVERNOR}" "${Cluster}/scaling_available_governors"',
    )
    replace_once(
        root / "usr/lib/armbian/armbian-firstrun",
        '\tsetupcon --save\n',
        '\t# This serial-only board does not load console fonts.\n',
    )
    units = {
        "sshd-keygen.service.d/20-r4pro8x.conf": (
            "[Unit]\n"
            "# Generate missing keys independently of machine-id initialization.\n"
            "ConditionFirstBoot=\n"
            "ConditionPathIsReadWrite=/etc/ssh\n"
            "ConditionPathIsSymbolicLink=!/etc/ssh\n"
        ),
        "console-setup.service.d/20-r4pro8x.conf": (
            "[Unit]\n"
            "# The board exposes a serial console and no framebuffer.\n"
            "ConditionPathExists=/sys/class/graphics/fb0\n"
        ),
    }
    for name, text in units.items():
        path = root / "etc/systemd/system" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    wants = root / "etc/systemd/system/ssh.service.wants/sshd-keygen.service"
    wants.parent.mkdir(parents=True, exist_ok=True)
    if not wants.is_symlink():
        wants.symlink_to("/usr/lib/systemd/system/sshd-keygen.service")


if __name__ == "__main__":
    install(Path(sys.argv[1]).resolve())
