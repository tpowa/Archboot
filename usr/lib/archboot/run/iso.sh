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
    # running system = aarch64 or x86_64
    echo "Starting ISO creation..."
    _prepare_kernel_initrd_files || exit 1
    _prepare_doc || exit 1
    _prepare_ucode || exit 1
    if rg -qw 'aarch64' <<< "${_BASENAME}"; then
        _prepare_fedora_shim_bootloaders_aarch64 || exit 1
        _prepare_grub_AA64 || exit 1
        _prepare_ipxe_AA64 || exit 1
    fi
    if rg -qw 'x86_64' <<< "${_BASENAME}"; then
        _prepare_fedora_shim_bootloaders_x86_64 || exit 1
        _prepare_uefi_shell_tianocore || exit 1
        _prepare_grub_X64 || exit 1
        _prepare_grub_IA32 || exit 1
        _prepare_ipxe_IA32 || exit 1
        _prepare_ipxe_X64 || exit 1
        _prepare_ipxe || exit 1
        _prepare_memtest || exit 1
    fi
    _prepare_background || exit 1
    _reproducibility "${_ISODIR}"
    _prepare_uefi_image || exit 1
    _prepare_release_txt || exit 1
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
if rg -qw 'aarch64' <<< "${_BASENAME}" || rg -qw 'x86_64' <<< "${_BASENAME}"; then
    echo "Finished ISO creation."
else
    echo "Finished Image creation."
fi
