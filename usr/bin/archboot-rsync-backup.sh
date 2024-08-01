#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# rsync-backup.sh - copy files recursivly with rsync
# by Tobias Powalowski <tpowa@archlinux.org>
# usage(exitvalue)
# outputs a usage message and exits with value
. /usr/lib/archboot/common.sh
_usage()
{
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Rsync Backup\e[m"
    echo -e "\e[1m-----------------------\e[m"
    echo -e "- Copy \e[1m<backupdir>\e[m to \e[1m<backupdestination>\e[m using rsync."
    echo -e "- For system backup, start with \e[1mfull\e[m mounted system and then"
    echo -e "  invoke this script with system's root directory as \e[1mbackupdir\e[m."
    echo -e "- \e[1mExcluded\e[m directories are: \e[1m/dev /lost+found /mnt /media /proc /run /sys\e[m"
    echo -e "                            \e[1m/sysroot /tmp /var/lib/systemd /var/run\e[m"
    echo -e "- \e[1mUsers\e[m are \e[1mpreserved\e[m as numeric-ids"
    echo ""
    echo -e "Usage: \e[1m${_BASENAME} <backupdir> <backupdestination>\e[m"
    exit 0
}
##################################################
if [ $# -ne 2 ]; then
    _usage
fi
_BACKUPDESTINATION="${2}"
_BACKUPDIR="${1}"
rsync -aAXv --numeric-ids \
--exclude={"/dev/*","/lost+found","/media/*","/mnt/*","/proc/*","/run/*","/sys/*","/sysroot/*","/tmp/*","/var/lib/systemd/*","/var/run/*"} \
"${_BACKUPDIR}" "${_BACKUPDESTINATION}"

