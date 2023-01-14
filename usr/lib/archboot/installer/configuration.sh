#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_check_root_password() {
    # check if empty password is set
    if chroot "${_DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q NP; then
        _dialog --msgbox "Setup detected no password set for root user,\nplease set new password now." 6 50
        _set_password || return 1
    fi
    # check if account is locked
    if chroot "${_DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q L; then
        _dialog --msgbox "Setup detected locked account for root user,\nplease set new password to unlock account now." 6 50
        _set_password || return 1
    fi
}

_set_mkinitcpio() {
    _dialog --msgbox "The mkinitcpio.conf file controls which modules will be placed into the initramfs for your system's kernel.\n\n- If you install under VMWARE add 'BusLogic' to MODULES= array\n- 2 or more disk controllers, please specify the correct module\n  loading order in MODULES= array \n\nMost of you will not need to change anything in this file." 12 70
    _HOOK_ERROR=""
    ${_EDITOR} "${_DESTDIR}""${_FILE}"
    #shellcheck disable=SC2013
    for i in $(grep ^HOOKS "${_DESTDIR}"/etc/mkinitcpio.conf | sed -e 's/"//g' -e 's/HOOKS=\(//g' -e 's/\)//g'); do
        [[ -e ${_DESTDIR}/usr/lib/initcpio/install/${i} ]] || _HOOK_ERROR=1
    done
    if [[ -n "${_HOOK_ERROR}" ]]; then
        _dialog --msgbox "ERROR: Detected error in 'HOOKS=' line, please correct HOOKS= in /etc/mkinitcpio.conf!" 18 70
    else
        _run_mkinitcpio
    fi
}

_set_locale() {
    if [[ -z ${_SET_LOCALE} ]]; then
        _LOCALES="en_US English de_DE German es_ES Spanish fr_FR French pt_PT Portuguese ru_RU Russian OTHER More"
        _CHECK_LOCALES="$(grep 'UTF' "${_DESTDIR}"/etc/locale.gen | sed -e 's:#::g' -e 's: UTF-8.*$::g')"
        _OTHER_LOCALES=""
        for i in ${_CHECK_LOCALES}; do
            _OTHER_LOCALES="${_OTHER_LOCALES} ${i} -"
        done
        #shellcheck disable=SC2086
        _dialog --menu "Select A System-Wide Locale:" 14 40 8 ${_LOCALES} 2>${_ANSWER} || return 1
        _SET_LOCALE=$(cat "${_ANSWER}")
        if [[ "${_SET_LOCALE}" == "OTHER" ]]; then
            #shellcheck disable=SC2086
            _dialog --menu "Select A System-Wide Locale:" 18 40 12 ${_OTHER_LOCALES} 2>${_ANSWER} || return 1
            _SET_LOCALE=$(cat "${_ANSWER}")
        fi
        sed -i -e "s#LANG=.*#LANG=${_SET_LOCALE}#g" "${_DESTDIR}"/etc/locale.conf
        _dialog --infobox "Setting locale LANG=${_SET_LOCALE} on installed system ..." 3 70
        _SET_LOCALE=1
        sleep 2
        _auto_set_locale
        _run_locale_gen
    fi
}

_set_password() {
    _PASSWORD=""
    _PASS=""
    _PASS2=""
    while [[ -z "${_PASSWORD}" ]]; do
        while [[ -z "${_PASS}" ]]; do
            _dialog --insecure --passwordbox "Enter new root password:" 0 0 2>"${_ANSWER}" || return 1
            _PASS=$(cat "${_ANSWER}")
        done
        while [[ -z  "${_PASS2}" ]]; do
            _dialog --insecure --passwordbox "Retype new root password:" 0 0 2>"${_ANSWER}" || return 1
            _PASS2=$(cat "${_ANSWER}")
        done
        if [[ "${_PASS}" == "${_PASS2}" ]]; then
            _PASSWORD=${_PASS}
            echo "${_PASSWORD}" > /tmp/.password
            echo "${_PASSWORD}" >> /tmp/.password
            _PASSWORD=/tmp/.password
        else
            _dialog --msgbox "Error:\nPassword didn't match, please enter again." 6 50
            _PASSWORD=""
            _PASS=""
            _PASS2=""
        fi
    done
    chroot "${_DESTDIR}" passwd root < /tmp/.password >"${_NO_LOG}"
    rm /tmp/.password
}

_run_mkinitcpio() {
    _dialog --infobox "Rebuilding initramfs on installed system ..." 3 70
    _chroot_mount
    echo "Initramfs progress ..." > /tmp/mkinitcpio.log
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        chroot "${_DESTDIR}" mkinitcpio -p "${_KERNELPKG}"-"${_RUNNING_ARCH}" |& tee -a "${_LOG}" /tmp/mkinitcpio.log >"${_NO_LOG}"
    else
        chroot "${_DESTDIR}" mkinitcpio -p "${_KERNELPKG}" |& tee -a "${_LOG}" /tmp/mkinitcpio.log >"${_NO_LOG}"
    fi
    echo $? > /tmp/.mkinitcpio-retcode
    if [[ $(cat /tmp/.mkinitcpio-retcode) -ne 0 ]]; then
        echo -e "\nMkinitcpio FAILED." >>/tmp/mkinitcpio.log
    else
        echo -e "\nMkinitcpio Complete." >>/tmp/mkinitcpio.log
    fi
    local _result=''
    # mkinitcpio finished, display scrollable output on error
    if [[ $(cat /tmp/.mkinitcpio-retcode) -ne 0 ]]; then
        _result="Mkinitcpio Failed (see errors below)"
        _dialog --title "${_result}" --exit-label "Continue" \
        --textbox "/tmp/mkinitcpio.log" 18 70 || return 1
    fi
    rm /tmp/.mkinitcpio-retcode
    _chroot_umount
    sleep 1
}

_run_locale_gen() {
    _dialog --infobox "Rebuilding glibc locales on installed system ..." 3 70
    _locale_gen
    sleep 1
}
