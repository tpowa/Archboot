#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
set_mkinitcpio() {
    DIALOG --msgbox "The mkinitcpio.conf file controls which modules will be placed into the initramfs for your system's kernel.\n\n- Non US keymap users should add 'keymap' to HOOKS= array\n- If you install under VMWARE add 'BusLogic' to MODULES= array\n- raid, lvm2, encrypt are not enabled by default\n- 2 or more disk controllers, please specify the correct module\n  loading order in MODULES= array \n\nMost of you will not need to change anything in this file." 15 70
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
    # enable glibc locales from locale.conf
    #shellcheck disable=SC2013
    for i in $(grep "^LANG" "${DESTDIR}"/etc/locale.conf | sed -e 's/.*=//g' -e's/\..*//g'); do
        sed -i -e "s/^#${i}/${i}/g" "${DESTDIR}"/etc/locale.gen
    done
    ${EDITOR} "${DESTDIR}""${FILE}"
}

set_password() {
    PASSWORD=""
    while [[ "${PASSWORD}" = "" ]]; do
        DIALOG --insecure --passwordbox "Enter root password:" 0 0 2>"${ANSWER}" || return 1
        PASS=$(cat "${ANSWER}")
        DIALOG --insecure --passwordbox "Retype root password:" 0 0 2>"${ANSWER}" || return 1
        PASS2=$(cat "${ANSWER}")
        if [[ "${PASS}" = "${PASS2}" ]]; then
            PASSWORD=${PASS}
            echo "${PASSWORD}" > /tmp/.password
            echo "${PASSWORD}" >> /tmp/.password
            PASSWORD=/tmp/.password
        else
            DIALOG --msgbox "Password didn't match, please enter again." 0 0
        fi
    done
    chroot "${DESTDIR}" passwd root < /tmp/.password >/dev/null 2>&1
    rm /tmp/.password
}

# run_mkinitcpio()
# runs mkinitcpio on the target system, displays output
#
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
}
