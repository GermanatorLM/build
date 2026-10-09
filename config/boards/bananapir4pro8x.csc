# Banana Pi BPI-R4 Pro 8X (MT7988A, 8 GiB DDR4)
BOARD_NAME="Banana Pi R4 Pro 8X"
BOARD_VENDOR="sinovoip"
BOARDFAMILY="filogic-r4pro"
BOARD_MAINTAINER=""
INTRODUCED="2025"

KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"

# U-Boot target added by patch/u-boot/u-boot-filogic/451-add-bpi-r4pro-8x.patch
BOOTCONFIG="mt7988a_bpir4pro_sd_defconfig"

# Linux base DT for the physical 8X board. Storage selection is applied with
# the R4-Pro SD overlay below.
BOOT_FDT_FILE="mediatek/mt7988a-bananapi-bpi-r4-pro-8x.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n1 earlyprintk loglevel=8 initcall_debug=0 swiotlb=512 cgroup_enable cgroup_memory=1 init=/sbin/init"
HAS_VIDEO_OUTPUT="no"

# The 6.18 R4-Pro base DT deliberately leaves the shared SD/eMMC controller
# unconfigured. For the first bring-up image we always boot from SD and apply
# Frank Wunderlich's matching storage overlay explicitly through extlinux.
function post_family_tweaks__bpi_r4pro_8x() {
	local extlinux_conf="${SDCARD}/boot/extlinux/extlinux.conf"
	local sd_overlay="/boot/dtb/mediatek/mt7988a-bananapi-bpi-r4-pro-sd.dtbo"

	display_alert "${BOARD}" "Applying BPI-R4 Pro 8X image tweaks" "info"

	# Provision an empty board EEPROM once, before network startup.
	local mac_package="${SRC}/packages/bpi-r4pro8x-mac"
	install -d "${SDCARD}/usr/lib/bpi-r4pro8x-mac" \
		"${SDCARD}/usr/lib/systemd/system" "${SDCARD}/etc/systemd/system/multi-user.target.wants"
	install -m 0644 "${mac_package}/common.sh" "${mac_package}/apply.sh" "${mac_package}/names.sh" \
		"${mac_package}/import-openwrt.sh" "${mac_package}/provision.sh" "${SDCARD}/usr/lib/bpi-r4pro8x-mac/"
	install -m 0644 "${mac_package}/bpi-r4pro8x-mac.service" "${SDCARD}/usr/lib/systemd/system/"
	install -m 0644 "${mac_package}/bpi-r4pro8x-names.service" "${SDCARD}/usr/lib/systemd/system/"
	ln -sf /usr/lib/systemd/system/bpi-r4pro8x-names.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/bpi-r4pro8x-names.service"
	ln -sf /usr/lib/systemd/system/bpi-r4pro8x-mac.service \
		"${SDCARD}/etc/systemd/system/multi-user.target.wants/bpi-r4pro8x-mac.service"

	# Same MT7988 WO firmware blobs used by Armbian's existing BPI-R4 target.
	mkdir -p "${SDCARD}/lib/firmware/mediatek/mt7988"
	cp -v "${SRC}/packages/blobs/filogic/firmware/mediatek/mt7988/mt7988_wo_0.bin" 		"${SDCARD}/lib/firmware/mediatek/mt7988/mt7988_wo_0.bin"
	cp -v "${SRC}/packages/blobs/filogic/firmware/mediatek/mt7988/mt7988_wo_1.bin" 		"${SDCARD}/lib/firmware/mediatek/mt7988/mt7988_wo_1.bin"

	# R4-Pro-specific PHY and Wi-Fi 7 firmware. The installer uses an immutable
	# linux-firmware snapshot and verifies every payload before installing it.
	local r4pro_firmware_installer="${SRC}/packages/bpi-r4pro8x-firmware/install.sh"
	[[ -f "${r4pro_firmware_installer}" ]] ||
		exit_with_error "BPI-R4 Pro firmware installer missing" "${r4pro_firmware_installer}"
	local r4pro_firmware_mode="${BPI_R4PRO8X_FIRMWARE_MODE:-pinned}"
	local r4pro_firmware_ref="${BPI_R4PRO8X_FIRMWARE_REF:-}"

	display_alert "${BOARD}" "Firmware mode=${r4pro_firmware_mode} ref=${r4pro_firmware_ref:-<default>}" "info"

	BPI_R4PRO8X_FIRMWARE_MODE="${r4pro_firmware_mode}" \
	BPI_R4PRO8X_FIRMWARE_REF="${r4pro_firmware_ref}" \
		bash "${r4pro_firmware_installer}" "${SDCARD}" "${SRC}/cache/bpi-r4pro8x-firmware" ||
		exit_with_error "BPI-R4 Pro firmware installation failed"

	# AS21XXX_PHY is built into the kernel and requests this DT-named firmware
	# before the root filesystem is mounted. The driver has no MODULE_FIRMWARE()
	# declaration, so initramfs-tools cannot discover the payload automatically.
	local aeonsemi_firmware="${SDCARD}/lib/firmware/aeonsemi/as21x1x_fw.bin"
	local aeonsemi_initramfs_hook="${SDCARD}/etc/initramfs-tools/hooks/bpi-r4pro8x-aeonsemi"
	local aeonsemi_firmware_sha256
	[[ -f "${aeonsemi_firmware}" ]] ||
		exit_with_error "BPI-R4 Pro Aeonsemi firmware missing" "${aeonsemi_firmware}"
	mkdir -p "$(dirname "${aeonsemi_initramfs_hook}")"
	cat > "${aeonsemi_initramfs_hook}" <<- 'AEONSEMI_INITRAMFS_HOOK'
		#!/bin/sh
		set -e

		case "${1:-}" in
			prereqs) exit 0 ;;
		esac

		. /usr/share/initramfs-tools/hook-functions
		add_firmware "aeonsemi/as21x1x_fw.bin"
	AEONSEMI_INITRAMFS_HOOK
	aeonsemi_firmware_sha256="$(sha256sum "${aeonsemi_firmware}" | awk '{print $1}')"
	printf '# firmware-sha256=%s\n' "${aeonsemi_firmware_sha256}" >> "${aeonsemi_initramfs_hook}"
	chmod 0755 "${aeonsemi_initramfs_hook}"

	[[ -f "${SDCARD}${sd_overlay}" ]] ||
		exit_with_error "BPI-R4 Pro SD overlay missing from kernel package" "${SDCARD}${sd_overlay}"
	[[ -f "${extlinux_conf}" ]] ||
		exit_with_error "BPI-R4 Pro extlinux configuration was not generated" "${extlinux_conf}"

	# Insert after the base FDT line. partitioning.sh appends the root= cmdline
	# later, so the resulting stanza remains valid extlinux syntax.
	sed -i "/^[[:space:]]*fdt /a\\  fdtoverlays ${sd_overlay}" "${extlinux_conf}"
}

# R4-Pro 8X network hardware added after Armbian's original 6.12 Filogic
# config: MaxLinear switch + Aeonsemi 10G PHY. Keep this board-local so the
# normal BPI-R4 kernel configuration remains untouched.
function custom_kernel_config__bpi_r4pro_8x_network() {
	opts_y+=(
		"SRAM"
		"GPIO_PCA953X"
		"NET_DSA_MXL862"
		"NET_DSA_TAG_MXL862_8021Q"
		"AS21XXX_PHY"
		"MEDIATEK_2P5GE_PHY"
		"NET_MEDIATEK_SOC_WED"
	)

	kernel_config_modifying_hashes+=("bpi-r4pro-8x-network-v3")
}
