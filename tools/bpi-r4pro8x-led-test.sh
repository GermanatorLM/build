#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
repo="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=packages/bpi-r4pro8x-led/restore.sh
source "$repo/packages/bpi-r4pro8x-led/restore.sh"
helper="$repo/packages/bsp/common/usr/lib/armbian/armbian-led-state-restore.sh"
test_dir="$(mktemp -d /tmp/bpi-r4pro8x-led-test.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
mkdir "$test_dir/led" "$test_dir/temp"
export TMPDIR="$test_dir/temp"
printf 'netdev\n' > "$test_dir/led/trigger"
printf '\n' > "$test_dir/led/device_name"
printf '0\n' > "$test_dir/led/rx"
state="$test_dir/state"
printf '[%s]\ntrigger=netdev\ndevice_name=\nrx=1\n' "$test_dir/led" > "$state"
before="$(sha256sum "$state")"
if bash "$helper" "$state" >/dev/null; then
	echo 'FAIL: original helper unexpectedly accepts the regression fixture'
	exit 1
fi
r4pro_led_restore "$state" "$helper"
[[ "$(cat "$test_dir/led/rx")" == 1 ]]
[[ "$(sha256sum "$state")" == "$before" ]]
[[ "$(cat "$test_dir/led/device_name")" == '' ]]

printf '[%s]\ntrigger=netdev\ndevice_name=wan\n' "$test_dir/led" > "$state"
r4pro_led_restore "$state" "$helper"
[[ "$(cat "$test_dir/led/device_name")" == wan ]]

for invalid in 'trigger=' 'broken' 'rx='; do
	printf '[%s]\ntrigger=netdev\n%s\n' "$test_dir/led" "$invalid" > "$state"
	if r4pro_led_restore "$state" "$helper" >/dev/null; then
		echo "FAIL: invalid setting accepted: $invalid"
		exit 1
	fi
done
printf '[%s]\ntrigger=none\ndevice_name=\n' "$test_dir/led" > "$state"
if r4pro_led_restore "$state" "$helper" >/dev/null; then
	echo 'FAIL: unrelated empty setting accepted'
	exit 1
fi
r4pro_led_restore "$test_dir/missing" "$helper" >/dev/null
[[ -z "$(ls -A "$test_dir/temp")" ]]
printf 'PASS: R4 Pro LED regression, valid names, input preservation, errors and cleanup\n'
