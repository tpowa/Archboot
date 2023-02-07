#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# 
#    archboot-restore-usbstick.sh - restore usbstick to FAT32
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
_APPNAME=$(basename "${0}")
_usage()
{
    echo -e "\e[1mWelcome to \e[36mARCHBOOT\e[0m \e[1m- RESTORE USB STICK:\e[0m"
    echo -e "\e[1m----------------------------------------\e[0m"
    echo -e "This script restores an USB device to a \e[1mFAT32\e[0m device."
    echo -e "\e[91mWARNING: ALL DATA WILL BE LOST ON THE DEVICE! \e[0m"
    echo ""
    echo -e "usage: \e[1m${_APPNAME} <device>\e[0m"
    exit "1"
}
##################################################
[[ -z "${1}" ]] && _usage "$@"
### check for root
if ! [[ ${UID} -eq 0 ]]; then 
    echo "ERROR: Please run as root user!"
    exit 1
fi
echo -e "\e[91mWARNING: 10 seconds for hitting CTRL+C to stop the process on ${1} now! \e[0m"
sleep 10
# clean partitiontable
echo -e "\e[1mRestoring USB STICK...\e[0m"
echo -e "\e[1mSTEP 1/3:\e[0m Cleaning partition table..."
dd if=/dev/zero of="${1}" bs=512 count=2048
wipefs -a "${1}"
# create new MBR and partition on <DEVICE>
echo -e "\e[1mSTEP 2/3:\e[0m Create new MBR and partitiontable..."
fdisk "${1}" <<EOF
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
echo -e "\e[1mSTEP 3/3:\e[0m Create FAT32 filesystem..."
mkfs.vfat -F32 "${1}"1
echo -e "\e[1mFinished.\e[0m"
