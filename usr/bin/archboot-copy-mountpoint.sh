#!/usr/bin/env bash
# 
#    copy-mointpoint.sh - copy recursivly a mountpoint using tar
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
APPNAME=$(basename "${0}")
usage()
{
    echo -e "\033[1mWelcome to \033[34marchboot's\033[0m \033[1mCOPY MOUNTPOINTS:\033[0m"
    echo -e "\033[1m---------------------------------------\033[0m"
    echo "- Copy mountpoint recursivly from one mountpoint to an other one,"
    echo "  using tar utility."
    echo -e "- For system copying start with mounted \033[1m/\033[0m and then invoke this script"
    echo -e "  for each additional mountpoint eg. \033[1m/boot\033[0m or \033[1m/home\033[0m."
    echo ""
    echo -e "usage: \033[1m${APPNAME} <oldmountpoint> <newmountpoint>\033[0m"
    exit "$1"
}

##################################################

if [ $# -ne 2 ]; then
    usage 1
fi

NEWMOUNTPOINT="${2}"
OLDMOUNTPOINT="${1}"

tar -C "$OLDMOUNTPOINT" -clpf - . | tar -C "$NEWMOUNTPOINT" -vxlspf - 
