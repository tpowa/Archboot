#!/usr/bin/env bash
## Script for creating a UEFI CD bootable ISO from existing Archboot ISO
## Contributed by "Keshav Padram" <the ddoott ridikulus ddoott rat aatt geemmayil ddoott ccoomm>
## ${1} == PATH to ISO

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
    echo "ERROR: Please run as root user!"
    exit 1
fi

## Extract old ISO
mkdir -p /tmp/ARCHBOOTISO/
bsdtar -C /tmp/ARCHBOOTISO/ -xf "${1}"
# 7z x -o /tmp/ARCHBOOTISO/ "${1}"

## Create efiboot.img
dd if=/dev/zero of=/tmp/efiboot.img bs=120000 count=1024 
mkfs.vfat /tmp/efiboot.img
LOOPDEV="$(losetup --find --show /tmp/efiboot.img)"

## Mount efiboot.img
mkdir -p /tmp/EFIBOOT/
mount -t vfat -o rw,users "${LOOPDEV}" /tmp/EFIBOOT

## Copy UEFI files fo efiboot.img
cp -r /tmp/ARCHBOOTISO/{EFI,loader,boot} /tmp/EFIBOOT/
rm -rf /tmp/EFIBOOT/boot/syslinux
rm /tmp/EFIBOOT/boot/memtest

## Unmount efiboot.img
umount "${LOOPDEV}"
losetup --detach "${LOOPDEV}"
rm -rf /tmp/EFIBOOT/

## Move updated efiboot.img to old ISO extracted dir
mv /tmp/efiboot.img /tmp/ARCHBOOTISO/EFI/efiboot.img

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
        -eltorito-alt-boot --efi-boot EFI/efiboot.img -no-emul-boot \
        -isohybrid-mbr /tmp/ARCHBOOTISO/boot/syslinux/isohdpfx.bin \
        -output /tmp/ARCHBOOT.iso /tmp/ARCHBOOTISO/ &> /tmp/xorriso.log

## Updated ISO at /tmp/ARCHBOOT.iso
if [[ -e "/tmp/ARCHBOOT.iso" ]]; then
    echo "Updated ISO at /tmp/ARCHBOOT.iso"
else
    echo "ISO generation failed. See /tmp/xorriso.log for more info."
fi

## Delete old ISO extracted files
rm -rf /tmp/ARCHBOOTISO/
