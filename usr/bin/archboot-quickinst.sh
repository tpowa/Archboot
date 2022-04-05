#!/bin/bash
. /usr/lib/archboot/installer/common.sh
DESTDIR="${1}"

usage() {
    echo -e "\033[1mWelcome to \033[34marchboot's\033[0m \033[1m QUICKINST INSTALLER:\033[0m"
    echo -e "\033[1m-------------------------------------------\033[0m"
    echo -e "Usage:"
    echo -e "\033[1mquickinst <destdir>\033[0m"
    echo ""
    echo "This script is for users who would rather partition/mkfs/mount their target"
    echo "media manually than go through the routines in the setup script."
    echo
    if ! [[ -e "${LOCAL_DB}" ]]; then
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
prepare_pacman() {
    # Set up the necessary directories for pacman use
    [[ ! -d "${DESTDIR}/var/cache/pacman/pkg" ]] && mkdir -p "${DESTDIR}/var/cache/pacman/pkg"
    [[ ! -d "${DESTDIR}/var/lib/pacman" ]] && mkdir -p "${DESTDIR}/var/lib/pacman"
    ${PACMAN} -Sy
}

# package_installation
install_packages() {
    # add packages from archboot defaults
    PACKAGES=$(grep '^_PACKAGES' /etc/archboot/defaults | sed -e 's#_PACKAGES=##g' -e 's#"##g')
    # fallback if _PACKAGES is empty
    [[ -z "${PACKAGES}" ]] && PACKAGES="base linux linux-firmware"
    auto_packages
    #shellcheck disable=SC2086
    ${PACMAN} -S ${PACKAGES}
}

# start script
if [[ -z "${1}" ]]; then
    usage
fi

! [[ -d /tmp ]] && mkdir /tmp

if [[ -e "${LOCAL_DB}" ]]; then
    local_pacman_conf
else
    PACMAN_CONF=""
fi

prepare_pacman || (echo "Pacman preparation FAILED!"; return 1)
chroot_mount
install_packages || (echo "Package installation FAILED."; chroot_umount; exit 1)
locale_gen
chroot_umount

echo
echo "Package installation complete."
echo
echo "Please install a bootloader.  Edit the appropriate config file for"
echo "your loader. Please use ${VMLINUZ} as kernel image."
echo "Chroot into your system to install it into the boot sector:"
echo "  # mount -o bind /dev ${DESTDIR}/dev"
echo "  # mount -t proc none ${DESTDIR}/proc"
echo "  # mount -t sysfs none ${DESTDIR}/sys"
echo "  # chroot ${DESTDIR} /bin/bash"
echo
echo "Next step, initramfs setup:"
echo "Edit your /etc/mkinitcpio.conf to fit your needs. After that run:"
echo "# mkinitcpio -p ${KERNELPKG}"
echo
echo "Then exit your chroot shell, edit ${DESTDIR}/etc/fstab and reboot!"
echo
exit 0

# vim: set ts=4 sw=4 et:
