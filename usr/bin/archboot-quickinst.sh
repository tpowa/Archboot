#!/usr/bin/env bash
_DESTDIR="${1}"
. /usr/lib/archboot/installer/common.sh

_usage() {
    echo -e "\033[1mWelcome to \033[34marchboot's\033[0m \033[1m QUICKINST INSTALLER:\033[0m"
    echo -e "\033[1m-------------------------------------------\033[0m"
    echo -e "Usage:"
    echo -e "\033[1mquickinst <destdir>\033[0m"
    echo ""
    echo "This script is for users who would rather partition/mkfs/mount their target"
    echo "media manually than go through the routines in the setup script."
    echo
    if ! [[ -e "${_LOCAL_DB}" ]]; then
        echo -e "First configure \033[1m/etc/pacman.conf\033[0m which repositories to use"
        echo -e "and set a mirror in \033[1m/etc/pacman.d/mirrorlist\033[0m"
    fi
    echo
    echo -e "Make sure you have all your filesystems mounted under \033[1m<destdir>\033[0m."
    echo -e "Then run this script to install all packages listed in \033[1m/etc/archboot/defaults\033[0m"
    echo -e "to \033[1m<destdir>\033[0m."
    echo
    echo "Example:"
    echo -e "  \033[1mquickinst /mnt\033[0m"
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
    while pgrep -x pacman-key > /dev/null 2>&1; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg > /dev/null 2>&1; do
        sleep 1
    done
    [[ -e /etc/systemd/system/pacman-init.service ]] && systemctl stop pacman-init.service
    ${_PACMAN} -Sy
    _KEYRING="archlinux-keyring"
    [[ "$(uname -m)" == "aarch64" ]] && _KEYRING="${_KEYRING} archlinuxarm-keyring"
    #shellcheck disable=SC2086
    pacman -Sy ${PACMAN_CONF} --noconfirm --noprogressbar ${_KEYRING} || exit 1
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
    echo -e "Pacman preparation \033[91mFAILED\033[0m."
    exit 1
fi
_chroot_mount
if ! _install_packages; then
    echo -e "Package installation \033[91mFAILED\033[0m."
    _chroot_umount
    exit 1
fi
_locale_gen
_chroot_umount

echo
echo -e "\033[1mPackage installation complete.\033[0m"
echo
echo -e "Please install a \033[1mbootloader\033[0m. Edit the appropriate config file for"
echo -e "your loader. Please use \033[1m${_VMLINUZ}\033[0m as kernel image."
echo -e "Chroot into your system to install it:"
echo -e "  \033[1m# mount -o bind /dev ${_DESTDIR}/dev\033[0m"
echo -e "  \033[1m# mount -t proc none ${_DESTDIR}/proc\033[0m"
echo -e "  \033[1m# mount -t sysfs none ${_DESTDIR}/sys\033[0m"
echo -e "  \033[1m# chroot ${_DESTDIR} /bin/bash\033[0m"
echo
echo "Next step, initramfs setup:"
echo -e "Edit your \033[1m/etc/mkinitcpio.conf\033[0m to fit your needs. After that run:"
echo -e "  \033[1m# mkinitcpio -p ${_KERNELPKG}\033[0m"
echo
echo -e "Then \033[1mexit\033[0m your chroot shell, edit \033[1m${_DESTDIR}/etc/fstab\033[0m and \033[1mreboot\033[0m! "
exit 0

# vim: set ts=4 sw=4 et:
