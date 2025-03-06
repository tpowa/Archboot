#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
# install stages
_S_QUICK_SETUP="" # guided fs/format
# menu item tracker- autoselect the next item
_NEXTITEM=""
# To allow choice in script set EDITOR=""
_EDITOR=""
# programs
_LSBLK="lsblk -rpno"
_FINDMNT="findmnt -vno SOURCE"
# don't use _DESTDIR=/mnt because it's intended to mount other things there!
# check first if bootet in archboot
if rg -qw '^archboot' /etc/hostname; then
    _DESTDIR="/mnt/install"
    _NSPAWN="systemd-nspawn -q -D ${_DESTDIR}"
else
    _DESTDIR="/"
    _NSPAWN=""
fi
# name of the kernel image
[[ "${_RUNNING_ARCH}" == "x86_64" || "${_RUNNING_ARCH}" == "riscv64" ]] && _VMLINUZ="vmlinuz-${_KERNELPKG}"
if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
    _VMLINUZ="Image.gz"
    #shellcheck disable=SC2034
    _VMLINUZ_EFISTUB="Image"
fi
# abstract the common pacman args
_PACMAN="pacman --root ${_DESTDIR} --cachedir=${_DESTDIR}${_CACHEDIR} --noconfirm"

_linux_firmware() {
    #shellcheck disable=SC2013
    for i in $(choose 0 </proc/modules); do
        if modinfo "${i}" | rg -qw 'firmware:'; then
            _PACKAGES+=(linux-firmware)
            break
        fi
    done
}

_marvell_firmware() {
    _MARVELL=()
    for i in $(fd -t f . /lib/modules/"${_RUNNING_KERNEL}" | rg -w 'wireless/marvell'); do
        #shellcheck disable=SC2207
        _MARVELL+=($(basename "${i}" | sd '.ko.*$' ''))
    done
    # check marvell modules if already loaded
    #shellcheck disable=SC2068
    for i in ${_MARVELL[@]}; do
        if lsmod | rg -qw "${i}"; then
            _PACKAGES+=(linux-firmware-marvell)
            break
        fi
    done
}

# prepares target system as a chroot
_chroot_mount()
{
    if rg -qw '^archboot' /etc/hostname; then
        [[ -e "${_DESTDIR}/proc" ]] || mkdir -m 555 "${_DESTDIR}/proc"
        [[ -e "${_DESTDIR}/sys" ]] || mkdir -m 555 "${_DESTDIR}/sys"
        [[ -e "${_DESTDIR}/dev" ]] || mkdir -m 755 "${_DESTDIR}/dev"
        mount proc "${_DESTDIR}/proc" -t proc -o nosuid,noexec,nodev
        mount sys "${_DESTDIR}/sys" -t sysfs -o nosuid,noexec,nodev,ro
        # needed for efi bootloader installation routines
        if mount | rg -qw 'efivarfs'; then
            mount efivarfs "${_DESTDIR}"/sys/firmware/efi/efivars -t efivarfs -o nosuid,noexec,nodev
        fi
        mount udev "${_DESTDIR}/dev" -t devtmpfs -o mode=0755,nosuid
        mount devpts "${_DESTDIR}/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec
        mount shm "${_DESTDIR}/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev
    fi
}

# tears down chroot in target system
_chroot_umount()
{
    if rg -qw '^archboot' /etc/hostname; then
        umount -R "${_DESTDIR}"/{proc,sys,dev}
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
    echo "Server = file://${_CACHEDIR}" >> "${_PACMAN_CONF}"
    _PACMAN_CONF="--config ${_PACMAN_CONF}"
    _PACMAN="pacman --root ${_DESTDIR} ${_PACMAN_CONF} --cachedir=${_DESTDIR}${_CACHEDIR} --noconfirm"
}

_auto_packages() {
    # add packages from Archboot defaults
    . /etc/archboot/defaults
    # remove linux-firmware packages first
    #shellcheck disable=SC2206
    _PACKAGES=(${_PACKAGES[@]/linux-firmware*})
    # Add filesystem packages
    if ${_LSBLK} FSTYPE | rg -q 'bcachefs'; then
        ! echo "${_PACKAGES[@]}" | rg -qw 'bcachefs-tools' && _PACKAGES+=(bcachefs-tools)
    fi
    if ${_LSBLK} FSTYPE | rg -q 'btrfs'; then
        ! echo "${_PACKAGES[@]}" | rg -qw 'btrfs-progs' && _PACKAGES+=(btrfs-progs)
    fi
    if ${_LSBLK} FSTYPE | rg -q 'ext'; then
        ! echo "${_PACKAGES[@]}" | rg -qw 'e2fsprogs' && _PACKAGES+=(e2fsprogs)
    fi
    if ${_LSBLK} FSTYPE | rg -q 'xfs'; then
        ! echo "${_PACKAGES[@]}" | rg -qw 'xfsprogs' && _PACKAGES+=(xfsprogs)
    fi
    if ${_LSBLK} FSTYPE | rg -q 'vfat'; then
        ! echo "${_PACKAGES[@]}" | rg -qw 'dosfstools' && _PACKAGES+=(dosfstools)
    fi
    # Add packages for complex blockdevices
    if ${_LSBLK} FSTYPE | rg -qw 'linux_raid_member'; then
        ! echo "${_PACKAGES[@]}" | rg -qw 'mdadm' && _PACKAGES+=(mdadm)
    fi
    if ${_LSBLK} FSTYPE | rg -qw 'LVM2_member'; then
        ! echo "${_PACKAGES[@]}" | rg -qw 'lvm2' && _PACKAGES+=(lvm2)
    fi
    if ${_LSBLK} FSTYPE | rg -qw 'crypto_LUKS'; then
        ! echo "${_PACKAGES[@]}" | rg -qw 'cryptsetup' && _PACKAGES+=(cryptsetup)
    fi
    #shellcheck disable=SC2010
    # Add iwd, if wlan is detected
    if fd . /sys/class/net | rg -q 'wlan'; then
        ! echo "${_PACKAGES[@]}" | rg -qw 'iwd' && _PACKAGES+=(iwd)
    fi
    rg -q '^FONT=ter' /etc/vconsole.conf && _PACKAGES+=(terminus-font)
    # only add firmware if already used
    _linux_firmware
    _marvell_firmware
}

# /etc/locale.gen
# enable at least C.UTF-8 if nothing was changed, else weird things happen on reboot!
_locale_gen() {
    ${_NSPAWN} locale-gen &>"${_NO_LOG}"
    [[ -e /.archboot ]] && rm /.archboot
}

_write_partition_template() {
    # write to template
    { echo "### partition start"
    echo "Partitioning \"${_DISK}\"..."
    echo "sfdisk \"${_DISK}\" << EOF"
    sfdisk -d "${_DISK}"
    echo "EOF"
    echo "### partition end"
    } >> "${_TEMPLATE}"
}
