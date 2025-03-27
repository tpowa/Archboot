#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_limine_common() {
    if [[ ! -f "${_DESTDIR}/usr/bin/limine" ]]; then
        _PACKAGES=(limine)
        _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES[*]}..." 7 75 0
        _pacman_error
    fi
}

_limine_config() {
    _PARTN="$(${_LSBLK} PARTN "${_BOOTDEV}")"
    cat << CONFEOF > "${_LIMINE_CONFIG}"
timeout: 5

/Arch Linux
    protocol: linux
    kernel_path: boot(${_PARTN}):/${_VMLINUZ}
    cmdline: ${_KERNEL_PARAMS_MOD}
    module_path: boot(${_PARTN}):/${_INITRAMFS}
CONFEOF
    ## Edit limine.conf config file
    _dialog --msgbox "You will now be put into the editor to edit:\nlimine.conf\n\nAfter you save your changes, exit the editor." 8 50
    _geteditor || return 1
    _editor "${_LIMINE_CONFIG}"
}

_limine_bios() {
    _BOOTDEV=""
    _limine_common
    _common_bootloader_checks
    _check_bootpart
    if ! ${_LSBLK} FSTYPE "${_BOOTDEV}" 2>"${_NO_LOG}" | rg -q 'vfat'; then
        _dialog --title " ERROR " --no-mouse --infobox "LIMINE BIOS can only boot from vfat partition with /boot on it." 3 70
        sleep 5
        return 1
    fi
    _dialog --no-mouse --infobox "Setting up LIMINE BIOS now..." 3 60
    _LIMINE_CONFIG="${_DESTDIR}/boot/limine.conf"
    _VMLINUZ="${_SUBDIR}/${_VMLINUZ}"
    _INITRAMFS="${_SUBDIR}/${_INITRAMFS}"
    _limine_config
    _geteditor
    _PARENT_BOOTDEV="$(${_LSBLK} PKNAME "${_BOOTDEV}")"
    _chroot_mount
    cp "${_DESTDIR}/usr/share/limine/limine-bios.sys" "${_DESTDIR}/boot/"
    # write to template
    { echo "### limine bios"
    echo "echo \"Setting up LIMINE BIOS now...\""
    echo "_chroot_mount"
    echo "cp \"\${_DESTDIR}/usr/share/limine/limine-bios.sys\" \"\${_DESTDIR}/boot/\""
    } >> "${_TEMPLATE}"
    if chroot "${_DESTDIR}" limine bios-install "${_PARENT_BOOTDEV}" &>"${_LOG}"; then
        _pacman_hook_limine_bios
        # write to template
        { echo "chroot \"\${_DESTDIR}\" limine bios-install \"${_PARENT_BOOTDEV}\" &>\"\${_LOG}\""
        echo ""
        } >> "${_TEMPLATE}"
        _dialog --title " Success " --no-mouse --infobox "LIMINE BIOS has been setup successfully." 3 50
        sleep 3
        _S_BOOTLOADER=1

    else
        _dialog --title " ERROR " --msgbox "Setting up LIMINE BIOS failed." 5 40
    fi
    _chroot_umount
    # write to template
    { echo "_chroot_umount"
    echo ""
    } >> "${_TEMPLATE}"
}

_limine_uefi() {
    _limine_common
    _dialog --no-mouse --infobox "Setting up LIMINE now..." 3 60
    if ! [[ -d "${_DESTDIR}/${_ESP_MP}/EFI/BOOT" ]]; then
        mkdir -p "${_DESTDIR}/${_ESP_MP}/EFI/BOOT/"
        # write to template
        echo "mkdir -p \"\${_DESTDIR}/${_ESP_MP}/EFI/BOOT/\"" >> "${_TEMPLATE}"
    fi
    cp -f "${_DESTDIR}/usr/share/limine/BOOT${_UEFI_ARCH}.EFI" "${_DESTDIR}/${_ESP_MP}/EFI/BOOT/LIMINE${_UEFI_ARCH}.EFI"
    # write to template
    { echo "### limine uefi"
    echo "echo \"Setting up LIMINE now...\""
    echo "cp -f \"\${_DESTDIR}/usr/share/limine/BOOT${_UEFI_ARCH}.EFI\" \"\${_DESTDIR}/${_ESP_MP}/EFI/BOOT/LIMINE${_UEFI_ARCH}.EFI\""
    } >> "${_TEMPLATE}"
    _LIMINE_CONFIG="${_DESTDIR}/${_ESP_MP}/EFI/BOOT/limine.conf"
    _limine_config
    if [[ -e "${_DESTDIR}/${_ESP_MP}/EFI/BOOT/LIMINE${_UEFI_ARCH}.EFI" ]]; then
        _BOOTMGR_LABEL="LIMINE"
        _BOOTMGR_LOADER_PATH="/EFI/BOOT/LIMINE${_UEFI_ARCH}.EFI"
        _uefi_bootmgr_setup
        rm -f "${_DESTDIR}/${_ESP_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        cp -f "${_DESTDIR}/${_ESP_MP}/EFI/BOOT/LIMINE${_UEFI_ARCH}.EFI" "${_DESTDIR}/${_ESP_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        # write to template
        { echo "### default uefi bootloader"
        echo "rm -f \"\${_DESTDIR}/${_ESP_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI\""
        echo "cp -f \"\${_DESTDIR}/${_ESP_MP}/EFI/BOOT/LIMINE${_UEFI_ARCH}.EFI\" \"\${_DESTDIR}/${_ESP_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI\""
        echo ""
        } >> "${_TEMPLATE}"
        sleep 2
        _pacman_hook_limine_uefi
        _dialog --title " Success " --no-mouse --infobox "LIMINE has been setup successfully." 3 50
        sleep 3
        _S_BOOTLOADER=1

    else
        _dialog --title " ERROR " --msgbox "Setting up LIMINE failed." 5 40
    fi
}
