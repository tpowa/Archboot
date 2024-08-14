#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/installer/common.sh
_DESTDIR="${1}"

_usage() {
    echo -e "\e[1m\e[36mArchboot\e[m \e[1m- Quickinst Installer\e[m"
    echo -e "\e[1m------------------------------\e[m"
    echo "This script is for users, who would rather partition/mkfs/mount"
    echo "their target media manually, than go through the routines in"
    echo "the setup script."
    echo
    if ! [[ -e "${_LOCAL_DB}" ]]; then
        echo -e "Configure repositories: \e[1m/etc/pacman.conf\e[m"
        echo -e "Configure mirror: \e[1m/etc/pacman.d/mirrorlist\e[m"
    fi
    echo -e "Configure packages to install: \e[1m/etc/archboot/defaults\e[m"
    echo -e "Mount all your filesystems: \e[1m<destdir>\e[m"
    echo ""
    echo -e "Usage: \e[1mquickinst <destdir>\e[m"
    exit 0
}

# configures pacman and syncs db on destination system
# params: none
# returns: 1 on error
_prepare_pacman() {
    # Set up the necessary directories for pacman use
    if [[ ! -d "${_DESTDIR}${_CACHEDIR}" ]]; then
        mkdir -p "${_DESTDIR}${_CACHEDIR}"
    fi
    if [[ ! -d "${_DESTDIR}${_PACMAN_LIB}" ]]; then
        mkdir -p "${_DESTDIR}${_PACMAN_LIB}"
    fi
    _pacman_keyring
    ${_PACMAN} -Sy
    _KEYRING="archlinux-keyring"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _KEYRING="${_KEYRING} archlinuxarm-keyring"
    #shellcheck disable=SC2086
    pacman -Sy ${_PACMAN_CONF} --noconfirm --noprogressbar ${_KEYRING} || exit 1
}

# package_installation
_install_packages() {
    # add packages from archboot defaults
    _PACKAGES="$(rg -o '^_PACKAGES="(.*)"' -r '$1' /etc/archboot/defaults)"
    # fallback if _PACKAGES is empty
    [[ -z "${_PACKAGES}" ]] && _PACKAGES="base linux linux-firmware"
    _auto_packages
    #shellcheck disable=SC2086
    ${_PACMAN} -S ${_PACKAGES}
}

_post_installation() {
    echo -e "

\e[1mPackage installation complete.\e[m

Please install a \e[1mbootloader\e[m. Edit the appropriate config file for
your loader. Please use \e[1m${_VMLINUZ}\e[m as kernel image.
Chroot into your system to install it:
  \e[1m# mount -o bind /dev ${_DESTDIR}/dev\e[m
  \e[1m# mount -t proc none ${_DESTDIR}/proc\e[m
  \e[1m# mount -t sysfs none ${_DESTDIR}/sys\e[m
  \e[1m# chroot ${_DESTDIR} /bin/bash\e[m

Next step, initramfs setup:
Edit your \e[1m/etc/mkinitcpio.conf\e[m to fit your needs. After that run:
  \e[1m# mkinitcpio -p ${_KERNELPKG}\e[m

Then \e[1mexit\e[m your chroot shell, edit \e[1m${_DESTDIR}/etc/fstab\e[m and \e[1mreboot\e[m!"
}

# start script
if [[ -z "${1}" ]]; then
    _usage
fi

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
_post_installation
exit 0

# vim: set ts=4 sw=4 et:
