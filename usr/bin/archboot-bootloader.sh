#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/bootloader.sh
_SHIM=$(mktemp -d shim.XXX)
_SHIM32=$(mktemp -d shim32.XXX)
_SHIMAA64=$(mktemp -d shimaa64.XXX)
_root_check
_x86_64_check
_prepare_shim_files || exit 1
_upload_efi_files shim-fedora || exit 1
_cleanup shim-fedora || exit 1
mkdir -m 777 grub-efi
_prepare_uefi_X64 || exit 1
_prepare_uefi_IA32 || exit 1
archboot-aarch64-create-container.sh grub-aarch64
_prepare_uefi_AA64 grub-aarch64 || exit 1
_cleanup grub-aarch64 || exit 1
#archboot-riscv64-create-container.sh grub-riscv64
#_prepare_uefi_RISCV64 grub-riscv64 || exit 1
#_cleanup grub-riscv64 || exit 1
_upload_efi_files grub-efi || exit 1
_cleanup grub-efi || exit 1
