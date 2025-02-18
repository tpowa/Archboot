#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_KVER="$(uname -r)"
_ARCH="$(uname -m)"
_TITLE="archboot.com | ${_ARCH} | ${_KVER} | Basic Setup | Early Userspace"
_KEEP="Please keep the boot medium inserted..."
_NO_LOG=/dev/null
_FW=/mnt/efi/boot/firmware
_VGA="VGA compatible controller"
_ETH="Ethernet controller"
_WIFI="Network controller"
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
# $1: start percentage $2: end percentage $3: message
_progress_wait() {
    while [[ -e /.archboot ]]; do
        if [[ "${_COUNT}" -lt "${2}" ]]; then
            _progress "${_COUNT}" "${3}"
        fi
        if [[ "${_COUNT}" -gt "${2}" ]]; then
            _COUNT="${1}"
        fi
        _COUNT="$((_COUNT+1))"
        sleep "0.05"
    done
}
_task() {
    if [[ "${1}" == mount ]]; then
        _COUNT=0
        while ! [[ "${_COUNT}" == 10 ]]; do
            # dd / rufus
            mount UUID=1234-ABCD /mnt/efi &>"${_NO_LOG}" && break
            # ventoy
            if mount LABEL=Ventoy /mnt/ventoy &>"${_NO_LOG}"; then
                mount /mnt/ventoy/archboot-*-*-"${_KVER}"-"${_ARCH}".iso /mnt/cdrom &>"${_NO_LOG}" && break
                mount /mnt/ventoy/archboot-*-*-"${_KVER}"-latest-"${_ARCH}".iso /mnt/cdrom &>"${_NO_LOG}" && break
                mount /mnt/ventoy/archboot-*-*-"${_KVER}"-local-"${_ARCH}".iso /mnt/cdrom &>"${_NO_LOG}" && break
            fi
            if [[ -b /dev/sr0 ]]; then
                mount /dev/sr0 /mnt/cdrom &>"${_NO_LOG}" && break
            fi
            sleep 1
            _COUNT=$((_COUNT+1))
        done
    fi
    if [[ "${1}" == check ]]; then
        if ! [[ -f "/mnt/efi/boot/initrd-${_ARCH}.img" ]] ; then
            if ! mount /mnt/cdrom/efi.img /mnt/efi &>"${_NO_LOG}"; then
                _clear
                _wrn "Archboot Emergeny Shell:"
                _wrn "Error: Didn't find a device with Archboot rootfs!"
                _msg "This needs further debugging. Please contact the Archboot author."
                _msg "Tobias Powalowski: tpowa@archlinux.org"
                echo ""
                systemctl start emergency.service
            fi
        fi
    fi
    if [[ "${1}" == btrfs ]]; then
        # if available, use zstd as compression algorithm
        rg -qw 'zstd' /sys/block/zram0/comp_algorithm && echo "zstd" >/sys/block/zram0/comp_algorithm
        echo "5G" >/sys/block/zram0/disksize
        mkfs.btrfs /dev/zram0 &>"${_NO_LOG}"
        # use discard to get immediate remove of files
        mount -o discard /dev/zram0 /sysroot
    fi
    if [[ "${1}" == system ]]; then
        rm -r /lib/modules
        #shellcheck disable=SC2164
        cd /sysroot
        # fastest uncompression of zstd cpio format
        3cpio -x "/mnt/efi/boot/initrd-${_ARCH}.img"
        rm -r sysroot
        rm init
    fi
    if [[ "${1}" == fw_run ]]; then
        #shellcheck disable=SC2164
        cd /sysroot
        3cpio -x --force "${2}" &>"${_NO_LOG}"
    fi
    if [[ "${1}" == unmount ]]; then
        if mountpoint /mnt/ventoy &>"${_NO_LOG}"; then
            for i in /mnt/{efi,cdrom,ventoy}; do
                umount -q -A "${i}" 2>"${_NO_LOG}"
            done
        fi
        if mountpoint /mnt/cdrom &>"${_NO_LOG}"; then
            for i in /mnt/{efi,cdrom}; do
                umount -q -A "${i}" 2>"${_NO_LOG}"
            done
        fi
        umount -q -A UUID=1234-ABCD 2>"${_NO_LOG}"
    fi
    rm /.archboot
}
_initrd_stage() {
    : >/.archboot
    _task mount &
    _progress_wait "0" "99" "\n${_KEEP}\n\nSearching rootfs on blockdevices..."
    : >/.archboot
    _task check &
    _progress_wait "0" "99" "\n${_KEEP}\n\nMounting rootfs on blockdevice..."
    : >/.archboot
    _task btrfs &
    _progress_wait "0" "99" "\n${_KEEP}\n\nCreating btrfs on /dev/zram0..."
    : >/.archboot
    _task system &
    _progress_wait "0" "99" "\n${_KEEP}\n\nCopying rootfs to /sysroot..."
    : >/.archboot
    # Graphic firmware
    if lspci -mm | rg -q "${_VGA}"; then
        if lspci -mm | rg "${_VGA}" | rg -q 'AMD'; then
            for i in "${_FW}"/amd*; do
                _FW_RUN+=("${i}")
            done
        fi
        if lspci -mm | rg "${_VGA}" | rg -q 'Intel'; then
            if lspci -mm | rg "${_VGA}" | rg 'Intel' | rg -q 'Xe'; then
                _FW_RUN+=("${_FW}/xe.img")
            else
                _FW_RUN+=("${_FW}/i915.img")
            fi
        fi
        if lspci -mm | rg "${_VGA}" | rg -q 'NVIDIA'; then
            _FW_RUN+=("${_FW}/nvidia.img")
        fi
        if lspci -mm | rg "${_VGA}" | rg -q 'RADEON|Radeon'; then
            _FW_RUN+=("${_FW}/radeon.img")
        fi
    fi
    # Ethernet firmware
    if lspci -mm | rg -q "${_ETH}"; then
        if lspci -mm | rg "${_ETH}" | rg -q 'Broadcom'; then
            _FW_RUN+=("${_FW}/bnx2.img" "${_FW}/tigon.img")
        fi
        if lspci -mm | rg "${_ETH}" | rg -q 'Realtek'; then
             _FW_RUN+=("${_FW}/rtl_nic.img")
        fi
    fi
    # Wifi firmware
    if lspci -mm | rg -q "${_WIFI}"; then
        if lspci -mm | rg "${_WIFI}" | rg -q 'Atheros'; then
            for i in "${_FW}"/ath*; do
                _FW_RUN+=("${i}")
            done
        fi
        if lspci -mm | rg "${_WIFI}" | rg -q 'Intel'; then
            _FW_RUN+=("${_FW}/iwlwifi.img")
        fi
        if lspci -mm | rg "${_WIFI}" | rg -q 'Marvell'; then
            for i in "${_FW}"/libertas "${_FW}"/mrvl "${_FW}"/mwl*; do
                _FW_RUN+=("${i}")
            done
        fi
        if lspci -mm | rg "${_WIFI}" | rg -q 'Mediatek'; then
            _FW_RUN+=("${_FW}/mediatek.img")
        fi
        if lspci -mm | rg "${_WIFI}" | rg -q 'Ralink'; then
            _FW_RUN+=("${_FW}/ralink.img")
        fi
        if lspci -mm | rg "${_WIFI}" | rg -q 'Realtek'; then
            _FW_RUN+=("${_FW}/rtlwifi.img")
            for i in "${_FW}"/rtw*; do
                _FW_RUN+=("${i}")
            done
        fi
        if lspci -mm | rg "${_WIFI}" | rg -q 'Texas'; then
            _FW_RUN+=("${_FW}/ti-connectivity.img")
        fi
    fi
    #shellcheck disable=SC2068
    for i in ${_FW_RUN[@]}; do
        : >/.archboot
        _task fw_run "${i}" &
        _progress_wait "0" "99" "\n${_KEEP}\n\nCopying $(basename -s '.img' "${i}") firmware to /sysroot..."
    done
    : >/.archboot
    _task unmount &
    _progress_wait "0" "99" "\n${_KEEP}\n\nUnmounting rootfs..."
    _progress "100" "The boot medium can be safely removed now."
}
# not all devices trigger autoload!
for i in atkbd cdrom i8042 usb-storage zram zstd; do
    modprobe -q "${i}"
done
# systemd >= 256 mounts /usr ro by default
mount -o remount,rw /usr 2>"${_NO_LOG}"
# take care of builtin drm modules, timeout after 10 seconds to avoid hang on some systems
udevadm wait --settle /dev/fb0 -t 10
_SIZE="16"
if [[ -e /sys/class/graphics/fb0/modes ]]; then
    # get screen setting mode from /sys
    _FB_SIZE="$(rg -o ':(.*)x' -r '$1' /sys/class/graphics/fb0/modes 2>"${_NO_LOG}")"
    if [[ "${_FB_SIZE}" -gt '1900' ]]; then
        _SIZE="32"
    fi
fi
# it needs one echo before, in order to reset the consolefont!
while true; do
    _msg "Initializing Console..."
    _clear
    setfont -C /dev/console ter-v${_SIZE}n && break
    sleep 0.1
done
_initrd_stage | _dialog --title " Initializing System " --gauge "\n${_KEEP}\n\nSearching rootfs on blockdevices..." 9 60 0
_clear
_msg "The boot medium can be safely removed now."
echo ""
_msg "Launching $(systemctl --version | head -n1)..."
# debug option for early userspace
rg -q 'archboot-early-debug' /proc/cmdline && mv /sysroot /sysroot.debug
