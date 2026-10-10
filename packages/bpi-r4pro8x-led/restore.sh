#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

function r4pro_led_restore() (
	set -eu
	local state="$1" helper="$2" filtered
	if [[ ! -f "$state" ]]; then
		bash "$helper" "$state"
		return
	fi
	filtered="$(mktemp "${TMPDIR:-/tmp}/r4pro-led-state.XXXXXX")"
	trap 'rm -f -- "$filtered"' EXIT
	# Unassigned netdev triggers legitimately have no device name.
	awk '
		/^\[.*\]$/ { trigger = "" }
		/^trigger=/ { trigger = substr($0, 9) }
		$0 == "device_name=" && trigger == "netdev" { next }
		{ print }
	' "$state" > "$filtered"
	bash "$helper" "$filtered"
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	r4pro_led_restore "${1:-/etc/armbian-leds.conf}" /usr/lib/armbian/armbian-led-state-restore.sh
fi
