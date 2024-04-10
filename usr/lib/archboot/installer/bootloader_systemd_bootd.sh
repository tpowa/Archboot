#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_systemd_boot_uefi() {
    _dialog --no-mouse --infobox "Setting up SYSTEMD-BOOT now..." 3 40
    # create directory structure, if it doesn't exist
    [[ -d "${_DESTDIR}/${_UEFISYS_MP}/loader/entries" ]] || mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/loader/entries"
    echo "title    Arch Linux" > "${_DESTDIR}/${_UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
    echo "linux    /${_KERNEL}" >> "${_DESTDIR}/${_UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
    cat << BOOTDEOF >> "${_DESTDIR}/${_UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
initrd   /${_INITRD}
options  ${_KERNEL_PARAMS_MOD}
BOOTDEOF
    cat << BOOTDEOF > "${_DESTDIR}/${_UEFISYS_MP}/loader/loader.conf"
timeout 5
default archlinux-core-main
BOOTDEOF
    _chroot_mount
    # systemd-boot https://www.freedesktop.org/software/systemd/man/latest/systemd-gpt-auto-generator.html
    # /boot XBOOTLDR in vfat format can be booted by systemd-boot
    if [[ "${_UEFISYS_MP}" == "efi" && \
          $(${_LSBLK} FSTYPE "${_BOOTDEV}" 2>"${_NO_LOG}" | grep -q "vfat") ]]; then
        chroot "${_DESTDIR} "bootctl --esp-path=/efi --boot-path=/boot install &>"${_LOG}"
        chroot "${_DESTDIR}" bootctl --esp-path=/efi --boot-path=/boot update &>"${_LOG}"
    else
        chroot "${_DESTDIR}" bootctl --path="/${_UEFISYS_MP}" install &>"${_LOG}"
        chroot "${_DESTDIR}" bootctl --path="/${_UEFISYS_MP}" update &>"${_LOG}"
    fi
    _chroot_umount
    if [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi" ]]; then
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        cp -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi"  \
              "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        _BOOTMGR_LABEL="SYSTEMD-BOOT"
        _BOOTMGR_LOADER_PATH="/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi"
        _uefi_bootmgr_setup
        sleep 2
        _dialog --msgbox "You will now be put into the editor to edit:\nloader.conf and menu entry files\n\nAfter you save your changes, exit the editor." 8 50
        _geteditor || return 1
        "${_EDITOR}" "${_DESTDIR}/${_UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
        "${_EDITOR}" "${_DESTDIR}/${_UEFISYS_MP}/loader/loader.conf"
        if ${_LSBLK} FSTYPE "${_BOOTDEV}" 2>"${_NO_LOG}" | grep -q "vfat"; then
            _dialog --title " Skipping " --no-mouse --infobox "Skipped kernel, ucode and initramfs copying to EFI SYSTEM PARTITION." 3 75
            sleep 3
        else
            _efistub_copy_to_efisys | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Copying kernel, ucode and initramfs to EFI SYSTEM PARTITION now..." 6 75 0
        fi
        _pacman_hook_systemd_bootd
        _dialog --title " Success " --no-mouse --infobox "SYSTEMD-BOOT has been setup successfully." 3 50
        sleep 3
        _S_BOOTLOADER=1
    else
        _dialog --msgbox "Error installing SYSTEMD-BOOT." 0 0
    fi
}
