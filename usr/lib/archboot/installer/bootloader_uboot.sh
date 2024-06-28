#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_uboot() {
    _common_bootloader_checks
    _check_bootpart
    _abort_uboot
    [[ -d "${_DESTDIR}/boot/extlinux" ]] || mkdir -p "${_DESTDIR}/boot/extlinux"
    _KERNEL_PARAMS_COMMON_UNMOD="root=${_ROOTDEV} rootfstype=${_ROOTFS} rw ${_ROOTFLAGS} ${_RAIDARRAYS} ${_LUKSSETUP}"
    _KERNEL_PARAMS_COMMON_MOD="$(echo "${_KERNEL_PARAMS_COMMON_UNMOD}" | sed -e 's#   # #g' | sed -e 's#  # #g')"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _TITLE="ARM 64"
    [[ "${_RUNNING_ARCH}" == "riscv64" ]] && _TITLE="RISC-V 64"
    # write extlinux.conf
    _dialog --no-mouse --infobox "Installing UBOOT..." 0 0
    cat << EOF >> "${_DESTDIR}/boot/extlinux/extlinux.conf"
menu title Welcome Arch Linux ${_TITLE}
timeout 100
default linux
label linux
    menu label Boot System (automatic boot in 10 seconds...)
    kernel ${_SUBDIR}/${_VMLINUZ}
    initrd ${_SUBDIR}/${_INITRAMFS}
    append ${_KERNEL_PARAMS_COMMON_MOD}
EOF
    _dialog --no-mouse --infobox "UBOOT has been installed successfully." 3 55
    read -r -t 3
}
