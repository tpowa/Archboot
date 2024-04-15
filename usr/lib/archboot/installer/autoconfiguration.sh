#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
# preprocess fstab file
# comments out old fields and inserts new ones
# according to partitioning/formatting stage
_auto_timesetting() {
    if [[ -e /etc/localtime && ! -e "${_DESTDIR}"/etc/localtime ]]; then
        _progress "5" "Enable timezone setting on installed system..."
        cp -a /etc/localtime "${_DESTDIR}"/etc/localtime
        sleep 2
    fi
    if [[ -f /etc/adjtime && ! -f "${_DESTDIR}"/etc/adjtime ]]; then
        _progress "8" "Enable clock setting on installed system..."
        cp /etc/adjtime "${_DESTDIR}"/etc/adjtime
        sleep 2
    fi
}

# configures network on host system according to Basic Setup
_auto_network()
{
    # exit if network wasn't configured in Basic Setup
    if [[ ! -e  /.network ]]; then
        return 1
    fi
    _progress "13" "Enable network and proxy settings on installed system..."
    # copy iwd keys and enable iwd
    if grep -q 'wlan' /.network-interface 2>"${_NO_LOG}"; then
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
    if [[ -e "/etc/profile.d/proxy.sh" ]]; then
        cp /etc/profile.d/proxy.sh "${_DESTDIR}"/etc/profile.d/proxy.sh
    fi
    # enable ipv6 privacy extensions
    if ! [[ -d ${_DESTDIR}/etc/systemd/network.conf.d ]]; then
        mkdir -p "${_DESTDIR}/etc/systemd/network.conf.d"
        cp /etc/systemd/network.conf.d/ipv6-privacy-extensions.conf \
           "${_DESTDIR}"/etc/systemd/network.conf.d/ipv6-privacy-extensions.conf
    fi
    sleep 2
}

_auto_fstab(){
    # Modify fstab
    _progress "20" "Create new fstab on installed system..."
    if [[ -f /tmp/.device-names ]]; then
        sort /tmp/.device-names >>"${_DESTDIR}"/etc/fstab
    fi
    if [[ -f /tmp/.fstab ]]; then
        # clean fstab first from entries
        sed -i -e '/^\#/!d' "${_DESTDIR}"/etc/fstab
        sort /tmp/.fstab >>"${_DESTDIR}"/etc/fstab
    fi
    sleep 2
}

# add udev rule for schedulers by default
_auto_scheduler () {
    if [[ ! -f ${_DESTDIR}/etc/udev/rules.d/70-ioschedulers.rules ]]; then
        _progress "24" "Enable performance ioscheduler settings on installed system..."
        cp /etc/udev/rules.d/60-ioschedulers.rules "${_DESTDIR}"/etc/udev/rules.d/60-ioschedulers.rules
        sleep 2
    fi
}

# add sysctl file for swaps
_auto_swap () {
    if [[ ! -f ${_DESTDIR}/etc/sysctl.d/99-sysctl.conf ]]; then
        _progress "29" "Enable sysctl swap settings on installed system..."
        cp /etc/sysctl.d/99-sysctl.conf "${_DESTDIR}"/etc/sysctl.d/99-sysctl.conf
        sleep 2
    fi
}

# add mdadm setup to existing /etc/mdadm.conf
_auto_mdadm()
{
    if [[ -e ${_DESTDIR}/etc/mdadm.conf ]]; then
        if grep -q ^md /proc/mdstat 2>"${_NO_LOG}"; then
            _progress "34" "Enable mdadm settings on installed system..."
            mdadm -Ds >> "${_DESTDIR}"/etc/mdadm.conf
        fi
        sleep 2
    fi
}

_auto_luks() {
    # remove root device from crypttab
    if [[ -e /tmp/.crypttab && "$(grep -v '^#' "${_DESTDIR}"/etc/crypttab)" == "" ]]; then
        _progress "40" "Enable luks settings on installed system..."
        # add to temp crypttab
        sed -i -e "/^$(basename "${_ROOTDEV}") /d" /tmp/.crypttab
        cat /tmp/.crypttab >> "${_DESTDIR}"/etc/crypttab
        chmod 700 /tmp/passphrase-* 2>"${_NO_LOG}"
        cp /tmp/passphrase-* "${_DESTDIR}"/etc/ 2>"${_NO_LOG}"
        sleep 2
    fi
}

_auto_pacman_keyring()
{
    if ! [[ -d ${_DESTDIR}/etc/pacman.d/gnupg ]]; then
        _progress "47" "Enable pacman's GPG keyring files on installed system..."
        cp -ar /etc/pacman.d/gnupg "${_DESTDIR}"/etc/pacman.d &>"${_NO_LOG}"
        sleep 2
    fi
}

_auto_testing()
{
    if grep -q "^\[.*testing\]" /etc/pacman.conf; then
        _progress "53"  "Enable [testing] repository on installed system..."
        sed -i -e '/^#\[core-testing\]/ { n ; s/^#// }' "${_DESTDIR}"/etc/pacman.conf
        sed -i -e '/^#\[extra-testing\]/ { n ; s/^#// }' "${_DESTDIR}"/etc/pacman.conf
        sed -i -e 's:^#\[core-testing\]:\[core-testing\]:g' -e  's:^#\[extra-testing\]:\[extra-testing\]:g' "${_DESTDIR}"/etc/pacman.conf
        sleep 2
    fi
}

_auto_pacman_mirror() {
    # /etc/pacman.d/mirrorlist
    # add installer-selected mirror to the top of the mirrorlist
    if grep -q '^Server' /etc/pacman.d/mirrorlist; then
        _progress "62" "Enable pacman mirror on installed system..."
        _SYNC_URL=$(grep '^Server' /etc/pacman.d/mirrorlist | sed -e 's#.*\ ##g')
        #shellcheck disable=SC2027,SC2086
        awk "BEGIN { printf(\"# Mirror used during installation\nServer = "${_SYNC_URL}"\n\n\") } 1 " "${_DESTDIR}"/etc/pacman.d/mirrorlist > /tmp/inst-mirrorlist
        mv /tmp/inst-mirrorlist "${_DESTDIR}/etc/pacman.d/mirrorlist"
        sleep 2
    fi
}

_auto_vconsole() {
    if [[ ! -f ${_DESTDIR}/etc/vconsole.conf ]]; then
        _progress "69" "Setting keymap and font on installed system..."
        cp /etc/vconsole.conf "${_DESTDIR}"/etc/vconsole.conf
        sleep 2
    fi
}

_auto_hostname() {
    if [[ ! -f ${_DESTDIR}/etc/hostname ]]; then
        _progress "76" "Set default hostname on installed system..."
        echo "myhostname" > "${_DESTDIR}"/etc/hostname
        sleep 2
    fi
}

_auto_locale() {
    _progress "83" "Set default locale on installed system..."
    if [[ ! -f ${_DESTDIR}/etc/locale.conf ]]; then
        if [[ -n ${_DESTDIR} && -e /.localize ]]; then
            cp /etc/locale.conf "${_DESTDIR}"/etc/locale.conf
        else
            echo "LANG=C.UTF-8" > "${_DESTDIR}"/etc/locale.conf
            echo "LC_COLLATE=C" >> "${_DESTDIR}"/etc/locale.conf
            sleep 2
        fi
    fi
}

_auto_set_locale() {
    # enable glibc locales from locale.conf
    _progress "90" "Enable glibc locales based on locale.conf on installed system..."
    #shellcheck disable=SC2013
    for i in $(grep "^LANG" "${_DESTDIR}"/etc/locale.conf | sed -e 's/.*=//g' -e's/\..*//g'); do
        sed -i -e "s/^#${i}/${i}/g" "${_DESTDIR}"/etc/locale.gen
    done
    sleep 2
}

_auto_windowkeys() {
    if ! [[ -e "${_DESTDIR}/etc/systemd/system/windowkeys.service" ]]; then
    # enable windowkeys on console
    _progress "98" "Enable windowkeys in console on installed system..."
        cp "/etc/systemd/system/windowkeys.service" "${_DESTDIR}/etc/systemd/system/windowkeys.service"
        chroot "${_DESTDIR}" systemctl enable windowkeys &>"${_NO_LOG}"
    fi
}

_auto_bash(){
    if [[ ! -f ${_DESTDIR}/etc/profile.d/custom-bash-prompt.sh ]]; then
        _progress "99" "Setup bash with custom options on installed system..."
         cp "${_DESTDIR}"/etc/skel/.bash* "${_DESTDIR}"/root/
        ! grep -qw 'custom-bash-options.sh' "${_DESTDIR}/etc/skel/.bashrc" &&\
            echo ". /etc/profile.d/custom-bash-options.sh" >> "${_DESTDIR}/etc/skel/.bashrc"
        ! grep -qw 'custom-bash-options.sh' "${_DESTDIR}/root/.bashrc" &&\
            echo ". /etc/profile.d/custom-bash-options.sh" >> "${_DESTDIR}/root/.bashrc"
        cp /etc/profile.d/custom-bash-options.sh "${_DESTDIR}"/etc/profile.d/
        sleep 2
    fi
}

_auto_hwdetect() {
    # check on framebuffer modules and kms FBPARAMETER
    grep -q "^radeon" /proc/modules && _FBPARAMETER="--ati-kms"
    grep -q "^amdgpu" /proc/modules && _FBPARAMETER="--amd-kms"
    grep -q "^i915" /proc/modules && _FBPARAMETER="--intel-kms"
    grep -q "^nouveau" /proc/modules && _FBPARAMETER="--nvidia-kms"
    _progress "66" "Preconfiguring mkinitcpio settings on installed system..."
    # arrange MODULES for mkinitcpio.conf
    _HWDETECTMODULES="$(hwdetect --root_directory="${_DESTDIR}" --hostcontroller --filesystem "${_FBPARAMETER}")"
    # arrange HOOKS for mkinitcpio.conf
    if [[ "${_EARLY_USERSPACE}" == "SYSTEMD" ]]; then
        _HWDETECTHOOKS="$(hwdetect --root_directory="${_DESTDIR}" --rootdevice="${_ROOTDEV}" --systemd)"
    else
        _HWDETECTHOOKS="$(hwdetect --root_directory="${_DESTDIR}" --rootdevice="${_ROOTDEV}")"
    fi
    # change mkinitcpio.conf
    [[ -n "${_HWDETECTMODULES}" ]] && sed -i -e "s/^MODULES=.*/${_HWDETECTMODULES}/g" "${_DESTDIR}"/etc/mkinitcpio.conf
    [[ -n "${_HWDETECTHOOKS}" ]] && sed -i -e "s/^HOOKS=.*/${_HWDETECTHOOKS}/g" "${_DESTDIR}"/etc/mkinitcpio.conf
    _progress "100" "Preconfiguring mkinitcpio settings on installed system..."
}

_auto_mkinitcpio() {
    _FBPARAMETER=""
    _HWDETECTMODULES=""
    _HWDETECTHOOKS=""
    if [[ -z "${_AUTO_MKINITCPIO}" ]]; then
        if [[ "${_NAME_SCHEME_PARAMETER}" == "SD_GPT_AUTO_GENERATOR" ]]; then
            _EARLY_USERSPACE="SYSTEMD"
        else
            _dialog --no-cancel --title " MKINITCPIO EARLY USERSPACE " --menu "" 8 50 2 "BUSYBOX" "Small and Fast" "SYSTEMD" "More Features" 2>"${_ANSWER}" || return 1
            _EARLY_USERSPACE=$(cat "${_ANSWER}")
        fi
        _printk off
        _AUTO_MKINITCPIO=""
        _dialog --no-mouse --infobox "" 3 70
        _auto_hwdetect | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Preconfiguring mkinitcpio settings on installed system..." 6 75 0
        # disable fallpack preset
        sed -i -e "s# 'fallback'##g" "${_DESTDIR}"/etc/mkinitcpio.d/*.preset
        # remove fallback initramfs
        [[ -e "${_DESTDIR}/boot/initramfs-linux-fallback.img" ]] && rm -f "${_DESTDIR}/boot/initramfs-linux-fallback.img"
        sleep 2
        _AUTO_MKINITCPIO=1
        _run_mkinitcpio | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Rebuilding initramfs on installed system..." 6 75 0
        _mkinitcpio_error
        _printk on
    fi
}
# vim: set ft=sh ts=4 sw=4 et:
