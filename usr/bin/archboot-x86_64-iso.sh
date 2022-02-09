#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
source /usr/lib/archboot/functions
source /usr/lib/archboot/iso_functions
[[ -z "${1}" ]] && _usage
_parameters "$@"
_root_check
_x86_64_check
[[ "${_GENERATE}" == "1" ]] || _usage
_config
echo "Starting ISO creation ..."
_prepare_kernel_initramfs_files
_prepare_fedora_shim_bootloaders_x86_64 >/dev/null 2>&1
_download_uefi_shell_tianocore >/dev/null 2>&1
_prepare_efitools_uefi >/dev/null 2>&1
_prepare_uefi_X64_GRUB_USB_files >/dev/null 2>&1
_prepare_uefi_IA32_GRUB_USB_files >/dev/null 2>&1
_prepare_uefi_image >/dev/null 2>&1
_grub_mkrescue
_create_cksum
_cleanup_iso
echo "Finished ISO creation."
