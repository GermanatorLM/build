#!/usr/bin/env python3
"""Backport alsa-utils f90124c73edd050b24961197a4abcf17e53b41a8."""
from pathlib import Path
import sys


def fix_rule(text: str) -> str:
    lines = text.splitlines(keepends=True)
    go = [i for i, line in enumerate(lines) if line.strip() == 'LABEL="alsa_restore_go"']
    std = [i for i, line in enumerate(lines) if line.strip() == 'LABEL="alsa_restore_std"']
    env = [i for i, line in enumerate(lines) if line.startswith('ENV{ALSA_CARD_NUMBER}=')]
    if len(env) != 1 or len(go) not in (1, 2) or len(std) > 1:
        raise ValueError("Unexpected ALSA restore rule layout")
    if len(go) == 1 and len(std) == 1 and go[0] < env[0] < std[0]:
        return text
    if std or go[-1] < env[0] or (len(go) == 2 and go[0] > env[0]):
        raise ValueError("Unexpected ALSA restore labels")
    lines[go[-1]] = 'LABEL="alsa_restore_std"\n'
    if len(go) == 1:
        lines.insert(env[0], 'LABEL="alsa_restore_go"\n\n')
    return ''.join(lines)


def install(root: Path) -> None:
    rule = root / "usr/lib/udev/rules.d/90-alsa-restore.rules"
    if rule.exists():
        text = rule.read_text()
        fixed = fix_rule(text)
        if fixed != text:
            rule.write_text(fixed)


if __name__ == "__main__":
    install(Path(sys.argv[1]).resolve())
