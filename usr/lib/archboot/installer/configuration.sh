#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_mkinitcpio() {
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        chroot "${_DESTDIR}" mkinitcpio -p "${_KERNELPKG}"-"${_RUNNING_ARCH}" |& tee -a "${_LOG}" /tmp/mkinitcpio.log &>"${_LOG}"
    else
        chroot "${_DESTDIR}" mkinitcpio -p "${_KERNELPKG}" |& tee -a "${_LOG}" /tmp/mkinitcpio.log &>"${_LOG}"
    fi
    echo $? > /tmp/.mkinitcpio-retcode
    if [[ $(cat /tmp/.mkinitcpio-retcode) -ne 0 ]]; then
        echo -e "\nMkinitcpio FAILED." >>/tmp/pacman.log
    else
        echo -e "\nMkinitcpio Complete." >>/tmp/pacman.log
    fi
    rm /.archboot
}

_run_mkinitcpio() {
    _dialog --no-mouse --infobox "" 3 70
    _chroot_mount
    echo "Initramfs progress..." > /tmp/mkinitcpio.log
    touch /.archboot
    _mkinitcpio &
    _progress_wait "0" "99" "Rebuilding initramfs on installed system..." "0.1"
    if [[ $(cat /tmp/.mkinitcpio-retcode) -ne 0 ]]; then
        _progress "100" "Rebuilding initramfs failed." 6 75
        sleep 2
    else
        _progress "100" "Rebuilding initramfs complete." 6 75
        sleep 2
    fi
    _chroot_umount
}

_mkinitcpio_error() {
    # mkinitcpio finished, display scrollable output on error
    if [[ $(cat /tmp/.mkinitcpio-retcode) -ne 0 ]]; then
        _RESULT="Mkinitcpio Failed (see errors below)"
        _dialog --title "${_RESULT}" --exit-label "Continue" \
        --textbox "/tmp/mkinitcpio.log" 18 70 || return 1
    fi
    rm /tmp/.mkinitcpio-retcode
}

_run_locale_gen() {
    touch /.archboot
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
        [[ -e ${_DESTDIR}/usr/lib/initcpio/install/${i} ]] || _HOOK_ERROR=1
    done
    if [[ -n "${_HOOK_ERROR}" ]]; then
        _dialog --title " ERROR " --no-mouse --infobox "Detected error in 'HOOKS=' line,\nplease correct HOOKS= in /etc/mkinitcpio.conf!" 6 70
        sleep 5
    else
        _run_mkinitcpio | _dialog --title " Logging to ${_LOG} " --gauge "Rebuilding initramfs on installed system..." 6 75 0
        _error_mkinitcpio
    fi
}

_set_locale() {
    if [[ -z "${_S_LOCALE}" && ! -e "/.localize" ]]  && grep -qw '^archboot' /etc/hostname ; then
        localize
        _auto_locale
        _auto_set_locale
        _run_locale_gen
    fi
    _S_LOCALE=1
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
