#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#  archboot-detect-vconsole.sh:
#  sets bigger font on bigger display resolutions
#  by Tobias Powalowski <tpowa@archlinux.org>
#
. /usr/lib/archboot/common.sh
_usage() {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Detect Big Screen\e[m"
    echo -e "\e[1m----------------------------\e[m"
    echo "Detect big screen on boot and change to bigger font afterwards."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} run\e[m"
    exit 0
}
[[ -z "${1}" || "${1}" != "run" ]] && _usage
_root_check
# wait for modules to initialize completely, timeout after 10 seconds to avoid hang on some systems
udevadm wait --settle /dev/fb0 -t 10
# get screen setting mode from /sys
_FB_SIZE="$(rg -o ':(.*)x' -r '$1' /sys/class/graphics/fb0/modes 2>/dev/null)"
if [[ "${_FB_SIZE}" -gt '1900' ]]; then
    _SIZE="32"
else
    _SIZE="16"
fi
# update vconsole.conf accordingly
echo KEYMAP=us >/etc/vconsole.conf
echo FONT=ter-v${_SIZE}n >>/etc/vconsole.conf
/lib/systemd/systemd-vconsole-setup
