#!/usr/bin/env bash
# written by Tobias Powalowski <tpowa@archlinux.org>

ANSWER="/tmp/.km"
TITLE="Arch Linux Keymap And Console Font Setting"
BASEDIR="/usr/share/kbd"

if [[ "${1}" = "--setup" ]]; then
    EXIT="Return to Main Menu"
else
    EXIT="Exit"
fi

abort()
{
    DIALOG --yesno "Abort Keymap And Console Font Setting?" 6 42 || return 0
    [[ -e /tmp/.km ]] && rm -f /tmp/.km
    [[ -e /tmp/.keymap ]] && rm -f /tmp/.keymap
    [[ -e /tmp/.font ]] && rm -f /tmp/.font
        [[ -e /tmp/.km-running ]] && rm /tmp/.km-running
    clear
    exit 1
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

error_kmset()
{
    DIALOG --msgbox "An error occured, your current keymap was not changed." 0 0
}

dokeymap() {
    echo "Scanning for keymaps..."
    KEYMAPS=
    for i in $(localectl list-keymaps --no-pager); do
        KEYMAPS="${KEYMAPS} ${i} -"
    done
    CANCEL=""
    #shellcheck disable=SC2086
    DIALOG --menu "Select A Keymap:" 22 60 16 ${KEYMAPS} 2>${ANSWER} || CANCEL="1"
    if [[ "${CANCEL}" = "1" ]]; then
        S_NEXTITEM="1"
        return 1
    fi
    keymap=$(cat ${ANSWER})
    echo "${keymap}" > /tmp/.keymap
    if [[ "${keymap}" ]]; then
        DIALOG --infobox "Loading keymap: ${keymap}" 0 0
        localectl set-keymap "${keymap}" || error_kmset 
    fi
S_NEXTITEM=2
}

doconsolefont() {
    echo "Scanning for fonts..."
    FONTS=
    # skip .cp.gz and partialfonts files for now see bug #6112, #6111
    for i in $(find ${BASEDIR}/consolefonts -maxdepth 1 ! -name '*.cp.gz' -name "*.gz"  | sed 's|^.*/||g' | sort); do
        FONTS="${FONTS} ${i} -"
    done
    CANCEL=""
    #shellcheck disable=SC2086
    DIALOG --menu "Select A Console Font:" 22 60 16 ${FONTS} 2>${ANSWER} || CANCEL=1
    if [[ "${CANCEL}" = "1" ]]; then
        S_NEXTITEM="2"
        return 1
    fi
    font=$(cat ${ANSWER})
    echo "${font}" > /tmp/.font
    if [[ "${font}" ]]; then
        DIALOG --infobox "Loading font: ${font}" 0 0
        for i in $(seq 1 6); do
            setfont "${BASEDIR}/consolefonts/${font}" -C "/dev/tty${i}" > /dev/null 2>&1
        done
        # set serial console if used too!
        if tty | grep -q /dev/ttyS; then
            SERIAL="$(tty)"
            setfont "${BASEDIR}/consolefonts/${font}" -C "/dev/${SERIAL}" > /dev/null 2>&1
        fi
    fi
S_NEXTITEM=3
}

mainmenu() {
    if [[ -n "${S_NEXTITEM}" ]]; then
        DEFAULT="--default-item ${S_NEXTITEM}"
    else
        DEFAULT=""
    fi
    #shellcheck disable=SC2086
    DIALOG ${DEFAULT} --backtitle "${TITLE}" --title " MAIN MENU " \
                --menu "Use the UP and DOWN arrows to navigate menus.\nUse TAB to switch between buttons and ENTER to select." 11 58 13 \
        "1" "Set Keymap" \
        "2" "Set Consolefont" \
        "3" "${EXIT}" 2>${ANSWER}
    case $(cat ${ANSWER}) in
        "1")
            dokeymap
            ;;
        "2")
            doconsolefont
            ;;
        "3")
            [[ -e /tmp/.km-running ]] && rm /tmp/.km-running
            clear
            exit 0 ;;
        *)
            abort ;;
    esac
}

: >/tmp/.keymap
: >/tmp/.font
: >/tmp/.km

if [[ ! -d ${BASEDIR}/keymaps ]]; then
    echo "Cannot load keymaps, as none were found in ${BASEDIR}/keymaps" >&2
    exit 1
fi

if [[ ! -d ${BASEDIR}/consolefonts ]]; then
    echo "Cannot load consolefonts, as none were found in ${BASEDIR}/consolefonts" >&2
fi

if [[ ! $(which loadkeys) ]]; then
    echo "'loadkeys' binary not found!" >&2
    exit 1
fi


if [[ ! $(which setfont) ]]; then
    echo "'setfont' binary not found!" >&2
    exit 1
fi

if [[ -e /tmp/.km-running ]]; then
    echo "km already runs on a different console!"
    echo "Please remove /tmp/.km-running first to launch tz!"
    exit 1
fi 
: >/tmp/.km-running

while true; do
    mainmenu
done

clear
exit 0

# vim: set ts=4 sw=4 et:
