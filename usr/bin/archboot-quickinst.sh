#!/usr/bin/env bash
DESTDIR="${1}"

PACMAN="pacman --root "${DESTDIR}" --cachedir "${DESTDIR}"/var/cache/pacman/pkg --noconfirm"

# name of kernel package
KERNELPKG="linux"
# name of the kernel image
VMLINUZ="vmlinuz-${KERNELPKG}"

usage() {
    echo "quickinst <destdir>"
    echo
    echo "This script is for users who would rather partition/mkfs/mount their target"
    echo "media manually than go through the routines in the setup script."
    echo
    echo "First configure /etc/pacman.conf which repositories to use"
    echo "and set a mirror in /etc/pacman.d/mirrorlist"
    echo ""
    echo "Make sure you have all your filesystems mounted under <destdir>."
    echo "Then run this script to install all base packages to <destdir>."
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
    [[ ! -d "${DESTDIR}/var/cache/pacman/pkg" ]] && mkdir -m 755 -p "${DESTDIR}/var/cache/pacman/pkg"
    [[ ! -d "${DESTDIR}/var/lib/pacman" ]] && mkdir -m 755 -p "${DESTDIR}/var/lib/pacman"
    ${PACMAN} -Sy
}

# chroot_mount()
# prepares target system as a chroot
#
chroot_mount()
{
    [[ -e "${DESTDIR}/sys" ]] || mkdir -m 555 "${DESTDIR}/sys"
    [[ -e "${DESTDIR}/proc" ]] || mkdir -m 555 "${DESTDIR}/proc"
    [[ -e "${DESTDIR}/dev" ]] || mkdir "${DESTDIR}/dev"
    mount -t sysfs sysfs "${DESTDIR}/sys"
    mount -t proc proc "${DESTDIR}/proc"
    mount -o bind /dev "${DESTDIR}/dev"
    chmod 555 "${DESTDIR}/sys"
    chmod 555 "${DESTDIR}/proc"
}

# chroot_umount()
# tears down chroot in target system
#
chroot_umount()
{
    umount "${DESTDIR}/proc"
    umount "${DESTDIR}/sys"
    umount "${DESTDIR}/dev"
}

# package_installation
install_packages() {

    PACKAGES="base linux linux-firmware"
    # Add packages which are not in core repository
    if [[ "$(lsblk -rnpo FSTYPE | grep ntfs)" ]]; then
        ! [[ "$(echo ${PACKAGES} | grep -w ntfs-3g)" ]] && PACKAGES="${PACKAGES} ntfs-3g"
    fi
    if [[ "$(lsblk -rnpo FSTYPE | grep btrfs)" ]]; then
        ! [[ "$(echo ${PACKAGES} | grep -w btrfs-progs)" ]] && PACKAGES="${PACKAGES} btrfs-progs"
    fi
    if [[ "$(lsblk -rnpo FSTYPE | grep nilfs2)" ]]; then
        ! [[ "$(echo ${PACKAGES} | grep -w nilfs-utils)" ]] && PACKAGES="${PACKAGES} nilfs-utils"
    fi
    if [[ "$(lsblk -rnpo FSTYPE | grep ext)" ]]; then
        ! [[ "$(echo ${PACKAGES} | grep -w e2fsprogs)" ]] && PACKAGES="${PACKAGES} e2fsprogs"
    fi
    if [[ "$(lsblk -rnpo FSTYPE | grep reiserfs)" ]]; then
        ! [[ "$(echo ${PACKAGES} | grep -w reiserfsprogs)" ]] && PACKAGES="${PACKAGES} reiserfsprogs"
    fi
    if [[ "$(lsblk -rnpo FSTYPE | grep xfs)" ]]; then
        ! [[ "$(echo ${PACKAGES} | grep -w xfsprogs)" ]] && PACKAGES="${PACKAGES} xfsprogs"
    fi
    if [[ "$(lsblk -rnpo FSTYPE | grep jfs)" ]]; then
        ! [[ "$(echo ${PACKAGES} | grep -w jfsutils)" ]] && PACKAGES="${PACKAGES} jfsutils"
    fi
    if [[ "$(lsblk -rnpo FSTYPE | grep f2fs)" ]]; then
        ! [[ "$(echo ${PACKAGES} | grep -w f2fs-tools)" ]] && PACKAGES="${PACKAGES} f2fs-tools"
    fi
    if [[ "$(lsblk -rnpo FSTYPE | grep vfat)" ]]; then
        ! [[ "$(echo ${PACKAGES} | grep -w dosfstools)" ]] && PACKAGES="${PACKAGES} dosfstools"
    fi
    if [[ -n "$(pgrep dhclient)" ]]; then
        ! [[ "$(echo ${PACKAGES} | grep -w dhclient)" ]] && PACKAGES="${PACKAGES} dhclient"
    fi
    ### HACK:
    # always add systemd-sysvcompat components
    PACKAGES="$(echo ${PACKAGES} | sed -e "s#\ systemd-sysvcompat\ # #g")"
    PACKAGES="${PACKAGES} systemd-sysvcompat"
    ### HACK:
    # always add intel-ucode
    if [[ "$(uname -m)" == "x86_64" ]]; then
        PACKAGES="$(echo ${PACKAGES} | sed -e "s#\ intel-ucode\ # #g")"
        PACKAGES="${PACKAGES} intel-ucode"
    fi
    # always add amd-ucode
    PACKAGES="$(echo ${PACKAGES} | sed -e "s#\ amd-ucode\ # #g")"
    PACKAGES="${PACKAGES} amd-ucode"
    ### HACK:
    # always add netctl with optdepends
    PACKAGES="$(echo ${PACKAGES} | sed -e "s#\ netctl\ # #g")"
    PACKAGES="${PACKAGES} netctl"
    PACKAGES="$(echo ${PACKAGES} | sed -e "s#\ dhcpd\ # #g")"
    PACKAGES="${PACKAGES} dhcpcd"
    PACKAGES="$(echo ${PACKAGES} | sed -e "s#\ wpa_supplicant\ # #g")"
    PACKAGES="${PACKAGES} wpa_supplicant"
    ### HACK:
    # always add lvm2, cryptsetup and mdadm
    PACKAGES="$(echo ${PACKAGES} | sed -e "s#\ lvm2\ # #g")"
    PACKAGES="${PACKAGES} lvm2"
    PACKAGES="$(echo ${PACKAGES} | sed -e "s#\ cryptsetup\ # #g")"
    PACKAGES="${PACKAGES} cryptsetup"
    PACKAGES="$(echo ${PACKAGES} | sed -e "s#\ mdadm\ # #g")"
    PACKAGES="${PACKAGES} mdadm"  
    ### HACK: circular depends are possible in base, install filesystem first!
    PACKAGES="$(echo ${PACKAGES} | sed -e "s#\ filesystem\ # #g")"
    PACKAGES="filesystem ${PACKAGES}"
    ${PACMAN} -S ${PACKAGES}
}

if [[ -z "${1}" ]]; then
    usage
fi

! [[ -d /tmp ]] && mkdir /tmp

# prepare pacman
prepare_pacman
if [[ $? -ne 0 ]]; then
    echo "Pacman preparation FAILED!"
    return 1
fi

# mount proc/sysfs first, so mkinitcpio can use auto-detection if it wants
chroot_mount

# install packages
install_packages
if [[ $? -gt 0 ]]; then
    echo
    echo "Package installation FAILED."
    echo
    chroot_umount
    exit 1
fi

# /etc/locale.gen
# enable at least en_US.UTF8 if nothing was changed, else weird things happen on reboot!
! [[ $(grep -q ^[a-z] ${DESTDIR}/etc/locale.gen) ]] && sed -i -e 's:^#en_US.UTF-8:en_US.UTF-8:g' ${DESTDIR}/etc/locale.gen
chroot ${DESTDIR} locale-gen >/dev/null 2>&1

# umount chroot
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
echo "Edit your /etc/mkinitcpio.conf and /etc/mkinitcpio.d/${KERNELPKG}-fallback.conf"
echo "to fit your needs. After that run:"
echo "# mkinitcpio -p ${KERNELPKG}"
echo
echo "Then exit your chroot shell, edit ${DESTDIR}/etc/fstab and reboot!"
echo
exit 0

# vim: set ts=4 sw=4 et:
