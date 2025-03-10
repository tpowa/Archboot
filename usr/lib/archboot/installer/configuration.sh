#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_mkinitcpio() {
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        # disable error out on kms install hook
        sd ' add_checked_modules_from_symbol' ' #add_checked_modules_from_symbol' \
            "${_DESTDIR}"/usr/lib/initcpio/install/kms
        if chroot "${_DESTDIR}" mkinitcpio -p "${_KERNELPKG}"-"${_RUNNING_ARCH}" &>"${_LOG}"; then
            : > /tmp/.mkinitcpio-success
            # write to template
            { echo "sd ' add_checked_modules_from_symbol' ' #add_checked_modules_from_symbol' \"\${_DESTDIR}\"/usr/lib/initcpio/install/kms"
            echo "chroot \"\${_DESTDIR}\" mkinitcpio -p \"${_KERNELPKG}\"-\"${_RUNNING_ARCH}\" &>\"\${_LOG}\""
            } >> "${_TEMPLATE}"
        fi
    else
        if chroot "${_DESTDIR}" mkinitcpio -p "${_KERNELPKG}" &>"${_LOG}"; then
        : > /tmp/.mkinitcpio-success
        # write to template
        echo "chroot \"\${_DESTDIR}\" mkinitcpio -p \"${_KERNELPKG}\" &>\"\${_LOG}\"" >> "${_TEMPLATE}"
        fi
    fi
    rm /.archboot
}

_run_mkinitcpio() {
    _chroot_mount
    # write to template
    { echo "### mkinitcpio"
    echo "_chroot_mount"
    } >> "${_TEMPLATE}"
    echo "Mkinitcpio progress..." > /tmp/mkinitcpio.log
    : > /.archboot
    # write to template
    echo "echo \"Running mkinitcpio on installed system...\"" >> "${_TEMPLATE}"
    _mkinitcpio &
    _progress_wait "0" "99" "Running mkinitcpio on installed system..." "0.1"
    if [[ -e "/tmp/.mkinitcpio-success" ]]; then
        _progress "100" "Mkinitcpio complete." 6 75
        sleep 2
    else
        _progress "100" "Mkinitcpio failed." 6 75
        sleep 2
    fi
    _chroot_umount
     # write to template
    { echo "_chroot_umount"
    echo ""
    } >> "${_TEMPLATE}"
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
     # write to template
     echo "echo \"Rebuilding glibc locales on installed system...\"" >> "${_TEMPLATE}"
    _locale_gen &
    _progress_wait "0" "99" "Rebuilding glibc locales on installed system..." "0.05"
    _progress "100" "Rebuilding glibc locales on installed system complete." 6 75
    sleep 2
}

_set_mkinitcpio() {
    _editor "${_DESTDIR}${_FILE}"
    _run_mkinitcpio | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Running mkinitcpio on installed system..." 6 75 0
    _mkinitcpio_error
}

_check_root_password() {
    _USER="root"
    # check if empty password is set
    if passwd -R "${_DESTDIR}" -S root | rg -q ' NP '; then
        _dialog --title " Root Account " --no-mouse --infobox "Setup detected no password set for root user.\nPlease set new password now." 4 50
        sleep 3
        if _prepare_password root; then
            _set_password
        else
            return 1
        fi
    fi
    # check if account is locked
    if passwd -R "${_DESTDIR}" -S root | rg -q ' L '; then
        _dialog --title " Root Account " --no-mouse --infobox "Setup detected locked account for root user.\nPlease set new password to unlock account now." 4 50
        if _prepare_password root; then
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
            # write to template
            { echo "### set ${1} password"
            echo "echo \"${_PASSWORD}\" > /tmp/.password"
            echo "echo \"${_PASSWORD}\" >> /tmp/.password"
            } >> "${_TEMPLATE}"
            _PASSWORD=/tmp/.password
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
    # write to template
    { echo "passwd -R \"\${_DESTDIR}\" \"${_USER}\" < /tmp/.password &>\"\${_NO_LOG}\""
    echo "echo \"New password set for ${_USER}.\""
    echo "rm /tmp/.password"
    echo ""
    } >> "${_TEMPLATE}"
    _dialog --title " Success " --no-mouse --infobox "New password set for ${_USER}." 3 50
    sleep 2
}

_set_user() {
    while true; do
        _dialog --title " Create User Account " --no-cancel --inputbox "Enter Username" 8 30 "" 2>"${_ANSWER}" || return 1
        _USER=$(cat "${_ANSWER}")
        [[ -n "${_USER}" ]] && break
    done
}

_set_comment() {
    _FN=""
    while true; do
        _dialog --title " ${_USER} Account " --no-cancel --inputbox "Enter a comment eg. your Full Name" 8 40 "" 2>"${_ANSWER}" || return 1
        _FN=$(cat "${_ANSWER}")
        [[ -n "${_FN}" ]] && break
    done
}

_user_management() {
    _NEXTITEM=1
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
            "1") if _dialog --title " Default Shell " --no-cancel --menu "" 8 45 2 \
                        "BASH" "Standard Base Shell" \
                        "ZSH"  "More features for experts" 2>"${_ANSWER}"; then
                    case $(cat "${_ANSWER}") in
                        "BASH") _SHELL="bash"
                                if ! [[ -f "${_DESTDIR}/usr/share/bash-completion/completions/arch" ]]; then
                                    _PACKAGES=(bash-completion)
                                    #shellcheck disable=SC2116,SC2068
                                    _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " \
                                        --gauge "Installing package(s):\n$(echo ${_PACKAGES[@]})..." 7 75 0
                                    _pacman_error
                                fi ;;
                        "ZSH") _SHELL="zsh"
                                if ! [[ -f "${_DESTDIR}/usr/bin/zsh" ]]; then
                                    _PACKAGES=(grml-zsh-config)
                                    #shellcheck disable=SC2116,SC2068
                                    _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " \
                                        --gauge "Installing package(s):\n$(echo ${_PACKAGES[@]})..." 7 75 0
                                    _pacman_error
                                fi ;;
                    esac
                    # change default shell for root and all users >= UID 1000
                    sd '^SHELL=.*' "SHELL=/usr/bin/${_SHELL}" "${_DESTDIR}"/etc/default/useradd
                    # write to template
                    { echo "### default shell"
                    echo "sd '^SHELL=.*' \"SHELL=/usr/bin/${_SHELL}\" \"\${_DESTDIR}\"/etc/default/useradd"
                    } >> "${_TEMPLATE}"
                    for i in root $(rg -o '(.*):x:10[0-9][0-9]' -r '$1' "${_DESTDIR}"/etc/passwd); do
                        usermod -R "${_DESTDIR}" -s "/usr/bin/${_SHELL}" "${i}" &>"${_LOG}"
                        # write to template
                        echo "usermod -R \"\${_DESTDIR}\" -s \"/usr/bin/${_SHELL}\" \"${i}\" &>\"\${_LOG}\"" >> "${_TEMPLATE}"
                    done
                    _dialog --title " Success " --no-mouse --infobox "Default shell set to ${_SHELL}." 3 50
                    # write to template
                    { echo "echo \"Default shell set to ${_SHELL}.\""
                    echo ""
                    } >> "${_TEMPLATE}"
                    sleep 3
                    _NEXTITEM=2
                else
                    _NEXTITEM=1
                fi ;;
            "2") while true; do
                     _set_user || break
                     if rg -q "^${_USER}:" "${_DESTDIR}"/etc/passwd; then
                         _dialog --title " ERROR " --no-mouse --infobox "Username already exists! Please choose an other one." 3 60
                         sleep 3
                     else
                         _ADMIN_ATTR=""
                         if _dialog --defaultno --yesno "Enable ${_USER} as Administrator and part of wheel group?" 5 60; then
                             _ADMIN_ATTR="-G wheel"
                         fi
                         _set_comment || break
                         _prepare_password user || break
                         #shellcheck disable=SC2086
                         if useradd -R "${_DESTDIR}" ${_ADMIN_ATTR} -c "${_FN}" -m "${_USER}" &>"${_LOG}"; then
                            # write to template
                            { echo "### add user"
                            echo "useradd -R \"\${_DESTDIR}\" ${_ADMIN_ATTR} -c \"${_FN}\" -m \"${_USER}\" &>\"\${_LOG}\""
                            echo "echo "user account ${_USER} created succesfully.""
                            echo ""
                            } >> "${_TEMPLATE}"
                            _set_password
                            _dialog --title " Success " --no-mouse --infobox "User account ${_USER} created succesfully." 3 50
                            sleep 2
                            _NEXTITEM=2
                            break
                         else
                             _dialog --title " ERROR " --no-mouse --infobox "User creation failed! Please try again." 3 50
                             sleep 3
                         fi
                     fi
                 done ;;
            "3") _USER="root"
                 while true; do
                     # root and all users with UID >= 1000
                     _USERS="$(rg -o '(.*):x:10[0-9][0-9]:.*:(.*):.*:' -r '$1#$2' "${_DESTDIR}"/etc/passwd |\
                               sd ' ' ':' | sd '#' ' ')"
                     #shellcheck disable=SC2086
                     _dialog --no-cancel --default-item ${_USER} --menu " User Account Selection " 15 40 10 \
                        "root" "Super User" ${_USERS} "< Back" "Return To Previous Menu" 2>"${_ANSWER}" || break
                     _USER=$(cat "${_ANSWER}")
                     _NEXTITEM="${_USER}"
                     if [[ "${_USER}" = "root" ]]; then
                         if _prepare_password root; then
                            _set_password
                         fi
                     elif [[ "${_USER}" = "< Back" ]]; then
                         break
                     else
                        _NEXTITEM=1
                        while true; do
                            _DEFAULT="--default-item ${_NEXTITEM}"
                            #shellcheck disable=SC2086
                            if rg wheel "${_DESTDIR}"/etc/group | rg -qw "${_USER}"; then
                                _ADMIN_ATTR=1
                                _USER_TITLE="${_USER} | Administrator | wheel group"
                                _USER_MENU="Change To Normal User"
                            else
                                _ADMIN_ATTR=""
                                _USER_TITLE="${_USER} | User | no wheel group"
                                _USER_MENU="Change To Administrator"
                            fi
                            #shellcheck disable=SC2086
                            _dialog --title " Account ${_USER_TITLE} " --no-cancel ${_DEFAULT} --menu "" 11 60 5 \
                                "1" "${_USER_MENU}" \
                                "2" "Change Password" \
                                "3" "Change Comment" \
                                "4" "Delete User" \
                                "<" "Return To User Selection" 2>"${_ANSWER}" || break
                            case $(cat "${_ANSWER}") in
                                "1") _NEXTITEM=1
                                     if [[ -n "${_ADMIN_ATTR}" ]]; then
                                         usermod -R "${_DESTDIR}" -rG wheel "${_USER}"
                                         _dialog --title " Success " --no-mouse --infobox "User ${_USER} removed as Administrator and removed from wheel group." 3 70
                                         # write to template
                                         { echo "### remove administrator"
                                         echo "usermod -R \"\${_DESTDIR}\" -rG wheel \"${_USER}\""
                                         echo "echo \"User ${_USER} removed as Administrator and removed from wheel group.\""
                                         echo ""
                                         } >> "${_TEMPLATE}"
                                         sleep 2
                                     else
                                         usermod -R "${_DESTDIR}" -aG wheel "${_USER}"
                                         _dialog --title " Success " --no-mouse --infobox "User ${_USER} switched to Administrator and added to wheel group." 3 70
                                         # write to template
                                         { echo "### add administrator"
                                         echo "usermod -R \"\${_DESTDIR}\" -aG wheel \"${_USER}\""
                                         echo "echo \"User ${_USER} switched to Administrator and added to wheel group.\""
                                         echo ""
                                         } >> "${_TEMPLATE}"
                                         sleep 2
                                     fi ;;
                                "2") _NEXTITEM=2
                                     if _prepare_password User; then
                                        _set_password
                                     fi ;;
                                "3") _NEXTITEM=3
                                     if _set_comment; then
                                         usermod -R "${_DESTDIR}" -c "${_FN}" "${_USER}"
                                         _dialog --title " Success " --no-mouse --infobox "New comment set for ${_USER}." 3 50
                                         # write to template
                                         { echo "### set comment"
                                         echo "usermod -R \"\${_DESTDIR}\" -c \"${_FN}\" \"${_USER}\""
                                         echo "echo \"New comment set for ${_USER}.\""
                                         echo ""
                                         } >> "${_TEMPLATE}"
                                         sleep 2
                                     fi ;;
                                "4") if _NEXTITEM=4
                                        _dialog --defaultno --yesno \
                                            "${_USER} will be COMPLETELY ERASED!\nALL USER DATA OF ${_USER} WILL BE LOST.\n\nAre you absolutely sure?" 0 0 && \
                                        userdel -R "${_DESTDIR}" -r "${_USER}" &>"${_LOG}"; then
                                        # write to template
                                         { echo "### delete user"
                                         echo "userdel -R \"\${_DESTDIR}\" -r \"${_USER}\" &>\"\${_LOG}\""
                                         echo "echo \"User ${_USER} deleted succesfully.\""
                                         echo ""
                                         } >> "${_TEMPLATE}"
                                        _dialog --title " Success " --no-mouse --infobox "User ${_USER} deleted succesfully." 3 50
                                        sleep 3
                                        break
                                     fi ;;
                                 *) break ;;
                            esac
                        done
                     fi
                 done
                 _NEXTITEM=3 ;;
            *) break ;;
        esac
    done
}
