#!/usr/bin/env bash
# 
#    copy-mointpoint.sh - copy recursivly a mountpoint using tar
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
APPNAME=$(basename "${0}")
usage()
{
    echo -e "\033[1mWelcome to the \033[34mArchboot\033[0m \033[1m${APPNAME}:\033[0m"
    echo -e "\033[1m-------------------------------------------------\033[0m"
    echo -e "\033[1mRSYNC BACKUP:\033[0m"
    echo -e "- Copy \033[1mbackupdir\033[0m to \033[1mbackupdestination\033[0m using rsync."
    echo ""
    echo -e "- For system backup start with \033[1mfull\033[0m mounted system and then invoke this script"
    echo -e "  with system's root directory as \033[1mbackupdir\033[0m."
    echo -e "- \033[1mexcluded\033[0m directories are \033[1m/dev /tmp /proc /sys /run /mnt /media /lost+found\033[0m"
    echo -e "- \033[1m--numeric-ids\033[0m option is invoked to \033[1mpreserve\033[0m users"
    echo ""
    echo -e "usage: \033[1m${APPNAME} <backupdir> <backupdestination>\033[0m"
    exit "$1"
}

##################################################

if [ $# -ne 2 ]; then
    usage 1
fi

BACKUPDESTINATION="${2}"
BACKUPDIR="${1}"

rsync -aAXv --numeric-ids --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} "$BACKUPDIR" "$BACKUPDESTINATION"

