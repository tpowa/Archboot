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
if echo "${_BASENAME}" | rg -qw 'aarch64' || echo "${_BASENAME}" | rg -qw 'x86_64'; then
    # running system = aarch64 or x86_64
    echo "Starting ISO creation..."
    _prepare_kernel_initrd_files || exit 1
    _prepare_doc || exit 1
    _prepare_ucode || exit 1
    if echo "${_BASENAME}" | rg -qw 'aarch64'; then
        _prepare_fedora_shim_bootloaders_aarch64 || exit 1
        _prepare_uefi_AA64 || exit 1
    fi
    if echo "${_BASENAME}" | rg -qw 'x86_64'; then
        _prepare_fedora_shim_bootloaders_x86_64 || exit 1
        _prepare_uefi_shell_tianocore || exit 1
        _prepare_uefi_X64 || exit 1
        _prepare_uefi_IA32 || exit 1
        _prepare_memtest || exit 1
    fi
    _prepare_background || exit 1
    _reproducibility "${_ISODIR}"
    _prepare_uefi_image || exit 1
    _reproducibility "${_ISODIR}"
    _grub_mkrescue || exit 1
    _unify_gpt_partitions || exit 1
else
    # running system = riscv64
    echo "Starting Image creation..."
    _prepare_kernel_initrd_files || exit 1
    _prepare_doc || exit 1
    _prepare_extlinux_conf || exit 1
    _reproducibility "${_ISODIR}"
    _uboot || exit 1
fi
_create_cksum || exit 1
_cleanup_iso || exit 1
if echo "${_BASENAME}" | rg -qw 'aarch64' || echo "${_BASENAME}" | rg -qw 'x86_64'; then
    echo "Finished ISO creation."
else
    echo "Finished Image creation."
fi
