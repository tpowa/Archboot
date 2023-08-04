#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>

_run_pacman(){
    _chroot_mount
    # Set up the necessary directories for pacman use
    [[ ! -d "${_DESTDIR}/var/cache/pacman/pkg" ]] && mkdir -p "${_DESTDIR}/var/cache/pacman/pkg"
    [[ ! -d "${_DESTDIR}/var/lib/pacman" ]] && mkdir -p "${_DESTDIR}/var/lib/pacman"
    _dialog --title " Pacman " --no-mouse --infobox "Installing package(s) to ${_DESTDIR}:\n${_PACKAGES}...\n\nCheck ${_VC} console (ALT-F${_VC_NUM}) for progress..." 8 70
    echo "Installing Packages..." >/tmp/pacman.log
    sleep 5
    #shellcheck disable=SC2086,SC2069
    ${_PACMAN} -Sy ${_PACKAGES} |& tee -a "${_LOG}" /tmp/pacman.log &>"${_NO_LOG}"
    echo $? > /tmp/.pacman-retcode
    if [[ $(cat /tmp/.pacman-retcode) -ne 0 ]]; then
        echo -e "\nPackage Installation FAILED." >>/tmp/pacman.log
    else
        echo -e "\nPackage Installation Complete." >>/tmp/pacman.log
    fi
    # pacman finished, display scrollable output
    local _RESULT=''
    if [[ $(cat /tmp/.pacman-retcode) -ne 0 ]]; then
        _RESULT="Installation Failed (see errors below)"
        _dialog --title "${_RESULT}" --exit-label "Continue" \
        --textbox "/tmp/pacman.log" 18 70 || return 1
    else
        _dialog --no-mouse --infobox "Package installation complete." 3 40
        sleep 3
    fi
    rm /tmp/.pacman-retcode
    # ensure the disk is synced
    sync
    _chroot_umount
}

_install_packages() {
    _destdir_mounts || return 1
    _PACKAGES=""
    # add packages from archboot defaults
    _PACKAGES=$(grep '^_PACKAGES' /etc/archboot/defaults | sed -e 's#_PACKAGES=##g' -e 's#"##g')
    # fallback if _PACKAGES is empty
    [[ -z "${_PACKAGES}" ]] && _PACKAGES="base linux linux-firmware"
    _auto_packages
    # fix double spaces
    _PACKAGES="${_PACKAGES//  / }"
    _dialog --title " Summary " --yesno "Next step will install the following packages for a minimal system:\n${_PACKAGES}\n\nYou can watch the progress on your ${_VC} console." 9 75 || return 1
    _run_pacman
    _NEXTITEM="3"
    _chroot_mount
    # automagic time!
    # any automatic configuration should go here
    (_auto_timesetting
    _auto_network
    _auto_fstab
    _auto_scheduler
    _auto_swap
    _auto_mdadm
    _auto_luks
    _auto_pacman_keyring
    _auto_testing
    _auto_pacman_mirror
    _auto_vconsole
    _auto_hostname
    _auto_locale
    _auto_set_locale
    _auto_bash) | _dialog --title " Autoconfiguration " --no-mouse --gauge "Writing base configuration..." 6 75 0
    # tear down the chroot environment
    _chroot_umount
    _run_locale_gen
}
# vim: set ft=sh ts=4 sw=4 et:
