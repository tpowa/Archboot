#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_mkinitcpio() {
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        # disable error out on kms install hook
        sed -i -e 's: add_checked_modules_from_symbol: #add_checked_modules_from_symbol:g' \
            "${_DESTDIR}"/usr/lib/initcpio/install/kms
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
    ${_EDITOR} "${_DESTDIR}""${_FILE}"
    _run_mkinitcpio | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Rebuilding initramfs on installed system..." 6 75 0
    _mkinitcpio_error
}

_check_root_password() {
    # check if empty password is set
    if chroot "${_DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q NP; then
        _dialog --no-mouse --infobox "Setup detected no password set for root user,\nplease set new password now." 6 50
        sleep 3
        _set_password Root root || return 1
    fi
    # check if account is locked
    if chroot "${_DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q L; then
        _dialog --no-mouse --infobox "Setup detected locked account for root user,\nplease set new password to unlock account now." 6 50
        _set_password Root root || return 1
    fi
}

_set_password() {
    _PASSWORD=""
    _PASS=""
    _PASS2=""
    while [[ -z "${_PASSWORD}" ]]; do
        while [[ -z "${_PASS}" ]]; do
            _dialog --title " New ${1} Password " --insecure --passwordbox "" 7 50 2>"${_ANSWER}" || return 1
            _PASS=$(cat "${_ANSWER}")
        done
        while [[ -z  "${_PASS2}" ]]; do
            _dialog --title " Retype ${1} Password " --insecure --passwordbox "" 7 50 2>"${_ANSWER}" || return 1
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
    chroot "${_DESTDIR}" passwd ${2} < /tmp/.password &>"${_NO_LOG}"
    rm /tmp/.password
}

_user_management() {
    _NEXTITEM=1
    while true; do
        _DEFAULT="--default-item ${_NEXTITEM}"
        _dialog --title " User Management " --no-cancel ${_DEFAULT} --menu "" 10 40 7 \
            "1" "Set Root Password" \
            "2" "Set Default Shell" \
            "3" "Add User" \
            "4" "Return to System Configuration" 2>"${_ANSWER}" || break
        _FILE="$(cat "${_ANSWER}")"
        if [[ "${_FILE}" = "1" ]]; then
            _set_password Root root
            _NEXTITEM=2
        elif [[ "${_FILE}" = "2" ]]; then
            _dialog --title " Default Shell " --no-cancel --menu "" 8 45 2 \
                "BASH" "Standard Shell" \
                "ZSH"  "More features for experts" 2>"${_ANSWER}" || return 1
            _SHELL=""
            case $(cat "${_ANSWER}") in
                "BASH") _SHELL="bash"
                    if ! [[ -f "${_DESTDIR}/usr/share/bash-completion/completions/arch" ]]; then
                        _PACKAGES="bash-completion"
                        _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
                        _pacman_error
                    fi
                    ;;
                "ZSH") _SHELL="zsh"
                    if ! [[ -f "${_DESTDIR}/usr/bin/zsh" ]]; then
                        _PACKAGES="grml-zsh-config"
                        _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
                        _pacman_error
                    fi
                    ;;
            esac
            if chroot "${_DESTDIR}" chsh -l | grep -q "/usr/bin/${_SHELL}"; then
                # change root shell
                chroot "${_DESTDIR}" chsh -s "/usr/bin/${_SHELL}" root &>"${_LOG}"
                # change default shell
                sed -i -e "s#^SHELL=.*#SHELL=/usr/bin/${_SHELL}#g" "${_DESTDIR}"/etc/default/useradd
            fi
            _NEXTITEM=3
        elif [[ "${_FILE}" = "3" ]]; then
            _USER=""
            while [[ -z "${_USER}" ]]; do
                _dialog --title " Setup User " --no-cancel --inputbox "Enter Username" 8 30 "" 2>"${_ANSWER}" || return 1
                _USER=$(cat "${_ANSWER}")
                if grep -q "^${_USER}:" ${_DESTDIR}/etc/passwd; then
                    _dialog --title " ERROR " --no-mouse --infobox "Username already exists! Please choose an other one." 3 60
                    sleep 3
                    _USER=""
                fi
            done
            _FN=""
            while [[ -z "${_FN}" ]]; do
                _dialog --title " Setup ${_USER} " --no-cancel --inputbox "Enter a comment eg. your Full Name" 8 40 "" 2>"${_ANSWER}" || return 1
                _FN=$(cat "${_ANSWER}")
            done
            chroot "${_DESTDIR}" useradd -c "${_FN}" -m "${_USER}"
            _set_password User ${_USER}
            _NEXTITEM=4
        elif [[ "${_FILE}" = "4" ]]; then
            _NEXTITEM=3
            break
        fi
    done
}
# vim: set ft=sh ts=4 sw=4 et:
