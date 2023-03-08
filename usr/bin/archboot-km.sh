#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.km"
_TITLE="Archboot Arch Linux --> Console Font And Keymap Setting"
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

_do_vconsole() {
    _dialog --infobox "Setting console font ${_FONT} and keymap ${_KEYMAP}..." 3 80
    echo KEYMAP="${_KEYMAP}" > /etc/vconsole.conf
    echo FONT="${_FONT}" >> /etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
    sleep 2
}

_set_vconsole() {
    if grep -q '^FONT=.*32' /etc/vconsole.conf; then
        _FONTS="ter-v32n Worldwide latarcyrheb-sun32 Worldwide"
    else
        _FONTS="ter-v16n Worldwide latarcyrheb-sun16 Worldwide eurlatgr Europe"
    fi
    #shellcheck disable=SC2086
    _dialog --menu "        Select Console Font:\n\n     Font Name          Region" 12 40 14 ${_FONTS} 2>${_ANSWER} || return 1
    #shellcheck disable=SC2086
    _FONT=$(cat ${_ANSWER})
    # get list of 2 sign locale
    #  ${KEYMAP} | grep -v '...' | grep "^[a-z]"
    _KEYMAPS="us English de German es Spanish fr French pt Portuguese OTHER More"
    _OTHER_KEYMAPS="be Belarusian bg Bulgarian br Brazil ca Canada cz Czech dk Dansk et Estonian fi Finnish gr Greek hu Hungarian it Italian lt Lithuanian lv Latvian mk Macedonian nl Dutch no Norwegian pl Polish ro Romanian ru Russian sk Slovak sr Serbian sv Swedish uk Ukrainian"
    #shellcheck disable=SC2086
    _dialog --menu "Select A Keymap Region:" 13 40 7 ${_KEYMAPS} 2>${_ANSWER} || return 1
    _KEYMAP=$(cat ${_ANSWER})
    if [[ "${_KEYMAP}" == "OTHER" ]]; then
        #shellcheck disable=SC2086
        _dialog --menu "Select A Keymap Region:" 18 40 12 ${_OTHER_KEYMAPS} 2>${_ANSWER} || return 1
        _KEYMAP=$(cat ${_ANSWER})
    fi
    _KEYMAPS=""
    for i in $(${_LIST_MAPS} | grep "^${_KEYMAP}" | grep -v '^carpalx' | grep -v 'defkey' | grep -v 'mac' | grep -v 'amiga' | grep -v 'sun' | grep -v 'atari'); do
        _KEYMAPS="${_KEYMAPS} ${i} -"
    done
    #shellcheck disable=SC2086
    _dialog --menu "Select A Keymap Layout:" 14 40 8 ${_KEYMAPS} 2>${_ANSWER} || return 1
    #shellcheck disable=SC2086
    _KEYMAP=$(cat ${_ANSWER})
}

if [[ -e /tmp/.km-running ]]; then
    echo "km already runs on a different console!"
    echo "Please remove /tmp/.km-running first to launch tz!"
    exit 1
fi 
: >/tmp/.km-running
if ! _set_vconsole; then
    [[ -e /tmp/.km ]] && rm /tmp/.km
    [[ -e /tmp/.km-running ]] && rm /tmp/.km-running
    clear
    exit 1
fi
[[ -e /tmp/.km-running ]] && rm /tmp/.km-running
_do_vconsole
clear
exit 0
# vim: set ts=4 sw=4 et:
