#!/usr/bin/env bash
LOCAL_DB="/var/cache/pacman/pkg/archboot.db"
DESTDIR="${1}"
RUNNING_ARCH="$(uname -m)"
# name of kernel package
KERNELPKG="linux"
# name of the kernel image
[[ "${RUNNING_ARCH}" == "x86_64" ]] && VMLINUZ="vmlinuz-${KERNELPKG}"
[[ "${RUNNING_ARCH}" == "aarch64" ]] && VMLINUZ="Image"

custom_pacman_conf() {
        _PACMAN_CONF="$(mktemp /tmp/pacman.conf.XXX)"
        #shellcheck disable=SC2129
        echo "[options]" >> "${_PACMAN_CONF}"
        echo "Architecture = auto" >> "${_PACMAN_CONF}"
        echo "SigLevel    = Required DatabaseOptional" >> "${_PACMAN_CONF}"
        echo "LocalFileSigLevel = Optional" >> "${_PACMAN_CONF}"
        echo "[archboot]" >> "${_PACMAN_CONF}"
        echo "Server = file:///var/cache/pacman/pkg" >> "${_PACMAN_CONF}"
        PACMAN_CONF="--config ${_PACMAN_CONF}"
}

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
    # add packages from archboot defaults
    PACKAGES=$(grep '^_PACKAGES' /etc/archboot/defaults | sed -e 's#_PACKAGES=##g' -e 's#"##g')
    # fallback if _PACKAGES is empty
    [[ -z "${PACKAGES}" ]] && PACKAGES="base linux linux-firmware"
    # Add packages which are not in core repository
    if lsblk -rnpo FSTYPE | grep -q btrfs; then
        ! echo "${PACKAGES}" | grep -qw btrfs-progs && PACKAGES="${PACKAGES} btrfs-progs"
    fi
    if lsblk -rnpo FSTYPE | grep -q nilfs2; then
        ! echo "${PACKAGES}" | grep -qw nilfs-utils && PACKAGES="${PACKAGES} nilfs-utils"
    fi
    if lsblk -rnpo FSTYPE | grep -q ext; then
        ! echo "${PACKAGES}" | grep -qw e2fsprogs && PACKAGES="${PACKAGES} e2fsprogs"
    fi
    if lsblk -rnpo FSTYPE | grep -q xfs; then
        ! echo "${PACKAGES}" | grep -qw xfsprogs && PACKAGES="${PACKAGES} xfsprogs"
    fi
    if lsblk -rnpo FSTYPE | grep -q jfs; then
        ! echo "${PACKAGES}" | grep -qw jfsutils && PACKAGES="${PACKAGES} jfsutils"
    fi
    if lsblk -rnpo FSTYPE | grep -q f2fs; then
        ! echo "${PACKAGES}" | grep -qw f2fs-tools && PACKAGES="${PACKAGES} f2fs-tools"
    fi
    if lsblk -rnpo FSTYPE | grep -q vfat; then
        ! echo "${PACKAGES}" | grep -qw dosfstools && PACKAGES="${PACKAGES} dosfstools"
    fi
    if [[ -n "$(pgrep dhclient)" ]]; then
        ! echo "${PACKAGES}" | grep -qw dhclient && PACKAGES="${PACKAGES} dhclient"
    fi
    if lsmod | grep -qw wl; then
        ! echo "${PACKAGES}" | grep -qw broadcom-wl && PACKAGES="${PACKAGES} broadcom-wl"
    fi
    ### HACK:
    # always add systemd-sysvcompat components
    PACKAGES="${PACKAGES//\ systemd-sysvcompat\ / }"
    PACKAGES="${PACKAGES} systemd-sysvcompat"
    ### HACK:
    # always add intel-ucode
    if [[ "$(uname -m)" == "x86_64" ]]; then
        PACKAGES="${PACKAGES//\ intel-ucode\ / }"
        PACKAGES="${PACKAGES} intel-ucode"
    fi
    # always add amd-ucode
    PACKAGES="${PACKAGES//\ amd-ucode\ / }"
    PACKAGES="${PACKAGES} amd-ucode"
    ### HACK:
    # always add netctl with optdepends
    PACKAGES="${PACKAGES//\ netctl\ / }"
    PACKAGES="${PACKAGES} netctl"
    PACKAGES="${PACKAGES//\ dhcpd\ / }"
    PACKAGES="${PACKAGES} dhcpcd"
    PACKAGES="${PACKAGES//\ wpa_supplicant\ / }"
    PACKAGES="${PACKAGES} wpa_supplicant"
    ### HACK:
    # always add lvm2, cryptsetup and mdadm
    PACKAGES="${PACKAGES//\ lvm2\ / }"
    PACKAGES="${PACKAGES} lvm2"
    PACKAGES="${PACKAGES//\ cryptsetup\ / }"
    PACKAGES="${PACKAGES} cryptsetup"
    PACKAGES="${PACKAGES//\ mdadm\ / }"
    PACKAGES="${PACKAGES} mdadm"
      ### HACK
    # always add nano and vi
    PACKAGES="${PACKAGES//\ nano\ / }"
    PACKAGES="${PACKAGES} nano"
    PACKAGES="${PACKAGES//\ vi\ / }"
    PACKAGES="${PACKAGES} vi"
    ### HACK: circular depends are possible in base, install filesystem first!
    PACKAGES="${PACKAGES//\ filesystem\ / }"
    PACKAGES="filesystem ${PACKAGES}"
    #shellcheck disable=SC2086
    ${PACMAN} -S ${PACKAGES}
}

if [[ -z "${1}" ]]; then
    usage
fi

! [[ -d /tmp ]] && mkdir /tmp

if [[ -e "${LOCAL_DB}" ]]; then
    custom_pacman_conf
else
    PACMAN_CONF=""
fi
PACMAN="pacman --root ${DESTDIR} ${PACMAN_CONF} --cachedir ${DESTDIR}/var/cache/pacman/pkg --noconfirm"

# prepare pacman
prepare_pacman || (echo "Pacman preparation FAILED!"; return 1)

# mount proc/sysfs first, so mkinitcpio can use auto-detection if it wants
chroot_mount

# install packages
install_packages || (echo "Package installation FAILED."; chroot_umount; exit 1)

# /etc/locale.gen
# enable at least en_US.UTF8 if nothing was changed, else weird things happen on reboot!
! grep -q "^[a-z]" "${DESTDIR}/etc/locale.gen" && sed -i -e 's:^#en_US.UTF-8:en_US.UTF-8:g' "${DESTDIR}/etc/locale.gen"
chroot "${DESTDIR}" locale-gen >/dev/null 2>&1

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
echo "Edit your /etc/mkinitcpio.conf to fit your needs. After that run:"
echo "# mkinitcpio -p ${KERNELPKG}"
echo
echo "Then exit your chroot shell, edit ${DESTDIR}/etc/fstab and reboot!"
echo
exit 0

# vim: set ts=4 sw=4 et:
