#!/usr/bin/env bash
# written by Tobias Powalowski <tpowa@archlinux.org>

ANSWER="/tmp/.km"
TITLE="Arch Linux Keymap And Console Font Setting"
LIST_MAPS="localectl list-keymaps --no-pager"
VCONSOLE="/usr/lib/systemd/systemd-vconsole-setup"
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

abort_dialog() {
    if [[ "${CANCEL}" = "1" ]]; then
        S_NEXTITEM="1"
        return 1
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

do_vconsole() {
    DIALOG --infobox "Loading keymap ${keymap} and console font ${font} ..." 3 60
    echo KEYMAP=${keymap} > /etc/vconsole.conf
    echo FONT=${font} >> /etc/vconsole.conf
    ${VCONSOLE}
    sleep 1
}

set_vconsole() {
    KEYMAPS=""
    # get list of 2 sign locale
    #  ${KEYMAP} | grep -v '...' | grep "^[a-z]"
    KEYMAPS="be Belarusian bg Bulgarian br Brazil ca Canada cz Czech de German dk Danish en English es Spanish  et Estonian fa Iran fi Finnish fr French gr Greek hu Hungarian it Itaiian lt Lithuanian lv Latvian mk Macedonian nl Dutch no Norwegian pl Polish pt Portuguese ro Romanian ru Russian sk Slovak sr Serbian sv Swedish uk Ukrainian us USA"
    CANCEL=""
    #shellcheck disable=SC2086
    DIALOG --menu "Select A Keymap Region:" 22 30 16 ${KEYMAPS} 2>${ANSWER} || CANCEL="1"
    abort_dialog
    ANSWER=$(cat ${ANSWER})
    KEYMAPS=""
    for i in $(${LIST_MAPS} | grep -w "${ANSWER}" | grep -v 'mac' | grep -v 'amiga' | grep -v 'sun' | grep -v 'atari'); do
        KEYMAPS="${KEYMAPS} ${i} -"
    done
    CANCEL=""
    #shellcheck disable=SC2086
    DIALOG --menu "Select A Keymap Layout:" 18 40 12 ${KEYMAPS} 2>${ANSWER} || CANCEL="1"
    abort_dialog
    #shellcheck disable=SC2086
    keymap=$(cat ${ANSWER})
    echo "${keymap}" > /tmp/.keymap
    # check for fb size
    FB_SIZE="$(dmesg | grep "x[0-9][0-9][0-9]x" | cut -d 'x' -f 1 | sed -e 's#.* ##g')"
    if [[ "${FB_SIZE}" -gt '2000' ]]; then
        SIZE="32"
    else
        SIZE="16"
    fi
    #shellcheck disable=SC2086
    if [[ "${SIZE}" == "32" ]]; then
        DIALOG --infobox "Detected big screen using size 32 font now ..." 3 50
        font="latarcyrheb-sun32"
        sleep 1
    fi
    if [[ "${SIZE}" == "16" ]]; then
        DIALOG --infobox "Detected normal screen using size 16 fonts..." 3 50
        FONTS="eurlatgr Europe latarcyrheb-sun16 Worldwide"
        sleep 1
        CANCEL=
        #shellcheck disable=SC2086
        DIALOG --menu "\n        Select Console Font:\n\n     Font Name          Region" 12 40 14 ${FONTS} 2>${ANSWER} || CANCEL=1
        if [[ "${CANCEL}" = "1" ]]; then
            S_NEXTITEM="1"
            return 1
        fi
        #shellcheck disable=SC2086
        font=$(cat ${ANSWER})
    fi
    echo "${font}" > /tmp/.font
    S_NEXTITEM=2
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
        "1" "Set Keymap And Set Consolefont"
        "2" "${EXIT}" 2>${ANSWER}
    #shellcheck disable=SC2086
    case $(cat ${ANSWER}) in
        "1")
            set_vconsole
            do_vconsole
            ;;
        "2")
            [[ -e /tmp/.km-running ]] && rm /tmp/.km-running
            clear
            exit 0 ;;
        *)
            abort ;;
    esac
}

: >/tmp/.keymap
: >/tmp/.font

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
