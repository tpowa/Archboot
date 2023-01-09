#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# we rely on some output which is parsed in english!
LANG=C.UTF8
_LOCAL_DB="/var/cache/pacman/pkg/archboot.db"
_RUNNING_ARCH="$(uname -m)"
_KERNELPKG="linux"
# name of the kernel image
[[ "${_RUNNING_ARCH}" == "x86_64" || "${_RUNNING_ARCH}" == "riscv64" ]] && _VMLINUZ="vmlinuz-${_KERNELPKG}"
if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
    _VMLINUZ="Image.gz"
    #shellcheck disable=SC2034
    _VMLINUZ_EFISTUB="Image"
fi
# abstract the common pacman args
_PACMAN="pacman --root ${_DESTDIR} ${_PACMAN_CONF} --cachedir=${_DESTDIR}/var/cache/pacman/pkg --noconfirm --noprogressbar"
_MIRRORLIST="/etc/pacman.d/mirrorlist"

_linux_firmware() {
    _PACKAGES="${_PACKAGES//\ linux-firmware\ / }"
    #shellcheck disable=SC2013
    for i in $(cut -d ' ' -f1</proc/modules); do
        if modinfo "${i}" | grep -qw 'firmware:'; then
            _PACKAGES="${_PACKAGES} linux-firmware"
            break
        fi
    done
}

_marvell_firmware() {
    unset MARVELL
    _PACKAGES="${_PACKAGES// linux-firmware-marvell/ }"
    for i in $(find /lib/modules/"$(uname -r)" | grep -w wireless | grep -w marvell); do
        [[ -f $i ]] && MARVELL="$MARVELL $(basename "${i}" | sed -e 's#\..*$##g')"
    done
    # check marvell modules if already loaded
    for i in ${MARVELL}; do
        if lsmod | grep -qw "${i}"; then
            _PACKAGES="${_PACKAGES} linux-firmware-marvell"
            break
        fi
    done
}

# chroot_mount()
# prepares target system as a chroot
_chroot_mount()
{
    if grep -qw archboot /etc/hostname; then
        [[ -e "${_DESTDIR}/proc" ]] || mkdir -m 555 "${_DESTDIR}/proc"
        [[ -e "${_DESTDIR}/sys" ]] || mkdir -m 555 "${_DESTDIR}/sys"
        [[ -e "${_DESTDIR}/dev" ]] || mkdir -m 755 "${_DESTDIR}/dev"
        mount proc "${_DESTDIR}/proc" -t proc -o nosuid,noexec,nodev
        mount sys "${_DESTDIR}/sys" -t sysfs -o nosuid,noexec,nodev,ro
        mount udev "${_DESTDIR}/dev" -t devtmpfs -o mode=0755,nosuid
        mount devpts "${_DESTDIR}/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec
        mount shm "${_DESTDIR}/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev
    fi
}

# chroot_umount()
# tears down chroot in target system
_chroot_umount()
{
    if grep -qw archboot /etc/hostname; then
        umount -R "${_DESTDIR}/proc"
        umount -R "${_DESTDIR}/sys"
        umount -R "${_DESTDIR}/dev"
    fi
}

_local_pacman_conf() {
    _PACMAN_CONF="$(mktemp /tmp/pacman.conf.XXX)"
    #shellcheck disable=SC2129
    echo "[options]" >> "${_PACMAN_CONF}"
    echo "Architecture = auto" >> "${_PACMAN_CONF}"
    echo "SigLevel    = Required DatabaseOptional" >> "${_PACMAN_CONF}"
    echo "LocalFileSigLevel = Optional" >> "${_PACMAN_CONF}"
    echo "[archboot]" >> "${_PACMAN_CONF}"
    echo "Server = file:///var/cache/pacman/pkg" >> "${_PACMAN_CONF}"
    _PACMAN_CONF="--config ${_PACMAN_CONF}"
}

_auto_packages() {
    # Add filesystem packages
    if lsblk -rnpo FSTYPE | grep -q btrfs; then
        ! echo "${_PACKAGES}" | grep -qw btrfs-progs && _PACKAGES="${_PACKAGES} btrfs-progs"
    fi
    if lsblk -rnpo FSTYPE | grep -q nilfs2; then
        ! echo "${_PACKAGES}" | grep -qw nilfs-utils && _PACKAGES="${_PACKAGES} nilfs-utils"
    fi
    if lsblk -rnpo FSTYPE | grep -q ext; then
        ! echo "${_PACKAGES}" | grep -qw e2fsprogs && _PACKAGES="${_PACKAGES} e2fsprogs"
    fi
    if lsblk -rnpo FSTYPE | grep -q xfs; then
        ! echo "${_PACKAGES}" | grep -qw xfsprogs && _PACKAGES="${_PACKAGES} xfsprogs"
    fi
    if lsblk -rnpo FSTYPE | grep -q jfs; then
        ! echo "${_PACKAGES}" | grep -qw jfsutils && _PACKAGES="${_PACKAGES} jfsutils"
    fi
    if lsblk -rnpo FSTYPE | grep -q f2fs; then
        ! echo "${_PACKAGES}" | grep -qw f2fs-tools && _PACKAGES="${_PACKAGES} f2fs-tools"
    fi
    if lsblk -rnpo FSTYPE | grep -q vfat; then
        ! echo "${_PACKAGES}" | grep -qw dosfstools && _PACKAGES="${_PACKAGES} dosfstools"
    fi
    if ! [[ "$(dmraid_devices)" == "" ]]; then
        ! echo "${_PACKAGES}" | grep -qw dmraid && _PACKAGES="${_PACKAGES} dmraid"
    fi
    if lsmod | grep -qw wl; then
        ! echo "${_PACKAGES}" | grep -qw broadcom-wl && _PACKAGES="${_PACKAGES} broadcom-wl"
    fi
    #shellcheck disable=SC2010
    if ls /sys/class/net | grep -q wlan; then
        ! echo "${_PACKAGES}" | grep -qw iwd && _PACKAGES="${_PACKAGES} iwd"
    fi
    # only add firmware if already used
    linux_firmware
    marvell_firmware
    ### HACK:
    # always add intel-ucode on x86_64
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        _PACKAGES="${_PACKAGES//\ intel-ucode\ / }"
        _PACKAGES="${_PACKAGES} intel-ucode"
    fi
    # always add amd-ucode
    if [[ "${_RUNNING_ARCH}" == "x86_64" ||  "${_RUNNING_ARCH}" == "aarch64"  ]]; then
        _PACKAGES="${_PACKAGES//\ amd-ucode\ / }"
        _PACKAGES="${_PACKAGES} amd-ucode"
    fi
    ### HACK:
    # always add lvm2, cryptsetup and mdadm
    _PACKAGES="${_PACKAGES//\ lvm2\ / }"
    _PACKAGES="${_PACKAGES} lvm2"
    _PACKAGES="${_PACKAGES//\ cryptsetup\ / }"
    _PACKAGES="${_PACKAGES} cryptsetup"
    _PACKAGES="${_PACKAGES//\ mdadm\ / }"
    _PACKAGES="${_PACKAGES} mdadm"
    ### HACK
    # always add nano and neovim
    _PACKAGES="${_PACKAGES//\ nano\ / }"
    _PACKAGES="${_PACKAGES} nano"
    _PACKAGES="${_PACKAGES//\ neovim\ / }"
    _PACKAGES="${_PACKAGES} neovim"
}

# /etc/locale.gen
# enable at least C.UTF-8 if nothing was changed, else weird things happen on reboot!
_locale_gen() {
    if [[ "${_DESTDIR}" == "/install" ]]; then
        systemd-nspawn -q -D "${_DESTDIR}" locale-gen >/dev/null 2>&1
    else
        locale-gen >/dev/null 2>&1
    fi
}
