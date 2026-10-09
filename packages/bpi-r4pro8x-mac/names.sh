#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=packages/bpi-r4pro8x-mac/common.sh
. "$script_dir/common.sh"
mac_require_board /sys || { mac_fail 'not a recognized R4 Pro 8X'; exit 1; }
[ "$(id -u)" -eq 0 ] || { mac_fail 'run as root'; exit 1; }
tmp=$(mktemp -d /tmp/bpi-r4pro8x-names.XXXXXX)
trap 'rm -f "$tmp"/*; rmdir "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
attempt=0
while :; do
	: > "$tmp/map"
	for dev in /sys/class/net/*; do
		node=$(readlink -f "$dev/of_node") || continue
		case "$node" in */ethernet@15100000/mac@*) ;; *) continue ;; esac
		if [ ! -r "$node/compatible" ] || [ ! -r "$node/reg" ]; then continue; fi
		tr '\000' '\n' < "$node/compatible" | grep -qx mediatek,eth-mac || continue
		case "$(mac_hex "$node/reg")" in
			00000000) target=eth1 ;;
			00000001) target=wan ;;
			00000002) target=eth0 ;;
			*) continue ;;
		esac
		printf '%s %s\n' "${dev##*/}" "$target" >> "$tmp/map"
	done
	missing=no
	for n in lan1 lan2 lan3 lan4 lan5 lan6 fpc; do
		if [ ! -r "/sys/class/net/$n/flags" ]; then missing=yes; fi
	done
	if [ "$(wc -l < "$tmp/map")" -eq 3 ] && [ "$missing" = no ]; then break; fi
	[ "$attempt" -lt 20 ] || { mac_fail 'GMACs or front-panel ports missing'; exit 1; }
	sleep 1
	attempt=$((attempt + 1))
done
[ "$(awk '{print $2}' "$tmp/map" | sort -u | wc -l)" -eq 3 ] || {
	mac_fail 'ambiguous GMAC identities'; exit 1;
}
for n in lan1 lan2 lan3 lan4 lan5 lan6 fpc; do
	[ "$(tr '\000' '\n' < "/sys/class/net/$n/of_node/label")" = "$n" ] || {
		mac_fail "unexpected DT label for $n"; exit 1;
	}
done
changed=no
original_names=$(awk '{print $1}' "$tmp/map" | tr '\n' ' ')
while read -r n target; do
	[ "$n" = "$target" ] || changed=yes
	if [ -e "/sys/class/net/$target" ]; then
		case " $original_names " in
			*" $target "*) ;;
			*) mac_fail "target name occupied: $target"; exit 1 ;;
		esac
	fi
done < "$tmp/map"
[ "$changed" = yes ] || { echo 'PASS: hardware port names already assigned'; exit 0; }
for n in $original_names lan1 lan2 lan3 lan4 lan5 lan6 fpc; do
	flags=$(cat "/sys/class/net/$n/flags")
	[ "$((flags & 1))" -eq 0 ] || { mac_fail "$n is already UP; refuse rename"; exit 1; }
done
for target in eth0 eth1 wan; do
	[ ! -e "/sys/class/net/bpi-$target" ] || { mac_fail 'temporary name occupied; inspect previous failure'; exit 1; }
done
# Stage every GMAC before using names that another GMAC currently owns.
while read -r n target; do ip link set dev "$n" name "bpi-$target"; done < "$tmp/map"
while read -r n target; do
	ip link set dev "bpi-$target" name "$target"
	echo "RENAMED: $n -> $target"
done < "$tmp/map"
