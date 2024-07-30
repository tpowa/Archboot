#!/usr/bin/env bash
# 
#    copy-mointpoint.sh - copy recursivly a mountpoint using tar
#    by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
. /usr/lib/archboot/common.sh
_usage()
{
    echo -e "\e[1mWelcome to \e[36mARCHBOOT\e[m\e[1m - RSYNC BACKUP:\e[m"
    echo -e "\e[1m-----------------------------------\e[m"
    echo -e "- Copy \e[1mbackupdir\e[m to \e[1mbackupdestination\e[m using rsync."
    echo -e "- For system backup, start with \e[1mfull\e[m mounted system and then invoke this script"
    echo -e "  with system's root directory as \e[1mbackupdir\e[m."
    echo -e "- \e[1mexcluded\e[m directories are \e[1m/dev /tmp /proc /sys /run /mnt /media /lost+found\e[m"
    echo -e "  \e[1mexcluded\e[m \e[1m/sysroot /var/run /var/lib/systemd\e[m"
    echo -e "- \e[1m--numeric-ids\e[m option is invoked to \e[1mpreserve\e[m users"
    echo ""
    echo -e "usage: \e[1m${_BASENAME} <backupdir> <backupdestination>\e[m"
    exit 0
}
##################################################
if [ $# -ne 2 ]; then
    _usage
fi
_BACKUPDESTINATION="${2}"
_BACKUPDIR="${1}"
rsync -aAXv --numeric-ids \
--exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/sysroot/*"} \
"${_BACKUPDIR}" "${_BACKUPDESTINATION}"

