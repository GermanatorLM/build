#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=packages/bpi-r4pro8x-mac/common.sh
. "$repo/packages/bpi-r4pro8x-mac/common.sh"
test_dir=$(mktemp -d /tmp/bpi-r4pro8x-mac-test.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT

for length in 0 1 12 255 256 1024; do
	dd if=/dev/zero of="$test_dir/checksum-input" bs=1 count="$length" 2>/dev/null
	[ "$(mac_cksum < "$test_dir/checksum-input")" = "$(cksum < "$test_dir/checksum-input" | awk '{print $1}')" ]
done
printf 'R4PRO8X-\377\000\020\200' > "$test_dir/checksum-input"
[ "$(mac_cksum < "$test_dir/checksum-input")" = "$(cksum < "$test_dir/checksum-input" | awk '{print $1}')" ]

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
derived1=$(mac_increment da:68:a5:94:9a:ee 1)
derived2=$(mac_increment da:68:a5:94:9a:ee 2)
mac_valid "$derived1"
mac_valid "$derived2"
[ "$derived1" != "$derived2" ]
[ "$derived1" != da:68:a5:94:9a:ee ]
[ "$derived1" = da:68:a5:94:9a:ef ]
[ "$derived2" = da:68:a5:94:9a:f0 ]
[ "$(mac_increment da:68:a5:94:9a:ff 1)" = da:68:a5:94:9b:00 ]
[ "$(mac_increment da:68:a5:ff:ff:ff 2)" = da:68:a6:00:00:01 ]
for offset in -1 invalid 65536; do
	if mac_increment da:68:a5:94:9a:ee "$offset"; then echo 'FAIL: invalid increment accepted'; exit 1; fi
done
if mac_increment fe:ff:ff:ff:ff:ff 1; then echo 'FAIL: multicast boundary accepted'; exit 1; fi
if mac_increment fe:ff:ff:ff:ff:ff 65535; then echo 'FAIL: overflow accepted'; exit 1; fi
[ "$((0x${derived1%%:*} & 3))" -eq 2 ]
[ "$((0x${derived2%%:*} & 3))" -eq 2 ]
mac_make_record da:68:a5:94:9a:ee > "$test_dir/record"
mac_finish_record "$test_dir/record"
cp "$test_dir/record" "$test_dir/corrupt"
printf '\001' | dd of="$test_dir/corrupt" bs=1 seek=5 conv=notrunc 2>/dev/null
if mac_read_record "$test_dir/corrupt"; then echo 'FAIL: corrupt record accepted'; exit 1; fi
for index in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
	cp "$test_dir/record" "$test_dir/corrupt"
	original=$(od -An -tu1 -j "$index" -N1 "$test_dir/record")
	mac_bytes "$((original ^ 1))" | dd of="$test_dir/corrupt" bs=1 seek="$index" conv=notrunc 2>/dev/null
	if mac_read_record "$test_dir/corrupt"; then echo "FAIL: corrupt byte $index accepted"; exit 1; fi
done
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
mv "$test_dir/eeprom@57/pagesize" "$test_dir/eeprom@57/page-size"
[ "$(mac_find_eeprom "$sys")" = "$sys/bus/i2c/devices/3-0057/eeprom" ]
mv "$test_dir/eeprom@57/page-size" "$test_dir/eeprom@57/pagesize"
mkdir "$sys/bus/i2c/devices/6-0051"
cp "$sys/bus/i2c/devices/3-0057/eeprom" "$sys/bus/i2c/devices/6-0051/eeprom"
[ "$(mac_find_eeprom "$sys")" = "$sys/bus/i2c/devices/3-0057/eeprom" ]
mkdir "$sys/bus/i2c/devices/4-0057"
ln -s "$test_dir/at24" "$sys/bus/i2c/devices/4-0057/driver"
ln -s "$test_dir/eeprom@57" "$sys/bus/i2c/devices/4-0057/of_node"
cp "$sys/bus/i2c/devices/3-0057/eeprom" "$sys/bus/i2c/devices/4-0057/eeprom"
if mac_find_eeprom "$sys" 2>/dev/null; then echo 'FAIL: ambiguous EEPROM accepted'; exit 1; fi
rm -rf "$sys/bus/i2c/devices/4-0057"

# Run the boot reader against fixtures. Mock ip prevents real network changes.
printf 'Bananapi BPI-R4 Pro 8X\000' > "$sys/firmware/devicetree/base/model"
cp "$repo/packages/bpi-r4pro8x-mac/common.sh" "$test_dir/common.sh"
sed "s|/sys|$sys|g" "$repo/packages/bpi-r4pro8x-mac/apply.sh" > "$test_dir/apply.sh"
printf '\377\021\042\063\104\377' > "$test_dir/entropy"
sed -e "s|/sys|$sys|g" -e "s|/var/lib/bpi-r4pro8x-mac|$test_dir/state|g" \
	-e "s|/dev/random|$test_dir/entropy|g" \
	"$repo/packages/bpi-r4pro8x-mac/provision.sh" > "$test_dir/provision.sh"
mkdir "$test_dir/bin"
printf '#!/bin/sh\nprintf "0\\n"\n' > "$test_dir/bin/id"
cat > "$test_dir/bin/ip" <<'MOCK_IP'
#!/bin/sh
set -eu
[ "$1 $2 $3 $5" = 'link set dev address' ]
case "$4" in eth0|eth1|wan|lan1|lan2|lan3|lan4|lan5|lan6|fpc) ;; *) exit 1 ;; esac
printf '%s\n' "$6" > "$TEST_MAC_SYS_DIR/class/net/$4/address"
printf '%s\n' "$*" >> "$TEST_MAC_SYS_DIR/ip-calls"
MOCK_IP
chmod 0755 "$test_dir/bin/id" "$test_dir/bin/ip"
printf '#!/bin/sh\nexit 0\n' > "$test_dir/bin/sleep"
chmod 0755 "$test_dir/bin/sleep"
for n in eth0 eth1 wan lan1 lan2 lan3 lan4 lan5 lan6 fpc; do
	mkdir -p "$sys/class/net/$n"
	printf '0x0\n' > "$sys/class/net/$n/flags"
	printf '1\n' > "$sys/class/net/$n/addr_assign_type"
	printf '02:00:00:00:00:01\n' > "$sys/class/net/$n/address"
done
export TEST_MAC_SYS_DIR="$sys"
PATH="$test_dir/bin:$PATH"
export PATH
mac_make_record da:68:a5:94:9a:ee > "$test_dir/record"
mac_finish_record "$test_dir/record"
dd if="$test_dir/record" of="$sys/bus/i2c/devices/3-0057/eeprom" bs=1 seek=64 conv=notrunc 2>/dev/null
before_reader=$(sha256sum "$sys/bus/i2c/devices/3-0057/eeprom")
sh "$test_dir/apply.sh" --show >/dev/null
[ ! -e "$sys/ip-calls" ]
sh "$test_dir/apply.sh" --apply >/dev/null
[ "$(cat "$sys/class/net/eth0/address")" = da:68:a5:94:9a:ee ]
[ "$(cat "$sys/class/net/eth1/address")" = "$derived1" ]
[ "$(cat "$sys/class/net/wan/address")" = "$derived2" ]
[ "$(cat "$sys/class/net/lan1/address")" = da:68:a5:94:9a:f1 ]
[ "$(cat "$sys/class/net/fpc/address")" = da:68:a5:94:9a:f7 ]
[ "$(wc -l < "$sys/ip-calls")" -eq 10 ]
[ "$before_reader" = "$(sha256sum "$sys/bus/i2c/devices/3-0057/eeprom")" ]
offset=0
for n in eth0 eth1 wan lan1 lan2 lan3 lan4 lan5 lan6 fpc; do
	[ "$(cat "$sys/class/net/$n/address")" = "$(mac_increment da:68:a5:94:9a:ee "$offset")" ]
	offset=$((offset + 1))
done
rm "$sys/ip-calls"
printf '0x1\n' > "$sys/class/net/wan/flags"
if sh "$test_dir/apply.sh" --apply >/dev/null 2>&1; then echo 'FAIL: UP interface accepted'; exit 1; fi
[ ! -e "$sys/ip-calls" ]
printf '0x0\n' > "$sys/class/net/wan/flags"
printf '0\n' > "$sys/class/net/eth1/addr_assign_type"
printf '00:11:22:33:44:55\n' > "$sys/class/net/eth1/address"
sh "$test_dir/apply.sh" --apply >/dev/null
[ "$(cat "$sys/class/net/eth1/address")" = "$derived1" ]
[ "$(wc -l < "$sys/ip-calls")" -eq 10 ]
rm "$sys/ip-calls"
printf '0x1\n' > "$sys/class/net/lan4/flags"
if sh "$test_dir/apply.sh" --apply >/dev/null 2>&1; then echo 'FAIL: UP DSA port accepted'; exit 1; fi
[ ! -e "$sys/ip-calls" ]
printf '0x0\n' > "$sys/class/net/lan4/flags"
mv "$sys/class/net/lan4" "$test_dir/missing-lan4"
if sh "$test_dir/apply.sh" --apply >/dev/null 2>&1; then echo 'FAIL: missing DSA port accepted'; exit 1; fi
[ ! -e "$sys/ip-calls" ]
mv "$test_dir/missing-lan4" "$sys/class/net/lan4"

# EEPROM identity survives byte carry. Corrupt records must never be overwritten.
mac_make_record 02:11:22:33:44:ff > "$test_dir/record"
mac_finish_record "$test_dir/record"
dd if="$test_dir/record" of="$sys/bus/i2c/devices/3-0057/eeprom" bs=1 seek=64 conv=notrunc 2>/dev/null
sh "$test_dir/apply.sh" --apply > "$test_dir/result"
grep -qx SOURCE=eeprom "$test_dir/result"
[ "$(cat "$sys/class/net/eth0/address")" = 02:11:22:33:44:ff ]
[ "$(cat "$sys/class/net/fpc/address")" = 02:11:22:33:45:08 ]
rm "$sys/ip-calls"
printf '\001' | dd of="$sys/bus/i2c/devices/3-0057/eeprom" bs=1 seek=77 conv=notrunc 2>/dev/null
corrupt_hash=$(sha256sum "$sys/bus/i2c/devices/3-0057/eeprom")
if sh "$test_dir/apply.sh" --apply >/dev/null 2>&1; then echo 'FAIL: corrupt EEPROM overwritten'; exit 1; fi
[ ! -e "$sys/ip-calls" ]
[ "$corrupt_hash" = "$(sha256sum "$sys/bus/i2c/devices/3-0057/eeprom")" ]
for index in 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79; do
	printf '\377' | dd of="$sys/bus/i2c/devices/3-0057/eeprom" bs=1 seek="$index" conv=notrunc 2>/dev/null
done
sh "$test_dir/apply.sh" --show > "$test_dir/result" 2>/dev/null
grep -q '^UNPROVISIONED:' "$test_dir/result"
[ ! -e "$sys/ip-calls" ]
printf 'R4PRO8X-TESTBOARD' | dd of="$sys/bus/i2c/devices/3-0057/eeprom" bs=1 conv=notrunc 2>/dev/null
blank_hash=$(sha256sum "$sys/bus/i2c/devices/3-0057/eeprom")
printf '0x1\n' > "$sys/class/net/fpc/flags"
if sh "$test_dir/apply.sh" --apply >/dev/null 2>&1; then echo 'FAIL: provisioning with UP FPC'; exit 1; fi
[ "$blank_hash" = "$(sha256sum "$sys/bus/i2c/devices/3-0057/eeprom")" ]
printf '0x0\n' > "$sys/class/net/fpc/flags"
sh "$test_dir/apply.sh" --apply > "$test_dir/result" 2>/dev/null
grep -qx SOURCE=random-provisioned "$test_dir/result"
[ "$(cat "$sys/class/net/eth0/address")" = fe:11:22:33:44:f0 ]
[ "$(cat "$sys/class/net/fpc/address")" = fe:11:22:33:44:f9 ]
provisioned_hash=$(sha256sum "$sys/bus/i2c/devices/3-0057/eeprom")
[ "$(find "$test_dir/state" -name eeprom-before.bin | wc -l)" -eq 1 ]
for sums in "$test_dir/state"/provision.*/SHA256SUMS; do
	(cd "$(dirname "$sums")" && sha256sum -c SHA256SUMS >/dev/null)
done
sh "$test_dir/apply.sh" --apply > "$test_dir/result"
grep -qx SOURCE=eeprom "$test_dir/result"
[ "$provisioned_hash" = "$(sha256sum "$sys/bus/i2c/devices/3-0057/eeprom")" ]
[ "$(find "$test_dir/state" -name eeprom-before.bin | wc -l)" -eq 1 ]
rm "$sys/ip-calls"
mv "$sys/bus/i2c/devices/3-0057/eeprom" "$test_dir/eeprom-saved"
if sh "$test_dir/apply.sh" --apply >/dev/null 2>&1; then echo 'FAIL: EEPROM absence accepted'; exit 1; fi
[ ! -e "$sys/ip-calls" ]
mv "$test_dir/eeprom-saved" "$sys/bus/i2c/devices/3-0057/eeprom"
for index in 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79; do
	printf '\377' | dd of="$sys/bus/i2c/devices/3-0057/eeprom" bs=1 seek="$index" conv=notrunc 2>/dev/null
done
printf 'TlvInfo\000' | dd of="$sys/bus/i2c/devices/3-0057/eeprom" bs=1 conv=notrunc 2>/dev/null
unknown_hash=$(sha256sum "$sys/bus/i2c/devices/3-0057/eeprom")
if sh "$test_dir/provision.sh" >/dev/null 2>&1; then echo 'FAIL: unknown EEPROM layout overwritten'; exit 1; fi
[ "$unknown_hash" = "$(sha256sum "$sys/bus/i2c/devices/3-0057/eeprom")" ]
# Emulate write protection: successful write calls do not alter the EEPROM.
printf 'R4PRO8X-TESTBOARD' | dd of="$sys/bus/i2c/devices/3-0057/eeprom" bs=1 conv=notrunc 2>/dev/null
TEST_REAL_DD=$(command -v dd)
export TEST_REAL_DD
export TEST_EEPROM_PATH="$sys/bus/i2c/devices/3-0057/eeprom"
cat > "$test_dir/bin/dd" <<'MOCK_PROTECTED'
#!/bin/sh
for arg in "$@"; do
	if [ "$arg" = "of=$TEST_EEPROM_PATH" ]; then exit 0; fi
done
exec "$TEST_REAL_DD" "$@"
MOCK_PROTECTED
chmod 0755 "$test_dir/bin/dd"
protected_hash=$(sha256sum "$TEST_EEPROM_PATH")
if sh "$test_dir/provision.sh" >/dev/null 2>&1; then echo 'FAIL: protected EEPROM reports success'; exit 1; fi
[ "$protected_hash" = "$(sha256sum "$TEST_EEPROM_PATH")" ]
rm "$test_dir/bin/dd"
# A fully erased chip is supported without inventing manufacturer metadata.
for index in $(seq 0 255); do
	printf '\377' | dd of="$TEST_EEPROM_PATH" bs=1 seek="$index" conv=notrunc 2>/dev/null
done
sh "$test_dir/provision.sh" > "$test_dir/random-base" 2>/dev/null
[ "$(cat "$test_dir/random-base")" = fe:11:22:33:44:f0 ]
[ "$(dd if="$TEST_EEPROM_PATH" bs=1 count=8 2>/dev/null | hexdump -v -e '1/1 "%02x"')" = ffffffffffffffff ]
mac_make_record fe:ff:ff:ff:ff:ff > "$test_dir/record"
mac_finish_record "$test_dir/record"
dd if="$test_dir/record" of="$sys/bus/i2c/devices/3-0057/eeprom" bs=1 seek=64 conv=notrunc 2>/dev/null
if sh "$test_dir/apply.sh" --apply >/dev/null 2>&1; then echo 'FAIL: invalid range applied'; exit 1; fi
[ ! -e "$sys/ip-calls" ]
# A separate fixture verifies hardware naming without touching host interfaces.
name_sys="$test_dir/name-sys"
mkdir -p "$name_sys/firmware/devicetree/base" "$name_sys/class/net"
printf 'Bananapi BPI-R4 Pro 8X\000' > "$name_sys/firmware/devicetree/base/model"
for index in 0 1 2; do
	node="$name_sys/firmware/devicetree/base/soc/ethernet@15100000/mac@$index"
	mkdir -p "$node" "$name_sys/class/net/eth$index"
	printf 'mediatek,eth-mac\000' > "$node/compatible"
	mac_bytes 0 0 0 "$index" > "$node/reg"
	ln -s "$node" "$name_sys/class/net/eth$index/of_node"
	printf '0x0\n' > "$name_sys/class/net/eth$index/flags"
done
for n in lan1 lan2 lan3 lan4 lan5 lan6 fpc; do
	node="$name_sys/firmware/devicetree/base/$n"
	mkdir -p "$node" "$name_sys/class/net/$n"
	printf '%s\000' "$n" > "$node/label"
	ln -s "$node" "$name_sys/class/net/$n/of_node"
	printf '0x0\n' > "$name_sys/class/net/$n/flags"
done
sed "s|/sys|$name_sys|g" "$repo/packages/bpi-r4pro8x-mac/names.sh" > "$test_dir/names.sh"
cat > "$test_dir/bin/ip" <<'MOCK_NAMES'
#!/bin/sh
set -eu
[ "$1 $2 $3 $5" = 'link set dev name' ]
[ ! -e "$TEST_MAC_SYS_DIR/class/net/$6" ]
mv "$TEST_MAC_SYS_DIR/class/net/$4" "$TEST_MAC_SYS_DIR/class/net/$6"
printf '%s\n' "$*" >> "$TEST_MAC_SYS_DIR/ip-calls"
MOCK_NAMES
export TEST_MAC_SYS_DIR="$name_sys"
printf '0x1\n' > "$name_sys/class/net/eth0/flags"
if sh "$test_dir/names.sh" >/dev/null 2>&1; then echo 'FAIL: active conduit renamed'; exit 1; fi
[ ! -e "$name_sys/ip-calls" ]
printf '0x0\n' > "$name_sys/class/net/eth0/flags"
mkdir "$name_sys/class/net/wan"
if sh "$test_dir/names.sh" >/dev/null 2>&1; then echo 'FAIL: foreign WAN overwritten'; exit 1; fi
[ ! -e "$name_sys/ip-calls" ]
rmdir "$name_sys/class/net/wan"
sh "$test_dir/names.sh" >/dev/null
[ "$(basename "$(readlink -f "$name_sys/class/net/eth0/of_node")")" = mac@2 ]
[ "$(basename "$(readlink -f "$name_sys/class/net/eth1/of_node")")" = mac@0 ]
[ "$(basename "$(readlink -f "$name_sys/class/net/wan/of_node")")" = mac@1 ]
[ "$(wc -l < "$name_sys/ip-calls")" -eq 6 ]
sh "$test_dir/names.sh" >/dev/null
[ "$(wc -l < "$name_sys/ip-calls")" -eq 6 ]
echo 'PASS: MAC records, device discovery, hardware naming and isolated boot-reader integration'
