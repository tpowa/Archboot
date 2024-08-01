#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/qemu.sh
[[ -z "${1}" || "${1}" != "run" ]] && _usage
_UBOOT=$(mktemp -d uboot.XXX)
_OVMF32=$(mktemp -d ovmf32.XXX)
_OVMF=$(mktemp -d ovmf.XXX)
_root_check
_x86_64_check
_prepare_files || exit 1
_upload_files qemu || exit 1
_cleanup qemu || exit 1
