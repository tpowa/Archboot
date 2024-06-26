#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#  archboot-detect-vconsole.sh:
#  sets bigger font on bigger display resolutions
#  by Tobias Powalowski <tpowa@archlinux.org>
#
# wait for modules to initialize cmompletely
udevadm wait --settle /dev/fb0
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
