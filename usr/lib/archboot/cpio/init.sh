#!/usr/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
LANG=C
_TITLE="Archboot $(uname -m) | $(uname -r) | Basic Setup | Early Userspace"
_KEEP="Please keep the boot medium inserted."
_dialog() {
    dialog --backtitle "${_TITLE}" "$@"
    return $?
}
_udev_trigger() {
    udevadm trigger --action=add --type=subsystems
    udevadm trigger --action=add --type=devices
    udevadm settle
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
        read -r -t "${4}"
        ! [[ -e /.archboot ]] && break
    done
}
_task() {
    [[ "${1}" == kernel ]] && bsdcpio -u -i "*/lib/modules/"  "*/lib/firmware/" <"/mnt/boot/initrd-$(uname -m).img" &>/dev/null
    if [[ "${1}" == cleanup ]]; then
        rm -rf /lib/modules/*/kernel/drivers/{acpi,ata,gpu,bcma,block,bluetooth,hid,input,platform,net,scsi,soc,spi,usb,video} /lib/modules/*/extramodules
        # keep ethernet NIC firmware
        rm -rf /lib/firmware/{RTL8192E,advansys,amd*,ar3k,ath*,atmel,brcm,cavium,cirrus,cxgb*,cypress,dvb*,ene-ub6250,i915,imx,intel,iwlwifi-[8-9]*,iwlwifi-[a-z]*,iwlwifi-[A-Z]*,keyspan*,korg,libertas,matrox,mediatek,mrvl,mwl*,nvidia,nxp,qca,radeon,r128,rsi,rtlwifi,rtl_bt,rtw*,ti-connectivity,tehuti,wfx,yam,yamaha}
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
        bsdcpio -u -f "*/lib/modules/" -f "*/lib/firmware/" -i<"/mnt/boot/initrd-$(uname -m).img" &>/dev/null
    fi
    if [[ "${1}" == unmount ]]; then
        if mountpoint /ventoy &>/dev/null; then
            for i in /mnt /cdrom /ventoy; do
                umount -q -A "${i}" 2>/dev/null
            done
        fi
        if mountpoint /cdrom &>/dev/null; then
            for i in /mnt /cdrom; do
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
_udev_stage() {
    udevadm control -R
    _udev_trigger
    # shutdown udevd
    udevadm control --exit
    udevadm info --cleanup-db
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
    read -r -t 2
    # remove files and directories
    rm -r /sysroot/sysroot
    rm /sysroot/init
}
# mount kernel filesystems
mount -t proc proc /proc -o nosuid,noexec,nodev
mount -t sysfs sys /sys -o nosuid,noexec,nodev
mount -t devtmpfs dev /dev -o mode=0755,nosuid
mount -t tmpfs run /run -o nosuid,nodev,mode=0755
if [ -e /sys/firmware/efi ]; then
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars -o nosuid,nodev,noexec
fi
echo archboot >/proc/sys/kernel/hostname
# initialize udev
kmod static-nodes --format=tmpfiles --output=/run/tmpfiles.d/kmod.conf
systemd-tmpfiles --prefix=/dev --create --boot
/usr/lib/systemd/systemd-udevd --daemon --resolve-names=never &>/dev/null
_udev_trigger
# not all devices trigger autoload!
modprobe -q cdrom
modprobe -q usb-storage
modprobe -q zram
modprobe -q zstd
echo 1 > /proc/sys/kernel/sysrq
echo "Initializing Console..."
printf "\ec"
# it needs one echo before, in order to reset the consolefont!
setfont consolefont-16.psf.gz -C /dev/console
echo "Searching 10 seconds for Archboot $(uname -m) rootfs..."
_COUNT=0
while true; do
    # dd / rufus
    mount UUID=1234-ABCD /mnt &>/dev/null && break
    # ventoy
    if mount LABEL=Ventoy /ventoy &>/dev/null; then
        mount /ventoy/archboot-*-*-"$(uname -r)"-"$(uname -m)".iso /cdrom &>/dev/null && break
        mount /ventoy/archboot-*-*-"$(uname -r)"-latest-"$(uname -m)".iso /cdrom &>/dev/null && break
        mount /ventoy/archboot-*-*-"$(uname -r)"-local-"$(uname -m)".iso /cdrom &>/dev/null && break
    fi
    if [[ -b /dev/sr0 ]]; then
        mount /dev/sr0 /cdrom &>/dev/null && break
    fi
    read -r -t 1
    _COUNT=$((_COUNT+1))
    [[ "${_COUNT}" == 10 ]] && break
done
if ! [[ -f "/mnt/boot/initrd-$(uname -m).img" ]] ; then
    if ! mount /cdrom/efi.img /mnt &>/dev/null; then
        echo -e "\e[1;91mArchboot Emergeny Shell:\e[m"
        echo -e "\e[1;91mError: Didn't find a device with archboot rootfs! \e[m"
        echo -e "\e[1mThis needs further debugging. Please contact the archboot author.\e[m"
        echo -e "\e[1mTobias Powalowski: tpowa@archlinux.org\e[m"
        echo ""
        echo -e "\e[1;93mType 'exit' or 'reboot' for reboot.\e[m"
        echo -e "\e[1;93mType 'poweroff' for poweroff.\e[m"
        /bin/bash
        echo b >/proc/sysrq-trigger
    fi
fi
_first_stage | _dialog --title " Loading Kernel Modules " --gauge "${_KEEP} Loading files..." 6 75 0
# avoid screen messup, don't run dialog on module loading!
printf "\ec"
# reinitialize available modules
_udev_stage
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
setfont consolefont-${SIZE}.psf.gz -C /dev/console
_second_stage | _dialog --title " Initializing System " --gauge "${_KEEP} Removing files..." 6 75 0
echo 0 > /proc/sys/kernel/sysrq
# set font size in vconsole.conf
echo FONT=ter-v${SIZE}n >> /sysroot/etc/vconsole.conf
printf "\ec"
echo "Launching systemd $(udevadm --version)..."
exec switch_root /sysroot /usr/bin/init "$@"
# vim: set ft=sh ts=4 sw=4 et: