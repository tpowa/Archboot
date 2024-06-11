#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_MODULE_DIR="/usr/lib/modules/${_RUNNING_ARCH}"
_FIRMWARE="/lib/firmware"
_usage () {
    echo " Check Firmware And Modules Archboot Environment"
    echo "------------------------------------------------"
    echo "usage: ${_APPNAME} run"
    exit 0
}
[[ -z "${1}" || "${1}" != "run" ]] && _usage
for i in $(find "${_MODULE_DIR}" | grep '.ko.*'); do
    modinfo -F firmware "${i}" >>modules.txt
done
find "${_FIRMWARE}" | grep '.zst$' >firmware.txt
while read -r i; do
    sed -i -e "s#${i}##g" firmware.txt
done < modules.txt
grep -v -E 'amd|intel|radeon' firmware.txt > error-firmware.txt
