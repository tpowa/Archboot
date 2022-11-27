#!/usr/bin/env bash
# written by Tobias Powalowski <tpowa@archlinux.org>

ANSWER="/tmp/.km"
TITLE="Arch Linux Keymap And Console Font Setting"
BASEDIR="/usr/share/kbd"
KEYMAP="localectl list-keymaps --no-pager"
if [[ "${1}" = "--setup" ]]; then
    EXIT="Return to Main Menu"
else
    EXIT="Exit"
fi

abort()
{
    DIALOG --yesno "Abort Keymap And Console Font Setting?" 6 42 || return 0
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
    KEYMAPS=""
    # get list of 2 sign locale
    #  ${KEYMAP} | grep -v '...' | grep "^[a-z]"
    KEYMAP_LIST="be bg br ca cf cz de dk en es et fa fi fr gr hu ie il is it la lt lv mk nl no pl pt ro ru se sg sk sr sv ua uk us"
    for i in ${KEYMAP_LIST}; do
        KEYMAPS="${KEYMAPS} ${i} -"
    done
    CANCEL=""
    #shellcheck disable=SC2086
    DIALOG --menu "Select A Keymap Region:" 22 30 16 ${KEYMAPS} 2>${ANSWER} || CANCEL="1"
    if [[ "${CANCEL}" = "1" ]]; then
        S_NEXTITEM="1"
        return 1
    fi
    ANSWER=$(cat ${ANSWER})
    KEYMAPS=""
    for i in $(${KEYMAP} | grep -w "${ANSWER}"); do
        KEYMAPS="${KEYMAPS} ${i} -"
    done
    #shellcheck disable=SC2086
    DIALOG --menu "Select A Keymap Layout:" 16 40 12 ${KEYMAPS} 2>${ANSWER} || CANCEL="1"
    if [[ "${CANCEL}" = "1" ]]; then
        S_NEXTITEM="1"
        return 1
    fi
    #shellcheck disable=SC2086
    keymap=$(cat ${ANSWER})
    echo "${keymap}" > /tmp/.keymap
    if [[ "${keymap}" ]]; then
        DIALOG --infobox "Loading keymap: ${keymap}" 0 0
        localectl set-keymap "${keymap}" || error_kmset
        echo "${keymap}" > /tmp/.keymap
    fi
S_NEXTITEM=2
}

doconsolefont() {
    # check for fb size
    FB_SIZE="$(dmesg | grep "x[0-9][0-9][0-9]x" | cut -d 'x' -f 1 | sed -e 's#.* ##g')"
    if [[ "${FB_SIZE}" -gt '2000' ]]; then
        SIZE="32"
    else
        SIZE="16"
    fi
    #shellcheck disable=SC2086
    if [[ "${SIZE}" == "32" ]]; then
        font="latarcyrheb-sun32"
    fi
    if [[ "${SIZE}" == "16" ]]; then
        FONTS="eurlatgr - latarcyrheb-sun16 -"
        CANCEL=
        #shellcheck disable=SC2086
        DIALOG --menu "Select A Console Font:" 5 40 8 ${FONTS} 2>${ANSWER} || CANCEL=1
        if [[ "${CANCEL}" = "1" ]]; then
            S_NEXTITEM="2"
            return 1
        fi
        #shellcheck disable=SC2086
        font=$(cat ${ANSWER})
    fi
    echo "${font}" > /tmp/.font
    DIALOG --infobox "Loading font: ${font}" 0 0
    for i in $(seq 1 6); do
        setfont "${BASEDIR}/consolefonts/${font}".psfu.gz -C "/dev/tty${i}" > /dev/null 2>&1
    done
    # set serial console if used too!
    if tty | grep -q /dev/ttyS; then
        SERIAL="$(tty)"
        setfont "${BASEDIR}/consolefonts/${font}".psfu.gz -C "/dev/${SERIAL}" > /dev/null 2>&1
    fi
    echo "${font}" > /tmp/.font
    sleep 3
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
    #shellcheck disable=SC2086
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

if [[ ! -d ${BASEDIR}/keymaps ]]; then
    echo "Cannot load keymaps, as none were found in ${BASEDIR}/keymaps" >&2
    exit 1
fi

if [[ ! -d ${BASEDIR}/consolefonts ]]; then
    echo "Cannot load consolefonts, as none were found in ${BASEDIR}/consolefonts" >&2
fi

if [[ ! $(which localectl) ]]; then
    echo "'localectl' binary not found!" >&2
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
