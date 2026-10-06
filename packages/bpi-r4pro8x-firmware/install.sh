#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Install the firmware needed by the Banana Pi BPI-R4 Pro 8X into an Armbian
# image root.
#
# Selection modes:
#   pinned (default) - use and strictly verify the manifest's immutable snapshot
#   latest           - resolve the configured latest ref to a concrete commit
#   ref              - resolve BPI_R4PRO8X_FIRMWARE_REF (commit/tag/branch)
#
# Dynamic modes always download from the resolved immutable commit and record
# the exact commit plus SHA256/Git-blob hashes in the image for later auditing.

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

pinned_source_repository="$(manifest_meta source_repository)"
dynamic_source_repository="$(manifest_meta dynamic_source_repository)"
pinned_ref="$(manifest_meta source_ref)"
latest_ref="$(manifest_meta source_latest_ref)"
pinned_raw_base="$(manifest_meta raw_base)"
dynamic_raw_base="$(manifest_meta dynamic_raw_base)"
verification="$(manifest_meta verification)"

[[ -n "${pinned_source_repository}" && -n "${dynamic_source_repository}" &&
	-n "${pinned_ref}" && -n "${pinned_raw_base}" && -n "${dynamic_raw_base}" ]] || {
	echo "ERROR: firmware source metadata missing in ${manifest}" >&2
	exit 1
}
[[ "${verification}" == "git-blob-sha1" ]] || {
	echo "ERROR: unsupported pinned verification mode: ${verification}" >&2
	exit 1
}

firmware_mode="${BPI_R4PRO8X_FIRMWARE_MODE:-pinned}"
requested_ref="${BPI_R4PRO8X_FIRMWARE_REF:-}"

case "${firmware_mode}" in
	pinned)
		[[ -z "${requested_ref}" ]] || {
			echo "ERROR: BPI_R4PRO8X_FIRMWARE_REF requires BPI_R4PRO8X_FIRMWARE_MODE=ref" >&2
			exit 1
		}
		selected_ref="${pinned_ref}"
		resolved_ref="${pinned_ref}"
		;;
	latest)
		[[ -z "${requested_ref}" ]] || {
			echo "ERROR: do not combine BPI_R4PRO8X_FIRMWARE_MODE=latest with BPI_R4PRO8X_FIRMWARE_REF" >&2
			exit 1
		}
		selected_ref="${latest_ref:-HEAD}"
		;;
	ref)
		[[ -n "${requested_ref}" ]] || {
			echo "ERROR: BPI_R4PRO8X_FIRMWARE_MODE=ref requires BPI_R4PRO8X_FIRMWARE_REF=<commit|tag|branch>" >&2
			exit 1
		}
		selected_ref="${requested_ref}"
		;;
	*)
		echo "ERROR: invalid BPI_R4PRO8X_FIRMWARE_MODE='${firmware_mode}' (expected pinned|latest|ref)" >&2
		exit 1
		;;
esac

resolve_git_ref() {
	local repo="$1"
	local ref="$2"
	local output sha

	# A full commit id is already immutable. We still use it as the raw URL pin.
	if [[ "${ref}" =~ ^[0-9a-fA-F]{40}$ ]]; then
		printf '%s\n' "${ref,,}"
		return 0
	fi

	output="$(git ls-remote "${repo}" 		"${ref}" 		"refs/heads/${ref}" 		"refs/tags/${ref}" 		"refs/tags/${ref}^{}" 2>/dev/null || true)"

	# Prefer an annotated-tag peeled commit, then an exact head/tag/ref match.
	sha="$(awk '$2 ~ /\^\{\}$/ {print $1; exit}' <<< "${output}")"
	[[ -n "${sha}" ]] || sha="$(awk 'NR==1 {print $1}' <<< "${output}")"

	[[ "${sha}" =~ ^[0-9a-fA-F]{40}$ ]] || {
		echo "ERROR: unable to resolve firmware ref '${ref}' from ${repo}" >&2
		return 1
	}

	printf '%s\n' "${sha,,}"
}

if [[ "${firmware_mode}" == "pinned" ]]; then
	selected_source_repository="${pinned_source_repository}"
else
	selected_source_repository="${dynamic_source_repository}"
	resolved_ref="$(resolve_git_ref "${selected_source_repository}" "${selected_ref}")"
fi

echo "Firmware mode: ${firmware_mode}"
echo "Firmware requested ref: ${selected_ref}"
echo "Firmware resolved commit: ${resolved_ref}"

git_blob_sha1() {
	local file="$1"
	local size
	size="$(stat -c '%s' "${file}")"
	{
		printf 'blob %s\0' "${size}"
		cat "${file}"
	} | sha1sum | awk '{print $1}'
}

verify_pinned_payload() {
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

verify_dynamic_cache() {
	local file="$1"
	local checksum_file="${file}.sha256"

	[[ -f "${file}" && -f "${checksum_file}" ]] || return 1
	(
		cd "$(dirname -- "${file}")"
		sha256sum --check --status "$(basename -- "${checksum_file}")"
	)
}

record_dynamic_cache_checksum() {
	local file="$1"
	(
		cd "$(dirname -- "${file}")"
		sha256sum "$(basename -- "${file}")" > "$(basename -- "${file}").sha256"
	)
}

resolved_manifest_tmp="$(mktemp)"
trap 'rm -f "${resolved_manifest_tmp}"' EXIT
printf 'git_blob_sha1\tsize_bytes\tsha256\tpath\n' > "${resolved_manifest_tmp}"

install_one() {
	local expected_sha1="$1"
	local expected_size="$2"
	local relative_path="$3"
	local cached_file="${cache_root}/${resolved_ref}/${relative_path}"
	local target_file="${target_root}/lib/firmware/${relative_path}"
	local tmp_file url actual_size actual_blob actual_sha256

	if [[ "${firmware_mode}" == "pinned" ]]; then
		if [[ -f "${cached_file}" ]] && ! verify_pinned_payload "${cached_file}" "${expected_sha1}" "${expected_size}"; then
			echo "Discarding invalid cached firmware: ${cached_file}" >&2
			rm -f "${cached_file}" "${cached_file}.sha256"
		fi
	else
		if [[ -f "${cached_file}" ]] && ! verify_dynamic_cache "${cached_file}"; then
			echo "Discarding unverifiable dynamic firmware cache: ${cached_file}" >&2
			rm -f "${cached_file}" "${cached_file}.sha256"
		fi
	fi

	if [[ ! -f "${cached_file}" ]]; then
		mkdir -p "$(dirname -- "${cached_file}")"
		tmp_file="${cached_file}.tmp.$$"
		if [[ "${firmware_mode}" == "pinned" ]]; then
			url="${pinned_raw_base}/${resolved_ref}/${relative_path}"
		else
			url="${dynamic_raw_base}/${relative_path}?id=${resolved_ref}"
		fi

		echo "Downloading firmware: ${relative_path}"
		rm -f "${tmp_file}"
		curl 			--fail 			--location 			--retry 5 			--retry-all-errors 			--connect-timeout 20 			--output "${tmp_file}" 			"${url}"

		if [[ "${firmware_mode}" == "pinned" ]]; then
			verify_pinned_payload "${tmp_file}" "${expected_sha1}" "${expected_size}"
		fi

		mv -f "${tmp_file}" "${cached_file}"
		record_dynamic_cache_checksum "${cached_file}"
	fi

	if [[ "${firmware_mode}" == "pinned" ]]; then
		verify_pinned_payload "${cached_file}" "${expected_sha1}" "${expected_size}"
	else
		verify_dynamic_cache "${cached_file}" || {
			echo "ERROR: dynamic firmware cache verification failed: ${cached_file}" >&2
			return 1
		}
	fi

	install -D -m 0644 "${cached_file}" "${target_file}"

	actual_size="$(stat -c '%s' "${cached_file}")"
	actual_blob="$(git_blob_sha1 "${cached_file}")"
	actual_sha256="$(sha256sum "${cached_file}" | awk '{print $1}')"
	printf '%s\t%s\t%s\t%s\n' 		"${actual_blob}" "${actual_size}" "${actual_sha256}" "${relative_path}" 		>> "${resolved_manifest_tmp}"
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
install -m 0644 "${resolved_manifest_tmp}" "${doc_dir}/RESOLVED_MANIFEST.tsv"

{
	echo "mode=${firmware_mode}"
	echo "requested_ref=${selected_ref}"
	echo "resolved_commit=${resolved_ref}"
	echo "source_repository=${selected_source_repository}"
	if [[ "${firmware_mode}" == "pinned" ]]; then
		echo "source_url=${pinned_raw_base}/${resolved_ref}"
	else
		echo "source_url=${dynamic_raw_base}?id=${resolved_ref}"
	fi
	if [[ "${firmware_mode}" == "pinned" ]]; then
		echo "verification=manifest-size+git-blob-sha1"
	else
		echo "verification=resolved-immutable-commit+download-sha256-cache"
	fi
} > "${doc_dir}/SOURCE"

: > "${doc_dir}/SHA256SUMS"
for relative_path in "${installed_paths[@]}"; do
	(
		cd "${target_root}/lib/firmware"
		sha256sum "${relative_path}"
	) >> "${doc_dir}/SHA256SUMS"
done

echo "Installed ${#installed_paths[@]} BPI-R4 Pro 8X firmware payloads from ${resolved_ref} (${firmware_mode})."
