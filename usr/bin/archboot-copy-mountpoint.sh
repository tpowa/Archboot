#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# 
#    copy-mointpoint.sh - copy recursivly a mountpoint using tar
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
_APPNAME=${0##*/}
_usage()
{
    echo -e "\e[1mWelcome to \e[36mARCHBOOT\e[m\e[1m - COPY MOUNTPOINT:\e[m"
    echo -e "\e[1m--------------------------------------\e[m"
    echo "- Copy mountpoint recursivly from one mountpoint to an other one,"
    echo "  using tar utility."
    echo -e "- For system copying start with mounted \e[1m/\e[m and then invoke this script"
    echo -e "  for each additional mountpoint eg. \e[1m/boot\e[m or \e[1m/home\e[m."
    echo ""
    echo -e "usage: \e[1m${_APPNAME} <oldmountpoint> <newmountpoint>\e[m"
    exit 0
}
##################################################
if [ $# -ne 2 ]; then
    _usage
fi
_NEWMOUNTPOINT="${2}"
_OLDMOUNTPOINT="${1}"
tar -C "${_OLDMOUNTPOINT}" --hard-dereference -clpf - . | tar -C "${_NEWMOUNTPOINT}" -vxlspf -
