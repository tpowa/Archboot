#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# auto_fstab()
# preprocess fstab file
# comments out old fields and inserts new ones
# according to partitioning/formatting stage
#
auto_fstab(){
    # Modify fstab
    if [[ "${S_MKFS}" = "1" || "${S_MKFSAUTO}" = "1" ]]; then
        DIALOG --infobox "Create new fstab on installed system ..." 6 60
        if [[ -f /tmp/.device-names ]]; then
            sort /tmp/.device-names >>"${DESTDIR}"/etc/fstab
        fi
        if [[ -f /tmp/.fstab ]]; then
            # clean fstab first from entries
            sed -i -e '/^\#/!d' "${DESTDIR}"/etc/fstab
            sort /tmp/.fstab >>"${DESTDIR}"/etc/fstab
        fi
        sleep 1
    fi
}

# auto_ssd()
# add udev rule for schedulers by default
# add sysctl file for swaps
auto_ssd () {
    if [[ ! -f ${DESTDIR}/etc/udev/rules.d/60-ioschedulers.rules ]]; then
        DIALOG --infobox "Enable performance ioscheduler settings on installed system ..." 6 60
        cp /etc/udev/rules.d/60-ioschedulers.rules "${DESTDIR}"/etc/udev/rules.d/60-ioschedulers.rules
        sleep 1
    fi
    if [[ ! -f ${DESTDIR}/etc/sysctl.d/99-sysctl.conf ]]; then
        DIALOG --infobox "Enable sysctl swap settings on installed system ..." 6 60
        cp /etc/sysctl.d/99-sysctl.conf "${DESTDIR}"/etc/sysctl.d/99-sysctl.conf
        sleep 1
    fi
}

# auto_mdadm()
# add mdadm setup to existing /etc/mdadm.conf
auto_mdadm()
{
    if [[ -e ${DESTDIR}/etc/mdadm.conf ]]; then
        DIALOG --infobox "Enable mdadm settings on installed system ..." 6 60
        if grep -q ^md /proc/mdstat 2>/dev/null; then
            mdadm -Ds >> "${DESTDIR}"/etc/mdadm.conf
        fi
        sleep 1
    fi
}

# auto_network()
# configures network on host system according to installer
# settings if user wishes to do so
#
auto_network()
{
    # exit if network wasn't configured in installer
    if [[ ${S_NET} -eq 0 ]]; then
        return 1
    fi
    DIALOG --infobox "Enable netctl network and proxy settings to installed system ..." 6 60
    # copy netctl profiles
    [[ -d ${DESTDIR}/etc/netctl ]] && cp /etc/netctl/* "${DESTDIR}"/etc/netctl/ 2>/dev/null
    # enable netctl profiles
    for i in $(echo /etc/netctl/*); do
         [[ -f $i ]] && systemd-nspawn -q -D "${DESTDIR}" netctl enable "$(basename "${i}")" >/dev/null 2>&1
    done
    # copy proxy settings
    if [[ -n "${PROXY}" ]]; then
        for i in ${PROXIES}; do
            echo "export ${i}=${PROXY}" >> "${DESTDIR}"/etc/profile.d/proxy.sh
            chmod a+x "${DESTDIR}"/etc/profile.d/proxy.sh
        done
    fi
    sleep 1
}

# Pacman signature check is enabled by default
# add gnupg pacman files to installed system
# in order to have a working pacman on installed system
auto_pacman()
{
    if ! [[ -d ${DESTDIR}/etc/pacman.d/gnupg ]]; then
        DO_PACMAN_GPG=""
        DIALOG --infobox "Enable pacman's GPG keyring files on installed system ..." 6 60
        cp -ar /etc/pacman.d/gnupg "${DESTDIR}"/etc/pacman.d 2>&1
        sleep 1
    fi
}

# If [testing] repository was enabled during installation,
# enable it on installed system too!
auto_testing()
{
    if [[ "${DOTESTING}" == "yes" ]]; then
        DIALOG --infobox "Enable [testing] repository on installed system ..." 6 60
        sed -i -e '/^#\[testing\]/ { n ; s/^#// }' "${DESTDIR}"/etc/pacman.conf
        sed -i -e '/^#\[community-testing\]/ { n ; s/^#// }' "${DESTDIR}"/etc/pacman.conf
        sed -i -e 's:^#\[testing\]:\[testing\]:g' -e  's:^#\[community-testing\]:\[community-testing\]:g' "${DESTDIR}"/etc/pacman.conf
        sleep 1
    fi
}

auto_mkinitcpio() {
    FBPARAMETER=""
    HWPARAMETER=""
    HWDETECTMODULES=""
    HWDETECTHOOKS=""
    HWKVER=""
    # check on nfs
    if lsmod | grep -q ^nfs; then
        DIALOG --defaultno --yesno "Setup detected nfs driver...\nDo you need support for booting from nfs shares?" 0 0 && HWPARAMETER="${HWPARAMETER} --nfs"
    fi
    DIALOG --infobox "Preconfiguring mkinitcpio settings on installed system ..." 6 60
    # check on framebuffer modules and kms FBPARAMETER
    grep -q "^radeon" /proc/modules && FBPARAMETER="--ati-kms"
    grep -q "^amdgpu" /proc/modules && FBPARAMETER="--amd-kms"
    grep -q "^i915" /proc/modules && FBPARAMETER="--intel-kms"
    grep -q "^nouveau" /proc/modules && FBPARAMETER="--nvidia-kms"
    # check on nfs,dmraid and keymap HWPARAMETER
    # check on used keymap, if not us keyboard layout
    ! grep -q '^KEYMAP="us"' "${DESTDIR}"/etc/vconsole.conf && HWPARAMETER="${HWPARAMETER} --keymap"
    # check on dmraid
    if [[ -e ${DESTDIR}/lib/initcpio/hooks/dmraid ]]; then
        if ! dmraid -r | grep ^no; then
            HWPARAMETER="${HWPARAMETER} --dmraid"
        fi
    fi
    # get kernel version
    if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
        offset=$(hexdump -s 526 -n 2 -e '"%0d"' "${DESTDIR}/boot/${VMLINUZ}")
        read -r HWKVER _ < <(dd if="${DESTDIR}/boot/${VMLINUZ}" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)
    elif [[ "${RUNNING_ARCH}" == "aarch64" || "${RUNNING_ARCH}" == "riscv64" ]]; then
        reader="cat"
        # try if the image is gzip compressed
        [[ $(file -b --mime-type "${DESTDIR}/boot/${VMLINUZ}") == 'application/gzip' ]] && reader="zcat"
        read -r _ _ HWKVER _ < <($reader "${DESTDIR}/boot/${VMLINUZ}" | grep -m1 -aoE 'Linux version .(\.[-[:alnum:]]+)+')
    fi
    # arrange MODULES for mkinitcpio.conf
    HWDETECTMODULES="$(hwdetect --kernel_directory="${DESTDIR}" --kernel_version="${HWKVER}" --hostcontroller --filesystem ${FBPARAMETER})"
    # arrange HOOKS for mkinitcpio.conf
    HWDETECTHOOKS="$(hwdetect --kernel_directory="${DESTDIR}" --kernel_version="${HWKVER}" --rootdevice="${PART_ROOT}" --hooks-dir="${DESTDIR}"/usr/lib/initcpio/install "${HWPARAMETER}" --hooks)"
    # change mkinitcpio.conf
    [[ -n "${HWDETECTMODULES}" ]] && sed -i -e "s/^MODULES=.*/${HWDETECTMODULES}/g" "${DESTDIR}"/etc/mkinitcpio.conf
    [[ -n "${HWDETECTHOOKS}" ]] && sed -i -e "s/^HOOKS=.*/${HWDETECTHOOKS}/g" "${DESTDIR}"/etc/mkinitcpio.conf
    # disable fallpack preset
    sed -i -e "s# 'fallback'##g" "${DESTDIR}"/etc/mkinitcpio.d/*.preset
    # remove fallback initramfs
    [[ -e "${DESTDIR}/boot/initramfs-linux-fallback.img" ]] && rm -f "${DESTDIR}/boot/initramfs-linux-fallback.img"
    sleep 1
}

auto_parameters() {
    if [[ ! -f ${DESTDIR}/etc/vconsole.conf ]]; then
        DIALOG --infobox "Setting keymap and font on installed system ..." 6 60
        : >"${DESTDIR}"/etc/vconsole.conf
        if [[ -s /tmp/.keymap ]]; then
            echo KEYMAP="$(sed -e 's/\..*//g' /tmp/.keymap)" >> "${DESTDIR}"/etc/vconsole.conf
        fi
        if [[ -s /tmp/.font ]]; then
            echo FONT="$(sed -e 's/\..*//g' /tmp/.font)" >> "${DESTDIR}"/etc/vconsole.conf
        fi
        sleep 1
    fi
}

auto_luks() {
    # remove root device from crypttab
    if [[ -e /tmp/.crypttab && "$(grep -v '^#' "${DESTDIR}"/etc/crypttab)"  = "" ]]; then
        DIALOG --infobox "Enable luks settings on installed system ..." 6 60
        # add to temp crypttab
        sed -i -e "/^$(basename "${PART_ROOT}") /d" /tmp/.crypttab
        cat /tmp/.crypttab >> "${DESTDIR}"/etc/crypttab
        chmod 600 /tmp/passphrase-* 2>/dev/null
        cp /tmp/passphrase-* "${DESTDIR}"/etc/ 2>/dev/null
        sleep 1
    fi
}

auto_timesetting() {
    if [[ -e /etc/localtime && ! -e "${DESTDIR}"/etc/localtime ]]; then
        DIALOG --infobox "Enable timezone setting on installed system ..." 6 60
        cp -a /etc/localtime "${DESTDIR}"/etc/localtime
        sleep 1
    fi
    if [[ ! -f "${DESTDIR}"/etc/adjtime ]]; then
        DIALOG --infobox "Enable clock setting on installed system ..." 6 60
        echo "0.0 0 0.0" > "${DESTDIR}"/etc/adjtime
        echo "0" >> "${DESTDIR}"/etc/adjtime
        [[ -s /tmp/.hardwareclock ]] && cat /tmp/.hardwareclock >>"${DESTDIR}"/etc/adjtime
        sleep 1
    fi
}

auto_pacman_mirror() {
    # /etc/pacman.d/mirrorlist
    # add installer-selected mirror to the top of the mirrorlist
    if [[ "${SYNC_URL}" != "" ]]; then
        DIALOG --infobox "Enable pacman mirror on installed system ..." 6 60
        #shellcheck disable=SC2027,SC2086
        awk "BEGIN { printf(\"# Mirror used during installation\nServer = "${SYNC_URL}"\n\n\") } 1 " "${DESTDIR}"/etc/pacman.d/mirrorlist > /tmp/inst-mirrorlist
        mv /tmp/inst-mirrorlist "${DESTDIR}/etc/pacman.d/mirrorlist"
        sleep 1
    fi
}

auto_system_files() {
    if [[ ! -f ${DESTDIR}/etc/hostname ]]; then
        DIALOG --infobox "Set default hostname on installed system ..." 6 60
        echo "myhostname" > "${DESTDIR}"/etc/hostname
        sleep 1
    fi
    if [[ ! -f ${DESTDIR}/etc/locale.conf ]]; then
        DIALOG --infobox "Set default locale on installed system ..." 6 60
        echo "LANG=C.UTF-8" > "${DESTDIR}"/etc/locale.conf
        echo "LC_COLLATE=C" >> "${DESTDIR}"/etc/locale.conf
        sleep 1
    fi
}
