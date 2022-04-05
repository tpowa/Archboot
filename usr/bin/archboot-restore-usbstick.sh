#!/usr/bin/env bash
# 
#    archboot-restore-usbstick.sh - restore usbstick to FAT32
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
APPNAME=$(basename "${0}")
usage()
{
    echo -e "\033[1mWelcome to \033[34marchboot's\033[0m \033[1mRESTORE USB STICK:\033[0m"
    echo -e "\033[1m----------------------------------------\033[0m"
    echo -e "This script restores an USB device to a \033[1mFAT32\033[0m device."
    echo -e "\033[91mWARNING: ALL DATA WILL BE LOST ON THE DEVICE! \033[0m"
    echo ""
    echo -e "usage: \033[1m${APPNAME} <device>\033[0m"
    exit "1"
}

##################################################

[[ -z "${1}" ]] && usage "$@"

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
    echo "ERROR: Please run as root user!"
    exit 1
fi
echo -e "\033[91mWARNING: 10 seconds for hitting CTRL+C to stop the process on ${1} now! \033[0m"
sleep 10
# clean partitiontable
echo -e "\033[1mRestoring USB STICK...\033[0m"
echo -e "\033[1mSTEP 1/3:\033[0m Cleaning partition table..."
dd if=/dev/zero of="${1}" bs=512 count=2048
wipefs -a "${1}"
# create new MBR and partition on <DEVICE>
echo -e "\033[1mSTEP 2/3:\033[0m Create new MBR and partitiontable..."
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
echo -e "\033[1mSTEP 3/3:\033[0m Create FAT32 filesystem..."
mkfs.vfat -F32 "${1}"1
echo -e "\033[1mFinished.\033[0m"
