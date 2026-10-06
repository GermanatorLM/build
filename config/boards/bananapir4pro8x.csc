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

	# Same MT7988 WO firmware blobs used by Armbian's existing BPI-R4 target.
	mkdir -p "${SDCARD}/lib/firmware/mediatek/mt7988"
	cp -v "${SRC}/packages/blobs/filogic/firmware/mediatek/mt7988/mt7988_wo_0.bin" 		"${SDCARD}/lib/firmware/mediatek/mt7988/mt7988_wo_0.bin"
	cp -v "${SRC}/packages/blobs/filogic/firmware/mediatek/mt7988/mt7988_wo_1.bin" 		"${SDCARD}/lib/firmware/mediatek/mt7988/mt7988_wo_1.bin"

	# R4-Pro-specific PHY and Wi-Fi 7 firmware. The installer uses an immutable
	# linux-firmware snapshot and verifies every payload before installing it.
	local r4pro_firmware_installer="${SRC}/packages/bpi-r4pro8x-firmware/install.sh"
	[[ -f "${r4pro_firmware_installer}" ]] ||
		exit_with_error "BPI-R4 Pro firmware installer missing" "${r4pro_firmware_installer}"
	bash "${r4pro_firmware_installer}" "${SDCARD}" "${SRC}/cache/bpi-r4pro8x-firmware" ||
		exit_with_error "BPI-R4 Pro firmware installation failed"

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
		"NET_DSA_MXL862"
		"NET_DSA_TAG_MXL862_8021Q"
		"AS21XXX_PHY"
		"MEDIATEK_2P5GE_PHY"
		"NET_MEDIATEK_SOC_WED"
	)

	kernel_config_modifying_hashes+=("bpi-r4pro-8x-network-v1")
}
