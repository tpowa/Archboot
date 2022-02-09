#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_ARCH="x86_64"
_ARCHBOOT="archboot"
source /usr/lib/archboot/functions
source /usr/lib/archboot/release_functions
[[ -z "${1}" ]] && _usage
_root_check
_x86_64_check
echo "Start release creation in $1 ..."
_create_iso "$@"
_create_boot
_create_torrent
_create_cksum
echo "Finished release creation in ${1} ."

