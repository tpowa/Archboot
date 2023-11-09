#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
LANG=C
_R_KVER="$(uname -r)"
_R_ARCH="$(uname -m)"
_TITLE="Archboot ${_R_ARCH} | ${_R_KVER} | Basic Setup | Early Userspace"
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
    if [[ "${1}" == kernel ]]; then
        bsdcpio -u -i "*/lib/modules/"  "*/lib/firmware/" <"/mnt/efi/boot/initrd-${_R_ARCH}.img" &>/dev/null
        # wait 1 second until proceeding with module loading, needed at least for kms activation
        sleep 1
    fi
    if [[ "${1}" == cleanup ]]; then
        rm -rf /lib/modules/*/kernel/drivers/{acpi,ata,gpu,bcma,block,bluetooth,hid,\
input,platform,net,scsi,soc,spi,usb,video} /lib/modules/*/extramodules
        # keep ethernet NIC firmware
        rm -rf /lib/firmware/{RTL8192E,advansys,amd*,ar3k,ath*,atmel,brcm,cavium,cirrus,cxgb*,\
cypress,dvb*,ene-ub6250,i915,imx,intel,iwlwifi-[8-9]*,iwlwifi-[a-z]*,iwlwifi-[A-Z]*,keyspan*,\
korg,libertas,matrox,mediatek,mrvl,mwl*,nvidia,nxp,qca,radeon,r128,rsi,rtlwifi,rtl_bt,rtw*,\
ti-connectivity,tehuti,wfx,yam,yamaha}
    fi
    if [[ "${1}" == system ]]; then
        echo "zstd" >/sys/block/zram0/comp_algorithm
        echo "5G" >/sys/block/zram0/disksize
        mkfs.btrfs /dev/zram0 &>/dev/null
        # use discard to get free RAM on delete!
        mount -o discard /dev/zram0 /sysroot &>/dev/null
        mkdir -p /sysroot/usr/lib
        mv /lib/modules /sysroot/usr/lib
        mv /lib/firmware /sysroot/usr/lib
        cd /sysroot
        bsdcpio -u -f "*/lib/modules/" -f "*/lib/firmware/" -i<"/mnt/efi/boot/initrd-${_R_ARCH}.img" &>/dev/null
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
_first_stage() {
    cd /
    # move in modules from main initrd
    : >/.archboot
    _task kernel &
    _progress_wait "0" "99" "${_KEEP} Loading files..." "0.5"
    _progress "100" "${_KEEP}"
}
_second_stage() {
    : >/.archboot
    _task cleanup &
    _progress_wait "0" "3" "${_KEEP} Removing files..." "0.125"
    : >/.archboot
    _task system &
    _progress_wait "4" "97" "${_KEEP} Creating rootfs in /sysroot..." "0.125"
    : >/.archboot
    # unmount everything after copying
    _task unmount &
    _progress_wait "98" "99" "${_KEEP} Unmounting archboot rootfs..." "1"
    _progress "100" "The boot medium can be safely removed now."
    sleep 2
    # remove files and directories
    rm -r /sysroot/sysroot
    rm /sysroot/init
}
# not all devices trigger autoload!
modprobe -q cdrom
modprobe -q usb-storage
modprobe -q zram
modprobe -q zstd
echo "Initializing Console..."
printf "\ec"
# it needs one echo before, in order to reset the consolefont!
setfont ter-v16n -C /dev/console
loadkeys us
echo "Searching 10 seconds for Archboot ${_R_ARCH} rootfs..."
_COUNT=0
while ! [[ "${_COUNT}" == 10 ]]; do
    # dd / rufus
    mount UUID=1234-ABCD /mnt/efi &>/dev/null && break
    # ventoy
    if mount LABEL=Ventoy /mnt/ventoy &>/dev/null; then
        mount /mnt/ventoy/archboot-*-*-"${_R_KVER}"-"${_R_ARCH}".iso /mnt/cdrom &>/dev/null && break
        mount /mnt/ventoy/archboot-*-*-"${_R_KVER}"-latest-"${_R_ARCH}".iso /mnt/cdrom &>/dev/null && break
        mount /mnt/ventoy/archboot-*-*-"${_R_KVER}"-local-"${_R_ARCH}".iso /mnt/cdrom &>/dev/null && break
    fi
    if [[ -b /dev/sr0 ]]; then
        mount /dev/sr0 /mnt/cdrom &>/dev/null && break
    fi
    sleep 1
    _COUNT=$((_COUNT+1))
done
if ! [[ -f "/mnt/efi/boot/initrd-${_R_ARCH}.img" ]] ; then
    if ! mount /mnt/cdrom/efi.img /mnt/efi &>/dev/null; then
        echo -e "\e[1;91mArchboot Emergeny Shell:\e[m"
        echo -e "\e[1;91mError: Didn't find a device with archboot rootfs! \e[m"
        echo -e "\e[1mThis needs further debugging. Please contact the archboot author.\e[m"
        echo -e "\e[1mTobias Powalowski: tpowa@archlinux.org\e[m"
        echo ""
        systemctl start emergency.service
    fi
fi
_first_stage | _dialog --title " Loading Kernel Modules " --gauge "${_KEEP} Loading files..." 6 75 0
# avoid screen messup, don't run dialog on module loading!
printf "\ec"
udevadm trigger --type=all --action=add --prioritized-subsystem=module,block,tpmrm,net,tty,input
udevadm settle
# autodetect screen size
FB_SIZE="$(cut -d 'x' -f 1 "$(find /sys -wholename '*fb0/modes')" | sed -e 's#.*:##g')"
if [[ "${FB_SIZE}" -gt '1900' ]]; then
    SIZE="32"
else
    SIZE="16"
fi
# clear screen
echo "Initializing Console..."
printf "\ec"
setfont ter-v${SIZE}n -C /dev/console
_second_stage | _dialog --title " Initializing System " --gauge "${_KEEP} Removing files..." 6 75 0
# set font size in vconsole.conf
echo FONT=ter-v${SIZE}n >> /sysroot/etc/vconsole.conf
systemd-sysusers --root=/sysroot &>/dev/null
systemd-tmpfiles -E --create --root=/sysroot &>/dev/null
printf "\ec"
echo "Launching systemd $(udevadm --version)..."
# vim: set ft=sh ts=4 sw=4 et:
