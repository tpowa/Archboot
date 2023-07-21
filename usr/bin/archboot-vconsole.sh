#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/basic-common.sh
_TITLE="Archboot ${_RUNNING_ARCH} | Basic Setup | Vconsole Configuration"
_LIST_MAPS="localectl list-keymaps --no-pager"

_vconsole() {
    _dialog --infobox "Setting vconsole font ${_FONT} and keymap ${_KEYMAP}..." 3 80
    echo KEYMAP="${_KEYMAP}" > /etc/vconsole.conf
    echo FONT="${_FONT}" >> /etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
    sleep 3
    _dialog --infobox "Vconsole configuration completed successfully." 3 50
    sleep 3
    return 0
}

_vconsole_font() {
    _CONTINUE=""
    while [[ -z "${_CONTINUE}" ]]; do
        if grep -q '^FONT=.*32' /etc/vconsole.conf; then
            _FONTS="ter-v32n Worldwide latarcyrheb-sun32 'Default Font'"
        else
            _FONTS='ter-v16n "Default Font" latarcyrheb-sun16 Worldwide eurlatgr Europe'
        fi
        #shellcheck disable=SC2086
        if _dialog --cancel-label "${_LABEL}" --title " Vconsole Font " --menu "" 9 40 3 ${_FONTS} 2>${_ANSWER}; then
            #shellcheck disable=SC2086
            _FONT=$(cat ${_ANSWER})
            _CONTINUE=1
        else
            _abort
        fi
    done
}

_vconsole_keymap() {
    _CONTINUE=""
    while [[ -z "${_CONTINUE}" ]]; do
        # get list of 2 sign locale
        #  ${KEYMAP} | grep -v '...' | grep "^[a-z]"
        _KEYMAPS="us English de German es Spanish fr French pt Portuguese OTHER More"
        _OTHER_KEYMAPS="be Belarusian bg Bulgarian br Brazil ca Canada cz Czech dk Dansk et Estonian fi Finnish gr Greek hu Hungarian it Italian lt Lithuanian lv Latvian mk Macedonian nl Dutch no Norwegian pl Polish ro Romanian ru Russian sk Slovak sr Serbian sv Swedish uk Ukrainian"
        #shellcheck disable=SC2086
        if _dialog --no-cancel --title " Keymap Region " --menu "" 12 40 6 ${_KEYMAPS} 2>${_ANSWER}; then
            _KEYMAP=$(cat ${_ANSWER})
            _CONTINUE="1"
            if [[ "${_KEYMAP}" == "OTHER" ]]; then
                _CONTINUE=""
                #shellcheck disable=SC2086
                if _dialog --cancel-label "Back" --title " Keymap Region " --menu "" 17 40 11 ${_OTHER_KEYMAPS} 2>${_ANSWER}; then
                    _KEYMAP=$(cat ${_ANSWER})
                    _CONTINUE=1
                fi
            fi
        else
            _abort
        fi
        if [[ -n "${_CONTINUE}" ]]; then
            _KEYMAPS=""
            for i in $(${_LIST_MAPS} | grep "^${_KEYMAP}" | grep -v 'olpc' | grep -v 'mobii' | grep -v 'alt' | grep -v '^carpalx' | grep -v 'defkey' | grep -v 'mac' | grep -v 'amiga' | grep -v 'sun' | grep -v 'atari'); do
                _KEYMAPS="${_KEYMAPS} ${i} -"
            done
            #shellcheck disable=SC2086
            if _dialog --cancel-label "Back" --title " Keymap Layout " --menu "" 13 40 7 ${_KEYMAPS} 2>${_ANSWER}; then
                #shellcheck disable=SC2086
                _KEYMAP=$(cat ${_ANSWER})
                _CONTINUE=1
            else
                _CONTINUE=""
            fi
        fi
    done
}

_check
while true; do
    _vconsole_font
    _vconsole_keymap
    _vconsole && break
done
_cleanup
# vim: set ts=4 sw=4 et:
