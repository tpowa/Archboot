#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
set_title() {
    if [[ -e "${LOCAL_DB}" ]]; then
        TITLE="Arch Linux Installation (Local mode) --> wiki.archlinux.org/title/Archboot"
    else
        TITLE="Arch Linux Installation (Online mode) --> wiki.archlinux.org/title/Archboot"
    fi
}

# DIALOG()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
DIALOG() {
    dialog --backtitle "${TITLE}" --aspect 15 "$@"
    return $?
}

printk()
{
    case ${1} in
        "on")  echo 4 >/proc/sys/kernel/printk ;;
        "off") echo 0 >/proc/sys/kernel/printk ;;
    esac
}

getdest() {
    [[ "${DESTDIR}" ]] && return 0
    DIALOG --inputbox "Enter the destination directory where your target system is mounted" 8 65 "${DESTDIR}" 2>${ANSWER} || return 1
    DESTDIR=$(cat ${ANSWER})
}
