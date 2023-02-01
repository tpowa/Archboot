#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
# preprocess fstab file
# comments out old fields and inserts new ones
# according to partitioning/formatting stage
_auto_fstab(){
    # Modify fstab
    if [[ -n "${_S_MKFS}" || -n "${_S_MKFSAUTO}" ]]; then
        _dialog --infobox "Create new fstab on installed system..." 3 70
        if [[ -f /tmp/.device-names ]]; then
            sort /tmp/.device-names >>"${_DESTDIR}"/etc/fstab
        fi
        if [[ -f /tmp/.fstab ]]; then
            # clean fstab first from entries
            sed -i -e '/^\#/!d' "${_DESTDIR}"/etc/fstab
            sort /tmp/.fstab >>"${_DESTDIR}"/etc/fstab
        fi
        sleep 2
    fi
}

# add udev rule for schedulers by default
_auto_scheduler () {
    if [[ ! -f ${_DESTDIR}/etc/udev/rules.d/70-ioschedulers.rules ]]; then
        _dialog --infobox "Enable performance ioscheduler settings on installed system..." 3 70
        cp /etc/udev/rules.d/60-ioschedulers.rules "${_DESTDIR}"/etc/udev/rules.d/60-ioschedulers.rules
        sleep 2
    fi
}

# add sysctl file for swaps
_auto_swap () {
    if [[ ! -f ${_DESTDIR}/etc/sysctl.d/99-sysctl.conf ]]; then
        _dialog --infobox "Enable sysctl swap settings on installed system..." 3 70
        cp /etc/sysctl.d/99-sysctl.conf "${_DESTDIR}"/etc/sysctl.d/99-sysctl.conf
        sleep 2
    fi
}

# add mdadm setup to existing /etc/mdadm.conf
_auto_mdadm()
{
    if [[ -e ${_DESTDIR}/etc/mdadm.conf ]]; then
        if grep -q ^md /proc/mdstat 2>"${_NO_LOG}"; then
            _dialog --infobox "Enable mdadm settings on installed system..." 3 70
            mdadm -Ds >> "${_DESTDIR}"/etc/mdadm.conf
        fi
        sleep 2
    fi
}

# configures network on host system according to installer
_auto_network()
{
    # exit if network wasn't configured in installer
    if [[ -z ${_S_NET} ]]; then
        return 1
    fi
    _dialog --infobox "Enable network and proxy settings on installed system..." 3 70
    # copy iwd keys and enable iwd
    if grep -q 'wlan' /tmp/.network-interface; then
        cp -r /var/lib/iwd "${_DESTDIR}"/var/lib
        chroot "${_DESTDIR}" systemctl enable iwd &>"${_NO_LOG}"
    fi
    # copy network profiles
    if [[ -d ${_DESTDIR}/etc/systemd/network ]]; then
        # enable network profiles
        cp /etc/systemd/network/* "${_DESTDIR}"/etc/systemd/network/ &>"${_NO_LOG}"
        chroot "${_DESTDIR}" systemctl enable systemd-networkd &>"${_NO_LOG}"
        chroot "${_DESTDIR}" systemctl enable systemd-resolved &>"${_NO_LOG}"
    fi
    # copy proxy settings
    if [[ -n "${_PROXY}" ]]; then
        for i in ${_PROXIES}; do
            echo "export ${i}=${_PROXY}" >> "${_DESTDIR}"/etc/profile.d/proxy.sh
            chmod a+x "${_DESTDIR}"/etc/profile.d/proxy.sh
        done
    fi
    sleep 2
}

_auto_pacman_keyring()
{
    if ! [[ -d ${_DESTDIR}/etc/pacman.d/gnupg ]]; then
        _dialog --infobox "Enable pacman's GPG keyring files on installed system..." 3 70
        cp -ar /etc/pacman.d/gnupg "${_DESTDIR}"/etc/pacman.d &>"${_NO_LOG}"
        sleep 2
    fi
}

_auto_testing()
{
    if [[ -n "${_DOTESTING}" ]]; then
        _dialog --infobox "Enable [testing] repository on installed system..." 3 70
        sed -i -e '/^#\[testing\]/ { n ; s/^#// }' "${_DESTDIR}"/etc/pacman.conf
        sed -i -e '/^#\[community-testing\]/ { n ; s/^#// }' "${_DESTDIR}"/etc/pacman.conf
        sed -i -e 's:^#\[testing\]:\[testing\]:g' -e  's:^#\[community-testing\]:\[community-testing\]:g' "${_DESTDIR}"/etc/pacman.conf
        sleep 2
    fi
}

_auto_mkinitcpio() {
    _FBPARAMETER=""
    _HWPARAMETER=""
    _HWDETECTMODULES=""
    _HWDETECTHOOKS=""
    _HWKVER=""
    if [[ -z "${_AUTO_MKINITCPIO}" ]]; then
        _printk off
        _AUTO_MKINITCPIO=""
        # check on nfs
        if lsmod | grep -q ^nfs; then
            _dialog --defaultno --yesno "Setup detected nfs driver...\nDo you need support for booting from nfs shares?" 0 0 && _HWPARAMETER="${_HWPARAMETER} --nfs"
        fi
        _dialog --infobox "Preconfiguring mkinitcpio settings on installed system..." 3 70
        # check on framebuffer modules and kms FBPARAMETER
        grep -q "^radeon" /proc/modules && _FBPARAMETER="--ati-kms"
        grep -q "^amdgpu" /proc/modules && _FBPARAMETER="--amd-kms"
        grep -q "^i915" /proc/modules && _FBPARAMETER="--intel-kms"
        grep -q "^nouveau" /proc/modules && _FBPARAMETER="--nvidia-kms"
        # check on nfs and keymap HWPARAMETER
        # check on used keymap, if not us keyboard layout
        ! grep -q '^KEYMAP="us"' "${_DESTDIR}"/etc/vconsole.conf && _HWPARAMETER="${_HWPARAMETER} --keymap"
        # get kernel version
        if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
            offset=$(hexdump -s 526 -n 2 -e '"%0d"' "${_DESTDIR}/boot/${_VMLINUZ}")
            read -r _HWKVER _ < <(dd if="${_DESTDIR}/boot/${_VMLINUZ}" bs=1 count=127 skip=$(( offset + 0x200 )) 2>"${_NO_LOG}")
        elif [[ "${_RUNNING_ARCH}" == "aarch64" || "${_RUNNING_ARCH}" == "riscv64" ]]; then
            reader="cat"
            # try if the image is gzip compressed
            [[ $(file -b --mime-type "${_DESTDIR}/boot/${_VMLINUZ}") == 'application/gzip' ]] && reader="zcat"
            read -r _ _ _HWKVER _ < <($reader "${_DESTDIR}/boot/${_VMLINUZ}" | grep -m1 -aoE 'Linux version .(\.[-[:alnum:]]+)+')
        fi
        # arrange MODULES for mkinitcpio.conf
        _HWDETECTMODULES="$(hwdetect --kernel_directory="${_DESTDIR}" --kernel_version="${_HWKVER}" --hostcontroller --filesystem ${_FBPARAMETER})"
        # arrange HOOKS for mkinitcpio.conf
        _HWDETECTHOOKS="$(hwdetect --kernel_directory="${_DESTDIR}" --kernel_version="${_HWKVER}" --rootdevice="${_ROOTDEV}" --hooks-dir="${_DESTDIR}"/usr/lib/initcpio/install "${_HWPARAMETER}" --hooks)"
        # change mkinitcpio.conf
        [[ -n "${_HWDETECTMODULES}" ]] && sed -i -e "s/^MODULES=.*/${_HWDETECTMODULES}/g" "${_DESTDIR}"/etc/mkinitcpio.conf
        [[ -n "${_HWDETECTHOOKS}" ]] && sed -i -e "s/^HOOKS=.*/${_HWDETECTHOOKS}/g" "${_DESTDIR}"/etc/mkinitcpio.conf
        # disable fallpack preset
        sed -i -e "s# 'fallback'##g" "${_DESTDIR}"/etc/mkinitcpio.d/*.preset
        # remove fallback initramfs
        [[ -e "${_DESTDIR}/boot/initramfs-linux-fallback.img" ]] && rm -f "${_DESTDIR}/boot/initramfs-linux-fallback.img"
        sleep 2
        _AUTO_MKINITCPIO=1
        _run_mkinitcpio
        _printk on
    fi
}

_auto_vconsole() {
    if [[ ! -f ${_DESTDIR}/etc/vconsole.conf ]]; then
        _dialog --infobox "Setting keymap and font on installed system..." 3 70
        cp /etc/vconsole.conf "${_DESTDIR}"/etc/vconsole.conf
        sleep 2
    fi
}

_auto_luks() {
    # remove root device from crypttab
    if [[ -e /tmp/.crypttab && "$(grep -v '^#' "${_DESTDIR}"/etc/crypttab)" == "" ]]; then
        _dialog --infobox "Enable luks settings on installed system..." 3 70
        # add to temp crypttab
        sed -i -e "/^$(basename "${_ROOTDEV}") /d" /tmp/.crypttab
        cat /tmp/.crypttab >> "${_DESTDIR}"/etc/crypttab
        chmod 700 /tmp/passphrase-* 2>"${_NO_LOG}"
        cp /tmp/passphrase-* "${_DESTDIR}"/etc/ 2>"${_NO_LOG}"
        sleep 2
    fi
}

_auto_timesetting() {
    if [[ -e /etc/localtime && ! -e "${_DESTDIR}"/etc/localtime ]]; then
        _dialog --infobox "Enable timezone setting on installed system..." 3 70
        cp -a /etc/localtime "${_DESTDIR}"/etc/localtime
        sleep 2
    fi
    if [[ -f /etc/adjtime && ! -f "${_DESTDIR}"/etc/adjtime ]]; then
        _dialog --infobox "Enable clock setting on installed system..." 3 70
        cp /etc/adjtime "${_DESTDIR}"/etc/adjtime
        sleep 2
    fi
}

_auto_pacman_mirror() {
    # /etc/pacman.d/mirrorlist
    # add installer-selected mirror to the top of the mirrorlist
    if [[ "${_SYNC_URL}" != "" ]]; then
        _dialog --infobox "Enable pacman mirror on installed system..." 3 70
        #shellcheck disable=SC2027,SC2086
        awk "BEGIN { printf(\"# Mirror used during installation\nServer = "${_SYNC_URL}"\n\n\") } 1 " "${_DESTDIR}"/etc/pacman.d/mirrorlist > /tmp/inst-mirrorlist
        mv /tmp/inst-mirrorlist "${_DESTDIR}/etc/pacman.d/mirrorlist"
        sleep 2
    fi
}

_auto_hostname() {
    if [[ ! -f ${_DESTDIR}/etc/hostname ]]; then
        _dialog --infobox "Set default hostname on installed system..." 3 70
        echo "myhostname" > "${_DESTDIR}"/etc/hostname
        sleep 2
    fi
}

_auto_locale() {
    if [[ ! -f ${_DESTDIR}/etc/locale.conf ]]; then
        _dialog --infobox "Set default locale on installed system..." 3 70
        echo "LANG=C.UTF-8" > "${_DESTDIR}"/etc/locale.conf
        echo "LC_COLLATE=C" >> "${_DESTDIR}"/etc/locale.conf
        sleep 2
    fi
}

_auto_set_locale() {
    # enable glibc locales from locale.conf
    _dialog --infobox "Enable glibc locales based on locale.conf on installed system..." 3 70
    #shellcheck disable=SC2013
    for i in $(grep "^LANG" "${_DESTDIR}"/etc/locale.conf | sed -e 's/.*=//g' -e's/\..*//g'); do
        sed -i -e "s/^#${i}/${i}/g" "${_DESTDIR}"/etc/locale.gen
    done
    sleep 2
}

_auto_nano_syntax() {
    _dialog --infobox "Enable nano's syntax highlighting on installed system..." 3 70
    grep -q '^include' "${_DESTDIR}/etc/nanorc" || echo "include \"/usr/share/nano/*.nanorc\"" >> "${_DESTDIR}/etc/nanorc"
    sleep 2
}

_auto_bash(){
    if [[ ! -f ${_DESTDIR}/etc/profile.d/custom-bash-prompt.sh ]]; then
        _dialog --infobox "Enable custom bash prompt on installed system..." 3 70
        ! grep -qw 'custom-bash-prompt.sh' "${_DESTDIR}/etc/bash.bashrc" &&\
            echo ". /etc/profile.d/custom-bash-prompt.sh" >> "${_DESTDIR}/etc/bash.bashrc"
        cp /etc/profile.d/custom-bash-prompt.sh "${_DESTDIR}"/etc/profile.d/
        sleep 2
    fi
    if [[ ! -f ${_DESTDIR}/etc/profile.d/custom-bash-aliases.sh ]]; then
        _dialog --infobox "Enable custom bash aliases on installed system..." 3 70
        ! grep -qw 'custom-bash-aliases.sh' "${_DESTDIR}/etc/bash.bashrc" &&\
            echo ". /etc/profile.d/custom-bash-aliases.sh" >> "${_DESTDIR}/etc/bash.bashrc"
        cp /etc/profile.d/custom-bash-aliases.sh "${_DESTDIR}"/etc/profile.d/
        sleep 2
    fi
    if [[ ! -f ${_DESTDIR}/etc/profile.d/custom-bash-history.sh ]]; then
        _dialog --infobox "Enable custom bash history on installed system..." 3 70
        ! grep -qw 'custom-bash-history.sh' "${_DESTDIR}/etc/bash.bashrc" &&\
            echo ". /etc/profile.d/custom-bash-history.sh" >> "${_DESTDIR}/etc/bash.bashrc"
        cp /etc/profile.d/custom-bash-history.sh "${_DESTDIR}"/etc/profile.d/
        sleep 2
    fi
}

# vim: set ft=sh ts=4 sw=4 et:
