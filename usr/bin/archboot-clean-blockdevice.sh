#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# archboot-restore-usbstick.sh - restore usbstick to FAT32
# by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_usage()
{
    echo -e "\e[1m\e[36mARCHBOOT\e[m \e[1m- Clean blockdevice\e[m"
    echo -e "\e[1m----------------------------\e[m"
    echo -e "This script removes all filesystem signatures"
    echo -e "and partitiontable from the device."
    echo -e "\e[1m\e[91mWARNING: ALL DATA WILL BE LOST ON THE DEVICE(S)! \e[m"
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} <device(s)>\e[m"
    exit 0
}
##################################################
[[ -z "${1}" ]] && _usage "$@"
### check for root
if ! [[ ${UID} -eq 0 ]]; then 
    echo "ERROR: Please run as root user!"
    exit 1
fi
#shellcheck disable=SC2068
for i in $@; do
    echo -e "\e[1mCleaning blockdevice ${i}...\e[m"
    echo -e "\e[91mWARNING: 10 seconds for hitting CTRL+C to stop the process on ${i} now! \e[m"
    sleep 10
    echo -e "\e[1mSTEP 1/2:\e[m Cleaning filesystem signatures..."
    wipefs -f -a "${i}"
    echo -e "\e[1mSTEP 2/2:\e[m Cleaning partition table..."
    dd if=/dev/zero of="${i}" bs=1M count=10
    echo -e "\e[1mFinished ${i}.\e[m"
done
