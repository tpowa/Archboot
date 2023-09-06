#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/installer/common.sh
_DESTDIR="${1}"

_usage() {
    echo -e "\e[1mWelcome to \e[36mARCHBOOT\e[m \e[1m- QUICKINST INSTALLER:\e[m"
    echo -e "\e[1m-------------------------------------------\e[m"
    echo -e "usage: \e[1mquickinst <destdir>\e[m"
    echo ""
    echo "This script is for users who would rather partition/mkfs/mount their target"
    echo "media manually than go through the routines in the setup script."
    echo
    if ! [[ -e "${_LOCAL_DB}" ]]; then
        echo -e "First configure \e[1m/etc/pacman.conf\e[m which repositories to use"
        echo -e "and set a mirror in \e[1m/etc/pacman.d/mirrorlist\e[m"
    fi
    echo
    echo -e "Make sure you have all your filesystems mounted under \e[1m<destdir>\e[m."
    echo -e "Then run this script to install all packages listed in \e[1m/etc/archboot/defaults\e[m"
    echo -e "to \e[1m<destdir>\e[m."
    echo
    echo "Example:"
    echo -e "  \e[1mquickinst /mnt\e[m"
    echo ""
    exit 0
}

# configures pacman and syncs db on destination system
# params: none
# returns: 1 on error
_prepare_pacman() {
    # Set up the necessary directories for pacman use
    if [[ ! -d "${_DESTDIR}/var/cache/pacman/pkg" ]]; then
        mkdir -p "${_DESTDIR}/var/cache/pacman/pkg"
    fi
    if [[ ! -d "${_DESTDIR}/var/lib/pacman" ]]; then
        mkdir -p "${_DESTDIR}/var/lib/pacman"
    fi
    # pacman-key process itself
    while pgrep -x pacman-key &>"${_NO_LOG}"; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg &>"${_NO_LOG}"; do
        sleep 1
    done
    [[ -e /etc/systemd/system/pacman-init.service ]] && systemctl stop pacman-init.service
    ${_PACMAN} -Sy
    _KEYRING="archlinux-keyring"
    [[ "$(uname -m)" == "aarch64" ]] && _KEYRING="${_KEYRING} archlinuxarm-keyring"
    #shellcheck disable=SC2086
    pacman -Sy ${_PACMAN_CONF} --noconfirm --noprogressbar ${_KEYRING} || exit 1
}

# package_installation
_install_packages() {
    # add packages from archboot defaults
    _PACKAGES=$(grep '^_PACKAGES' /etc/archboot/defaults | sed -e 's#_PACKAGES=##g' -e 's#"##g')
    # fallback if _PACKAGES is empty
    [[ -z "${_PACKAGES}" ]] && _PACKAGES="base linux linux-firmware"
    _auto_packages
    #shellcheck disable=SC2086
    ${_PACMAN} -S ${_PACKAGES}
}

# start script
if [[ -z "${1}" ]]; then
    _usage
fi

! [[ -d /tmp ]] && mkdir /tmp

if [[ -e "${_LOCAL_DB}" ]]; then
    _local_pacman_conf
else
    _PACMAN_CONF=""
fi

if ! _prepare_pacman; then
    echo -e "Pacman preparation \e[91mFAILED\e[m."
    exit 1
fi
_chroot_mount
if ! _install_packages; then
    echo -e "Package installation \e[91mFAILED\e[m."
    _chroot_umount
    exit 1
fi
_locale_gen
_chroot_umount

echo
echo -e "\e[1mPackage installation complete.\e[m"
echo
echo -e "Please install a \e[1mbootloader\e[m. Edit the appropriate config file for"
echo -e "your loader. Please use \e[1m${_VMLINUZ}\e[m as kernel image."
echo -e "Chroot into your system to install it:"
echo -e "  \e[1m# mount -o bind /dev ${_DESTDIR}/dev\e[m"
echo -e "  \e[1m# mount -t proc none ${_DESTDIR}/proc\e[m"
echo -e "  \e[1m# mount -t sysfs none ${_DESTDIR}/sys\e[m"
echo -e "  \e[1m# chroot ${_DESTDIR} /bin/bash\e[m"
echo
echo "Next step, initramfs setup:"
echo -e "Edit your \e[1m/etc/mkinitcpio.conf\e[m to fit your needs. After that run:"
echo -e "  \e[1m# mkinitcpio -p ${_KERNELPKG}\e[m"
echo
echo -e "Then \e[1mexit\e[m your chroot shell, edit \e[1m${_DESTDIR}/etc/fstab\e[m and \e[1mreboot\e[m! "
exit 0

# vim: set ts=4 sw=4 et:
