#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_systemd_boot_uefi() {
    _dialog --no-mouse --infobox "Setting up SYSTEMD-BOOT now..." 3 40
    # create directory structure, if it doesn't exist
    [[ -d "${_DESTDIR}/boot/loader/entries" ]] || mkdir -p "${_DESTDIR}/boot/loader/entries"
    [[ -d "${_DESTDIR}/${_UEFISYS_MP}/loader" ]] || mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/loader"
    _MAIN_CFG="boot/loader/entries/archlinux-core-main.conf"
    _LOADER_CFG="/${_UEFISYS_MP}/loader/loader.conf"
    cat << BOOTDEOF > "${_DESTDIR}/${_MAIN_CFG}"
title    Arch Linux
linux    /${_VMLINUZ}
initrd   /${_INITRAMFS}
options  ${_KERNEL_PARAMS_MOD}
BOOTDEOF
    cat << BOOTDEOF > "${_DESTDIR}/${_LOADER_CFG}"
timeout 5
default archlinux-core-main
BOOTDEOF
    _chroot_mount
    # systemd-boot https://www.freedesktop.org/software/systemd/man/latest/systemd-gpt-auto-generator.html
    # /boot XBOOTLDR in vfat format can be booted by systemd-boot
    chroot "${_DESTDIR}" bootctl install &>"${_LOG}"
    _chroot_umount
    if [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi" ]]; then
        _dialog --msgbox "You will now be put into the editor to edit:\nloader.conf and menu entry files\n\nAfter you save your changes, exit the editor." 8 50
        _geteditor || return 1
        _editor "${_DESTDIR}/${_MAIN_CFG}"
        _editor "${_DESTDIR}/${_LOADER_CFG}"
        _pacman_hook_systemd_bootd
        _dialog --title " Success " --no-mouse --infobox "SYSTEMD-BOOT has been setup successfully." 3 50
        sleep 3
        _S_BOOTLOADER=1
    else
        _dialog --msgbox "Error installing SYSTEMD-BOOT." 0 0
    fi
}
