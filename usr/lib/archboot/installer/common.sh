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
    _VMLINUZ_EFISTUB="Image"
fi
# abstract the common pacman args
_PACMAN="pacman --root ${_DESTDIR} --cachedir=${_DESTDIR}${_CACHEDIR} --noconfirm"

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
    { echo "[options]"
    echo "Architecture = auto"
    echo "SigLevel    = Required DatabaseOptional"
    echo "LocalFileSigLevel = Optional"
    echo "[archboot]"
    echo "Server = file://${_CACHEDIR}"
    } >> "${_PACMAN_CONF}"
    _PACMAN_CONF="--config ${_PACMAN_CONF}"
    _PACMAN="pacman --root ${_DESTDIR} ${_PACMAN_CONF} --cachedir=${_DESTDIR}${_CACHEDIR} --noconfirm"
}

_auto_packages() {
    # add packages from Archboot defaults
    . /etc/archboot/defaults
    # Add filesystem packages
    if ${_LSBLK} FSTYPE | rg -q 'btrfs'; then
        ! rg -qw 'btrfs-progs' <<< "${_PACKAGES[@]}" && _PACKAGES+=(btrfs-progs)
    fi
    if ${_LSBLK} FSTYPE | rg -q 'ext'; then
        ! rg -qw 'e2fsprogs' <<< "${_PACKAGES[@]}" && _PACKAGES+=(e2fsprogs)
    fi
    if ${_LSBLK} FSTYPE | rg -q 'xfs'; then
        ! rg -qw 'xfsprogs' <<< "${_PACKAGES[@]}" && _PACKAGES+=(xfsprogs)
    fi
    if ${_LSBLK} FSTYPE | rg -q 'vfat'; then
        ! rg -qw 'dosfstools' <<< "${_PACKAGES[@]}" && _PACKAGES+=(dosfstools)
    fi
    # Add packages for complex blockdevices
    if ${_LSBLK} FSTYPE | rg -qw 'linux_raid_member'; then
        ! rg -qw 'mdadm' <<< "${_PACKAGES[@]}" && _PACKAGES+=(mdadm)
    fi
    if ${_LSBLK} FSTYPE | rg -qw 'LVM2_member'; then
        ! rg -qw 'lvm2' <<< "${_PACKAGES[@]}" && _PACKAGES+=(lvm2)
    fi
    if ${_LSBLK} FSTYPE | rg -qw 'crypto_LUKS'; then
        ! rg -qw 'cryptsetup' <<< "${_PACKAGES[@]}" && _PACKAGES+=(cryptsetup)
    fi
    # Add iwd, if wlan is detected
    if fd . /sys/class/net | rg -q 'wlan'; then
        ! rg -qw 'iwd' <<< "${_PACKAGES[@]}" && _PACKAGES+=(iwd)
    fi
    rg -q '^FONT=ter' /etc/vconsole.conf && _PACKAGES+=(terminus-font)
    rg -q '^WIRELESS' /etc/conf.d/wireless-regdom && _PACKAGES+=(wireless-regdb)
    _auto_fw
}

# /etc/locale.gen
# enable at least C.UTF-8 if nothing was changed, else weird things happen on reboot!
_locale_gen() {
    ${_NSPAWN} locale-gen &>"${_NO_LOG}"
    # write to template
    echo "${_NSPAWN} locale-gen &>\"\${_NO_LOG}\"" >> "${_TEMPLATE}"
    [[ -e /.archboot ]] && rm /.archboot
}

_write_partition_template() {
    # write to template
    { echo "### partition"
    echo "echo \"Partitioning ${_DISK}...\""
    echo "sfdisk \"${_DISK}\" << EOF &>\"\${_LOG}\""
    sfdisk -d "${_DISK}"
    echo "EOF"
    echo ""
    } >> "${_TEMPLATE}"
}

_editor() {
    ${_EDITOR} "${1}"
     # write to template
    _file_to_template "${1}"
}

_file_to_template() {
    # write to template
    { echo "### ${1} file"
    echo ": > \"${1}\""
    sd '^' "echo \'" < "${1}" | sd '$' "\' >> ${1}"
    } >> "${_TEMPLATE}"
    # new line is not added by default on last line
    { echo -n $'\n'
    echo ""
    } >> "${_TEMPLATE}"
}

_remove_from_devs() {
    IFS=" " read -r -a _DEVS <<< "$(sd "$(${_LSBLK} NAME,SIZE -d "${1}")" "" <<< "${_DEVS[@]}")"
}
