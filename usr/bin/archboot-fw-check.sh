#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_APPNAME=${0##*/}
_MODULE_DIR="/usr/lib/modules/${_RUNNING_KERNEL}"
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
cp firmware.txt firmware.orig.txt
while read -r i; do
    sed -i -e "s#${i}##g" firmware.txt
done < modules.txt
grep -v -E 'amd|amss|atmel|ath[0-9]|board-2|brcm|cs42l43|htc_*|i915|imx|intel|iwlwifi|libertas|m3\.bin|mediatek|mrvl|mwl.*|mt7650|nvidia|radeon|regdb|rsi|rt[0-9][0-9]*|rtl|rtw8[8-9]|slicoss|ti-connect|ti_*|vpu_*|/.zst' firmware.txt > fw-error.txt
if [[ -s fw-error.txt ]]; then
    exit 1
fi
exit 0