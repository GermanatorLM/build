#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Install the firmware needed by the Banana Pi BPI-R4 Pro 8X into an Armbian
# image root. Payloads are fetched from an immutable linux-firmware snapshot
# and verified against the Git blob ids recorded in manifest.tsv.

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
	echo "Usage: $0 <image-root> [cache-root]" >&2
	exit 2
fi

target_root="$1"
cache_root="${2:-${TMPDIR:-/tmp}/bpi-r4pro8x-firmware}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
manifest="${script_dir}/manifest.tsv"

[[ -d "${target_root}" ]] || {
	echo "ERROR: image root does not exist: ${target_root}" >&2
	exit 1
}
[[ -f "${manifest}" ]] || {
	echo "ERROR: firmware manifest missing: ${manifest}" >&2
	exit 1
}

manifest_meta() {
	local key="$1"
	sed -n "s/^# ${key}=//p" "${manifest}" | head -n1
}

source_ref="$(manifest_meta source_ref)"
raw_base="$(manifest_meta raw_base)"
verification="$(manifest_meta verification)"

[[ -n "${source_ref}" && -n "${raw_base}" ]] || {
	echo "ERROR: source_ref/raw_base missing in ${manifest}" >&2
	exit 1
}
[[ "${verification}" == "git-blob-sha1" ]] || {
	echo "ERROR: unsupported firmware verification mode: ${verification}" >&2
	exit 1
}

git_blob_sha1() {
	local file="$1"
	local size
	size="$(stat -c '%s' "${file}")"
	{
		printf 'blob %s\0' "${size}"
		cat "${file}"
	} | sha1sum | awk '{print $1}'
}

verify_payload() {
	local file="$1"
	local expected_sha1="$2"
	local expected_size="$3"
	local actual_size actual_sha1

	actual_size="$(stat -c '%s' "${file}")"
	if [[ "${actual_size}" != "${expected_size}" ]]; then
		echo "ERROR: size mismatch for ${file}: expected ${expected_size}, got ${actual_size}" >&2
		return 1
	fi

	actual_sha1="$(git_blob_sha1 "${file}")"
	if [[ "${actual_sha1}" != "${expected_sha1}" ]]; then
		echo "ERROR: Git blob mismatch for ${file}: expected ${expected_sha1}, got ${actual_sha1}" >&2
		return 1
	fi
}

install_one() {
	local expected_sha1="$1"
	local expected_size="$2"
	local relative_path="$3"
	local cached_file="${cache_root}/${source_ref}/${relative_path}"
	local target_file="${target_root}/lib/firmware/${relative_path}"
	local tmp_file url

	if [[ -f "${cached_file}" ]] && ! verify_payload "${cached_file}" "${expected_sha1}" "${expected_size}"; then
		echo "Discarding invalid cached firmware: ${cached_file}" >&2
		rm -f "${cached_file}"
	fi

	if [[ ! -f "${cached_file}" ]]; then
		mkdir -p "$(dirname -- "${cached_file}")"
		tmp_file="${cached_file}.tmp.$$"
		url="${raw_base}/${source_ref}/${relative_path}"

		echo "Downloading firmware: ${relative_path}"
		rm -f "${tmp_file}"
		curl 			--fail 			--location 			--retry 5 			--retry-all-errors 			--connect-timeout 20 			--output "${tmp_file}" 			"${url}"

		verify_payload "${tmp_file}" "${expected_sha1}" "${expected_size}"
		mv -f "${tmp_file}" "${cached_file}"
	fi

	verify_payload "${cached_file}" "${expected_sha1}" "${expected_size}"
	install -D -m 0644 "${cached_file}" "${target_file}"
}

installed_paths=()
while IFS=$'\t' read -r expected_sha1 expected_size relative_path; do
	[[ -z "${expected_sha1}" || "${expected_sha1}" == \#* ]] && continue
	[[ -n "${expected_size}" && -n "${relative_path}" ]] || {
		echo "ERROR: malformed firmware manifest line: ${expected_sha1} ${expected_size} ${relative_path}" >&2
		exit 1
	}
	install_one "${expected_sha1}" "${expected_size}" "${relative_path}"
	installed_paths+=("${relative_path}")
done < "${manifest}"

doc_dir="${target_root}/usr/share/doc/bpi-r4pro8x-firmware"
mkdir -p "${doc_dir}"
install -m 0644 "${manifest}" "${doc_dir}/manifest.tsv"

{
	echo "source_ref=${source_ref}"
	echo "source_url=${raw_base}/${source_ref}"
	echo "verification=${verification}"
} > "${doc_dir}/SOURCE"

: > "${doc_dir}/SHA256SUMS"
for relative_path in "${installed_paths[@]}"; do
	(
		cd "${target_root}/lib/firmware"
		sha256sum "${relative_path}"
	) >> "${doc_dir}/SHA256SUMS"
done

echo "Installed ${#installed_paths[@]} BPI-R4 Pro 8X firmware payloads from ${source_ref}."
