#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_uki_config() {
    _UKIFY_CONFIG="${_DESTDIR}/etc/ukify.conf"
    _CMDLINE="${_DESTDIR}/etc/kernel/cmdline"
    echo "${_KERNEL_PARAMS_MOD}" > "${_CMDLINE}"
    echo "[UKI]" > "${_UKIFY_CONFIG}"
    echo "Linux=/boot/${_VMLINUZ}" >> "${_UKIFY_CONFIG}"
    if [[ -n ${_UCODE} ]]; then
        echo "Initrd=/boot/${_UCODE} /boot/${_INITRAMFS}" >> "${_UKIFY_CONFIG}"
    else
        echo "Initrd=/boot/${_INITRAMFS}" >> "${_UKIFY_CONFIG}"
    fi
    cat << CONFEOF >> "${_UKIFY_CONFIG}"
Cmdline=@/etc/kernel/cmdline
OSRelease=@/etc/os-release
Splash=/usr/share/systemd/bootctl/splash-arch.bmp
CONFEOF
    mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/Linux"
    _dialog --msgbox "You will now be put into the editor to edit:\n- kernel commandline config file\n- ukify.conf config file\n\nAfter you save your changes, exit the editor." 9 50
}

_uki_install() {
    _uki_autobuild
    _BOOTMGR_LABEL="Arch Linux - Unified Kernel Image"
    _BOOTMGR_LOADER_PATH="/EFI/Linux/archlinux-linux.efi"
    _uefi_bootmgr_setup
    mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT"
    rm -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
    cp -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/Linux/archlinux-linux.efi" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
    sleep 2
    _progress "100" "Unified Kernel Image has been setup successfully."
    sleep 2
    _S_BOOTLOADER=1
}

_uki_uefi() {
    if [[ ! -f "${_DESTDIR}/usr/lib/systemd/ukify" ]]; then
        _PACKAGES="systemd-ukify"
        _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
        _pacman_error
    fi
    _uki_config
    _geteditor || return 1
    "${_EDITOR}" "${_CMDLINE}"
    "${_EDITOR}" "${_UKIFY_CONFIG}"
    ${_NSPAWN} /usr/lib/systemd/ukify build --config=/etc/ukify.conf --output "${_UEFISYS_MP}"/EFI/Linux/archlinux-linux.efi >>"${_LOG}"
    if [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/Linux/archlinux-linux.efi" ]]; then
        _uki_install | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Setting up Unified Kernel Image..." 6 75 0
    else
        _dialog --title " ERROR " --no-mouse --infobox "Setting up Unified Kernel Image failed!" 3 60
        sleep 3
    fi
}
