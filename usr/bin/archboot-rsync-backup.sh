#!/usr/bin/env bash
# 
#    copy-mointpoint.sh - copy recursivly a mountpoint using tar
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
_APPNAME=$(basename "${0}")
_usage()
{
    echo -e "\e[1mWelcome to \e[36mARCHBOOT\e[0m\e[1m - RSYNC BACKUP:\e[0m"
    echo -e "\e[1m-----------------------------------\e[0m"
    echo -e "- Copy \e[1mbackupdir\e[0m to \e[1mbackupdestination\e[0m using rsync."
    echo -e "- For system backup, start with \e[1mfull\e[0m mounted system and then invoke this script"
    echo -e "  with system's root directory as \e[1mbackupdir\e[0m."
    echo -e "- \e[1mexcluded\e[0m directories are \e[1m/dev /tmp /proc /sys /run /mnt /media /lost+found\e[0m"
    echo -e "- \e[1m--numeric-ids\e[0m option is invoked to \e[1mpreserve\e[0m users"
    echo ""
    echo -e "usage: \e[1m${_APPNAME} <backupdir> <backupdestination>\e[0m"
    exit "$1"
}
##################################################
if [ $# -ne 2 ]; then
    _usage 1
fi
_BACKUPDESTINATION="${2}"
_BACKUPDIR="${1}"
rsync -aAXv --numeric-ids \
--exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
"${_BACKUPDIR}" "${_BACKUPDESTINATION}"

