# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
passwd -S root | grep -q 'L' && passwd -d root >/dev/null"
