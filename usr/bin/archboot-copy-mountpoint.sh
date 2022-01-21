#!/usr/bin/env bash
# 
#    copy-mointpoint.sh - copy recursivly a mountpoint using tar
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
APPNAME=$(basename "${0}")
usage()
{
    echo "COPY MOUNTPOINTS:"
    echo "- Copy mountpoint recursivly from one mountpoint to an other one,"
    echo "  using tar utility."
    echo "- For system copying start with mounted / and then invoke this script"
    echo "  for each additional mountpoint eg. /boot or /home."
    echo ""
    echo "usage: ${APPNAME} <oldmountpoint> <newmountpoint>"
    exit "$1"
}

##################################################

if [ $# -ne 2 ]; then
    usage 1
fi

NEWMOUNTPOINT="${2}"
OLDMOUNTPOINT="${1}"

tar -C "$OLDMOUNTPOINT" -clpf - . | tar -C "$NEWMOUNTPOINT" -vxlspf - 
