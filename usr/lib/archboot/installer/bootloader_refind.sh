#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_refind_uefi() {
    if [[ ! -f "${_DESTDIR}/usr/bin/refind-install" ]]; then
        _PACKAGES=(refind)
        #shellcheck disable=SC2116,SC2068
        _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n$(echo ${_PACKAGES[@]})..." 7 75 0
        _pacman_error
    fi
    _dialog --no-mouse --infobox "Setting up rEFInd now..." 3 60
    _chroot_mount
    # refind-install mounts devices again
    umount -q "${_DESTDIR}"/{boot,efi}
    chroot "${_DESTDIR}" refind-install &>"${_LOG}"
    _chroot_umount
    # write to template
    { echo "### refind"
    echo "echo \"Setting up rEFInd now...\""
    echo "_chroot_mount"
    echo "umount -q \"\${_DESTDIR}\"/{boot,efi}"
    echo "chroot \"\${_DESTDIR}\" refind-install &>\"\${_LOG}\""
    echo "_chroot_umount"
    } >> "${_TEMPLATE}"
    _REFIND_CONFIG="${_DESTDIR}/${_ESP_MP}/EFI/refind/refind.conf"
    cat << CONFEOF > "${_REFIND_CONFIG}"
timeout 20
use_nvram false
resolution 1024 768
scanfor manual,internal,external,optical,firmware
menuentry "Arch Linux" {
    icon     /EFI/refind/icons/os_arch.png
    volume   $(${_LSBLK} PARTUUID "${_BOOTDEV}")
    loader   /${_VMLINUZ}
    initrd   /${_INITRAMFS}
    options  "${_KERNEL_PARAMS_MOD}"
}
CONFEOF
    if [[ -e "${_DESTDIR}/${_ESP_MP}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" ]]; then
        if ! [[ -d "${_DESTDIR}/${_ESP_MP}/EFI/BOOT" ]]; then
            mkdir -p "${_DESTDIR}/${_ESP_MP}/EFI/BOOT"
            # write to template
            echo "mkdir -p \"\${_DESTDIR}/${_ESP_MP}/EFI/BOOT\"" >> "${_TEMPLATE}"
        fi
        rm -f "${_DESTDIR}/${_ESP_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        rm -f "${_DESTDIR}"/boot/refind_linux.conf
        cp -f "${_DESTDIR}/${_ESP_MP}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${_DESTDIR}/${_ESP_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        # write to template
        { echo "rm -f \"\${_DESTDIR}/${_ESP_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI\""
        echo "rm -f \"\${_DESTDIR}\"/boot/refind_linux.conf"
        echo "cp -f \"\${_DESTDIR}/${_ESP_MP}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi\" \"\${_DESTDIR}/${_ESP_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI\""
        } >> "${_TEMPLATE}"
        sleep 2
        _dialog --msgbox "You will now be put into the editor to edit:\nrefind.conf\n\nAfter you save your changes, exit the editor." 8 50
        _geteditor || return 1
        _editor "${_REFIND_CONFIG}"
        cp -f "${_REFIND_CONFIG}" "${_DESTDIR}/${_ESP_MP}/EFI/BOOT/"
        # write to template
        { echo "cp -f \"${_REFIND_CONFIG}\" \"\${_DESTDIR}/${_ESP_MP}/EFI/BOOT/\""
        echo ""
        } >> "${_TEMPLATE}"
        _pacman_hook_refind
        _dialog --title " Success " --no-mouse --infobox "rEFInd has been setup successfully." 3 50
        sleep 3
        _S_BOOTLOADER=1
    else
        _dialog --title " ERROR " --msgbox "Setting up rEFInd failed." 5 40
    fi
}
