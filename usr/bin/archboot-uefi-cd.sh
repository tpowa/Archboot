#!/usr/bin/env bash
## Script for creating a UEFI CD bootable ISO from existing Archboot ISO
## by Tobias Powalowski <tpowa@archlinux.org>
## Contributed by "Keshav Padram" <the ddoott ridikulus ddoott rat aatt geemmayil ddoott ccoomm>
## ${1} == PATH to ISO

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
    echo "ERROR: Please run as root user!"
    exit 1
fi

### check for available loop devices in a container
! [[ -e /dev/loop0 ]] && mknod /dev/loop0 b 7 0
! [[ -e /dev/loop-control ]] && mknod /dev/loop-control c 10 237

FSIMG=$(mktemp -d)
ISOIMG=$(mktemp -d)
MOUNT_FSIMG=$(mktemp -d)

## Extract old ISO
bsdtar -C "${ISOIMG}" -xf "${1}"
# 7z x -o /tmp/ARCHBOOTISO/ "${1}"

## get size of boot x86_64 files
BOOTSIZE=$(LANG=EN_US du -bc ${ISOIMG}/{EFI,loader,boot/*x86_64*} | grep total | cut -f1)
IMGSZ=$(( (${BOOTSIZE}*102)/100/1024 + 1)) # image size in sectors

## Create cdefiboot.img
dd if=/dev/zero of="${FSIMG}"/cdefiboot.img bs="${IMGSZ}" count=1024 
mkfs.vfat "${FSIMG}"/cdefiboot.img
LOOPDEV="$(losetup --find --show "${FSIMG}"/cdefiboot.img)"

## Mount cdefiboot.img
mount -t vfat -o rw,users "${LOOPDEV}" "${MOUNT_FSIMG}"

## Copy UEFI files fo cdefiboot.img
mkdir "${MOUNT_FSIMG}"/boot
cp -r "${ISOIMG}"/{EFI,loader} "${MOUNT_FSIMG}"
cp "${ISOIMG}"/boot/*x86_64* "${MOUNT_FSIMG}"/boot

## Unmount cdefiboot.img
umount "${LOOPDEV}"
losetup --detach "${LOOPDEV}"
rm -rf "${MOUNT_FSIMG}"

## Move updated cdefiboot.img to old ISO extracted dir
mkdir -p "${ISOIMG}"/CDEFI/
rm "${ISOIMG}"/CDEFI/cdefiboot.img
mv "${FSIMG}"/cdefiboot.img "${ISOIMG}"/CDEFI/cdefiboot.img
rm -rf "${FSIMG}"

## Create new ISO with BIOS, ISOHYBRID and UEFI support
xorriso -as mkisofs \
        -iso-level 3 -rock -joliet \
        -max-iso9660-filenames -omit-period \
        -omit-version-number -allow-leading-dots \
        -relaxed-filenames -allow-lowercase -allow-multidot \
        -volid "ARCHBOOT" \
        -preparer "prepared by archboot-uefi-cd.sh" \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e CDEFI/cdefiboot.img -isohybrid-gpt-basdat \
        -no-emul-boot \
        -isohybrid-mbr "${ISOIMG}"/boot/syslinux/isohdpfx.bin \
        -output ARCHBOOT.iso "${ISOIMG}"/ &> /tmp/xorriso.log

if [[ -e "ARCHBOOT.iso" ]]; then
    echo "Updated ISO at ARCHBOOT.iso"
else
    echo "ISO generation failed. See /tmp/xorriso.log for more info."
fi

## Delete old ISO extracted files
rm -rf "${ISOIMG}"
