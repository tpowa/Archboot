#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_uki_config() {
    _UKIFY_CONFIG="${_DESTDIR}/etc/kernel/uki.conf"
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
    _dialog --msgbox "You will now be put into the editor to edit:\n- kernel commandline config file\n- uki config file\n\nAfter you save your changes, exit the editor." 9 50
}

_uki_install() {
    _BOOTMGR_LABEL="Arch Linux - Unified Kernel Image"
    _BOOTMGR_LOADER_PATH="/EFI/Linux/arch-linux.efi"
    _uefi_bootmgr_setup
    mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT"
    rm -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
    cp -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/Linux/arch-linux.efi" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
    sleep 2
    _progress "100" "Unified Kernel Image has been setup successfully."
    sleep 2
    _S_BOOTLOADER=1
}

_uki_uefi() {
    if [[ ! -f "${_DESTDIR}/usr/lib/systemd/ukify" ]]; then
        _PACKAGES=(systemd-ukify)
        #shellcheck disable=SC2116,SC2068
        _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n$(echo ${_PACKAGES[@]})..." 7 75 0
        _pacman_error
    fi
    _uki_config
    _geteditor || return 1
    "${_EDITOR}" "${_CMDLINE}"
    "${_EDITOR}" "${_UKIFY_CONFIG}"
    # enable uki handling in presets
    sd '#default_uki' 'default_uki' "${_DESTDIR}"/etc/mkinitcpio.d/*.preset
    _run_mkinitcpio | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Running mkinitcpio on installed system..." 6 75 0
    _mkinitcpio_error
    if [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/Linux/arch-linux.efi" ]]; then
        _uki_install | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Setting up Unified Kernel Image..." 6 75 0
    else
        _dialog --title " ERROR " --no-mouse --infobox "Setting up Unified Kernel Image failed!" 3 60
        sleep 3
    fi
}
