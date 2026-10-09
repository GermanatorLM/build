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
No concrete board MAC is embedded in the image or script.

## Armbian boot reader

`apply.sh --show` reads and validates the record without changing interfaces.
`apply.sh --apply` sets addresses before network startup. It refuses already-UP interfaces.
The board-local systemd service loads at24 and runs before network-pre.target and supported network managers.
An empty EEPROM record leaves the existing boot behaviour unchanged.
A corrupt record causes failure without applying that record.

`eth0` receives the stored base MAC.
Random `eth1` and `eth2` receive separate, deterministic, locally administered addresses.
These addresses use SHA256 of the base MAC and controller index.
Non-random secondary addresses remain unchanged.
Network configuration applied later can override these addresses.
The reader never writes EEPROM. No kernel MAC parser or Device Tree format change is required.

## Verification status

Local tests cover record round trips, corrupt records, truncation, MAC validation, and device discovery.
The tests exclude ambiguous EEPROMs and the Wi-Fi EEPROM.
Shell syntax and ShellCheck are checked locally.
OpenWrt import, physical write protection, EEPROM programming, and Armbian boot integration remain hardware tests.
