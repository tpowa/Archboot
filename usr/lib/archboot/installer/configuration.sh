#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_mkinitcpio() {
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        chroot "${_DESTDIR}" mkinitcpio -p "${_KERNELPKG}"-"${_RUNNING_ARCH}" &>"${_LOG}" && : > /tmp/.mkinitcpio-success
    else
        chroot "${_DESTDIR}" mkinitcpio -p "${_KERNELPKG}" &>"${_LOG}" && : > /tmp/.mkinitcpio-success
    fi
    rm /.archboot
}

_run_mkinitcpio() {
    _chroot_mount
    echo "Initramfs progress..." > /tmp/mkinitcpio.log
    : > /.archboot
    _mkinitcpio &
    _progress_wait "0" "99" "Rebuilding initramfs on installed system..." "0.1"
    if [[ -e "/tmp/.mkinitcpio-success" ]]; then
        _progress "100" "Rebuilding initramfs complete." 6 75
        sleep 2
    else
        _progress "100" "Rebuilding initramfs failed." 6 75
        sleep 2
    fi
    _chroot_umount
}

_mkinitcpio_error() {
    # mkinitcpio finished, display scrollable output on error
    if ! [[ -e "/tmp/.mkinitcpio-success" ]]; then
        _dialog --title " ERROR " --msgbox "Mkinitcpio Failed (see errors ${_LOG} | ${_VC})" 5 70 || return 1
    fi
    rm /tmp/.mkinitcpio-success
}

_run_locale_gen() {
    : > /.archboot
    _locale_gen &
    _progress_wait "0" "99" "Rebuilding glibc locales on installed system..." "0.05"
    _progress "100" "Rebuilding glibc locales on installed system complete." 6 75
    sleep 2
}

_set_mkinitcpio() {
    _HOOK_ERROR=""
    ${_EDITOR} "${_DESTDIR}""${_FILE}"
    #shellcheck disable=SC2013
    for i in $(grep ^HOOKS "${_DESTDIR}"/etc/mkinitcpio.conf | sed -e 's/"//g' -e 's/HOOKS=\(//g' -e 's/\)//g'); do
        if ! [[ -e ${_DESTDIR}/usr/lib/initcpio/install/${i} ]];
            _HOOK_ERROR=1
        fi
    done
    if [[ -n "${_HOOK_ERROR}" ]]; then
        _dialog --title " ERROR " --no-mouse --infobox "Detected error in 'HOOKS=' line,\nplease correct HOOKS= in /etc/mkinitcpio.conf!" 6 70
        sleep 5
    else
        _run_mkinitcpio | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Rebuilding initramfs on installed system..." 6 75 0
        _mkinitcpio_error
    fi
}

_check_root_password() {
    # check if empty password is set
    if chroot "${_DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q NP; then
        _dialog --no-mouse --infobox "Setup detected no password set for root user,\nplease set new password now." 6 50
        sleep 3
        _set_password || return 1
    fi
    # check if account is locked
    if chroot "${_DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q L; then
        _dialog --no-mouse --infobox "Setup detected locked account for root user,\nplease set new password to unlock account now." 6 50
        _set_password || return 1
    fi
}

_set_password() {
    _PASSWORD=""
    _PASS=""
    _PASS2=""
    while [[ -z "${_PASSWORD}" ]]; do
        while [[ -z "${_PASS}" ]]; do
            _dialog --title " New Root Password " --insecure --passwordbox "" 7 50 2>"${_ANSWER}" || return 1
            _PASS=$(cat "${_ANSWER}")
        done
        while [[ -z  "${_PASS2}" ]]; do
            _dialog --title " Retype Root Password " --insecure --passwordbox "" 7 50 2>"${_ANSWER}" || return 1
            _PASS2=$(cat "${_ANSWER}")
        done
        if [[ "${_PASS}" == "${_PASS2}" ]]; then
            _PASSWORD=${_PASS}
            echo "${_PASSWORD}" > /tmp/.password
            echo "${_PASSWORD}" >> /tmp/.password
            _PASSWORD=/tmp/.password
        else
            _dialog --title " ERROR " --no-mouse --infobox "Password didn't match, please enter again." 5 50
            sleep 3
            _PASSWORD=""
            _PASS=""
            _PASS2=""
        fi
    done
    chroot "${_DESTDIR}" passwd root < /tmp/.password &>"${_NO_LOG}"
    rm /tmp/.password
}
# vim: set ft=sh ts=4 sw=4 et:
