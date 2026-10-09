#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
LC_ALL=C
export LC_ALL
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packages/bpi-r4pro8x-mac/common.sh
. "$script_dir/common.sh"

usage() {
	echo "Usage: sh $0 [--write --confirm-chip P24C02A --confirm-mac MAC --backup-dir NEW_DIRECTORY]"
}

write=no
chip=
confirm_mac=
backup_dir=
while [ "$#" -gt 0 ]; do
	case "$1" in
		--write) write=yes; shift ;;
		--confirm-chip|--confirm-mac|--backup-dir)
			[ "$#" -ge 2 ] || { usage; exit 2; }
			case "$1" in
				--confirm-chip) chip=$2 ;;
				--confirm-mac) confirm_mac=$2 ;;
				--backup-dir) backup_dir=$2 ;;
			esac
			shift 2 ;;
		--help) usage; exit 0 ;;
		*) usage; exit 2 ;;
	esac
done
[ "$(id -u)" -eq 0 ] || { mac_fail 'run as root'; exit 1; }
mac_require_board /sys || { mac_fail 'not a recognized R4 Pro 8X'; exit 1; }
for tool in fw_printenv dd hexdump sha256sum cmp mktemp readlink awk; do
	command -v "$tool" >/dev/null || { mac_fail "missing command: $tool"; exit 1; }
done
eeprom=$(mac_find_eeprom /sys) || { mac_fail 'board 24c02 EEPROM at 0x57 not found'; exit 1; }
emmc=
for dev in /sys/class/block/mmcblk[0-9]*; do
	[ -f "$dev/device/type" ] || continue
	[ "$(cat "$dev/device/type")" = MMC ] || continue
	[ -z "$emmc" ] || { mac_fail 'multiple eMMC devices'; exit 1; }
	emmc=${dev##*/}
done
[ -n "$emmc" ] || { mac_fail 'eMMC unavailable; boot OpenWrt from eMMC or NAND, not SD'; exit 1; }
[ -b "/dev/$emmc" ] || { mac_fail 'eMMC block device missing'; exit 1; }
# Only the audited vendor layout supports this import.
if [ "$(cat "/sys/class/block/${emmc}p1/start")" != 8192 ] ||
	[ "$(cat "/sys/class/block/${emmc}p1/size")" != 1024 ]; then
	mac_fail 'unsupported vendor environment partition'; exit 1;
fi
umask 077
tmp=$(mktemp -d /tmp/bpi-r4pro8x-mac.XXXXXX)
trap 'rm -f "$tmp"/*; rmdir "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
dd if="/dev/$emmc" of="$tmp/environment.bin" bs=4096 skip=1024 count=128 2>/dev/null
[ "$(wc -c < "$tmp/environment.bin")" -eq 524288 ] || { mac_fail 'short environment read'; exit 1; }
printf '%s 0x0 0x40000\n%s 0x40000 0x40000\n' \
	"$tmp/environment.bin" "$tmp/environment.bin" > "$tmp/fw_env.config"
if ! mac=$(fw_printenv -c "$tmp/fw_env.config" -n ethaddr 2> "$tmp/environment.stderr"); then
	cat "$tmp/environment.stderr" >&2
	mac_fail 'cannot read CRC-validated eMMC environment'; exit 1
fi
[ ! -s "$tmp/environment.stderr" ] || {
	cat "$tmp/environment.stderr" >&2
	mac_fail 'environment warning; refuse defaults'; exit 1;
}
mac=$(printf '%s' "$mac" | tr 'A-F' 'a-f')
mac_valid "$mac" || { mac_fail 'invalid ethaddr'; exit 1; }
dd if="$eeprom" of="$tmp/before.bin" bs=256 count=1 2>/dev/null
[ "$(wc -c < "$tmp/before.bin")" -eq 256 ] || { mac_fail 'short EEPROM read'; exit 1; }
# Reject unknown occupied layouts, including ONIE TLV records.
[ "$(dd if="$tmp/before.bin" bs=1 count=8 2>/dev/null)" = R4PRO8X- ] || {
	mac_fail 'unknown EEPROM header; preserve existing layout'; exit 1;
}
dd if="$tmp/before.bin" of="$tmp/current.bin" bs=1 skip=64 count=16 2>/dev/null
mac_make_record "$mac" > "$tmp/record.bin"
mac_finish_record "$tmp/record.bin"
echo "eMMC source: /dev/$emmc, redundant environment at 0x400000/0x440000"
echo "EEPROM: $eeprom; 24c02-compatible, 256 bytes, 8-byte pages"
echo "Physical P24C02A marking and write-protect wiring cannot be verified by software."
echo "Base MAC: $mac; record: 0x40..0x4f"
if cmp -s "$tmp/current.bin" "$tmp/record.bin"; then
	echo 'Already provisioned; no EEPROM write needed.'
	exit 0
fi
[ "$(mac_hex "$tmp/current.bin")" = ffffffffffffffffffffffffffffffff ] || {
	mac_fail 'record region is occupied; no overwrite'; exit 1;
}
[ "$write" = yes ] || { echo 'DRY RUN: no EEPROM write.'; exit 0; }
[ "$chip" = P24C02A ] || { mac_fail 'confirm the physical chip with --confirm-chip P24C02A'; exit 1; }
[ "$confirm_mac" = "$mac" ] || { mac_fail '--confirm-mac must match the preview'; exit 1; }
case "$backup_dir" in /*) ;; *) mac_fail 'use an absolute backup directory'; exit 1 ;; esac
case "$backup_dir" in /tmp|/tmp/*|/run|/run/*|/dev|/dev/*|/sys|/sys/*|/proc|/proc/*)
	mac_fail 'backup must survive shutdown'; exit 1 ;;
esac
mkdir "$backup_dir" || { mac_fail 'backup directory must be new'; exit 1; }
cp "$tmp/before.bin" "$backup_dir/eeprom-before.bin"
cp "$tmp/environment.bin" "$backup_dir/emmc-environment.bin"
cp "$tmp/record.bin" "$backup_dir/eeprom-record.bin"
printf 'source=/dev/%s\neeprom=%s\nbase_mac=%s\n' "$emmc" "$eeprom" "$mac" > "$backup_dir/SOURCE"
(cd "$backup_dir" && sha256sum ./*.bin > SHA256SUMS)
sync
# Check for concurrent changes before the first hardware write.
dd if="$eeprom" of="$tmp/recheck.bin" bs=256 count=1 2>/dev/null
cmp -s "$tmp/before.bin" "$tmp/recheck.bin" || { mac_fail 'EEPROM changed during import'; exit 1; }
# Commit the checksum page last. Use at24, not direct I2C access.
dd if="$tmp/record.bin" of="$eeprom" bs=1 seek=64 count=8 conv=notrunc 2>/dev/null
dd if="$tmp/record.bin" of="$eeprom" bs=1 skip=8 seek=72 count=8 conv=notrunc 2>/dev/null
dd if="$eeprom" of="$backup_dir/eeprom-after.bin" bs=256 count=1 2>/dev/null
cp "$tmp/before.bin" "$tmp/expected.bin"
dd if="$tmp/record.bin" of="$tmp/expected.bin" bs=1 seek=64 conv=notrunc 2>/dev/null
if ! cmp -s "$tmp/expected.bin" "$backup_dir/eeprom-after.bin"; then
	mac_fail "readback differs; inspect $backup_dir; do not retry blindly"
	exit 1
fi
(cd "$backup_dir" && sha256sum ./*.bin > SHA256SUMS)
sync
echo "PASS: complete EEPROM readback matches; backup: $backup_dir"
