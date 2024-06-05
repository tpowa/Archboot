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
    _USER="root"
    # check if empty password is set
    if passwd -R "${_DESTDIR}" -S root | cut -d ' ' -f2 | grep -q NP; then
        _dialog --title " Root Account " --no-mouse --infobox "Setup detected no password set for root user.\nPlease set new password now." 4 50
        sleep 3
        if _prepare_password Root; then
            _set_password
        else
            return 1
        fi
    fi
    # check if account is locked
    if passwd -R "${_DESTDIR}" -S root | cut -d ' ' -f2 | grep -q L; then
        _dialog --title " Root Account " --no-mouse --infobox "Setup detected locked account for root user.\nPlease set new password to unlock account now." 4 50
        if _prepare_password Root; then
            _set_password
        else
            return 1
        fi
    fi
}

_prepare_password() {
    while true; do
        _PASS=""
        _PASS2=""
        while [[ -z "${_PASS}" ]]; do
            _dialog --no-cancel --title " New ${1} Password " --insecure --passwordbox "" 7 50 2>"${_ANSWER}" || return 1
            _PASS=$(cat "${_ANSWER}")
        done
        while [[ -z "${_PASS2}" ]]; do
            _dialog --no-cancel --title " Retype ${1} Password " --insecure --passwordbox "" 7 50 2>"${_ANSWER}" || return 1
            _PASS2=$(cat "${_ANSWER}")
        done
        if [[ "${_PASS}" == "${_PASS2}" ]]; then
            _PASSWORD=${_PASS}
            echo "${_PASSWORD}" > /tmp/.password
            echo "${_PASSWORD}" >> /tmp/.password
            _PASSWORD=/tmp/.password
            _dialog --title " Success " --no-mouse --infobox "Password entered correct." 3 50
            sleep 3
            break
        else
            _dialog --title " ERROR " --no-mouse --infobox "Password didn't match, please enter again." 3 50
            sleep 3
        fi
    done
}

_set_password() {
    passwd -R "${_DESTDIR}" "${_USER}" < /tmp/.password &>"${_NO_LOG}"
    rm /tmp/.password
    _dialog --title " Success " --no-mouse --infobox "New password set for ${_USER}." 3 50
    sleep 3
}

_set_user() {
    while true; do
        _dialog --title " Create User Account " --no-cancel --inputbox "Enter Username" 8 30 "" 2>"${_ANSWER}" || return 1
        _USER=$(cat "${_ANSWER}")
        [[ -n "${_USER}" ]] && break
    done
}

_set_comment() {
    while true; do
        _dialog --title " ${_USER} Account " --no-cancel --inputbox "Enter a comment eg. your Full Name" 8 40 "" 2>"${_ANSWER}" || return 1
        _FN=$(cat "${_ANSWER}")
        [[ -n "${_FN}" ]] && break
    done
}

_user_management() {
    _NEXTITEM="1"
    while true; do
        _DEFAULT="--default-item ${_NEXTITEM}"
        #shellcheck disable=SC2086
        _dialog --title " User Management " --no-cancel ${_DEFAULT} --menu "" 10 40 7 \
            "1" "Set Default Shell" \
            "2" "Create User Account" \
            "3" "Modify User Account" \
            "<" "Return to System Configuration" 2>"${_ANSWER}" || break
        _NEXTITEM="$(cat "${_ANSWER}")"
        case $(cat "${_ANSWER}") in
            "1") _dialog --title " Default Shell " --no-cancel --menu "" 8 45 2 \
                 "BASH" "Standard Base Shell" \
                 "ZSH"  "More features for experts" 2>"${_ANSWER}" || return 1
                 case $(cat "${_ANSWER}") in
                    "BASH") _SHELL="bash"
                            if ! [[ -f "${_DESTDIR}/usr/share/bash-completion/completions/arch" ]]; then
                                _PACKAGES="bash-completion"
                                _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " \
                                    --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
                                _pacman_error
                            fi ;;
                    "ZSH") _SHELL="zsh"
                           if ! [[ -f "${_DESTDIR}/usr/bin/zsh" ]]; then
                                _PACKAGES="grml-zsh-config"
                                _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " \
                                    --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
                                _pacman_error
                            fi ;;
                 esac
                 # change default shell for root and all users >= UID 1000
                 sed -i -e "s#^SHELL=.*#SHELL=/usr/bin/${_SHELL}#g" "${_DESTDIR}"/etc/default/useradd
                 for i in root $(grep 'x:10[0-9][0-9]' "${_DESTDIR}"/etc/passwd | cut -d : -f 1); do
                     usermod -R "${_DESTDIR}" -s "/usr/bin/${_SHELL}" "${i}" &>"${_LOG}"
                 done
                 _dialog --title " Success " --no-mouse --infobox "Default shell set to ${_SHELL}." 3 50
                 sleep 3
                _NEXTITEM="2" ;;
            "2") while true; do
                     _set_user || break
                     if grep -q "^${_USER}:" "${_DESTDIR}"/etc/passwd; then
                         _dialog --title " ERROR " --no-mouse --infobox "Username already exists! Please choose an other one." 3 60
                         sleep 3
                     else
                         _set_comment || break
                         _prepare_password User || break
                         if useradd -R "${_DESTDIR}" -c "${_FN}" -m "${_USER}" &>"${_LOG}"; then
                            _set_password
                            _dialog --title " Success " --no-mouse --infobox "User Account ${_USER} created succesfully." 3 60
                            sleep 3
                            _NEXTITEM="2"
                            break
                         else
                             _dialog --title " ERROR " --no-mouse --infobox "User creation failed! Please try again." 3 60
                             sleep 3
                         fi
                     fi
                 done ;;
            "3") while true; do
                     # root and all users with UID >= 1000
                     _USERS="$(grep 'x:10[0-9][0-9]' "${_DESTDIR}"/etc/passwd | cut -d : -f 1,5 | sed -e 's: :#:g' | sed -e 's#:# #g')"
                     #shellcheck disable=SC2086
                     _dialog --no-cancel --menu " User Account Selection " 15 40 10 \
                        "root" "Super User" ${_USERS} "< Back" "Return To Previous Menu" 2>"${_ANSWER}" || return 1
                     _USER=$(cat "${_ANSWER}")
                     if [[ "${_USER}" = "root" ]]; then
                         if _prepare_password Root; then
                            _set_password
                         fi
                     elif [[ "${_USER}" = "< Back" ]]; then
                         break
                     else
                        while true; do
                            _dialog --title " Modify User Account ${_USER} " --no-cancel --menu "" 10 45 4 \
                                "1" "Change Password" \
                                "2" "Change Comment" \
                                "3" "Delete User" \
                                "<" "Return To User Selection" 2>"${_ANSWER}" || break
                            case $(cat "${_ANSWER}") in
                                "1") if _prepare_password User; then
                                        _set_password
                                     fi ;;
                                "2") if _set_comment; then
                                         usermod -R "${_DESTDIR}" -c "${_FN}" "${_USER}"
                                         _dialog --title " Success " --no-mouse --infobox "New comment set for ${_USER}." 3 50
                                         sleep 3
                                     fi ;;
                                "3") if _dialog --defaultno --yesno \
                                         "${_USER} will be COMPLETELY ERASED!\nALL USER DATA OF ${_USER} WILL BE LOST.\n\nAre you absolutely sure?" 0 0 && \
                                         userdel -R "${_DESTDIR}" -r "${_USER}" &>"${_LOG}"; then
                                        _dialog --title " Success " --no-mouse --infobox "User ${_USER} deleted succesfully." 3 50
                                        sleep 3
                                     fi ;;
                                 *) break ;;
                            esac
                        done
                     fi
                 done
                 _NEXTITEM="3" ;;
        *) _NEXTITEM="3"
            break ;;
        esac
    done
}
# vim: set ft=sh ts=4 sw=4 et:
