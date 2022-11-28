#!/usr/bin/env bash
# written by Tobias Powalowski <tpowa@archlinux.org>

ANSWER="/tmp/.km"
TITLE="Arch Linux Console Font And Keymap Setting"
LIST_MAPS="localectl list-keymaps --no-pager"
if [[ "${1}" = "--setup" ]]; then
    EXIT="Return to Main Menu"
else
    EXIT="Exit"
fi

abort()
{
    DIALOG --yesno "Abort Console Font And Keymap Setting?" 6 42 || return 0
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
    DIALOG --infobox "Setting console font ${font} and keymap ${keymap} ..." 3 60
    echo KEYMAP=${keymap} > /etc/vconsole.conf
    echo FONT=${font} >> /etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
    sleep 1
}

set_vconsole() {
    # check for fb size
    FB_SIZE="$(dmesg | grep "[0-9][0-9][0-9][0-9]x" | cut -d 'x' -f 1 | sed -e 's#.* ##g')"
    if [[ "${FB_SIZE}" -gt '2000' ]]; then
        SIZE="32"
    else
        SIZE="16"
    fi
    #shellcheck disable=SC2086
    if [[ "${SIZE}" == "32" ]]; then
        DIALOG --infobox "Detected big screen size, using 32 font size now ..." 3 50
        font="latarcyrheb-sun32"
        sleep 2
    fi
    if [[ "${SIZE}" == "16" ]]; then
        FONTS="latarcyrheb-sun16 Worldwide eurlatgr Europe"
        CANCEL=
        #shellcheck disable=SC2086
        DIALOG --menu "\n        Select Console Font:\n\n     Font Name          Region" 12 40 14 ${FONTS} 2>${ANSWER} || CANCEL=1
        abort_dialog || return 1
        #shellcheck disable=SC2086
        font=$(cat ${ANSWER})
    fi
    echo "${font}" > /tmp/.font
    # get list of 2 sign locale
    #  ${KEYMAP} | grep -v '...' | grep "^[a-z]"
    KEYMAPS="us English de German es Spanish fr French pt Portuguese ru Russian OTHER More"
    OTHER_KEYMAPS="be Belarusian bg Bulgarian br Brazil ca Canada cz Czech dk Danish et Estonian fa Iran fi Finnish gr Greek hu Hungarian it Itaiian lt Lithuanian lv Latvian mk Macedonian nl Dutch no Norwegian pl Polish ro Romanian  sk Slovak sr Serbian sv Swedish uk Ukrainian"
    CANCEL=""
    #shellcheck disable=SC2086
    DIALOG --menu "Select A Keymap Region:" 14 30 8 ${KEYMAPS} 2>${ANSWER} || CANCEL="1"
    keymap=$(cat ${ANSWER})
    if [[ "${keymap}" == "OTHER" ]]; then
        #shellcheck disable=SC2086
        DIALOG --menu "Select A Keymap Region:" 18 30 12 ${OTHER_KEYMAPS} 2>${ANSWER} || CANCEL="1"
        keymap=$(cat ${ANSWER})
    fi
    abort_dialog || return 1
    KEYMAPS=""
    for i in $(${LIST_MAPS} | grep -w "^${keymap}" | grep -v 'mac' | grep -v 'amiga' | grep -v 'sun' | grep -v 'atari'); do
        KEYMAPS="${KEYMAPS} ${i} -"
    done
    CANCEL=""
    #shellcheck disable=SC2086
    DIALOG --menu "Select A Keymap Layout:" 14 30 8 ${KEYMAPS} 2>${ANSWER} || CANCEL="1"
    abort_dialog || return 1
    #shellcheck disable=SC2086
    keymap=$(cat ${ANSWER})
    echo "${keymap}" > /tmp/.keymap
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
        "1" "Set Console Font And Keymap" \
        "2" "${EXIT}" 2>${ANSWER}
    #shellcheck disable=SC2086
    case $(cat ${ANSWER}) in
        "1")
            set_vconsole || return 1
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
