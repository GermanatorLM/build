# R4 Pro 8X EEPROM MAC provisioning

This package supports the audited vendor OpenWrt eMMC layout.
Run the importer from an eMMC or NAND boot. SD boot cannot access eMMC.
No script writes eMMC, NAND, bootloader environments, or Wi-Fi EEPROMs.
The importer writes only the board EEPROM after explicit confirmation.
OpenWrt itself can write its mounted filesystems during boot.

## EEPROM identity

Puya P24C02A provides 256 bytes with eight-byte pages.
[Manufacturer datasheet](https://www.puyasemi.com/download_path/%E6%95%B0%E6%8D%AE%E6%89%8B%E5%86%8C/EEPROM%20%E8%8A%AF%E7%89%87/P24C02A_Datasheet_V2.0.pdf).
The audited Device Tree names `p24c02`, address `0x57`, size 256, and page size eight.
Its compatible string is `atmel,24c02`. That string does not identify the physical manufacturer.
[The R4 Pro manufacturer guide explicitly names P24C02A](https://docs.banana-pi.org/en/BPI-R4_Pro/GettingStarted_BPI-R4_Pro#_eeprom).
Confirm the board variant against this documentation or its chip marking before writing.
Check board-specific write protection before any retry.
Do not apply the normal R4 LED write-protect workaround without checking the Pro schematic.

The importer discovers the at24 device through its Device Tree node, not a fixed I2C bus number.
It supports Frank's `pagesize` property and the vendor's `page-size` spelling.
The vendor spelling does not configure at24 page writes. The importer therefore retains one-byte writes.
It excludes the Wi-Fi EEPROM at `0x51`.
It accepts only the known `R4PRO8X-` board header and an empty target region.
Unknown headers, occupied regions, and ambiguous devices cause refusal.
Other EEPROM layouts require separate support. The script does not overwrite ONIE TLV records.

## Import with vendor OpenWrt

Copy `common.sh` and `import-openwrt.sh` into the same directory on OpenWrt.
Run as root. Install `fw_printenv` if unavailable.
The script uses POSIX shell and standard OpenWrt utilities. Python and Bash are unnecessary.
The vendor image lacks `od` and `cksum`. The scripts use `hexdump` and an AWK checksum implementation instead.

Preview:

```sh
sh import-openwrt.sh
```

The importer requires an MMC device of type `MMC`, never `SD`.
It checks the vendor environment partition: start sector 8192, length 1024 sectors.
It snapshots both 256 KiB environment slots at offsets `0x400000` and `0x440000`.
`fw_printenv` validates the snapshot CRC and redundant slot selection.
Any environment warning causes refusal, including fallback to defaults.
The script does not use the running NAND environment or the interface MAC as a substitute.

After checking the preview and physical chip, write with a new persistent backup directory:

```sh
sh import-openwrt.sh --write --confirm-chip P24C02A \
  --confirm-mac YOUR_PREVIEW_MAC --backup-dir /mnt/usb/r4pro8x-mac-backup
```

Use a mounted USB filesystem for the backup. `/tmp` is rejected.
The backup includes the full EEPROM, eMMC environment snapshot, record, and SHA256 checksums.
The environment snapshot can contain secrets. Keep the directory private and copy it off the board.
The script compares the complete EEPROM after writing. All bytes outside the record must remain unchanged.
It writes through at24 with one-byte operations. It does not bypass write protection.
Identical records cause no additional write. Different existing records cause refusal.
On failure, inspect the saved data. Do not repeat or restore automatically.

## Record format

| EEPROM offset | Length | Content |
| --- | --- | --- |
| `0x40` | 6 | Binary base MAC from eMMC `ethaddr` |
| `0x46` | 2 | Reserved, `ff ff` |
| `0x48` | 4 | ASCII `R4M1` |
| `0x4c` | 4 | Big-endian POSIX `cksum` of the preceding 12 bytes |

The record occupies two eight-byte pages. The checksum page is written last.
The checksum detects incomplete writes. It is not an authenticity check.
The importer preserves the manufacturer data before `0x40` and all data from `0x50` onward.
These offsets are a port-specific format, not an existing manufacturer standard.

The source MAC remains a locally stored identity, not a proven globally unique factory assignment.
Cloned vendor environments can produce duplicate identities. Check uniqueness when provisioning multiple boards.
The importer embeds no individual board MAC. The boot reader includes the explicitly requested fixed fallback.

## Armbian boot reader

`apply.sh --show` reads and validates the record without changing interfaces.
`apply.sh --apply` sets addresses before network startup. It refuses already-UP interfaces.
The board-local systemd service loads at24 and runs before network-pre.target and supported network managers.
A valid EEPROM record supplies the base MAC.
An unavailable EEPROM, empty record, unreadable record, or invalid checksum selects `da:68:a5:94:9a:ee` as fallback.
The reader logs the selected source and warns about fixed fallback collisions.
It generates sequential addresses with byte carry, not SHA256.

| Interface | Role | Offset | Reference address |
| --- | --- | --- | --- |
| `eth0` | Management switch conduit | +0 | `da:68:a5:94:9a:ee` |
| `eth1` | 10G WAN RJ45 / SFP mux | +1 | `da:68:a5:94:9a:ef` |
| `eth2` | MaxLinear switch conduit | +2 | `da:68:a5:94:9a:f0` |
| `mgmt` | Management RJ45 | +3 | `da:68:a5:94:9a:f1` |
| `lan0` | 2.5G RJ45 | +4 | `da:68:a5:94:9a:f2` |
| `lan1` | 2.5G RJ45 | +5 | `da:68:a5:94:9a:f3` |
| `lan2` | 2.5G RJ45 | +6 | `da:68:a5:94:9a:f4` |
| `lan3` | 2.5G RJ45 | +7 | `da:68:a5:94:9a:f5` |
| `lan4` | 10G LAN RJ45 / SFP mux | +8 | `da:68:a5:94:9a:f6` |

The mapping follows [Frank's board DT](https://github.com/frank-w/BPI-Router-Linux/tree/6.18-main/arch/arm64/boot/dts/mediatek).
Muxed RJ45 and SFP connections share their interface identity. Separate simultaneous identities require separate interfaces.
The reader waits up to 20 seconds for all nine interfaces, then checks every interface before assignment.
Missing or already-UP interfaces cause refusal without applying the plan.
Overflow or a multicast boundary also causes refusal before assignment.
The reader replaces existing MACs on all nine DOWN interfaces, including non-random addresses.
Network configuration applied later can override these addresses.
The reader never writes EEPROM. No kernel MAC parser or Device Tree format change is required.

Every board needs a unique nine-address block. Adjacent EEPROM base MACs can produce overlapping blocks.
All boards using the fixed fallback receive identical addresses. Do not connect those boards to the same Layer-2 network.

## Verification status

Local tests cover record round trips, corrupt records, truncation, MAC validation, and device discovery.
The tests exclude ambiguous EEPROMs and the Wi-Fi EEPROM.
Shell syntax and ShellCheck are checked locally.
The dry-run import passes on vendor OpenWrt 24.10-SNAPSHOT with BusyBox ash 1.36.1.
EEPROM programming passes on the target board with a persistent USB backup and complete readback comparison.
The repeat import performs no write. The reader validates the programmed record on vendor OpenWrt.
The hardware test changes only offsets `0x40` through `0x4f`. All other EEPROM bytes remain unchanged.
The record survives a cold boot into vendor SPI-NAND OpenWrt.
The importer reads the eMMC environment from that NAND boot and detects the matching record without writing.
The previous three-controller reader preview passes under both vendor boot modes.
Local fixtures cover the new nine-interface sequence, byte carry, fallback, range rejection, and interface readiness.
Initial programming from NAND remains untested.
The new nine-interface assignment and Armbian boot integration remain hardware tests.
