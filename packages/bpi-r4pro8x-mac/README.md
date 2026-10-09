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
No individual board MAC is embedded in the importer or boot reader.

## Armbian boot reader

`apply.sh --show` reads and validates the record without changing interfaces.
`apply.sh --apply` sets addresses before network startup. It refuses already-UP interfaces.
The board-local naming service runs before the MAC service and supported network managers.
The MAC service loads at24 and requires successful hardware naming.
A valid EEPROM record supplies the base MAC.
An empty record triggers one-time random EEPROM provisioning during `--apply`.
Preview mode reports an unprovisioned record without generating or storing an address.
Missing EEPROMs, unknown occupied layouts, and corrupt records cause refusal. There is no shared fixed fallback.
It generates sequential addresses with byte carry, not SHA256.

| Interface | Role | Offset | Reference address |
| --- | --- | --- | --- |
| `eth0` | GMAC2 to MaxLinear switch | +0 | `da:68:a5:94:9a:ee` |
| `eth1` | GMAC0 to internal MT7988 switch | +1 | `da:68:a5:94:9a:ef` |
| `wan` | GMAC1 to 10G RJ45 / SFP mux | +2 | `da:68:a5:94:9a:f0` |
| `lan1` | MaxLinear 2.5G port 0 | +3 | `da:68:a5:94:9a:f1` |
| `lan2` | MaxLinear 2.5G port 1 | +4 | `da:68:a5:94:9a:f2` |
| `lan3` | MaxLinear 2.5G port 2 | +5 | `da:68:a5:94:9a:f3` |
| `lan4` | MaxLinear 2.5G port 3 | +6 | `da:68:a5:94:9a:f4` |
| `lan5` | Internal switch 1G RJ45 port 0 | +7 | `da:68:a5:94:9a:f5` |
| `lan6` | MaxLinear 10G RJ45 / SFP mux | +8 | `da:68:a5:94:9a:f6` |
| `fpc` | Internal switch 1G FPC port 3 | +9 | `da:68:a5:94:9a:f7` |

The board-local 8X DT patch assigns front-panel labels and enables the existing port-3 PHY for FPC.
[The manufacturer identifies FPC as internal switch port 3](https://docs.banana-pi.org/en/BPI-R4_Pro/GettingStarted_BPI-R4_Pro#_1g_eth_fpc_connector).
`names.sh` identifies GMACs by their Device Tree node and `reg`, never by MAC or discovery order.
It stages all three GMACs through temporary names before assigning `eth0`, `eth1`, and `wan`.
Occupied target names, ambiguous identities, active interfaces, or unexpected DSA labels cause refusal.
An interrupted rename requires inspection. The MAC service does not run after a naming failure.
The hardware GMAC numbers and Device Tree Ethernet aliases remain unchanged.
Muxed RJ45 and SFP connections share their interface identity. Separate simultaneous identities require separate interfaces.
The services wait up to 20 seconds for their expected interfaces before assignment.
Missing or already-UP interfaces cause refusal without applying the plan.
Overflow or a multicast boundary also causes refusal before assignment.
The reader replaces existing MACs on all ten DOWN interfaces, including non-random addresses.
Network configuration applied later can override these addresses.
Armbian's existing Netplan matches cover `eth*`, `lan*`, and `wan*`.
Configure `fpc` explicitly when needed. This change does not create bridges or router rules.
Wi-Fi remains entirely under driver control. No WLAN MACs or calibration data are modified.

## Random EEPROM provisioning

The boot reader invokes `provision.sh` only after verifying all interfaces are present and DOWN.
The helper requires the audited board EEPROM, an empty `0x40..0x4f` region, and the known vendor header.
A fully erased 256-byte EEPROM is also supported. Other occupied layouts are preserved.
It reads six bytes from `/dev/random`, sets local/unicast bits, and aligns the base to a 16-address block.
Random block collisions remain theoretically possible. Imported bases can overlap and require external uniqueness checks.
Existing valid records are reused without EEPROM writes.
The helper serializes its own invocations using `flock`.
Do not run the OpenWrt importer concurrently; it does not share that lock.

Private backups reside in `/var/lib/bpi-r4pro8x-mac/provision.*`, managed by the service's `StateDirectory`.
Backups contain the complete EEPROM before and after writing, the record, source metadata, and SHA256 checksums.
The helper flushes the backup and checks for concurrent EEPROM changes before writing through at24.
It preserves every byte outside `0x40..0x4f` and verifies the complete readback.
Missing entropy, unavailable backup storage, write protection, or readback mismatches cause failure without network MAC assignment.
An interrupted or mismatching record is not overwritten automatically. Inspect the backup before recovery.
The scripts never alter eMMC/NAND environments or Wi-Fi EEPROMs.

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
Local fixtures cover ten-interface sequences, hardware naming, byte carry, random provisioning, and interface readiness.
They verify reuse, private backups, readback failure, and rejection of corrupt or unknown layouts.
Initial programming from NAND remains untested.
The new ten-interface assignment, FPC link, random provisioning, and Armbian boot integration remain hardware tests.
