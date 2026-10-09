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
eeprom=$(mac_find_eeprom /sys) || { mac_fail 'board EEPROM unavailable or ambiguous'; exit 1; }
dd if="$eeprom" of="$tmp/record.bin" bs=1 skip=64 count=16 2>/dev/null
source=eeprom
if ! base=$(mac_read_record "$tmp/record.bin"); then
	[ "$(mac_hex "$tmp/record.bin")" = ffffffffffffffffffffffffffffffff ] || {
		mac_fail 'occupied or corrupt EEPROM record; refuse overwrite'; exit 1;
	}
	if [ "$mode" = --show ]; then
		echo 'UNPROVISIONED: --apply creates a random local base MAC in EEPROM'
		exit 0
	fi
	# Provision only after the naming service and interface readiness checks.
	[ "$(id -u)" -eq 0 ] || { mac_fail 'run as root'; exit 1; }
	for n in eth0 eth1 wan lan1 lan2 lan3 lan4 lan5 lan6 fpc; do
		[ -r "/sys/class/net/$n/flags" ] || { mac_fail "missing $n"; exit 1; }
		flags=$(cat "/sys/class/net/$n/flags")
		[ "$((flags & 1))" -eq 0 ] || { mac_fail "$n is already UP; refuse provisioning"; exit 1; }
	done
	base=$(sh "$script_dir/provision.sh") || { mac_fail 'EEPROM provisioning failed'; exit 1; }
	source=random-provisioned
fi
printf 'SOURCE=%s\nEEPROM=%s\nBASE=%s\n' "$source" "$eeprom" "$base"
# Reserve unique addresses for conduits before assigning external port addresses.
offset=0
for n in eth0 eth1 wan lan1 lan2 lan3 lan4 lan5 lan6 fpc; do
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
