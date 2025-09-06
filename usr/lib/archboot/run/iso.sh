#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/iso.sh
[[ -z "${1}" ]] && _usage
_parameters "$@"
[[ "${_GENERATE}" == "1" ]] || _usage
_root_check
_architecture_check
_config
_ISODIR="$(mktemp -d ISODIR.XXX)"
if rg -qw 'aarch64' <<< "${_BASENAME}" || rg -qw 'x86_64' <<< "${_BASENAME}"; then
    _I_TYPE="ISO"
else
    _I_TYPE="Image"
fi
echo "Starting ${_I_TYPE} creation..."
_prepare_kernel_initrd_files || exit 1
_prepare_doc || exit 1
if [[ "${_I_TYPE}" == "ISO" ]]; then
    # running system = aarch64 or x86_64
    _prepare_ucode || exit 1
    _prepare_bootloaders || exit 1
    _reproducibility "${_ISODIR}"
    _prepare_uefi_image || exit 1
    _prepare_release_txt || exit 1
    _reproducibility "${_ISODIR}"
    _grub_mkrescue || exit 1
    _unify_gpt_partitions || exit 1
else
    # running system = riscv64
    _prepare_extlinux_conf || exit 1
    _reproducibility "${_ISODIR}"
    _uboot || exit 1
fi
_create_cksum
_cleanup_iso || exit 1
echo "Finished ${_I_TYPE} creation."
