#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=packages/bpi-r4pro8x-mac/common.sh
. "$repo/packages/bpi-r4pro8x-mac/common.sh"
test_dir=$(mktemp -d /tmp/bpi-r4pro8x-mac-test.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT

for mac in da:68:a5:94:9a:ee 02:00:00:00:00:01 00:11:22:33:44:55; do
	mac_valid "$mac"
	mac_make_record "$mac" > "$test_dir/record"
	mac_finish_record "$test_dir/record"
	[ "$(mac_read_record "$test_dir/record")" = "$mac" ]
done
for mac in 00:00:00:00:00:00 ff:ff:ff:ff:ff:ff 01:00:00:00:00:01 \
	da:68:a5:94:9a:zz da:68:a5:94:9a 'da:68:a5:94:9a:ee extra'; do
	if mac_valid "$mac"; then echo "FAIL: accepted $mac"; exit 1; fi
done
derived1=$(mac_derive da:68:a5:94:9a:ee 1)
derived2=$(mac_derive da:68:a5:94:9a:ee 2)
mac_valid "$derived1"
mac_valid "$derived2"
[ "$derived1" != "$derived2" ]
[ "$derived1" != da:68:a5:94:9a:ee ]
[ "$derived1" = "$(mac_derive da:68:a5:94:9a:ee 1)" ]
[ "$derived1" != "$(mac_derive da:68:a5:94:9a:ef 1)" ]
mac_make_record da:68:a5:94:9a:ee > "$test_dir/record"
mac_finish_record "$test_dir/record"
cp "$test_dir/record" "$test_dir/corrupt"
printf '\001' | dd of="$test_dir/corrupt" bs=1 seek=5 conv=notrunc 2>/dev/null
if mac_read_record "$test_dir/corrupt"; then echo 'FAIL: corrupt record accepted'; exit 1; fi
dd if="$test_dir/record" of="$test_dir/short" bs=1 count=15 2>/dev/null
if mac_read_record "$test_dir/short"; then echo 'FAIL: short record accepted'; exit 1; fi

# Fixture writes cannot access real EEPROM or block devices.
sys="$test_dir/sys"
mkdir -p "$sys/firmware/devicetree/base" "$sys/bus/i2c/devices/3-0057" \
	"$test_dir/at24" "$test_dir/eeprom@57"
printf 'Bananapi BPI-R4 Pro 8X\000' > "$sys/firmware/devicetree/base/model"
mac_require_board "$sys"
printf 'Bananapi BPI-R4\000' > "$sys/firmware/devicetree/base/model"
if mac_require_board "$sys"; then echo 'FAIL: wrong board accepted'; exit 1; fi
ln -s "$test_dir/at24" "$sys/bus/i2c/devices/3-0057/driver"
ln -s "$test_dir/eeprom@57" "$sys/bus/i2c/devices/3-0057/of_node"
printf 'atmel,24c02\000' > "$test_dir/eeprom@57/compatible"
printf '\000\000\001\000' > "$test_dir/eeprom@57/size"
printf '\000\000\000\010' > "$test_dir/eeprom@57/pagesize"
dd if=/dev/zero of="$sys/bus/i2c/devices/3-0057/eeprom" bs=256 count=1 2>/dev/null
[ "$(mac_find_eeprom "$sys")" = "$sys/bus/i2c/devices/3-0057/eeprom" ]
mkdir "$sys/bus/i2c/devices/6-0051"
cp "$sys/bus/i2c/devices/3-0057/eeprom" "$sys/bus/i2c/devices/6-0051/eeprom"
[ "$(mac_find_eeprom "$sys")" = "$sys/bus/i2c/devices/3-0057/eeprom" ]
mkdir "$sys/bus/i2c/devices/4-0057"
ln -s "$test_dir/at24" "$sys/bus/i2c/devices/4-0057/driver"
ln -s "$test_dir/eeprom@57" "$sys/bus/i2c/devices/4-0057/of_node"
cp "$sys/bus/i2c/devices/3-0057/eeprom" "$sys/bus/i2c/devices/4-0057/eeprom"
if mac_find_eeprom "$sys" 2>/dev/null; then echo 'FAIL: ambiguous EEPROM accepted'; exit 1; fi
echo 'PASS: MAC validation, record checksum, truncation, derivation, board and EEPROM discovery'
