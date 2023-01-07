#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
check_root_password() {
    # check if empty password is set
    if chroot "${_DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q NP; then
        DIALOG --msgbox "Setup detected no password set for root user,\nplease set new password now." 6 50
        set_password || return 1
    fi
    # check if account is locked
    if chroot "${_DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q L; then
        DIALOG --msgbox "Setup detected locked account for root user,\nplease set new password to unlock account now." 6 50
        set_password || return 1
    fi
}

set_mkinitcpio() {
    DIALOG --msgbox "The mkinitcpio.conf file controls which modules will be placed into the initramfs for your system's kernel.\n\n- If you install under VMWARE add 'BusLogic' to MODULES= array\n- 2 or more disk controllers, please specify the correct module\n  loading order in MODULES= array \n\nMost of you will not need to change anything in this file." 12 70
    HOOK_ERROR=""
    ${_EDITOR} "${_DESTDIR}""${FILE}"
    #shellcheck disable=SC2013
    for i in $(grep ^HOOKS "${_DESTDIR}"/etc/mkinitcpio.conf | sed -e 's/"//g' -e 's/HOOKS=\(//g' -e 's/\)//g'); do
        [[ -e ${_DESTDIR}/usr/lib/initcpio/install/${i} ]] || HOOK_ERROR=1
    done
    if [[ "${HOOK_ERROR}" == "1" ]]; then
        DIALOG --msgbox "ERROR: Detected error in 'HOOKS=' line, please correct HOOKS= in /etc/mkinitcpio.conf!" 18 70
    else
        run_mkinitcpio
    fi
}

set_locale() {
    if [[ ${SET_LOCALE} == "" ]]; then
        LOCALES="en_US English de_DE German es_ES Spanish fr_FR French pt_PT Portuguese ru_RU Russian OTHER More"
        CHECK_LOCALES="$(grep 'UTF' "${_DESTDIR}"/etc/locale.gen | sed -e 's:#::g' -e 's: UTF-8.*$::g')"
        OTHER_LOCALES=""
        for i in ${CHECK_LOCALES}; do
            OTHER_LOCALES="${OTHER_LOCALES} ${i} -"
        done
        #shellcheck disable=SC2086
        DIALOG --menu "Select A System-Wide Locale:" 14 40 8 ${LOCALES} 2>${_ANSWER} || return 1
        set_locale=$(cat "${_ANSWER}")
        if [[ "${set_locale}" == "OTHER" ]]; then
            #shellcheck disable=SC2086
            DIALOG --menu "Select A System-Wide Locale:" 18 40 12 ${OTHER_LOCALES} 2>${_ANSWER} || return 1
            set_locale=$(cat "${_ANSWER}")
        fi
        sed -i -e "s#LANG=.*#LANG=${set_locale}#g" "${_DESTDIR}"/etc/locale.conf
        DIALOG --infobox "Setting locale LANG=${set_locale} on installed system ..." 3 70
        SET_LOCALE="1"
        sleep 2
        auto_set_locale
        run_locale_gen
    fi
}

set_password() {
    PASSWORD=""
    PASS=""
    PASS2=""
    while [[ "${PASSWORD}" == "" ]]; do
        while [[ "${PASS}" == "" ]]; do
            DIALOG --insecure --passwordbox "Enter new root password:" 0 0 2>"${_ANSWER}" || return 1
            PASS=$(cat "${_ANSWER}")
        done
        while [[ "${PASS2}" == "" ]]; do
            DIALOG --insecure --passwordbox "Retype new root password:" 0 0 2>"${_ANSWER}" || return 1
            PASS2=$(cat "${_ANSWER}")
        done
        if [[ "${PASS}" == "${PASS2}" ]]; then
            PASSWORD=${PASS}
            echo "${PASSWORD}" > /tmp/.password
            echo "${PASSWORD}" >> /tmp/.password
            PASSWORD=/tmp/.password
        else
            DIALOG --msgbox "Error:\nPassword didn't match, please enter again." 6 50
            PASSWORD=""
            PASS=""
            PASS2=""
        fi
    done
    chroot "${_DESTDIR}" passwd root < /tmp/.password >/dev/null 2>&1
    rm /tmp/.password
}

# run_mkinitcpio()
# runs mkinitcpio on the target system, displays output
run_mkinitcpio() {
    DIALOG --infobox "Rebuilding initramfs on installed system ..." 3 70
    chroot_mount
    echo "Initramfs progress ..." > /tmp/mkinitcpio.log
    if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
        chroot "${_DESTDIR}" mkinitcpio -p "${KERNELPKG}"-"${RUNNING_ARCH}" |& tee -a "${_LOG}" /tmp/mkinitcpio.log >/dev/null 2>&1
    else
        chroot "${_DESTDIR}" mkinitcpio -p "${KERNELPKG}" |& tee -a "${_LOG}" /tmp/mkinitcpio.log >/dev/null 2>&1
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
        DIALOG --title "${_result}" --exit-label "Continue" \
        --textbox "/tmp/mkinitcpio.log" 18 70 || return 1
    fi
    rm /tmp/.mkinitcpio-retcode
    chroot_umount
    sleep 1
}

run_locale_gen() {
    DIALOG --infobox "Rebuilding glibc locales on installed system ..." 3 70
    locale_gen
    sleep 1
}
