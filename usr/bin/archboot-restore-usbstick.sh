#!/usr/bin/env bash
# 
#    archboot-restore-usbstick.sh - restore usbstick to FAT32
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
APPNAME=$(basename "${0}")
usage()
{
    echo "Restoring an USB device to its original state (FAT32):"
    echo "usage: ${APPNAME} <device>"
    exit $1
}

##################################################

[[ -z "${1}" ]] && usage

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

# clean partitiontable
dd if=/dev/zero of=<DEVICE> bs=512 count=2048
wipefs -a "$1"

# create new MBR and partition on <DEVICE>
fdisk "$1" <<EOF
n
p
1


t
b
w
EOF
# wait for partitiontable to be resynced
sleep 5
# create FAT32 filesystem on <device-partition>
mkfs.vfat -F32 "$1"1
