#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_limine_common() {
    if [[ ! -f "${_DESTDIR}/usr/bin/limine" ]]; then
        _PACKAGES="limine"
        _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
        _pacman_error
    fi
}

_limine_config() {
    _PARTN="$(${LSBLK} PARTN ${_BOOTDEV})"
    cat << CONFEOF > "${_LIMINE_CONFIG}"
    TIMEOUT=5

:Arch Linux
    PROTOCOL=linux
    KERNEL_PATH=boot://${_PARTN}/${_KERNEL}
    CMDLINE=${_KERNEL_PARAMS_MOD}
CONFEOF
    echo "MODULE_PATH=boot://${_PARTN}/${_INITRD}" >> "${_LIMINE_CONFIG}"
    ## Edit limine.cfg config file
    _dialog --msgbox "You will now be put into the editor to edit:\nlimine.cfg\n\nAfter you save your changes, exit the editor." 8 50
    _geteditor || return 1
    "${_EDITOR}" "${_LIMINE_CONFIG}"
}

_limine_bios() {
    _BOOTDEV=""
    _limine_common
    _common_bootloader_checks
    _check_bootpart
    if ! ${_LSBLK} FSTYPE "${_BOOTDEV}" 2>"${_NO_LOG}" | grep -q "ext"; then
        _dialog --title " ERROR " --no-mouse --infobox "LIMINE BIOS can only boot from ext2/3/4 partition with /boot on it." 3 70
        return 1
    fi
    _dialog --no-mouse --infobox "Setting up LIMINE BIOS now..." 3 60
    _LIMINE_CONFIG="${_DESTDIR}/boot/limine.cfg"
    _KERNEL="${_SUBDIR}/${_VMLINUZ}"
    _INITRD="${_SUBDIR}/${_INITRAMFS}"
    _limine_config
    _geteditor
    _PARENT_BOOTDEV="$(${_LSBLK} PKNAME "${_BOOTDEV}")"
    _chroot_mount
    cp "${_DESTDIR}/usr/share/limine/limine-bios.sys" "${_DESTDIR}/boot/"
    if chroot "${_DESTDIR}" limine bios-install "${_PARENT_BOOTDEV}" &>"${_LOG}"; then
        _pacman_hook_limine_bios
        _dialog --title " Success " --no-mouse --infobox "LIMINE BIOS has been setup successfully." 3 50
        sleep 3
        _S_BOOTLOADER=1

    else
        _dialog --title " ERROR " --msgbox "Setting up LIMINE BIOS failed." 5 40
    fi
    _chroot_umount
}

_limine_uefi() {
    _limine_common
    _dialog --no-mouse --infobox "Setting up LIMINE now..." 3 60
    [[ -d "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT" ]] || mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/"
    cp -f "${_DESTDIR}/usr/share/limine/BOOT${_UEFI_ARCH}.EFI" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/LIMINE${_UEFI_ARCH}.EFI"
    _LIMINE_CONFIG="${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/limine.cfg"
    _limine_config
    if [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/LIMINE${_UEFI_ARCH}.EFI" ]]; then
        _BOOTMGR_LABEL="LIMINE"
        _BOOTMGR_LOADER_PATH="/EFI/BOOT/LIMINE${_UEFI_ARCH}.EFI"
        _uefi_bootmgr_setup
        mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT"
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        cp -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/LIMINE${_UEFI_ARCH}.EFI" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        sleep 2
        _pacman_hook_limine_uefi
        _dialog --title " Success " --no-mouse --infobox "LIMINE has been setup successfully." 3 50
        sleep 3
        _S_BOOTLOADER=1

    else
        _dialog --title " ERROR " --msgbox "Setting up LIMINE failed." 5 40
    fi
}
