#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# 
#    copy-mointpoint.sh - copy recursivly a mountpoint using tar
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
_APPNAME=$(basename "${0}")
_usage()
{
    echo -e "\e[1mWelcome to \e[36mARCHBOOT\e[0m\e[1m - COPY MOUNTPOINT:\e[0m"
    echo -e "\e[1m--------------------------------------\e[0m"
    echo "- Copy mountpoint recursivly from one mountpoint to an other one,"
    echo "  using tar utility."
    echo -e "- For system copying start with mounted \e[1m/\e[0m and then invoke this script"
    echo -e "  for each additional mountpoint eg. \e[1m/boot\e[0m or \e[1m/home\e[0m."
    echo ""
    echo -e "usage: \e[1m${_APPNAME} <oldmountpoint> <newmountpoint>\e[0m"
    exit "$1"
}
##################################################
if [ $# -ne 2 ]; then
    _usage 1
fi
_NEWMOUNTPOINT="${2}"
_OLDMOUNTPOINT="${1}"
tar -C "${_OLDMOUNTPOINT}" -clpf - . | tar -C "${_NEWMOUNTPOINT}" -vxlspf -
