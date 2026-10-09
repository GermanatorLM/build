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
eeprom=$(mac_find_eeprom /sys) || { echo 'SKIP: board EEPROM unavailable'; exit 0; }
tmp=$(mktemp -d /tmp/bpi-r4pro8x-mac-read.XXXXXX)
trap 'rm -f "$tmp"/*; rmdir "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
dd if="$eeprom" of="$tmp/record.bin" bs=1 skip=64 count=16 2>/dev/null
if [ "$(od -An -v -tx1 "$tmp/record.bin" | tr -d ' \n')" = ffffffffffffffffffffffffffffffff ]; then
	echo 'SKIP: EEPROM has no provisioned MAC record'
	exit 0
fi
base=$(mac_read_record "$tmp/record.bin") || { mac_fail 'invalid EEPROM MAC record; leave interfaces unchanged'; exit 1; }
addr1=$(mac_derive "$base" 1)
addr2=$(mac_derive "$base" 2)
if ! mac_valid "$addr1" || ! mac_valid "$addr2"; then exit 1; fi
[ "$base" != "$addr1" ] && [ "$base" != "$addr2" ] && [ "$addr1" != "$addr2" ] || {
	mac_fail 'derived address collision'; exit 1;
}
printf 'EEPROM=%s\neth0=%s\neth1=%s\neth2=%s\n' "$eeprom" "$base" "$addr1" "$addr2"
[ "$mode" = --apply ] || exit 0
[ "$(id -u)" -eq 0 ] || { mac_fail 'run as root'; exit 1; }
# Check all devices before changing any address. Never take live links down.
for n in eth0 eth1 eth2; do
	[ -r "/sys/class/net/$n/flags" ] || { mac_fail "missing $n"; exit 1; }
	flags=$(cat "/sys/class/net/$n/flags")
	[ "$((flags & 1))" -eq 0 ] || { mac_fail "$n is already UP; refuse late assignment"; exit 1; }
done
if [ "$(cat /sys/class/net/eth1/addr_assign_type)" != 1 ]; then
	addr1=$(cat /sys/class/net/eth1/address)
fi
if [ "$(cat /sys/class/net/eth2/addr_assign_type)" != 1 ]; then
	addr2=$(cat /sys/class/net/eth2/address)
fi
if ! mac_valid "$addr1" || ! mac_valid "$addr2"; then
	mac_fail 'invalid existing secondary MAC'; exit 1
fi
[ "$base" != "$addr1" ] && [ "$base" != "$addr2" ] && [ "$addr1" != "$addr2" ] || {
	mac_fail 'existing secondary address collision'; exit 1;
}
for n in eth0 eth1 eth2; do
	case "$n" in eth0) addr=$base ;; eth1) addr=$addr1 ;; eth2) addr=$addr2 ;; esac
	# Preserve non-random secondary addresses from firmware or configuration.
	if [ "$n" != eth0 ] && [ "$(cat "/sys/class/net/$n/addr_assign_type")" != 1 ]; then
		echo "KEEP: $n already has a non-random address"
		continue
	fi
	ip link set dev "$n" address "$addr"
	[ "$(cat "/sys/class/net/$n/address")" = "$addr" ] || { mac_fail "$n readback failed"; exit 1; }
	echo "APPLIED: $n=$addr"
done
