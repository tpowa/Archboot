#!/bin/bash
#    based on mkusbimg, modified to use syslinux 
#    by Tobias Powalowski <tpowa@archlinux.org>
# 
#    mkusbimg - creates a bootable disk image
#    Copyright (C) 2008  Simo Leone <simo@archlinux.org>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

# usage(exitvalue)
# outputs a usage message and exits with value

APPNAME="$(basename "${0}")"

_usage() {
    echo "usage: ${APPNAME} <imageroot> <imagefile>"
    exit ${1}
}

##################################################

if [ $# -ne 2 ]; then
    _usage 1
fi

DISKIMG="${2}"
IMGROOT="${1}"
TMPDIR=$(mktemp -d)
TMPDIR2=$(mktemp -d)
FSIMG=$(mktemp)

# ext2 overhead's upper bound is 6%
# empirically tested up to 1GB
rootsize=$(du -bs ${IMGROOT}|cut -f1)
IMGSZ=$(( (${rootsize}*102)/100/512 + 1)) # image size in sectors

# create the filesystem image file
dd if=/dev/zero of="${FSIMG}" bs="512" count="${IMGSZ}"

# create a filesystem on the image
mkfs.vfat -S 512 -F32 -n "ARCHBOOT" "${FSIMG}"

# mount the filesystem and copy data
if ! [[ "$(lsmod | grep ^loop)" ]]; then
	modprobe -q loop || echo "Your hostsystem has a different kernel version installed, please load loop module first on hostsystem!"
fi
LOOP_DEVICE="$(losetup --show --find "${FSIMG}")"
mount -o rw,flush -t vfat "${LOOP_DEVICE}" "${TMPDIR}"

if [[ ! -e "${IMGROOT}/efi/boot/bootx64.efi" ]]; then
	
	LOOP_DEVICE2="$(losetup --show --find "${IMGROOT}/efi/grub2/grub2_efi.bin")"
	mount -o ro -t vfat "${LOOP_DEVICE2}" "${TMPDIR2}"
	cp -f "${TMPDIR2}/bootx64.efi" "${IMGROOT}/efi/boot/bootx64.efi"
	
	umount "${TMPDIR2}"
	losetup --detach "${LOOP_DEVICE2}"
	
	rm -rf "${TMPDIR2}"
fi

cp -rf "${IMGROOT}"/* "${TMPDIR}"

rm -f "${TMPDIR}/boot/syslinux"/*.{com,bin,c32} || true
cp -f "/usr/lib/syslinux"/*.{com,bin,c32} "${TMPDIR}/boot/syslinux/"

# unmount filesystem
umount "${TMPDIR}"
losetup --detach "${LOOP_DEVICE}"

cat "${FSIMG}" > "${DISKIMG}"

# install syslinux on the image
syslinux "${DISKIMG}"

# all done :)
rm -rf "${TMPDIR}"
rm -f "${FSIMG}"
