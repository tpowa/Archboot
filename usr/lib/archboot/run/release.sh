#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/release.sh
[[ -z "${1}" ]] && _usage
_root_check
_container_check
echo "Starting release creation in ${1}..."
_create_iso "$@" || exit 1
echo "Finished release creation in ${1}."

