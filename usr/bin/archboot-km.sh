#!/usr/bin/env bash
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.km"
_TITLE="Arch Linux Console Font And Keymap Setting"
LIST_MAPS="localectl list-keymaps --no-pager"

abort()
{
    _dialog --yesno "Abort Console Font And Keymap Setting?" 6 42 || return 0
    [[ -e /tmp/.keymap ]] && rm -f /tmp/.keymap
    [[ -e /tmp/.font ]] && rm -f /tmp/.font
    [[ -e /tmp/.km-running ]] && rm /tmp/.km-running
    clear
    exit 1
}

abort_dialog() {
    if [[ "${_CANCEL}" = "1" ]]; then
        _S_NEXTITEM="1"
        return 1
    fi
}

# _dialog()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dialog() {
    dialog --backtitle "${_TITLE}" --aspect 15 "$@"
    return $?
}

do_vconsole() {
    _dialog --infobox "Setting console font ${_FONT} and keymap ${_KEYMAP} ..." 3 80
    echo KEYMAP="${_KEYMAP}" > /etc/vconsole.conf
    echo FONT="${_FONT}" >> /etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
    sleep 2
}

set_vconsole() {
    if grep -qw 'sun32' /etc/vconsole.conf; then
        _dialog --infobox "Detected big screen size, using 32 font size now ..." 3 60
        _FONT="latarcyrheb-sun32"
        sleep 2
    else
        _FONTS="latarcyrheb-sun16 Worldwide eurlatgr Europe"
        _CANCEL=
        #shellcheck disable=SC2086
        _dialog --menu "\n        Select Console Font:\n\n     Font Name          Region" 12 40 14 ${_FONTS} 2>${_ANSWER} || _CANCEL=1
        abort_dialog || return 1
        #shellcheck disable=SC2086
        _FONT=$(cat ${_ANSWER})
    fi
    echo "${_FONT}" > /tmp/.font
    # get list of 2 sign locale
    #  ${KEYMAP} | grep -v '...' | grep "^[a-z]"
    _KEYMAPS="us English de German es Spanish fr French pt Portuguese ru Russian OTHER More"
    OTHER__KEYMAPS="be Belarusian bg Bulgarian br Brazil ca Canada cz Czech dk Danish et Estonian fa Iran fi Finnish gr Greek hu Hungarian it Italian lt Lithuanian lv Latvian mk Macedonian nl Dutch no Norwegian pl Polish ro Romanian  sk Slovak sr Serbian sv Swedish uk Ukrainian"
    _CANCEL=""
    #shellcheck disable=SC2086
    _dialog --menu "Select A Keymap Region:" 14 30 8 ${_KEYMAPS} 2>${_ANSWER} || _CANCEL="1"
    _KEYMAP=$(cat ${_ANSWER})
    if [[ "${_KEYMAP}" == "OTHER" ]]; then
        #shellcheck disable=SC2086
        _dialog --menu "Select A Keymap Region:" 18 30 12 ${OTHER__KEYMAPS} 2>${_ANSWER} || _CANCEL="1"
        _KEYMAP=$(cat ${_ANSWER})
    fi
    abort_dialog || return 1
    _KEYMAPS=""
    for i in $(${LIST_MAPS} | grep "^${_KEYMAP}" | grep -v '^carpalx' | grep -v 'defkey' | grep -v 'mac' | grep -v 'amiga' | grep -v 'sun' | grep -v 'atari'); do
        _KEYMAPS="${_KEYMAPS} ${i} -"
    done
    _CANCEL=""
    #shellcheck disable=SC2086
    _dialog --menu "Select A Keymap Layout:" 14 30 8 ${_KEYMAPS} 2>${_ANSWER} || _CANCEL="1"
    abort_dialog || return 1
    #shellcheck disable=SC2086
    _KEYMAP=$(cat ${_ANSWER})
    echo "${_KEYMAP}" > /tmp/.keymap
    _S_NEXTITEM=2
}

mainmenu() {
    if [[ -n "${_S_NEXTITEM}" ]]; then
        _DEFAULT="--default-item ${_S_NEXTITEM}"
    else
        _DEFAULT=""
    fi
    #shellcheck disable=SC2086
    _dialog ${_DEFAULT} --backtitle "${_TITLE}" --title " MAIN MENU " \
                --menu "Use the UP and DOWN arrows to navigate menus.\nUse TAB to switch between buttons and ENTER to select." 10 58 12 \
        "1" "Set Console Font And Keymap" \
        "2" "${EXIT}" 2>${_ANSWER}
    #shellcheck disable=SC2086
    case $(cat ${_ANSWER}) in
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

if [[ "${1}" = "--setup" ]]; then
    if ! set_vconsole; then
        [[ -e /tmp/.km-running ]] && rm /tmp/.km-running
        clear
        exit 1
    fi
    [[ -e /tmp/.km-running ]] && rm /tmp/.km-running
    clear
    do_vconsole
    exit 0
else
    EXIT="Exit"
fi

while true; do
    mainmenu
done

clear
exit 0

# vim: set ts=4 sw=4 et:
