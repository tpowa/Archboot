#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# copy-mointpoint.sh - copy recursivly a mountpoint using tar
# by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
. /usr/lib/archboot/common.sh
_usage()
{
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Copy Mountpoint\e[m"
    echo -e "\e[1m--------------------------\e[m"
    echo "- Copy mountpoint recursivly from <oldmountpoint> to <newmountpoint>,"
    echo -e "  using the \e[1mtar\e[m utility."
    echo -e "- For system copying start with mounted \e[1m/\e[m and then invoke this script"
    echo -e "  for each additional mountpoint eg. \e[1m/boot\e[m or \e[1m/home\e[m."
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} <oldmountpoint> <newmountpoint>\e[m"
    exit 0
}
##################################################
if [ $# -ne 2 ]; then
    _usage
fi
_NEWMOUNTPOINT="${2}"
_OLDMOUNTPOINT="${1}"
tar -C "${_OLDMOUNTPOINT}" --hard-dereference -clpf - . | tar -C "${_NEWMOUNTPOINT}" -vxlspf -
