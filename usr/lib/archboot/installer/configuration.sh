#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
check_root_password() {
    # check if empty password is set
    if chroot "${DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q NP; then
        DIALOG --msgbox "Setup detected no password set for root user,\nplease set new password now." 6 50
        set_password || return 1
    fi
    # check if account is locked
    if chroot "${DESTDIR}" passwd -S root | cut -d ' ' -f2 | grep -q L; then
        DIALOG --msgbox "Setup detected locked account for root user,\nplease set new password to unlock account now." 6 50
        set_password || return 1
    fi
}

set_mkinitcpio() {
    DIALOG --msgbox "The mkinitcpio.conf file controls which modules will be placed into the initramfs for your system's kernel.\n\n- If you install under VMWARE add 'BusLogic' to MODULES= array\n- 2 or more disk controllers, please specify the correct module\n  loading order in MODULES= array \n\nMost of you will not need to change anything in this file." 12 70
    HOOK_ERROR=""
    ${EDITOR} "${DESTDIR}""${FILE}"
    #shellcheck disable=SC2013
    for i in $(grep ^HOOKS "${DESTDIR}"/etc/mkinitcpio.conf | sed -e 's/"//g' -e 's/HOOKS=\(//g' -e 's/\)//g'); do
        [[ -e ${DESTDIR}/usr/lib/initcpio/install/${i} ]] || HOOK_ERROR=1
    done
    if [[ "${HOOK_ERROR}" = "1" ]]; then
        DIALOG --msgbox "ERROR: Detected error in 'HOOKS=' line, please correct HOOKS= in /etc/mkinitcpio.conf!" 18 70
    fi
}

set_locale() {
    if [[ ${SET_LOCALE} == "" ]]; then
        LOCALES="en_US English de_DE German es_ES Spanish fr_FR French pt_PT Portuguese ru_RU Russian OTHER More"
        OTHER_LOCALES="$(grep 'UTF' ${DESTDIR}/etc/locale.gen | sed -e 's:#::g' -e 's: UTF-8.*$::g')"
        #shellcheck disable=SC2086
        DIALOG --menu "Select A System-Wide Locale:" 14 40 8 ${LOCALES} 2>${ANSWER} || return 1
        set_locale=$(cat ${ANSWER})
        if [[ "${set_locale}" == "OTHER" ]]; then
            #shellcheck disable=SC2086
            DIALOG --menu "Select A System-Wide Locale:" 18 40 12 ${OTHER_LOCALES} 2>${ANSWER} || return 1
            set_locale=$(cat ${ANSWER})
        fi
        sed -i -e "s#LANG=.*#LANG=${set_locale}#g" "${DESTDIR}"/etc/locale.conf
        SET_LOCALE="1"
    fi
    # enable glibc locales from locale.conf
    #shellcheck disable=SC2013
    for i in $(grep "^LANG" "${DESTDIR}"/etc/locale.conf | sed -e 's/.*=//g' -e's/\..*//g'); do
        sed -i -e "s/^#${i}/${i}/g" "${DESTDIR}"/etc/locale.gen
    done
}

set_password() {
    PASSWORD=""
    PASS=""
    PASS2=""
    while [[ "${PASSWORD}" = "" ]]; do
        while [[ "${PASS}" = "" ]]; do
            DIALOG --insecure --passwordbox "Enter new root password:" 0 0 2>"${ANSWER}" || return 1
            PASS=$(cat "${ANSWER}")
        done
        while [[ "${PASS2}" = "" ]]; do
            DIALOG --insecure --passwordbox "Retype new root password:" 0 0 2>"${ANSWER}" || return 1
            PASS2=$(cat "${ANSWER}")
        done
        if [[ "${PASS}" = "${PASS2}" ]]; then
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
    chroot "${DESTDIR}" passwd root < /tmp/.password >/dev/null 2>&1
    rm /tmp/.password
}

# run_mkinitcpio()
# runs mkinitcpio on the target system, displays output
run_mkinitcpio() {
    DIALOG --infobox "Rebuilding initramfs ..." 3 40
    chroot_mount
    echo "Initramfs progress ..." > /tmp/mkinitcpio.log
    if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
        chroot "${DESTDIR}" /usr/bin/mkinitcpio -p "${KERNELPKG}"-"${RUNNING_ARCH}" |& tee -a "${LOG}" /tmp/mkinitcpio.log >/dev/null 2>&1
    else
        chroot "${DESTDIR}" /usr/bin/mkinitcpio -p "${KERNELPKG}" |& tee -a "${LOG}" /tmp/mkinitcpio.log >/dev/null 2>&1
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
    DIALOG --infobox "Rebuilding glibc locales ..." 3 40
    locale_gen
    sleep 1
}
