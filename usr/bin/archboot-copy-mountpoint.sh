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
    echo -e "\033[1mWelcome to \033[36mARCHBOOT\033[0m \033[1mCOPY MOUNTPOINTS:\033[0m"
    echo -e "\033[1m---------------------------------------\033[0m"
    echo "- Copy mountpoint recursivly from one mountpoint to an other one,"
    echo "  using tar utility."
    echo -e "- For system copying start with mounted \033[1m/\033[0m and then invoke this script"
    echo -e "  for each additional mountpoint eg. \033[1m/boot\033[0m or \033[1m/home\033[0m."
    echo ""
    echo -e "usage: \033[1m${_APPNAME} <oldmountpoint> <newmountpoint>\033[0m"
    exit "$1"
}
##################################################
if [ $# -ne 2 ]; then
    _usage 1
fi
_NEWMOUNTPOINT="${2}"
_OLDMOUNTPOINT="${1}"
tar -C "${_OLDMOUNTPOINT}" -clpf - . | tar -C "${_NEWMOUNTPOINT}" -vxlspf -
