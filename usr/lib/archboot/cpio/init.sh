#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
LANG=C
_KVER="$(uname -r)"
_ARCH="$(uname -m)"
_TITLE="Archboot ${_ARCH} | ${_KVER} | Basic Setup | Early Userspace"
_KEEP="Please keep the boot medium inserted."
_dialog() {
    dialog --backtitle "${_TITLE}" "$@"
    return $?
}
_progress() {
cat <<EOF
XXX
${1}
${2}
XXX
EOF
}
_msg() {
    echo -e "\e[1m${1}\e[m"
}
_wrn() {
    echo -e "\e[1;91m${1}\e[m"
}
_clear() {
    printf "\ec"
}
# $1: start percentage $2: end percentage $3: message $4: sleep time
_progress_wait() {
    _COUNT=${1}
    while true; do
        if [[ "${_COUNT}" -lt "${2}" ]]; then
            _progress "${_COUNT}" "${3}"
        fi
        if [[ "${_COUNT}" -gt "${2}" ]]; then
            _progress "${2}" "${3}"
        fi
        _COUNT="$((_COUNT+1))"
        sleep "${4}"
        ! [[ -e /.archboot ]] && break
    done
}
_task() {
    if [[ "${1}" == mount ]]; then
        _COUNT=0
        while ! [[ "${_COUNT}" == 10 ]]; do
            # dd / rufus
            mount UUID=1234-ABCD /mnt/efi &>/dev/null && break
            # ventoy
            if mount LABEL=Ventoy /mnt/ventoy &>/dev/null; then
                mount /mnt/ventoy/archboot-*-*-"${_KVER}"-"${_ARCH}".iso /mnt/cdrom &>/dev/null && break
                mount /mnt/ventoy/archboot-*-*-"${_KVER}"-latest-"${_ARCH}".iso /mnt/cdrom &>/dev/null && break
                mount /mnt/ventoy/archboot-*-*-"${_KVER}"-local-"${_ARCH}".iso /mnt/cdrom &>/dev/null && break
            fi
            if [[ -b /dev/sr0 ]]; then
                mount /dev/sr0 /mnt/cdrom &>/dev/null && break
            fi
            sleep 1
            _COUNT=$((_COUNT+1))
        done
    fi
    if [[ "${1}" == btrfs ]]; then
        echo "zstd" >/sys/block/zram0/comp_algorithm
        echo "5G" >/sys/block/zram0/disksize
        mkfs.btrfs /dev/zram0 &>/dev/null
        # use discard to get immediate remove of files
        mount -o discard /dev/zram0 /sysroot
    fi
    if [[ "${1}" == system ]]; then
        rm -r /lib/modules
        cd /sysroot
        # fastest uncompression of zstd cpio format
        bsdcpio -i -d -u <"/mnt/efi/boot/initrd-${_ARCH}.img" &>/dev/null
        rm -r /sysroot/sysroot
        rm /sysroot/init
    fi
    if [[ "${1}" == unmount ]]; then
        if mountpoint /mnt/ventoy &>/dev/null; then
            for i in /mnt/{efi,cdrom,ventoy}; do
                umount -q -A "${i}" 2>/dev/null
            done
        fi
        if mountpoint /mnt/cdrom &>/dev/null; then
            for i in /mnt/{efi,cdrom}; do
                umount -q -A "${i}" 2>/dev/null
            done
        fi
        umount -q -A UUID=1234-ABCD 2>/dev/null
    fi
    rm /.archboot
}
_mount_stage() {
    : >/.archboot
    _task mount &
    _progress_wait "0" "99" "${_KEEP} Searching for rootfs..." "0.1"
    : >/.archboot
    _progress "100" "${_KEEP}"
}
_sysroot_stage() {
    : >/.archboot
    _task btrfs &
    _progress_wait "0" "10" "${_KEEP} Creating ZRAM device..." "0.1"
    : >/.archboot
    _task system &
    _progress_wait "0" "95" "${_KEEP} Copying rootfs to /sysroot..." "0.5"
    : >/.archboot
    _task unmount &
    _progress_wait "96" "99" "${_KEEP} Unmounting rootfs..." "1"
    _progress "100" "The boot medium can be safely removed now."
}
# not all devices trigger autoload!
for i in cdrom usb-storage zram zstd; do
    modprobe -q "${i}"
done
    # it needs one echo before, in order to reset the consolefont!
_msg "Initializing Console..."
_clear
setfont ter-v16n -C /dev/console
_mount_stage | _dialog --title " Initializing System " --gauge "${_KEEP} Searching for rootfs..." 6 75 0
if ! [[ -f "/mnt/efi/boot/initrd-${_ARCH}.img" ]] ; then
    if ! mount /mnt/cdrom/efi.img /mnt/efi &>/dev/null; then
        _clear
        _wrn "Archboot Emergeny Shell:"
        _wrn "Error: Didn't find a device with archboot rootfs!"
        _msg "This needs further debugging. Please contact the archboot author."
        _msg "Tobias Powalowski: tpowa@archlinux.org"
        echo ""
        systemctl start emergency.service
    fi
fi
_sysroot_stage | _dialog --title " Initializing System " --gauge "${_KEEP} Creating ZRAM device..." 6 75 0
systemd-sysusers --root=/sysroot &>/dev/null
systemd-tmpfiles -E --create --root=/sysroot &>/dev/null
_clear
_msg "The boot medium can be safely removed now."
echo ""
_msg "Launching systemd $(udevadm --version)..."
# vim: set ft=sh ts=4 sw=4 et:
