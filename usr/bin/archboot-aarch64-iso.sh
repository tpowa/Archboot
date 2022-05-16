#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/iso.sh
[[ -z "${1}" ]] && _usage
_parameters "$@"
_root_check
_aarch64_check
[[ "${_GENERATE}" == "1" ]] || _usage
_config
echo "Starting ISO creation ..."
_prepare_kernel_initramfs_files || exit 1
_prepare_fedora_shim_bootloaders_aarch64 || exit 1
_prepare_efitools_uefi || exit 1
_prepare_uefi_AA64 || exit 1
_prepare_background || exit 1
_reproducibility
_prepare_uefi_image || exit 1
_reproducibility
_grub_mkrescue || exit 1
_reproducibility_iso  || exit 1
_create_cksum || exit 1
_cleanup_iso || exit 1
echo "Finished ISO creation."
