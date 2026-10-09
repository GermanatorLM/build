#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Test extracted, patched kernel functions with simulated data sources.
set -euo pipefail
ulimit -c 0

[[ $# == 1 ]] || { echo "Usage: $0 <patched-kernel-source>" >&2; exit 2; }
mt76="$1/drivers/net/wireless/mediatek/mt76"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

extract_function() {
	awk -v name="$2" '
		$0 ~ "^(static int )?" name "\\(" {
			found=1
			if ($0 !~ /^static int /) print "int"
		}
		found {
			print
			line=$0
			opens=gsub(/\{/, "", line)
			closes=gsub(/\}/, "", line)
			depth+=opens-closes
			if (opens) started=1
			if (started && depth==0) { complete=1; exit }
		}
		END { if (!complete) exit 1 }
	' "$1"
}

{
	cat <<'C'
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef uint8_t u8;
typedef uint32_t u32;
#define GFP_KERNEL 0
#define MT7996_EEPROM_SIZE 7680
#define MT7996_EEPROM_BLOCK_SIZE 16
#define DIV_ROUND_UP(n, d) (((n) + (d) - 1) / (d))
struct mt76_dev { void *dev; struct { int size; u8 *data; } eeprom; };
struct mt7996_dev { struct mt76_dev mt76; bool flash_mode; };
static int file_ret, of_ret, file_calls, of_calls, efuse_calls;
static bool valid_file, no_memory, efuse_empty, used_default;
static void *devm_kzalloc(void *dev, int len, int flags)
{
    (void)dev; (void)flags;
    return no_memory ? NULL : calloc(1, len);
}
static int mt76_get_eeprom_file(struct mt76_dev *dev, int len)
{
    file_calls++;
    if (file_ret) return file_ret;
    memset(dev->eeprom.data, 0xa5, len);
    dev->eeprom.data[0] = valid_file ? 0x96 : 0;
    return 0;
}
static int mt76_get_of_eeprom(struct mt76_dev *dev, void *data, int len)
{
    (void)dev;
    of_calls++;
    if (of_ret) return of_ret;
    memset(data, 0x5a, len);
    ((u8 *)data)[0] = 0x96;
    return 0;
}
static int mt7996_check_eeprom(struct mt7996_dev *dev)
{
    return dev->mt76.eeprom.data[0] == 0x96 ? 0 : -EINVAL;
}
static int mt7996_mcu_get_eeprom_free_block(struct mt7996_dev *dev, u8 *blocks)
{
    (void)dev;
    efuse_calls++;
    *blocks = efuse_empty ? 59 : 0;
    return 0;
}
static int mt7996_mcu_get_eeprom(struct mt7996_dev *dev, int offset,
                                  void *unused, u32 len)
{
    (void)unused;
    if (!offset) len = MT7996_EEPROM_BLOCK_SIZE;
    memset(dev->mt76.eeprom.data + offset, 0x3c, len);
    dev->mt76.eeprom.data[0] = 0x96;
    return 0;
}
static int mt7996_eeprom_check_or_use_default(struct mt7996_dev *dev, bool use_default)
{
    used_default = use_default;
    if (use_default) memset(dev->mt76.eeprom.data, 0xdd, MT7996_EEPROM_SIZE);
    return 0;
}
C
	extract_function "$mt76/eeprom.c" mt76_eeprom_init
	extract_function "$mt76/mt7996/eeprom.c" mt7996_eeprom_load
	cat <<'C'
static void test(const char *name, int file_status, int of_status, bool valid,
                 bool empty, bool oom, int expected_ret, int expected_of,
                 int expected_efuse, bool expected_flash, bool expected_default,
                 u8 expected_marker)
{
    struct mt7996_dev dev = {0};
    file_ret = file_status; of_ret = of_status; valid_file = valid;
    efuse_empty = empty; no_memory = oom;
    file_calls = of_calls = efuse_calls = 0; used_default = false;
    assert(mt7996_eeprom_load(&dev) == expected_ret);
    assert(file_calls == (oom ? 0 : 1));
    assert(of_calls == expected_of);
    assert(efuse_calls == expected_efuse);
    assert(dev.flash_mode == expected_flash);
    assert(used_default == expected_default);
    if (!oom) assert(dev.mt76.eeprom.data[100] == expected_marker);
    free(dev.mt76.eeprom.data);
    printf("PASS: %s\n", name);
}
int main(void)
{
    test("valid RF file survives", 0, -ENOENT, true, false, false,
         0, 0, 0, true, false, 0xa5);
    test("missing RF file uses eFuse", -ENOENT, -ENOENT, true, false, false,
         0, 1, 1, false, false, 0x3c);
    test("rejected RF file uses eFuse", -EINVAL, -ENOENT, true, false, false,
         0, 1, 1, false, false, 0x3c);
    test("invalid RF chip ID uses eFuse", 0, -ENOENT, false, false, false,
         0, 0, 1, false, false, 0x3c);
    test("missing RF file retains OF data", -ENOENT, 0, true, false, false,
         0, 1, 0, true, false, 0x5a);
    test("empty eFuse uses defaults", -ENOENT, -ENOENT, true, true, false,
         0, 1, 1, false, true, 0xdd);
    test("allocation failure propagates", 0, -ENOENT, true, false, true,
         -ENOMEM, 0, 0, false, false, 0);
    return 0;
}
C
} > "$test_dir/test.c"

"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -Wno-sign-compare "$test_dir/test.c" -o "$test_dir/test"
"$test_dir/test"
