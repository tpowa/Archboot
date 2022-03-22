#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
set_mkinitcpio() {
    DIALOG --msgbox "The mkinitcpio.conf file controls which modules will be placed into the initramfs for your system's kernel.\n\n- Non US keymap users should add 'keymap' to HOOKS= array\n- If you install under VMWARE add 'BusLogic' to MODULES= array\n- raid, lvm2, encrypt are not enabled by default\n- 2 or more disk controllers, please specify the correct module\n  loading order in MODULES= array \n\nMost of you will not need to change anything in this file." 18 70
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
        DIALOG --insecure --passwordbox "Enter root password:" 0 0 2>${ANSWER} || return 1
        PASS=$(cat ${ANSWER})
        DIALOG --insecure --passwordbox "Retype root password:" 0 0 2>${ANSWER} || return 1
        PASS2=$(cat ${ANSWER})
        if [[ "${PASS}" = "${PASS2}" ]]; then
            PASSWORD=${PASS}
            echo "${PASSWORD}" > /tmp/.password
            echo "${PASSWORD}" >> /tmp/.password
            PASSWORD=/tmp/.password
        else
            DIALOG --msgbox "Password didn't match, please enter again." 0 0
        fi
    done
    chroot "${DESTDIR}" passwd root < /tmp/.password
    rm /tmp/.password
}

# run_mkinitcpio()
# runs mkinitcpio on the target system, displays output
#
run_mkinitcpio() {
    chroot_mount
    # all mkinitcpio output goes to /tmp/mkinitcpio.log, which we tail into a dialog
    ( \
    touch /tmp/setup-mkinitcpio-running
    echo "Initramfs progress ..." > /tmp/initramfs.log; echo >> /tmp/mkinitcpio.log
    if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
        chroot "${DESTDIR}" /usr/bin/mkinitcpio -p ${KERNELPKG}-"${RUNNING_ARCH}" >>/tmp/mkinitcpio.log 2>&1
    else
        chroot "${DESTDIR}" /usr/bin/mkinitcpio -p ${KERNELPKG} >>/tmp/mkinitcpio.log 2>&1
    fi
    echo >> /tmp/mkinitcpio.log
    rm -f /tmp/setup-mkinitcpio-running
    ) &
    sleep 2
    dialog --backtitle "${TITLE}" --title "Rebuilding initramfs images ..." --no-kill --tailboxbg "/tmp/mkinitcpio.log" 18 70
    while [[ -f /tmp/setup-mkinitcpio-running ]]; do
        /usr/bin/true
    done
    chroot_umount
}
