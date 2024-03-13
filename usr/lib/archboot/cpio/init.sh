#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
LANG=C
_KVER="$(uname -r)"
_ARCH="$(uname -m)"
_TITLE="Archboot ${_ARCH} | ${_KVER} | Basic Setup | Early Userspace | archboot.com"
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
    while [[ -e /.archboot ]]; do
        if [[ "${_COUNT}" -lt "${2}" ]]; then
            _progress "${_COUNT}" "${3}"
        fi
        if [[ "${_COUNT}" -gt "${2}" ]]; then
            _progress "${2}" "${3}"
        fi
        _COUNT="$((_COUNT+1))"
        sleep "${4}"
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
    if [[ "${1}" == check ]]; then
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
        rm -r sysroot
        rm init
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
_initrd_stage() {
    : >/.archboot
    _task mount &
    _progress_wait "0" "10" "${_KEEP} Searching for rootfs..." "1"
    : >/.archboot
    _task check &
    _progress_wait "11" "12" "${_KEEP} Checking rootfs..." "1"
    : >/.archboot
    _task btrfs &
    _progress_wait "13" "20" "${_KEEP} Creating btrfs on /dev/zram0..." "0.5"
    : >/.archboot
    _task system &
    _progress_wait "21" "95" "${_KEEP} Copying rootfs to /sysroot..." "0.75"
    : >/.archboot
    _task unmount &
    _progress_wait "96" "99" "${_KEEP} Unmounting rootfs..." "1"
    _progress "100" "The boot medium can be safely removed now."
}
# not all devices trigger autoload!
for i in cdrom usb-storage zram zstd; do
    modprobe -q "${i}"
done
# take care of builtin drm modules, timeout after 10 seconds to avoid hang on some systems
udevadm wait --settle /dev/fb0 -t 10
_SIZE="16"
if [[ -e /sys/class/graphics/fb0/modes ]]; then
    # get screen setting mode from /sys
    _FB_SIZE="$(sed -e 's#.*:##g' -e 's#x.*##g' /sys/class/graphics/fb0/modes 2>/dev/null)"
    if [[ "${_FB_SIZE}" -gt '1900' ]]; then
        _SIZE="32"
    fi
fi
# it needs one echo before, in order to reset the consolefont!
_msg "Initializing Console..."
_clear
setfont ter-v${_SIZE}n -C /dev/console
_initrd_stage | _dialog --title " Initializing System " --gauge "${_KEEP} Searching for rootfs..." 6 75 0
_clear
_msg "The boot medium can be safely removed now."
echo ""
_msg "Launching $(systemctl --version | head -n1)..."
# vim: set ft=sh ts=4 sw=4 et:
