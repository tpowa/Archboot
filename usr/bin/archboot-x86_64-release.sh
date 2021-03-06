#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_ARCH="x86_64"
_ARCHBOOT="archboot"
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/release.sh
[[ -z "${1}" ]] && _usage
_root_check
_x86_64_check
echo "Start release creation in $1 ..."
_create_iso "$@" || exit 1
_create_boot || exit 1
_create_cksum || exit 1
echo "Finished release creation in ${1} ."

