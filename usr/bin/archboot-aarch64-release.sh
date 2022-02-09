#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_ARCH="aarch64"
_ARCHBOOT="archboot-arm"
source /usr/lib/archboot/functions
source /usr/lib/archboot/release_functions
[[ -z "${1}" ]] && _usage
_root_check
echo "Start release creation in $1 ..."
_create_iso "$@" || exit 1
_create_boot || exit 1
_create_cksum || exit 1
echo "Finished release creation in ${1} ."
