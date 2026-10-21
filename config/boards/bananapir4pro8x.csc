# shellcheck shell=bash disable=SC2034
# MediaTek MT7988A, R4 Pro 8X, 8 GiB DDR4, BE14 Rev. 1.0
BOARD_NAME="Banana Pi R4 Pro 8X"
BOARD_VENDOR="sinovoip"
BOARDFAMILY="filogic-r4pro8x"
BOARD_MAINTAINER="GermanatorLM"
INTRODUCED="2026"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"
BOOT_FDT_FILE="mediatek/mt7988a-bananapi-bpi-r4-pro-8x.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n1 earlycon=uart8250,mmio32,0x11000000 rootwait"
HAS_VIDEO_OUTPUT="no"
INSTALL_ARMBIAN_FIRMWARE="no"
PACKAGE_LIST_BOARD+=" iw wpasupplicant rfkill ethtool iperf3 linuxptp"

function post_family_tweaks_bsp__r4pro8x_initramfs() {
	declare file_added_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/r4pro8x-phy-firmware" <<-'HOOK'
		#!/bin/sh
		set -eu
		[ "${1:-}" = prereqs ] && exit 0
		. /usr/share/initramfs-tools/hook-functions
		add_firmware aeonsemi/as21x1x_fw.bin
	HOOK
	run_host_command_logged chmod +x "${file_added_to_bsp_destination}"
}

function post_family_tweaks_bsp__r4pro8x_led_restore() {
	declare file_added_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/usr/lib/armbian/armbian-led-state-restore.sh" < <(
		sed '/^\tVALUE=${BASH_REMATCH\[2\]}/a\	[[ "$PARAM" == device_name && -z "$VALUE" ]] \&\& continue' \
			"${SRC}/packages/bsp/common/usr/lib/armbian/armbian-led-state-restore.sh"
	)
	run_host_command_logged chmod +x "${file_added_to_bsp_destination}"
}

function post_family_tweaks__r4pro8x_firmware() {
	run_host_command_logged python3 "${SRC}/tools/r4pro8x/firmware.py" "${SDCARD}"
	install -Dm644 "${SRC}/config/optional/boards/bananapir4pro8x/sources.lock.json" \
		"${SDCARD}/usr/share/r4pro8x/sources.lock.json"
	mkdir -p "${SDCARD}/etc/apt/preferences.d"
	cat > "${SDCARD}/etc/apt/preferences.d/99-r4pro8x-board" <<-'PINS'
		Package: linux-image-* linux-dtb-* linux-headers-* linux-u-boot-* armbian-bsp-* armbian-firmware*
		Pin: version *
		Pin-Priority: -1
	PINS
}

function armbian_kernel_config__r4pro8x() {
	opts_y+=("SRAM" "GPIO_PCA953X" "I2C_MT65XX" "PHYLINK" "NET_DSA"
		"NET_DSA_MT7530" "NET_DSA_MXL862" "AS21XXX_PHY" "MEDIATEK_GE_SOC_PHY"
		"MEDIATEK_2P5GE_PHY" "NET_MEDIATEK_SOC" "MTK_INFRACFG" "MTK_PMIC_WRAP"
		"PTP_1588_CLOCK" "THERMAL" "HWMON" "LEDS_TRIGGER_NETDEV")
	opts_m+=("MT7996E" "USB_SERIAL_OPTION" "USB_NET_QMI_WWAN" "USB_NET_CDC_MBIM"
		"USB_NET_CDC_NCM" "USB_SERIAL_CP210X" "USB_SERIAL_CH341" "USB_SERIAL_FTDI_SIO")
}

function post_install_kernel_debs__r4pro8x_overlay_path() {
	mkdir -p "${SDCARD}/boot/dtb/mediatek/overlay"
	cp "${SDCARD}/boot/dtb/mediatek/mt7988a-bananapi-bpi-r4-pro-${R4PRO_BOOT_MEDIA}.dtbo" \
		"${SDCARD}/boot/dtb/mediatek/overlay/"
}
