#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
ANSWER="/tmp/.setup"
# use the first VT not dedicated to a running console
# don't use DESTDIR=/mnt because it's intended to mount other things there!
# check first if bootet in archboot
if grep -qw archboot /etc/hostname; then
    DESTDIR="/install"
else
    DESTDIR="/"
fi
if pgrep -x Xorg > /dev/null 2>&1; then
    LOG="/dev/tty8"
else
    LOG="/dev/tty7"
fi
VC_NUM="$(basename ${LOG} | sed -e 's#tty##g')"
VC="VC${VC_NUM}"
# install stages
S_SRC=0         # choose mirror
S_NET=0         # network configuration
S_MKFS=0        # formatting
S_MKFSAUTO=0    # auto fs part/formatting
S_CONFIG=0      # configuration editing
# menu item tracker- autoselect the next item
NEXTITEM=""
# To allow choice in script set EDITOR=""
EDITOR=""

set_title() {
    if [[ -e "${LOCAL_DB}" ]]; then
        TITLE="Archboot Arch Linux Installation (Local mode) --> https://bit.ly/archboot"
    else
        TITLE="Archboot Arch Linux Installation (Online mode) --> https://bit.ly/archboot"
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

# geteditor()
# prompts the user to choose an editor
# sets EDITOR global variable
geteditor() {
    if ! [[ "${EDITOR}" ]]; then
        DIALOG --menu "Select a Text Editor to Use" 10 35 3 \
        "1" "nano (easier)" \
        "2" "vi(m)" 2>${ANSWER} || return 1
        case $(cat ${ANSWER}) in
            "1") EDITOR="nano" ;;
            "2") if [[ -e /usr/bin/vim ]]; then
                        EDITOR="vim"
                    else
                        EDITOR="vi"
                    fi
                    ;;
        esac
    fi
}

