#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/iso.sh
[[ -z "${1}" ]] && _usage
_parameters "$@"
_root_check
_riscv64_check
_loop_check
[[ "${_GENERATE}" == "1" ]] || _usage
_config
echo "Starting ISO creation ..."
_prepare_kernel_initramfs_files_RISCV64 || exit 1
_reproducibility
_reproducibility_iso  || exit 1
_create_cksum || exit 1
_cleanup_iso || exit 1
echo "Finished ISO creation."
