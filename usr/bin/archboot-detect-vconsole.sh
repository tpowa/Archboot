#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# 
#    archboot-vconsole.sh - sets bigger font on bigger display resolutions
#    by Tobias Powalowski <tpowa@archlinux.org>
#

FB_SIZE="$(cut -d 'x' -f 1 "$(find /sys -wholename '*fb0/modes')" 2>"${_NO_LOG}" | sed -e 's#.*:##g')"
if [[ "${FB_SIZE}" -gt '1900' ]]; then
    SIZE="32"
else
    SIZE="16"
fi
echo KEYMAP=us >/etc/vconsole.conf
echo FONT=ter-v${SIZE}n >>/etc/vconsole.conf
