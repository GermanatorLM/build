#!/usr/bin/env python3
"""Apply R4 Pro userspace corrections to the board package."""
from pathlib import Path
import shutil
import sys


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if new in text and old not in text:
        return
    if text.count(old) != 1:
        raise ValueError(f"Unexpected layout: {path}")
    path.write_text(text.replace(old, new))


def install(root: Path) -> None:
    mac = root / "usr/lib/armbian/r4pro8x-mac-addresses"
    mac.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__).with_name("mac-addresses.py"), mac)
    mac.chmod(0o755)
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
        "r4pro8x-mac-addresses.service": (
            "[Unit]\nDescription=Prepare persistent R4 Pro Ethernet MAC addresses\n"
            "DefaultDependencies=no\n"
            "After=local-fs.target systemd-udev-trigger.service\n"
            "Before=systemd-networkd.service\n"
            "RequiresMountsFor=/var/lib/r4pro8x\n\n"
            "[Service]\nType=oneshot\nRemainAfterExit=yes\n"
            "ExecStart=/usr/lib/armbian/r4pro8x-mac-addresses apply\n\n"
            "[Install]\nWantedBy=multi-user.target\n"
        ),
        "systemd-networkd.service.d/20-r4pro8x-mac.conf": (
            "[Unit]\nRequires=r4pro8x-mac-addresses.service\n"
            "After=r4pro8x-mac-addresses.service\n"
        ),
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
    wants = root / "etc/systemd/system/multi-user.target.wants/r4pro8x-mac-addresses.service"
    wants.parent.mkdir(parents=True, exist_ok=True)
    if not wants.is_symlink():
        wants.symlink_to("/etc/systemd/system/r4pro8x-mac-addresses.service")


if __name__ == "__main__":
    install(Path(sys.argv[1]).resolve())
