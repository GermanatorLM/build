# R4 Pro 8X community build

Community build by GermanatorLM, based on Armbian.
Target: R4 Pro **8X**, **8 GiB DDR4**, **BE14 Rev. 1.0** only.
System: Debian Trixie Minimal, Linux **7.3**.

Follow the [Armbian host requirements](https://docs.armbian.com/build-framework/getting-started/).
Use Debian 13 inside Docker on this Linux host.
Reserve about 50 GB of disk space.
The build configuration disables BTF for hosts with limited RAM.
Use `CPUTHREADS=2 FORCE_USE_RAMDISK=no` on the current host.
Keep `SHARE_LOG=no`. Logs remain under `output/logs`.

**Development only. No image has hardware acceptance. Keep all test images private.**

## Build

Build locally first. Actions builds remain deferred until included usage is available.
Use `GermanatorLM/armbian-r4pro-build-private` for later GitHub builds.
Install `tools/r4pro8x/private-build.yml` as `.github/workflows/build.yml` there.
Start the workflow manually with a full `GermanatorLM/build` commit SHA.
The workflow rejects public repositories and unapproved resource inputs.
It uses the standard `ubuntu-24.04` runner and records the runner image version.
Actions use fixed commit SHAs. No workflow publishes releases.

Verify included minutes and free storage before every build.
Keep an Actions budget that stops paid usage at zero dollars.
The job limit is 300 minutes. Reserve at least 320 minutes.
The artifact limit is 450 MiB. Retention is one day. Download artifacts before expiration.
Oversized artifacts stop the upload. Use approved private storage before increasing this limit.

For a local SD build on a supported Debian/Ubuntu host or Debian build container:

```bash
mkdir -p userpatches
cp config/optional/boards/bananapir4pro8x/build.conf userpatches/config-r4pro8x.conf
./compile.sh r4pro8x R4PRO_BOOT_MEDIA=sd PREFER_DOCKER=no
```

For experimental eMMC **bootloader packages only**:

```bash
./compile.sh uboot r4pro8x R4PRO_BOOT_MEDIA=emmc PREFER_DOCKER=no
```

The SD writer refuses eMMC packages. No eMMC installer is supplied yet.
Do not use the generic Armbian installer for this board before eMMC validation.
SD and eMMC share a controller. Do not assume simultaneous access.
SPI-NAND installation is outside this project stage.

## Sources

See [sources.lock.json](../../../config/optional/boards/bananapir4pro8x/sources.lock.json).
Every firmware file has a source URL, destination, and SHA256.
Kernel, U-Boot, and TF-A use full commit SHAs.
Archive SHA256 values identify the downloaded source archives.
The Linux archive matches the kernel.org SHA256 listing.
GitHub archive hashes identify bytes; they are not signatures.

Frank's `7.3-rc` commit is `32b3bd5458be1657056f9852b0b309f73b65a4d7`.
Its upstream base is **7.3-rc1**, not final 7.3.
The board patch ports that range onto final Linux 7.3.
[frank-commits.json](frank-commits.json) preserves original authors and commit messages.

The patch retains final 7.3 EEE checks and netdev/work lifetime fixes.
It omits build scripts, firmware blobs, defconfigs, and `.orig`/`.rej` files.
It omits the unvalidated PCIe Wi-Fi hardware reset sequence.
Already merged GPIO and xHCI fixes remain unchanged.
The port includes Frank's dependent network changes and experimental switch support.
No feature claim follows from inclusion alone.

The separate mt7996 patch suppresses recovery before hardware registration.
It returns the original timeout. It does **not** fix intermittent BE14 initialization.
Do not force the 233 or 444 firmware selection.
Both firmware sets include internal-FEM EEPROM defaults.
No board EEPROM writer or personal calibration data is included.

TF-A uses `DRAM_USE_DDR4=1 DDR4_4BG_MODE=1` for both media.
TF-A builds `fiptool` through its top-level target.
U-Boot probes memory up to 8 GiB. Verify actual RAM through UART and Linux.
U-Boot uses a volatile environment and loads extlinux from SD partition five.
The overlay address is `0x62080000`.
The image includes Aeonsemi firmware in the initramfs.
Ethernet SRAM and the PCA9555 driver are enabled.

## First boot and updates

Keep Armbian first-login setup enabled.
Ethernet uses DHCP clients through systemd-networkd.
There is no configured router, forwarding rule, bridge, Wi-Fi client, or AP.
Install antennas before any scan, client connection, or AP test.
The image contains no custom password, SSH host key, MAC address, or calibration backup.
Verify the completed image before hardware use and publication.

Debian security updates use APT.
The image excludes the Armbian repository and pins board packages against automatic replacement.
Install reviewed board packages explicitly from versioned community releases.
Keep the image, kernel, DTB, BSP, firmware manifest, and bootloader package versions together.
Do not automatically write a bootloader during package updates.

## Release blockers

Complete [hardware-tests.md](hardware-tests.md) for the final image SHA256.
The intermittent WLAN startup failure blocks release.
Verify firmware licenses and the TF-A DDR initialization blobs before redistribution.
Include original license texts and complete corresponding sources with the release.
Audit the finished image for credentials, host keys, wireless profiles, and device identities.
Record measured Ethernet speeds. Do not advertise untested speeds.

Publish only the exact accepted private artifacts and their SHA256 checksums.
Include image, board packages, sources, source manifest, installation guide, and test report.
Never rebuild during promotion.
Official Armbian inclusion and a community APT repository remain future work.

## Status

Board integration and the private workflow are under development.
Kernel compilation does not prove a bootable image or working hardware.
SD hardware tests, eMMC installation, and radio acceptance remain pending.
No release approval exists.
