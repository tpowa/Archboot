#!/usr/bin/env bash
# 
#    copy-mointpoint.sh - copy recursivly a mountpoint using tar
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
APPNAME=$(basename "${0}")
usage()
{
    echo "RSYNC BACKUP:"
    echo "- Copy backupdir to backupdestination using rsync."
    echo ""
    echo "- For system backup start with full mounted system and then invoke this script"
    echo "  with system's root directory as backupdir."
    echo " - excluded directories are /dev /var/tmp /proc /sys /run /mnt /media /lost+found"
    echo " - --numeric-ids option is invoked to preserve users"
    echo ""
    echo "usage: ${APPNAME} <backupdir> <backupdestination>"
    exit $1
}

##################################################

if [ $# -ne 2 ]; then
    usage 1
fi

BACKUPDESTINATION="${2}"
BACKUPDIR="${1}"

rsync -aAXv --numeric-ids --exclude={"/dev/*","/proc/*","/sys/*","/var/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} $BACKUPDIR $BACKUPDESTINATION

