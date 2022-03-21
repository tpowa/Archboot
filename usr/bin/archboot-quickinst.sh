#!/bin/bash
. /usr/lib/archboot/installer/common.sh
DESTDIR="${1}"

usage() {
    echo "quickinst <destdir>"
    echo
    echo "This script is for users who would rather partition/mkfs/mount their target"
    echo "media manually than go through the routines in the setup script."
    echo
    if ! [[ -e "${LOCAL_DB}" ]]; then
        echo "First configure /etc/pacman.conf which repositories to use"
        echo "and set a mirror in /etc/pacman.d/mirrorlist"
    fi
    echo
    echo "Make sure you have all your filesystems mounted under <destdir>."
    echo "Then run this script to install all packages listed in /etc/archboot/defaults"
    echo "to <destdir>."
    echo
    echo "Example:"
    echo "  quickinst /mnt"
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
