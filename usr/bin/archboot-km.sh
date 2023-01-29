#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.km"
_TITLE="Arch Linux Console Font And Keymap Setting"
_LIST_MAPS="localectl list-keymaps --no-pager"
# _dialog()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dialog() {
    dialog --backtitle "${_TITLE}" --aspect 15 "$@"
    return $?
}

_abort()
{
    _dialog --yesno "Abort Console Font And Keymap Setting?" 6 42 || return 0
    [[ -e /tmp/.keymap ]] && rm -f /tmp/.keymap
    [[ -e /tmp/.font ]] && rm -f /tmp/.font
    [[ -e /tmp/.km-running ]] && rm /tmp/.km-running
    clear
    exit 1
}

_abort_dialog() {
    if [[ "${_CANCEL}" = "1" ]]; then
        _S_NEXTITEM="1"
        return 1
    fi
}

_do_vconsole() {
    _dialog --infobox "Setting console font ${_FONT} and keymap ${_KEYMAP}..." 3 80
    echo KEYMAP="${_KEYMAP}" > /etc/vconsole.conf
    echo FONT="${_FONT}" >> /etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
    sleep 2
}

_set_vconsole() {
    if grep -qw 'FONT=*32*' /etc/vconsole.conf; then
        _FONTS="ter-v32n Worldwide latarcyrheb-sun32 Worldwide"
        _CANCEL=
        #shellcheck disable=SC2086
        _dialog --menu "\n        Select Console Font:\n\n     Font Name          Region" 13 40 15 ${_FONTS} 2>${_ANSWER} || _CANCEL=1
        _abort_dialog || return 1
        #shellcheck disable=SC2086
        _FONT=$(cat ${_ANSWER})
        sleep 2
    else
        _FONTS="ter-v16n Worldwide latarcyrheb-sun16 Worldwide eurlatgr Europe"
        _CANCEL=
        #shellcheck disable=SC2086
        _dialog --menu "\n        Select Console Font:\n\n     Font Name          Region" 13 40 15 ${_FONTS} 2>${_ANSWER} || _CANCEL=1
        _abort_dialog || return 1
        #shellcheck disable=SC2086
        _FONT=$(cat ${_ANSWER})
    fi
    echo "${_FONT}" > /tmp/.font
    # get list of 2 sign locale
    #  ${KEYMAP} | grep -v '...' | grep "^[a-z]"
    _KEYMAPS="us English de German es Spanish fr French pt Portuguese ru Russian OTHER More"
    _OTHER_KEYMAPS="be Belarusian bg Bulgarian br Brazil ca Canada cz Czech dk Danish et Estonian fa Iran fi Finnish gr Greek hu Hungarian it Italian lt Lithuanian lv Latvian mk Macedonian nl Dutch no Norwegian pl Polish ro Romanian  sk Slovak sr Serbian sv Swedish uk Ukrainian"
    _CANCEL=""
    #shellcheck disable=SC2086
    _dialog --menu "Select A Keymap Region:" 14 30 8 ${_KEYMAPS} 2>${_ANSWER} || _CANCEL="1"
    _KEYMAP=$(cat ${_ANSWER})
    if [[ "${_KEYMAP}" == "OTHER" ]]; then
        #shellcheck disable=SC2086
        _dialog --menu "Select A Keymap Region:" 18 30 12 ${_OTHER_KEYMAPS} 2>${_ANSWER} || _CANCEL="1"
        _KEYMAP=$(cat ${_ANSWER})
    fi
    _abort_dialog || return 1
    _KEYMAPS=""
    for i in $(${_LIST_MAPS} | grep "^${_KEYMAP}" | grep -v '^carpalx' | grep -v 'defkey' | grep -v 'mac' | grep -v 'amiga' | grep -v 'sun' | grep -v 'atari'); do
        _KEYMAPS="${_KEYMAPS} ${i} -"
    done
    _CANCEL=""
    #shellcheck disable=SC2086
    _dialog --menu "Select A Keymap Layout:" 14 30 8 ${_KEYMAPS} 2>${_ANSWER} || _CANCEL="1"
    _abort_dialog || return 1
    #shellcheck disable=SC2086
    _KEYMAP=$(cat ${_ANSWER})
    echo "${_KEYMAP}" > /tmp/.keymap
    _S_NEXTITEM=2
}

_mainmenu() {
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
            _set_vconsole || return 1
            _do_vconsole
            ;;
        "2")
            [[ -e /tmp/.km-running ]] && rm /tmp/.km-running
            clear
            exit 0 ;;
        *)
            _abort ;;
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
    if ! _set_vconsole; then
        [[ -e /tmp/.km-running ]] && rm /tmp/.km-running
        clear
        exit 1
    fi
    [[ -e /tmp/.km-running ]] && rm /tmp/.km-running
    clear
    _do_vconsole
    exit 0
else
    EXIT="Exit"
fi
while true; do
    _mainmenu
done
clear
exit 0
# vim: set ts=4 sw=4 et:
