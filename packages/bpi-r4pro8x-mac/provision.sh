#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# stdout contains only the selected base MAC.
set -eu
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packages/bpi-r4pro8x-mac/common.sh
. "$script_dir/common.sh"
mac_require_board /sys || { mac_fail 'not a recognized R4 Pro 8X'; exit 1; }
[ "$(id -u)" -eq 0 ] || { mac_fail 'run as root'; exit 1; }
umask 077
state=/var/lib/bpi-r4pro8x-mac
mkdir -p "$state"
exec 9> "$state/provision.lock"
flock -n 9 || { mac_fail 'EEPROM provisioning already running'; exit 1; }
eeprom=$(mac_find_eeprom /sys) || { mac_fail 'board EEPROM unavailable or ambiguous'; exit 1; }
tmp=$(mktemp -d /tmp/bpi-r4pro8x-provision.XXXXXX)
trap 'rm -f "$tmp"/*; rmdir "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
dd if="$eeprom" of="$tmp/before.bin" bs=256 count=1 2>/dev/null
[ "$(wc -c < "$tmp/before.bin")" -eq 256 ] || { mac_fail 'short EEPROM read'; exit 1; }
dd if="$tmp/before.bin" of="$tmp/current.bin" bs=1 skip=64 count=16 2>/dev/null
if base=$(mac_read_record "$tmp/current.bin"); then printf '%s\n' "$base"; exit 0; fi
[ "$(mac_hex "$tmp/current.bin")" = ffffffffffffffffffffffffffffffff ] || {
	mac_fail 'occupied or corrupt EEPROM record; refuse overwrite'; exit 1;
}
header=$(dd if="$tmp/before.bin" bs=1 count=8 2>/dev/null)
if [ "$header" != R4PRO8X- ]; then
	# A fully erased device is the only accepted layout without the vendor header.
	hexdump -v -e '1/1 "%u\n"' "$tmp/before.bin" | awk '$1!=255 {exit 1}' || {
		mac_fail 'unknown EEPROM layout; preserve existing data'; exit 1;
	}
fi
# /dev/random waits for initialized kernel entropy. Reserve a 16-address block.
dd if=/dev/random of="$tmp/random.bin" bs=6 count=1 2>/dev/null
[ "$(wc -c < "$tmp/random.bin")" -eq 6 ] || { mac_fail 'short entropy read'; exit 1; }
base=$(hexdump -v -e '1/1 "%u "' "$tmp/random.bin" | awk '{
	printf "%02x:%02x:%02x:%02x:%02x:%02x\n",int($1/4)*4+2,$2,$3,$4,$5,int($6/16)*16;
}')
mac_valid "$base" || { mac_fail 'invalid random MAC'; exit 1; }
mac_make_record "$base" > "$tmp/record.bin"
mac_finish_record "$tmp/record.bin"
backup=$(mktemp -d "$state/provision.XXXXXX")
cp "$tmp/before.bin" "$backup/eeprom-before.bin"
cp "$tmp/record.bin" "$backup/eeprom-record.bin"
printf 'source=random\neeprom=%s\nbase_mac=%s\n' "$eeprom" "$base" > "$backup/SOURCE"
(cd "$backup" && sha256sum ./*.bin > SHA256SUMS)
sync
dd if="$eeprom" of="$tmp/recheck.bin" bs=256 count=1 2>/dev/null
cmp -s "$tmp/before.bin" "$tmp/recheck.bin" || { mac_fail 'EEPROM changed; refuse write'; exit 1; }
dd if="$tmp/record.bin" of="$eeprom" bs=1 seek=64 count=8 conv=notrunc 2>/dev/null
dd if="$tmp/record.bin" of="$eeprom" bs=1 skip=8 seek=72 count=8 conv=notrunc 2>/dev/null
dd if="$eeprom" of="$backup/eeprom-after.bin" bs=256 count=1 2>/dev/null
cp "$tmp/before.bin" "$tmp/expected.bin"
dd if="$tmp/record.bin" of="$tmp/expected.bin" bs=1 seek=64 conv=notrunc 2>/dev/null
cmp -s "$tmp/expected.bin" "$backup/eeprom-after.bin" || {
	mac_fail "readback mismatch; inspect $backup; do not retry blindly"; exit 1;
}
(cd "$backup" && sha256sum ./*.bin > SHA256SUMS)
sync
echo "PROVISIONED: random EEPROM base MAC; backup: $backup" >&2
printf '%s\n' "$base"
