#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_refind_uefi() {
    if [[ ! -f "${_DESTDIR}/usr/bin/refind-install" ]]; then
        _PACKAGES="refind"
        _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
        _pacman_error
    fi
    _dialog --no-mouse --infobox "Setting up rEFInd now..." 3 60
    _chroot_mount
    # refind-install mounts devices again
    umount -q "${_DESTDIR}"/{boot,efi}
    chroot "${_DESTDIR}" refind-install &>"${_LOG}"
    _chroot_umount
    _REFIND_CONFIG="${_DESTDIR}/${_UEFISYS_MP}/EFI/refind/refind.conf"
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
    if [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" ]]; then
        [[ -d "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT" ]] || mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT"
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        rm -f "${_DESTDIR}"/boot/refind_linux.conf
        cp -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        sleep 2
        _dialog --msgbox "You will now be put into the editor to edit:\nrefind.conf\n\nAfter you save your changes, exit the editor." 8 50
        _geteditor || return 1
        "${_EDITOR}" "${_REFIND_CONFIG}"
        cp -f "${_REFIND_CONFIG}" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/"
        _pacman_hook_refind
        _dialog --title " Success " --no-mouse --infobox "rEFInd has been setup successfully." 3 50
        sleep 3
        _S_BOOTLOADER=1
    else
        _dialog --title " ERROR " --msgbox "Setting up rEFInd failed." 5 40
    fi
}
