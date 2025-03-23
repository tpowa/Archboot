#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# archboot-clean-blockdevice.sh - clean blockdevice from filesystem 
# signatures and partition table
# by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_usage()
{
    echo -e "\e[1m\e[36mARCHBOOT\e[m \e[1m- Clean blockdevice\e[m"
    echo -e "\e[1m----------------------------\e[m"
    echo -e "This script removes all filesystem signatures"
    echo -e "and partition table from the device."
    echo -e "\e[1m\e[91mWARNING: ALL DATA WILL BE LOST ON THE DEVICE(S)! \e[m"
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} <device(s)>\e[m"
    exit 0
}
##################################################
[[ -z "${1}" ]] && _usage
_root_check
echo -e "\e[1mCleaning blockdevice(s) $*...\e[m"
echo -e "\e[91mWARNING: 10 seconds for hitting CTRL+C to stop the process on $* now! \e[m"
sleep 10
for i in "$@"; do
    if [[ -b "${i}" ]]; then
        echo -e "\e[1mSTEP 1/2:\e[m Cleaning ${i} filesystem signatures..."
        wipefs -f -a "${i}"
        echo -e "\e[1mSTEP 2/2:\e[m Cleaning ${i} partition table..."
        dd if=/dev/zero of="${i}" bs=1M count=10
        echo -e "\e[1mFinished ${i}.\e[m"
    else
        echo -e "\e[1m\e[91mError: ${i} not a valid blockdevice! \e[m"
    fi
done
