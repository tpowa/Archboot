#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>


_pacman() {
    #shellcheck disable=SC2086,SC2068
    ${_PACMAN} -Sy ${_PACKAGES[@]} &>"${_LOG}" && : > /tmp/.pacman-success
    rm /.archboot
}

_run_pacman(){
    _chroot_mount
    # Set up the necessary directories for pacman use
    [[ ! -d "${_DESTDIR}${_CACHEDIR}" ]] && mkdir -p "${_DESTDIR}${_CACHEDIR}"
    [[ ! -d "${_DESTDIR}${_PACMAN_LIB}" ]] && mkdir -p "${_DESTDIR}${_PACMAN_LIB}"
    : > /.archboot
    _pacman &
    #shellcheck disable=SC2116,SC2068
    _progress_wait "0" "99" "Installing package(s):\n$(echo ${_PACKAGES[@]})..." "2"
    # pacman finished, display scrollable output
    if [[ -e "/tmp/.pacman-success" ]]; then
        _progress "100" "Package installation complete." 6 75
        sleep 2
    else
        _progress "100" "Package installation failed." 6 75
        sleep 2
    fi
    # ensure the disk is synced
    sync
    _chroot_umount
}

_pacman_error() {
    if ! [[ -e "/tmp/.pacman-success" ]]; then
        _RESULT="Installation Failed (see errors below)"
        _dialog --title "${_RESULT}" --exit-label "Continue" \
        --textbox "${_DESTDIR}/var/log/pacman.log" 18 70 || return 1
    fi
    rm /tmp/.pacman-success
}

# any automatic configuration should go here
_run_autoconfig() {
    _auto_timesetting
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
    _auto_windowkeys
    _auto_bash
}

_install_packages() {
    _destdir_mounts || return 1
    # add packages from Archboot defaults
    . /etc/archboot/defaults
    _PACKAGES=(${_PACKAGES[@]/linux-firmware*})
    _auto_packages
    #shellcheck disable=SC2116,SC2068
    _dialog --title " Summary " --yesno "Next step will install the following packages for a minimal system:\n$(echo ${_PACKAGES[@]})\n\nYou can watch the progress on your ${_VC} console." 9 75 || return 1
    #shellcheck disable=SC2116,SC2068
    _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n$(echo ${_PACKAGES[@]})..." 8 75 0
    _pacman_error || return 1
    _NEXTITEM=3
    _chroot_mount
    # automagic time!
    _run_autoconfig | _dialog --title " Autoconfiguration " --no-mouse --gauge "Writing base configuration..." 6 75 0
    _chroot_umount
    _run_locale_gen | _dialog --title " Locales " --no-mouse --gauge "Rebuilding glibc locales on installed system..." 6 75 0
}
