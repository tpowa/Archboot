# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
passwd -S root | grep -q 'L' && passwd -d root >/dev/null
