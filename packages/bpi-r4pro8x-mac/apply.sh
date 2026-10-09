#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
LC_ALL=C
export LC_ALL
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packages/bpi-r4pro8x-mac/common.sh
. "$script_dir/common.sh"
mode=${1:---show}
case "$mode" in --show|--apply) ;; *) echo "Usage: sh $0 [--show|--apply]" >&2; exit 2 ;; esac
[ "$#" -le 1 ] || exit 2
mac_require_board /sys || { mac_fail 'not a recognized R4 Pro 8X'; exit 1; }
tmp=$(mktemp -d /tmp/bpi-r4pro8x-mac-read.XXXXXX)
trap 'rm -f "$tmp"/*; rmdir "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
base=da:68:a5:94:9a:ee
source=fallback
eeprom=unavailable
if eeprom=$(mac_find_eeprom /sys); then
	if dd if="$eeprom" of="$tmp/record.bin" bs=1 skip=64 count=16 2>/dev/null &&
		stored=$(mac_read_record "$tmp/record.bin"); then
		base=$stored
		source=eeprom
	else
		echo 'WARNING: no valid EEPROM MAC record; use fixed fallback' >&2
	fi
else
	eeprom=unavailable
	echo 'WARNING: board EEPROM unavailable; use fixed fallback' >&2
fi
if [ "$source" = fallback ]; then
	echo 'WARNING: fixed fallback MACs collide across unprovisioned boards' >&2
fi
printf 'SOURCE=%s\nEEPROM=%s\nBASE=%s\n' "$source" "$eeprom" "$base"
# Reserve unique addresses for conduits before assigning external port addresses.
offset=0
for n in eth0 eth1 eth2 mgmt lan0 lan1 lan2 lan3 lan4; do
	addr=$(mac_increment "$base" "$offset") || { mac_fail 'MAC range overflow or multicast boundary'; exit 1; }
	mac_valid "$addr" || { mac_fail 'invalid generated MAC'; exit 1; }
	printf '%s %s\n' "$n" "$addr" >> "$tmp/plan"
	printf '%s=%s\n' "$n" "$addr"
	offset=$((offset + 1))
done
[ "$mode" = --apply ] || exit 0
[ "$(id -u)" -eq 0 ] || { mac_fail 'run as root'; exit 1; }
# Wait for deferred DSA probes. Never take live links down.
attempt=0
while :; do
	missing=
	while read -r n addr; do
		if [ ! -r "/sys/class/net/$n/flags" ]; then missing="$missing $n"; fi
	done < "$tmp/plan"
	[ -n "$missing" ] || break
	[ "$attempt" -lt 20 ] || { mac_fail "missing interfaces:$missing"; exit 1; }
	sleep 1
	attempt=$((attempt + 1))
done
# Check the complete plan before changing any interface.
while read -r n addr; do
	flags=$(cat "/sys/class/net/$n/flags")
	[ "$((flags & 1))" -eq 0 ] || { mac_fail "$n is already UP; refuse late assignment"; exit 1; }
done < "$tmp/plan"
while read -r n addr; do
	ip link set dev "$n" address "$addr"
	[ "$(cat "/sys/class/net/$n/address")" = "$addr" ] || { mac_fail "$n readback failed"; exit 1; }
	echo "APPLIED: $n=$addr"
done < "$tmp/plan"
