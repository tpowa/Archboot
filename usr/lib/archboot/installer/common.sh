#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# we rely on some output which is parsed in english!
LANG=C.UTF8
LOCAL_DB="/var/cache/pacman/pkg/archboot.db"
RUNNING_ARCH="$(uname -m)"
KERNELPKG="linux"
# name of the kernel image
[[ "${RUNNING_ARCH}" == "x86_64" ]] && VMLINUZ="vmlinuz-${KERNELPKG}"
if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
    VMLINUZ="Image.gz"
    VMLINUZ_EFISTUB="Image"
fi
# abstract the common pacman args
PACMAN="pacman --root ${DESTDIR} ${PACMAN_CONF} --cachedir=${DESTDIR}/var/cache/pacman/pkg --noconfirm --noprogressbar"


linux_firmware() {
    PACKAGES="${PACKAGES//\ linux-firmware\ / }"
    #shellcheck disable=SC2013
    for i in $(cut -d ' ' -f1</proc/modules); do
        if modinfo "${i}" | grep -w 'firmware:'; then
            PACKAGES="${PACKAGES} linux-firmware"
            break
        fi
    done
}

marvell_firmware() {
    unset MARVELL
    PACKAGES="${PACKAGES// linux-firmware-marvell/ }"
    for i in $(find /lib/modules/"$(uname -r)" | grep -w wireless | grep -w marvell); do
        [[ -f $i ]] && MARVELL="$MARVELL $(basename "${i}" | sed -e 's#\..*$##g')"
    done
    # check marvell modules if already loaded
    for i in ${MARVELL}; do
        if lsmod | grep -qw "${i}"; then
            PACKAGES="${PACKAGES} linux-firmware-marvell"
            break
        fi
    done
}

# chroot_mount()
# prepares target system as a chroot
chroot_mount()
{
    if grep -qw archboot /etc/hostname; then
        [[ -e "${DESTDIR}/proc" ]] || mkdir -m 555 "${DESTDIR}/proc"
        [[ -e "${DESTDIR}/sys" ]] || mkdir -m 555 "${DESTDIR}/sys"
        [[ -e "${DESTDIR}/dev" ]] || mkdir -m 755 "${DESTDIR}/dev"
        mount proc "${DESTDIR}/proc" -t proc -o nosuid,noexec,nodev
        mount sys "${DESTDIR}/sys" -t sysfs -o nosuid,noexec,nodev,ro
        mount udev "${DESTDIR}/dev" -t devtmpfs -o mode=0755,nosuid
        mount devpts "${DESTDIR}/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec
        mount shm "${DESTDIR}/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev
    fi
}

# chroot_umount()
# tears down chroot in target system
chroot_umount()
{
    if grep -qw archboot /etc/hostname; then
        umount -R "${DESTDIR}/proc"
        umount -R "${DESTDIR}/sys"
        umount -R "${DESTDIR}/dev"
    fi
}

local_pacman_conf() {
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

auto_packages() {
    # Add packages which are not in core repository
    if [[ -n "$(pgrep dhclient)" ]]; then
        ! echo "${PACKAGES}" | grep -qw dhclient && PACKAGES="${PACKAGES} dhclient"
    fi
    # Add filesystem packages
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
    if ! [[ "$(dmraid_devices)" = "" ]]; then
        ! echo "${PACKAGES}" | grep -qw dmraid && PACKAGES="${PACKAGES} dmraid"
    fi
    if lsmod | grep -qw wl; then
        ! echo "${PACKAGES}" | grep -qw broadcom-wl && PACKAGES="${PACKAGES} broadcom-wl"
    fi
    if ls /sys/class/net | grep -q wlan; then
        ! echo "${PACKAGES}" | grep -qw iwd && PACKAGES="${PACKAGES} iwd"
    fi
    # only add firmware if already used
    linux_firmware
    marvell_firmware
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
}

# /etc/locale.gen
# enable at least C.UTF-8 if nothing was changed, else weird things happen on reboot!
locale_gen() {
    if [[ "${DESTDIR}" == "/install" ]]; then
        systemd-nspawn -q -D "${DESTDIR}" locale-gen >/dev/null 2>&1
    else
        locale-gen >/dev/null 2>&1
    fi
}
