#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/iso.sh
[[ -z "${1}" ]] && _usage
_parameters "$@"
[[ "${_GENERATE}" == "1" ]] || _usage
_root_check
_architecture_check
_config
if echo "${0}" | grep -qw aarch64 || echo "${0}" | grep -qw x86_64; then
    # running system = aarch64 or x86_64
    echo "Starting ISO creation ..."
    _prepare_kernel_initramfs_files || exit 1
    _prepare_ucode || exit 1
    if echo "${0}" | grep -qw aarch64; then
        _prepare_fedora_shim_bootloaders_aarch64 || exit 1
        _prepare_uefi_AA64 || exit 1
    fi
    if echo "${0}" | grep -qw x86_64; then
        _prepare_fedora_shim_bootloaders_x86_64 || exit 1
        _prepare_uefi_shell_tianocore || exit 1
        _prepare_uefi_X64 || exit 1
        _prepare_uefi_IA32 || exit 1
    fi
    _prepare_efitools_uefi || exit 1
    _prepare_background || exit 1
    _reproducibility
    _prepare_uefi_image || exit 1
    _reproducibility
    _grub_mkrescue || exit 1
    _reproducibility_iso  || exit 1
else
    # running system = riscv64
    echo "Starting Image creation ..."
    _prepare_kernel_initramfs_files_RISCV64 || exit 1
    _prepare_extlinux_conf || exit 1
    _reproducibility
    _uboot || exit 1
fi
_create_cksum || exit 1
_cleanup_iso || exit 1
if echo "${0}" | grep -qw aarch64 || echo "${0}" | grep -qw x86_64; then
    echo "Finished ISO creation."
else
    echo "Finished Image creation."
fi
