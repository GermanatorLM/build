# R4 Pro 8X community build

Community build by GermanatorLM, based on Armbian.
Target: R4 Pro **8X**, **8 GiB DDR4**, **BE14 Rev. 1.0** only.
System: Debian Trixie Minimal, Linux **7.3**.

Follow the [Armbian host requirements](https://docs.armbian.com/build-framework/getting-started/).
Use Debian 13 inside Docker on this Linux host.
Reserve about 50 GB of disk space.
The build requires `KERNEL_BTF=yes` for BPF-LSM support.
BTF generation increases build memory and disk requirements.
Use swap and reduce parallel jobs when memory is limited.
Use `CPUTHREADS=6 FORCE_USE_RAMDISK=no` on the current host.
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
The writer accepts build loop devices only.
Do not use the generic Armbian installer for this board before eMMC validation.
SD and eMMC share a controller. Do not assume simultaneous access.
SPI-NAND installation is outside this project stage.
The 8X device tree enables SPI-NAND and exposes the inherited BL2 and UBI MTD partitions.
The board patch removes automatic UBI attachment. Explicit UBI attachment remains available.
No backup prerequisite or NAND installation workflow is imposed.

## Userspace defaults

The default hostname is `bpi`, following Frank's image configuration.
Set `HOST` explicitly to select another name.
DHCP may supply a transient hostname. `polkitd` enables the packaged systemd-networkd authorization rule.
SSH generates missing host keys before startup, independently of systemd first-boot detection.
Armbian firstrun preserves those keys. Images still contain no host keys.
The serial-only board skips console font setup.
An empty CPU governor setting preserves the kernel default.
The ext4 profile masks journal CoW rules, which cannot apply to the ramlog symlink.
Other journal permission rules remain active.
The board excludes unsupported MTK_SOCINFO. MediaTek eFuse access remains enabled.
The first boot generates nine unique, locally administered unicast MAC addresses for built-in Ethernet devices.
The board stores the addresses in `/var/lib/r4pro8x/mac-addresses.json` and reuses them before networkd starts.
Device Tree paths select the interfaces. USB Ethernet, BE14 and modem identities remain unchanged.
Generated link files also preserve the addresses when a built-in interface reappears.
Invalid state blocks networkd startup. Preserve the state file for recovery instead of generating replacement identities.
Image cleanup removes generated MAC state and link files.
Kernel messages about initial random MAC addresses can precede the userspace assignment.

Frank's hostname reference: [BPI-Router-Images at 8ff8bfb](https://github.com/frank-w/BPI-Router-Images/blob/8ff8bfb8de1b199c6ca425b2baa592ced277e5c6/buildchroot.sh#L171).
SoC information reference: [OpenWrt 8097cbc](https://github.com/openwrt/openwrt/commit/8097cbc14a21d5ae6867ea76d5d4ba4b19e579bd).

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

The MDIO patch ports patch 984 from [OpenWrt PR #25841](https://github.com/openwrt/openwrt/pull/25841).
Its source revision is `79d2df17ad98373c84bfcb412fdf1026519ee09d`.
The reset callback sleeps for 150 ms before the MDIO scan.
This targets stale Aeonsemi PHY IDs on the 8X board.
Hardware verification remains pending. This patch does not address BE14 initialization.

The PCIe patches port patches 991 and 992 from the same PR.
Their source revision is `81fcdc849ae8905e1b4ab4f43036de6d5e7576e8`.
Each MT7988 PCIe host declares its own PEXTP reference clock.
The existing driver enables listed clocks before link training.
Binding validation and SD/eMMC DT compilation pass. Hardware verification remains pending.
No `CLK_IS_CRITICAL` workaround or CPUfreq change accompanies this port.

The separate mt7996 patch suppresses recovery before hardware registration.
It returns the original timeout. It does **not** fix intermittent BE14 initialization.
Do not force the 233 or 444 firmware selection.
Both firmware sets include internal-FEM EEPROM defaults.
No board EEPROM writer or personal calibration data is included.
Firmware downloads use `cache/download/r4pro8x-firmware`, indexed by SHA256.
Every installation verifies cached bytes against the locked checksum.
Verified cached files support builds during network failures.

TF-A uses `DRAM_USE_COMB=1 DDR4_4BG_MODE=1` for both media, matching Frank's MT7988 build configuration.
The first hardware boot fails DDR calibration with the forced `DRAM_USE_DDR4=1` configuration.
One observed SD start passes DDR initialization and reports 8 GiB with the combined configuration.
Repeated starts and full memory testing remain pending.
TF-A builds `fiptool` through its top-level target.
U-Boot probes memory up to 8 GiB. Verify actual RAM through UART and Linux.

U-Boot enables `DM_RNG` and `RNG_MTK_V2` for SD and eMMC builds.
The port includes Daniel Golle's secure-monitor RNG driver and MT7988 node from Frank's tree.
The existing TF-A TRNG service supplies fresh hardware randomness.
U-Boot passes a 64-bit `/chosen/kaslr-seed` to Linux during boot.
No static seed is stored in the image or environment.
Verify KASLR activation on hardware. Do not record seed values in test logs.
U-Boot uses a volatile environment and loads extlinux from SD partition five.
The overlay address is `0x62080000`.
The default LAN6 overlay selects the RJ45 PHY through GPIO54.
For LAN6 SFP tests, replace `8x-lan-phy` with `8x-lan-sfp` in the extlinux overlay path.
Keep the boot medium overlay. Never load both LAN6 overlays together.
The default `R4PRO_NVME_SLOT=both` selects both M-key sockets, CN13 and CN14.
Use `cn13` or `cn14` for individual slot tests. Use `none` to omit both slot overlays.
The M-key selection excludes the alternative PCIe paths to B-key sockets CN15 and CN18.
Both slot overlays are included for later extlinux configuration.
Example: `./compile.sh r4pro8x R4PRO_BOOT_MEDIA=sd R4PRO_NVME_SLOT=cn14 PREFER_DOCKER=no`.

The image includes Aeonsemi firmware in the initramfs.
Ethernet SRAM and the PCA9555 driver are enabled.

The image backports alsa-utils commit `f90124c73edd050b24961197a4abcf17e53b41a8`.
The restore rule defines distinct entry and standard restore labels.
The backport accepts the Debian partial fix and the complete upstream fix.

See [pcie.md](pcie.md) for the current PCIe state and controlled comparison tests.

## CPU frequency driver

The board profile follows Frank's R4 configuration and enables the MediaTek CPUfreq drivers.
The generic CPUFREQ_DT driver and its platform device are disabled.
The board hook enforces those settings for reused configurations.
MediaTek CCI devfreq, CPUfreq statistics, and governor settings remain enabled.

The running baseline already uses mtk-cpufreq at 800, 1100, 1500, and 1800 MHz.
This change removes duplicate registration. It does not promise a performance increase.
If the MediaTek driver fails, the generic driver cannot provide an alternative path.
Keep this configuration specific to the isolated board family.
Verify scaling, governors, and temperature behavior on the next hardware candidate.

Frank source: [R4 defconfig](https://github.com/frank-w/BPI-Router-Linux/blob/32b3bd5458be1657056f9852b0b309f73b65a4d7/arch/arm64/configs/mt7988a_bpi-r4_defconfig).

## ACL and BPF-LSM support

The kernel enables POSIX ACLs for ext4, tmpfs, and devtmpfs.
The kernel enables BPF-LSM, securityfs, and BTF metadata.
The default LSM list contains `bpf`. The capability module remains active.
No additional access policy is installed.
Do not override the boot LSM list with a value that excludes `bpf`.

After booting the new kernel, check `/sys/kernel/security/lsm` and `/sys/kernel/btf/vmlinux`.
Mount securityfs when the LSM list is unavailable.
Repeat ACL tests on ext4, `/run`, `/dev`, and `/dev/shm`.
Test BPF-LSM attachment and systemd `RestrictFileSystems=` enforcement before accepting this feature.
Configuration checks do not prove runtime enforcement.

## First boot and updates

Keep Armbian first-login setup enabled.
Ethernet uses DHCP clients through systemd-networkd.
The DHCP configuration includes `e*`, `lan*`, `wan*`, and `sfp-*` interface names.
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
