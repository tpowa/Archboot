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
        # write to template
        { echo "echo \"Enable timezone setting on installed system...\""
        echo " cp -a /etc/localtime \"${_DESTDIR}\"/etc/localtime"
        } >> "${_TEMPLATE}"
        sleep 2
    fi
    if [[ -f /etc/adjtime && ! -f "${_DESTDIR}"/etc/adjtime ]]; then
        _progress "8" "Enable clock setting on installed system..."
        cp /etc/adjtime "${_DESTDIR}"/etc/adjtime
        # write to template
        { echo "echo \"Enable clock setting on installed system...\""
        echo "cp /etc/adjtime \"${_DESTDIR}\"/etc/adjtime"
        } >> "${_TEMPLATE}"
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
    if rg -q 'wlan' /.network-interface 2>"${_NO_LOG}"; then
        cp -r /var/lib/iwd "${_DESTDIR}"/var/lib
        chroot "${_DESTDIR}" systemctl enable iwd &>"${_NO_LOG}"
        # write to template
        { echo "echo \"Enable network and proxy settings on installed system...\""
        echo "cp -r /var/lib/iwd \"${_DESTDIR}\"/var/lib"
        echo "chroot \"${_DESTDIR}\" systemctl enable iwd &>\"${_NO_LOG}\""
        } >> "${_TEMPLATE}"
    fi
    # copy network profiles
    if [[ -d ${_DESTDIR}/etc/systemd/network ]]; then
        # enable network profiles
        cp /etc/systemd/network/* "${_DESTDIR}"/etc/systemd/network/ &>"${_NO_LOG}"
        chroot "${_DESTDIR}" systemctl enable systemd-networkd &>"${_NO_LOG}"
        chroot "${_DESTDIR}" systemctl enable systemd-resolved &>"${_NO_LOG}"
        # write to template
        { echo "cp /etc/systemd/network/* \"${_DESTDIR}\"/etc/systemd/network/ &>\"${_NO_LOG}\""
        echo "chroot \"${_DESTDIR}\" systemctl enable systemd-networkd &>\"${_NO_LOG}\""
        echo "chroot \"${_DESTDIR}" systemctl enable systemd-resolved &>"${_NO_LOG}\""
        } >> "${_TEMPLATE}"
    fi
    # copy proxy settings
    if [[ -e "/etc/profile.d/proxy.sh" ]]; then
        cp /etc/profile.d/proxy.sh "${_DESTDIR}"/etc/profile.d/proxy.sh
        # write to template
        echo "cp /etc/profile.d/proxy.sh \"${_DESTDIR}\"/etc/profile.d/proxy.sh" >> "${_TEMPLATE}"
    fi
    # enable ipv6 privacy extensions
    if ! [[ -d ${_DESTDIR}/etc/systemd/network.conf.d ]]; then
        mkdir -p "${_DESTDIR}/etc/systemd/network.conf.d"
        cp /etc/systemd/network.conf.d/ipv6-privacy-extensions.conf \
           "${_DESTDIR}"/etc/systemd/network.conf.d/ipv6-privacy-extensions.conf
        # write to template
        { echo "mkdir -p \"${_DESTDIR}/etc/systemd/network.conf.d\""
        echo "cp /etc/systemd/network.conf.d/ipv6-privacy-extensions.conf \
           \"${_DESTDIR}\"/etc/systemd/network.conf.d/ipv6-privacy-extensions.conf"
        } >> "${_TEMPLATE}"
    fi
    sleep 2
}

_auto_fstab(){
    # Modify fstab
    _progress "20" "Create new fstab on installed system..."
    if [[ -f /tmp/.device-names ]]; then
        sort /tmp/.device-names >>"${_DESTDIR}"/etc/fstab
        # write to template
        { echo \"echo "Create new fstab on installed system...\""
        echo "sort /tmp/.device-names >>\"${_DESTDIR}\"/etc/fstab"
        } >> "${_TEMPLATE}"
    fi
    if [[ -f /tmp/.fstab ]]; then
        # clean fstab first from entries
        sd -p '^[^#]*' '' "${_DESTDIR}"/etc/fstab
        sort /tmp/.fstab >>"${_DESTDIR}"/etc/fstab
        # write to template
        { echo "sd -p '^[^#]*' '' \"${_DESTDIR}\"/etc/fstab"
        echo "sort /tmp/.fstab >>\"${_DESTDIR}\"/etc/fstab"
        } >> "${_TEMPLATE}"
    fi
    sleep 2
}

# add udev rule for schedulers by default
_auto_scheduler () {
    if [[ ! -f ${_DESTDIR}/etc/udev/rules.d/70-ioschedulers.rules ]]; then
        _progress "24" "Enable performance ioscheduler settings on installed system..."
        cp /etc/udev/rules.d/60-ioschedulers.rules "${_DESTDIR}"/etc/udev/rules.d/60-ioschedulers.rules
        # write to template
        { echo "echo \"Enable performance ioscheduler settings on installed system...\""
        echo "cp /etc/udev/rules.d/60-ioschedulers.rules \"${_DESTDIR}\"/etc/udev/rules.d/60-ioschedulers.rules"
        } >> "${_TEMPLATE}"
        sleep 2
    fi
}

# add sysctl file for swaps
_auto_swap () {
    if [[ ! -f ${_DESTDIR}/etc/sysctl.d/99-sysctl.conf ]]; then
        _progress "29" "Enable sysctl swap settings on installed system..."
        cp /etc/sysctl.d/99-sysctl.conf "${_DESTDIR}"/etc/sysctl.d/99-sysctl.conf
        # write to template
        { echo "echo \"Enable sysctl swap settings on installed system...\""
        echo "cp /etc/sysctl.d/99-sysctl.conf \"${_DESTDIR}\"/etc/sysctl.d/99-sysctl.conf"
        } >> "${_TEMPLATE}"
        sleep 2
    fi
}

# add mdadm setup to existing /etc/mdadm.conf
_auto_mdadm()
{
    if [[ -e ${_DESTDIR}/etc/mdadm.conf ]]; then
        if rg -q '^md' /proc/mdstat 2>"${_NO_LOG}"; then
            _progress "34" "Enable mdadm settings on installed system..."
            mdadm -Ds >> "${_DESTDIR}"/etc/mdadm.conf
            # write to template
            { echo "echo \"Enable mdadm settings on installed system...\""
            echo "mdadm -Ds >> \"${_DESTDIR}\"/etc/mdadm.conf"
            } >> "${_TEMPLATE}"
        fi
        sleep 2
    fi
}

_auto_luks() {
    # remove root device from crypttab
    if [[ -e /tmp/.crypttab && "$(rg -v '^#' "${_DESTDIR}"/etc/crypttab)" == "" ]]; then
        _progress "40" "Enable luks settings on installed system..."
        # add to temp crypttab
        sd "^$(basename "${_ROOTDEV}").*\n" '' /tmp/.crypttab
        cat /tmp/.crypttab >> "${_DESTDIR}"/etc/crypttab
        chmod 700 /tmp/passphrase-* 2>"${_NO_LOG}"
        cp /tmp/passphrase-* "${_DESTDIR}"/etc/ 2>"${_NO_LOG}"
        # write to template
        { echo "echo \"Enable luks settings on installed system...\""
        echo "sd "^$(basename \"${_ROOTDEV}\").*\n" '' /tmp/.crypttab"
        echo "cat /tmp/.crypttab >> \"${_DESTDIR}\"/etc/crypttab"
        echo "chmod 700 /tmp/passphrase-* 2>\"${_NO_LOG}\""
        echo "cp /tmp/passphrase-* \"${_DESTDIR}\"/etc/ 2>\"${_NO_LOG}\""
        } >> "${_TEMPLATE}"
        sleep 2
    fi
}

_auto_pacman_keyring()
{
    if ! [[ -d ${_DESTDIR}/etc/pacman.d/gnupg ]]; then
        _progress "47" "Enable pacman's GPG keyring files on installed system..."
        cp -ar /etc/pacman.d/gnupg "${_DESTDIR}"/etc/pacman.d &>"${_NO_LOG}"
        # write to template
        { echo "echo \"Enable pacman's GPG keyring files on installed system...\""
        echo "cp -ar /etc/pacman.d/gnupg \"${_DESTDIR}\"/etc/pacman.d &>\"${_NO_LOG}\""
        } >> "${_TEMPLATE}"
        sleep 2
    fi
}

_auto_testing()
{
    if rg -q '^\[core-testing' /etc/pacman.conf; then
        _progress "53"  "Enable [testing] repository on installed system..."
        #shellcheck disable=SC2016
        sd '^#(\[[c,e].*-testing\]\n)#' '$1' "${_DESTDIR}"/etc/pacman.conf
        { echo "echo \"Enable [testing] repository on installed system...\""
        echo "sd '^#(\[[c,e].*-testing\]\n)#' '$1' \"${_DESTDIR}\"/etc/pacman.conf"
        } >> "${_TEMPLATE}"
        sleep 2
    fi
}

_auto_pacman_mirror() {
    # /etc/pacman.d/mirrorlist
    # add installer-selected mirror to the top of the mirrorlist
    if rg -q '^Server' /etc/pacman.d/mirrorlist; then
        _progress "62" "Enable pacman mirror on installed system..."
        _SYNC_URL=$(rg '^Server.* (.*)' -r '$1' /etc/pacman.d/mirrorlist)
        #shellcheck disable=SC2027,SC2086
        cat << EOF > /tmp/inst-mirrorlist
# Mirror used during installation
Server = ${_SYNC_URL}
EOF
        cat "${_DESTDIR}"/etc/pacman.d/mirrorlist >> /tmp/inst-mirrorlist
        mv /tmp/inst-mirrorlist "${_DESTDIR}/etc/pacman.d/mirrorlist"
        # write to template
        { echo "echo \"Enable pacman mirror on installed system...\""
        echo "_SYNC_URL=$(rg '^Server.* (.*)' -r '$1' /etc/pacman.d/mirrorlist)"
        echo "cat << EOF > /tmp/inst-mirrorlist"
        echo "# Mirror used during installation"
        echo "Server = ${_SYNC_URL}"
        echo "EOF"
        echo "cat \"${_DESTDIR}\"/etc/pacman.d/mirrorlist >> /tmp/inst-mirrorlist"
        echo "mv /tmp/inst-mirrorlist \"${_DESTDIR}/etc/pacman.d/mirrorlist\""
        } >> "${_TEMPLATE}"
        sleep 2
    fi
}

_auto_vconsole() {
    if [[ ! -f ${_DESTDIR}/etc/vconsole.conf ]]; then
        _progress "69" "Setting keymap and font on installed system..."
        cp /etc/vconsole.conf "${_DESTDIR}"/etc/vconsole.conf
        # write to template
        { echo "echo \"Setting keymap and font on installed system...\""
        echo "cp /etc/vconsole.conf \"${_DESTDIR}\"/etc/vconsole.conf"
        } >> "${_TEMPLATE}"
        sleep 2
    fi
}

_auto_hostname() {
    if [[ ! -f ${_DESTDIR}/etc/hostname ]]; then
        _progress "76" "Set default hostname on installed system..."
        echo "myhostname" > "${_DESTDIR}"/etc/hostname
        # write to template
        { echo "echo \"Set default hostname on installed system...\""
        echo "echo \"myhostname\" > \"${_DESTDIR}\"/etc/hostname"
        } >> "${_TEMPLATE}"
        sleep 2
    fi
}

_auto_locale() {
    _progress "83" "Set default locale on installed system..."
    # write to template
    echo "echo \"Set default locale on installed system...\"" >> "${_TEMPLATE}"
    if [[ ! -f ${_DESTDIR}/etc/locale.conf ]]; then
        if [[ -n ${_DESTDIR} && -e /.localize ]]; then
            cp /etc/locale.conf "${_DESTDIR}"/etc/locale.conf
            # write to template
            echo "cp /etc/locale.conf \"${_DESTDIR}\"/etc/locale.conf" >> "${_TEMPLATE}"
        else
            echo "LANG=C.UTF-8" > "${_DESTDIR}"/etc/locale.conf
            echo "LC_COLLATE=C" >> "${_DESTDIR}"/etc/locale.conf
            # write to template
            { echo "echo \"LANG=C.UTF-8\" > \"${_DESTDIR}\"/etc/locale.conf"
            echo "echo \"LC_COLLATE=C\" >> \"${_DESTDIR}\"/etc/locale.conf"
            } >> "${_TEMPLATE}"
            sleep 2
        fi
    fi
}

_auto_set_locale() {
    # enable glibc locales from locale.conf
    _progress "90" "Enable glibc locales based on locale.conf on installed system..."
    # write to template
    echo "echo \"Enable glibc locales based on locale.conf on installed system...\"" >> "${_TEMPLATE}"
    #shellcheck disable=SC2013
    for i in $(rg -o "^LANG=(.*)\..*" -r '$1' "${_DESTDIR}"/etc/locale.conf); do
        sd "^#${i}" "${i}" "${_DESTDIR}"/etc/locale.gen
        # write to template
        echo "sd \"^#${i}\" \"${i}\" \"${_DESTDIR}\"/etc/locale.gen" >> "${_TEMPLATE}"
    done
    sleep 2
}

_auto_windowkeys() {
    if ! [[ -e "${_DESTDIR}/etc/systemd/system/windowkeys.service" ]]; then
        # enable windowkeys on console
        _progress "98" "Enable windowkeys in console on installed system..."
        cp "/etc/systemd/system/windowkeys.service" "${_DESTDIR}/etc/systemd/system/windowkeys.service"
        chroot "${_DESTDIR}" systemctl enable windowkeys &>"${_NO_LOG}"
        # write to template
        { echo "echo \"Enable windowkeys in console on installed system...\""
        echo "cp \"/etc/systemd/system/windowkeys.service\" \"${_DESTDIR}/etc/systemd/system/windowkeys.service\""
        echo "chroot \"${_DESTDIR}\" systemctl enable windowkeys &>\"${_NO_LOG}\""
        } >> "${_TEMPLATE}"
    fi
}

_auto_bash(){
    if [[ ! -f ${_DESTDIR}/etc/profile.d/custom-bash-prompt.sh ]]; then
        _progress "99" "Setup bash with custom options on installed system..."
        cp "${_DESTDIR}"/etc/skel/.bash* "${_DESTDIR}"/root/
        # write to template
        { echo "echo \"Setup bash with custom options on installed system...\""
        echo "cp \"${_DESTDIR}\"/etc/skel/.bash* \"${_DESTDIR}\"/root/"
        } >> "${_TEMPLATE}"
        if ! rg -qw 'custom-bash-options.sh' "${_DESTDIR}/etc/skel/.bashrc"; then
            echo ". /etc/profile.d/custom-bash-options.sh" >> "${_DESTDIR}/etc/skel/.bashrc"
            # write to template
            echo "echo \". /etc/profile.d/custom-bash-options.sh\" >> \"${_DESTDIR}/etc/skel/.bashrc\"" >> "${_TEMPLATE}"
        fi
        if ! rg -qw 'custom-bash-options.sh' "${_DESTDIR}/root/.bashrc"; then
            echo ". /etc/profile.d/custom-bash-options.sh" >> "${_DESTDIR}/root/.bashrc"
            # write to template
            echo "echo \". /etc/profile.d/custom-bash-options.sh\" >> \"${_DESTDIR}/root/.bashrc\"" >> "${_TEMPLATE}"
        fi
        cp /etc/profile.d/custom-bash-options.sh "${_DESTDIR}"/etc/profile.d/
        # write to template
        echo "cp /etc/profile.d/custom-bash-options.sh \"${_DESTDIR}\"/etc/profile.d/" >> "${_TEMPLATE}"
        sleep 2
    fi
}

_auto_hwdetect() {
    # check on framebuffer modules and kms FBPARAMETER
    rg -q "^radeon" /proc/modules && _FBPARAMETER="--ati-kms"
    rg -q "^amdgpu" /proc/modules && _FBPARAMETER="--amd-kms"
    rg -q "^i915" /proc/modules && _FBPARAMETER="--intel-kms"
    rg -q "^xe" /proc/modules && _FBPARAMETER="--intel-xe-kms"
    rg -q "^nouveau" /proc/modules && _FBPARAMETER="--nvidia-kms"
    _progress "66" "Preconfiguring mkinitcpio settings on installed system..."
    # write to template
    echo "echo \"Preconfiguring mkinitcpio settings on installed system...\"" >> "${_TEMPLATE}"
    # arrange MODULES for mkinitcpio.conf
    _HWDETECTMODULES="$(hwdetect --root_directory="${_DESTDIR}" --hostcontroller --filesystem "${_FBPARAMETER}")"
    # arrange HOOKS for mkinitcpio.conf
    if [[ -n "${_SD_EARLY_USERSPACE}" ]]; then
        _HWDETECTHOOKS="$(hwdetect --root_directory="${_DESTDIR}" --rootdevice="${_ROOTDEV}" --systemd)"
    else
        _HWDETECTHOOKS="$(hwdetect --root_directory="${_DESTDIR}" --rootdevice="${_ROOTDEV}")"
    fi
    # change mkinitcpio.conf
    if [[ -n "${_HWDETECTMODULES}" ]]; then
        sd "^MODULES=.*" "${_HWDETECTMODULES}" "${_DESTDIR}"/etc/mkinitcpio.conf
        # write to template
        echo "sd \"^MODULES=.*\" \"${_HWDETECTMODULES}\" \"${_DESTDIR}\"/etc/mkinitcpio.conf" >> "${_TEMPLATE}"
    fi
    if [[ -n "${_HWDETECTHOOKS}" ]]; then
        sd "^HOOKS=.*" "${_HWDETECTHOOKS}" "${_DESTDIR}"/etc/mkinitcpio.conf
        # write to template
        echo "sd \"^HOOKS=.*\" \"${_HWDETECTHOOKS}\" \"${_DESTDIR}\"/etc/mkinitcpio.conf" >> "${_TEMPLATE}"
    fi
    _progress "100" "Preconfiguring mkinitcpio settings on installed system..."
}

_auto_mkinitcpio() {
    _SD_EARLY_USERSPACE=""
    _FBPARAMETER=""
    _HWDETECTMODULES=""
    _HWDETECTHOOKS=""
    if [[ -z "${_AUTO_MKINITCPIO}" ]]; then
        if [[ "${_NAME_SCHEME_PARAMETER}" == "SD_GPT_AUTO_GENERATOR" ]]; then
            _SD_EARLY_USERSPACE=1
        else
            _dialog --no-cancel --title " MKINITCPIO EARLY USERSPACE " --menu "" 8 45 2 "BUSYBOX" "Small and Fast" "SYSTEMD" "More Features" 2>"${_ANSWER}" || return 1
            if [[ $(cat "${_ANSWER}") == "SYSTEMD" ]]; then
                _SD_EARLY_USERSPACE=1
            fi
        fi
        _printk off
        _AUTO_MKINITCPIO=""
        _dialog --no-mouse --infobox "" 3 70
        _auto_hwdetect | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Preconfiguring mkinitcpio settings on installed system..." 6 75 0
        # disable fallpack preset
        sd " 'fallback'" '' "${_DESTDIR}"/etc/mkinitcpio.d/*.preset
        # write to template
        echo "sd \" 'fallback'\" '' \"${_DESTDIR}\"/etc/mkinitcpio.d/*.preset" >> "${_TEMPLATE}"
        # remove fallback initramfs
        if [[ -e "${_DESTDIR}/boot/initramfs-linux-fallback.img" ]]; then
            rm -f "${_DESTDIR}/boot/initramfs-linux-fallback.img"
            echo "rm -f \"${_DESTDIR}/boot/initramfs-linux-fallback.img\"" >> "${_TEMPLATE}"
        fi
        sleep 2
        _AUTO_MKINITCPIO=1
        _run_mkinitcpio | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Running mkinitcpio on installed system..." 6 75 0
        _mkinitcpio_error
        _printk on
    fi
}
