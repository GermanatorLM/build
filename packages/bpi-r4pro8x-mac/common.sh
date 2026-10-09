#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# R4 Pro 8X EEPROM MAC record. Offset 0x40, length 16.

mac_fail() { echo "ERROR: $*" >&2; return 1; }

mac_valid() {
	printf '%s\n' "$1" | LC_ALL=C grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || return 1
	[ "$1" != 00:00:00:00:00:00 ] || return 1
	mac_first=${1%%:*}
	[ "$((0x$mac_first & 1))" -eq 0 ]
}

mac_bytes() {
	# POSIX printf needs octal escapes for binary output.
	for mac_byte in "$@"; do
		printf '%b' "$(printf '\\%03o' "$mac_byte")"
	done
}

mac_hex() { hexdump -v -e '1/1 "%02x"' "$1"; }

mac_cksum() {
	# POSIX cksum, including the length suffix. Vendor BusyBox lacks that applet.
	hexdump -v -e '1/1 "%u\n"' | awk '
	function crc_xor(a,b, r,p) {
		r=0; p=1;
		while(a>0 || b>0) {
			if(a%2 != b%2) r+=p;
			a=int(a/2); b=int(b/2); p*=2;
		}
		return r;
	}
	function feed(byte, i,top) {
		crc=crc_xor(crc,byte*16777216);
		for(i=0;i<8;i++) {
			top=(crc>=2147483648); crc=(crc*2)%4294967296;
			if(top) crc=crc_xor(crc,79764919);
		}
	}
	{feed($1); len++}
	END {
		n=len;
		while(n>0) {feed(n%256); n=int(n/256)}
		printf "%.0f\n",4294967295-crc;
	}'
}

mac_make_record() {
	mac_valid "$1" || return 1
	printf '%s' "$1" | tr ':' ' ' | while read -r mac_line || [ -n "$mac_line" ]; do
		for mac_octet in $mac_line; do mac_bytes "$((0x$mac_octet))"; done
	done
	mac_bytes 255 255
	printf R4M1
}

mac_finish_record() {
	mac_crc=$(mac_cksum < "$1")
	mac_bytes "$((mac_crc / 16777216))" "$((mac_crc / 65536 % 256))" \
		"$((mac_crc / 256 % 256))" "$((mac_crc % 256))" >> "$1"
}

mac_read_record() {
	[ "$(wc -c < "$1")" -eq 16 ] || return 1
	mac_hex_value=$(mac_hex "$1")
	case "$mac_hex_value" in ????????????ffff52344d31????????) ;; *) return 1 ;; esac
	mac_checksum=$(dd if="$1" bs=1 count=12 2>/dev/null | mac_cksum)
	mac_stored=$(dd if="$1" bs=1 skip=12 count=4 2>/dev/null |
		hexdump -v -e '1/1 "%u "' | awk '{printf "%.0f\n",$1*16777216+$2*65536+$3*256+$4}')
	[ "$mac_checksum" = "$mac_stored" ] || return 1
	mac_result=$(printf '%s\n' "$mac_hex_value" | awk '{for(i=1;i<=11;i+=2) printf "%s%s",(i>1?":":""),substr($0,i,2); print ""}')
	mac_valid "$mac_result" || return 1
	printf '%s\n' "$mac_result"
}

mac_require_board() {
	[ -r "$1/firmware/devicetree/base/model" ] || return 1
	tr '\000' '\n' < "$1/firmware/devicetree/base/model" |
		LC_ALL=C grep -Eqi 'bpi-r4[ -]*pro[ -]*8x'
}

mac_find_eeprom() {
	mac_found=
	for mac_dev in "$1"/bus/i2c/devices/*-0057; do
		[ -r "$mac_dev/eeprom" ] || continue
		[ "$(basename "$(readlink -f "$mac_dev/driver")")" = at24 ] || continue
		[ "$(basename "$(readlink -f "$mac_dev/of_node")")" = eeprom@57 ] || continue
		tr '\000' '\n' < "$mac_dev/of_node/compatible" | grep -qx 'atmel,24c02' || continue
		[ "$(mac_hex "$mac_dev/of_node/size")" = 00000100 ] || continue
		# Vendor DT uses page-size. at24 ignores that spelling and writes one byte.
		mac_page_property=$mac_dev/of_node/pagesize
		if [ ! -f "$mac_page_property" ]; then mac_page_property=$mac_dev/of_node/page-size; fi
		[ -f "$mac_page_property" ] || continue
		[ "$(mac_hex "$mac_page_property")" = 00000008 ] || continue
		[ "$(wc -c < "$mac_dev/eeprom")" -eq 256 ] || continue
		[ -z "$mac_found" ] || { mac_fail 'ambiguous board EEPROM'; return 1; }
		mac_found=$mac_dev/eeprom
	done
	[ -n "$mac_found" ] || return 1
	printf '%s\n' "$mac_found"
}

mac_derive() {
	# Hash each controller separately. Adjacent base addresses must not overlap.
	printf 'bpi-r4pro8x:%s:eth%s' "$1" "$2" | sha256sum | awk '
	function hex(s, n,i) {n=0; for(i=1;i<=length(s);i++) n=n*16+index("0123456789abcdef",substr(s,i,1))-1; return n}
	{printf "%02x",int(hex(substr($1,1,2))/4)*4+2;
	 for(i=3;i<=11;i+=2) printf ":%s",substr($1,i,2); print ""}'
}
