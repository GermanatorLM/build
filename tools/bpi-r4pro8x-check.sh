#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Static and optional image-root checks for the Banana Pi BPI-R4 Pro 8X port.
#
#   bash tools/bpi-r4pro8x-check.sh
#   bash tools/bpi-r4pro8x-check.sh --image-root /path/to/mounted/rootfs

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "${repo_root}" ]] || {
	echo "ERROR: not inside a Git checkout" >&2
	exit 1
}
cd "${repo_root}"

board="config/boards/bananapir4pro8x.csc"
family="config/sources/families/filogic-r4pro.conf"
uboot_patch="patch/u-boot/u-boot-filogic/451-add-bpi-r4pro-8x.patch"
firmware_manifest="packages/bpi-r4pro8x-firmware/manifest.tsv"
firmware_installer="packages/bpi-r4pro8x-firmware/install.sh"

image_root=""
if [[ $# -gt 0 ]]; then
	if [[ $# -eq 2 && "$1" == "--image-root" ]]; then
		image_root="$2"
	else
		echo "Usage: $0 [--image-root /path/to/mounted/rootfs]" >&2
		exit 2
	fi
fi

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for file in "${board}" "${family}" "${uboot_patch}" "${firmware_manifest}" "${firmware_installer}"; do
	[[ -f "${file}" ]] || fail "required file missing: ${file}"
done
pass "all R4 Pro port files are present"

bash -n "${board}"
bash -n "${family}"
bash -n "${firmware_installer}"
pass "Bash syntax for board, family and firmware installer"

python3 tools/validate-board-config.py "${board}"
pass "Armbian board metadata validation"

grep -q 'BOARDFAMILY="filogic-r4pro"' "${board}" || fail "unexpected BOARDFAMILY"
grep -q 'BOOTCONFIG="mt7988a_bpir4pro_sd_defconfig"' "${board}" || fail "unexpected U-Boot target"
grep -q 'mt7988a-bananapi-bpi-r4-pro-8x.dtb' "${board}" || fail "8X Linux DTB missing"
grep -q 'mt7988a-bananapi-bpi-r4-pro-sd.dtbo' "${board}" || fail "R4 Pro SD overlay missing"
pass "board selects expected U-Boot target, 8X DTB and SD overlay"

grep -q "KERNELBRANCH='branch:6.18-main'" "${family}" || fail "Frank 6.18 kernel branch not selected"
grep -q "ATFBRANCH='branch:mtk-atf-2026'" "${family}" || fail "Frank MTK ATF branch not selected"
grep -q 'DDR4_4BG_MODE=1' "${family}" || fail "8 GiB DDR4 ATF flag missing"
pass "kernel and ATF source pins"

grep -q 'mt7988a_bpir4pro_sd_defconfig' "${uboot_patch}" || fail "R4 Pro U-Boot defconfig missing from patch"
grep -q 'mt7988-sd-bpi-r4pro.dts' "${uboot_patch}" || fail "R4 Pro U-Boot SD DTS missing from patch"
grep -q 'CONFIG_DISTRO_DEFAULTS=y' "${uboot_patch}" || fail "U-Boot distro/extlinux support missing"
pass "minimal R4 Pro SD U-Boot patch structure"

firmware_count="$(awk -F '\t' 'NF == 3 && $1 !~ /^#/ {count++} END {print count+0}' "${firmware_manifest}")"
[[ "${firmware_count}" -eq 9 ]] || fail "expected 9 firmware payloads, found ${firmware_count}"

while IFS=$'\t' read -r blob size path; do
	[[ -z "${blob}" || "${blob}" == \#* ]] && continue
	[[ "${blob}" =~ ^[0-9a-f]{40}$ ]] || fail "invalid Git blob id in manifest: ${blob}"
	[[ "${size}" =~ ^[0-9]+$ ]] || fail "invalid size in manifest for ${path}: ${size}"
	[[ -n "${path}" ]] || fail "empty firmware path in manifest"
done < "${firmware_manifest}"
grep -q '^# source_latest_ref=' "${firmware_manifest}" || fail "latest firmware ref missing from manifest"
grep -q 'pinned|latest|ref' "${firmware_installer}" || fail "firmware selection modes missing from installer"
grep -q 'BPI_R4PRO8X_FIRMWARE_MODE' "${board}" || fail "firmware mode build flag is not wired into board"
grep -q 'BPI_R4PRO8X_FIRMWARE_REF' "${board}" || fail "firmware ref build flag is not wired into board"
pass "firmware manifest and selectable pinned/latest/ref modes"

for symbol in NET_DSA_MXL862 NET_DSA_TAG_MXL862_8021Q AS21XXX_PHY MEDIATEK_2P5GE_PHY NET_MEDIATEK_SOC_WED; do
	grep -q ""${symbol}"" "${board}" || fail "kernel config symbol missing: ${symbol}"
done
pass "R4 Pro network Kconfig additions"

if [[ -n "${image_root}" ]]; then
	[[ -d "${image_root}" ]] || fail "image root not found: ${image_root}"

	doc_dir="${image_root}/usr/share/doc/bpi-r4pro8x-firmware"
	source_meta="${doc_dir}/SOURCE"
	resolved_manifest="${doc_dir}/RESOLVED_MANIFEST.tsv"
	checksums="${doc_dir}/SHA256SUMS"

	[[ -f "${source_meta}" ]] || fail "firmware SOURCE metadata missing"
	[[ -f "${resolved_manifest}" ]] || fail "resolved firmware manifest missing"
	[[ -f "${checksums}" ]] || fail "firmware SHA256 audit file missing"

	firmware_mode="$(sed -n 's/^mode=//p' "${source_meta}" | head -n1)"
	resolved_commit="$(sed -n 's/^resolved_commit=//p' "${source_meta}" | head -n1)"
	[[ "${firmware_mode}" =~ ^(pinned|latest|ref)$ ]] || fail "invalid firmware mode recorded in image: ${firmware_mode}"
	[[ "${resolved_commit}" =~ ^[0-9a-f]{40}$ ]] || fail "invalid resolved firmware commit in image"

	while IFS=

printf '\nBPI-R4 Pro 8X static checks completed successfully.\n'
\t' read -r blob size path; do
		[[ -z "${blob}" || "${blob}" == \#* ]] && continue
		[[ -f "${image_root}/lib/firmware/${path}" ]] || fail "firmware missing in image: ${path}"

		# Only pinned mode promises the exact sizes/blob ids from manifest.tsv.
		if [[ "${firmware_mode}" == "pinned" ]]; then
			[[ "$(stat -c '%s' "${image_root}/lib/firmware/${path}")" == "${size}" ]] ||
				fail "pinned firmware size mismatch in image: ${path}"
		fi
	done < "${firmware_manifest}"

	(
		cd "${image_root}/lib/firmware"
		sha256sum --check --status "${checksums}"
	) || fail "firmware SHA256 audit verification failed"
	pass "firmware payloads and audit metadata (${firmware_mode}, ${resolved_commit})"

	extlinux="${image_root}/boot/extlinux/extlinux.conf"
	[[ -f "${extlinux}" ]] || fail "extlinux.conf missing in image root"
	grep -q 'mt7988a-bananapi-bpi-r4-pro-8x.dtb' "${extlinux}" || fail "8X DTB not referenced by extlinux"
	grep -q 'mt7988a-bananapi-bpi-r4-pro-sd.dtbo' "${extlinux}" || fail "SD overlay not referenced by extlinux"
	pass "extlinux selects 8X base DTB plus R4 Pro SD overlay"
fi

printf '\nBPI-R4 Pro 8X static checks completed successfully.\n'
