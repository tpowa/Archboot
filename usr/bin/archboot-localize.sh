#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# written by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/basic-common.sh
_TITLE="Archboot ${_RUNNING_ARCH} | Basic Setup | Localization"

_locale_menu() {
    _LOCALE=""
    while [[ -z "${_LOCALE}" ]]; do
        _LOCALE=""
        _LOCALES="en_US English de_DE German es_ES Spanish fr_FR French pt_PT Portuguese OTHER Other"
        _OTHER_LOCALES="be_BY Belarusian bg_BG Bulgarian cs_CZ Czech da_DK Dansk fi_FI Finnish el_GR Greek hu_HU Hungarian it_IT Italian lt_LT Lithuanian lv_LV Latvian mk_MK Macedonian nl_NL Dutch nn_NO Norwegian pl_PL Polish ro_RO Romanian  ru_RU Russian sk_SK Slovak sr_RS Serbian sv_SE Swedish uk_UA Ukrainian"
        _CANCEL=""
        #shellcheck disable=SC2086
        _dialog --cancel-label "Exit" --title " Locale " --menu "" 12 35 5 ${_LOCALES} 2>${_ANSWER} || _abort
        _LOCALE=$(cat "${_ANSWER}")
        if [[ "${_LOCALE}" == "OTHER" ]]; then
            #shellcheck disable=SC2086
            if _dialog --cancel-label "Back" --title " Other Locale " --menu "" 17 35 11 ${_OTHER_LOCALES} 2>${_ANSWER}; then
                _LOCALE=$(cat ${_ANSWER})
            else
                _LOCALE=""
            fi
        fi
    done
}

_vconsole_keymap() {
    _LIST_MAPS="localectl list-keymaps --no-pager"
    _KEYMAPS="us de es fr pt be bg br ca cz dk et fi gr hu it l lv mk nl no pl ro ru sk sr sv uk"
    _LOW_LOCALE="$(echo "${_LOCALE}" | tr "[:upper:]" "[:lower:]")"
    _KEYMAP=""
    for i in ${_KEYMAPS}; do
        echo "${_LOW_LOCALE}" | grep -q "${i}" && _KEYMAP="${i}"
        [[ -n ${_KEYMAP} ]] && break
    done
    _KEYMAPS=""
    for i in $(${_LIST_MAPS} | grep "^${_KEYMAP}" | grep -v 'olpc' | grep -v 'mobii' | grep -v 'alt' |\
                               grep -v '^carpalx' | grep -v 'defkey' | grep -v 'mac' | grep -v 'amiga' |\
                               grep -v 'sun' | grep -v 'atari'); do
        _KEYMAPS="${_KEYMAPS} ${i} -"
    done
    #shellcheck disable=SC2086
    if _dialog --cancel-label "Back" --title " Keymap Layout " --menu "" 13 40 7 ${_KEYMAPS} 2>${_ANSWER}; then
        #shellcheck disable=SC2086
        _KEYMAP=$(cat ${_ANSWER})
    else
        _LOCALE=""
    fi
}

_vconsole() {
    # Terminus font size detection
    if grep -q '^FONT=.*32' /etc/vconsole.conf; then
        _FONT="ter-v32n"
    else
        _FONT="ter-v16n"
    fi
    echo KEYMAP="${_KEYMAP}" > /etc/vconsole.conf
    echo FONT="${_FONT}" >> /etc/vconsole.conf
    systemctl restart systemd-vconsole-setup
    rm /.archboot
}

_locale() {
    echo "LANG=${_LOCALE}.UTF-8" > /etc/locale.conf
    echo "LANG=${_LOCALE}.UTF-8" > /.localize
    echo LC_COLLATE=C >> /etc/locale.conf
    localectl set-locale "${_LOCALE}.UTF-8" &>"${_NO_LOG}"
    sed -i -e "s:^[a-z]:#&:g" /etc/locale.gen
    sed -i -e "s:^#${_LOCALE}.UTF-8:${_LOCALE}.UTF-8:g" /etc/locale.gen
    locale-gen &>"${_NO_LOG}"
    rm /.archboot
}

_run() {
    : >/.archboot
    _locale &
    _progress_wait "0" "66" "Setting locale to ${_LOCALE}.UTF-8..." "0.1"
    : >/.archboot
    _vconsole &
    _progress_wait "67" "99" "Setting keymap to ${_KEYMAP}..." "0.1"
    _progress "100" "Localization completed successfully."
    sleep 2
}

_localize() {
    _run | _dialog --title " Localization " --no-mouse --gauge "Setting locale to ${_LOCALE}.UTF-8..." 6 50 0
}

_check
while [[ -z "${_LOCALE}" ]]; do
    _locale_menu
    _vconsole_keymap
done
_localize
_cleanup
# vim: set ts=4 sw=4 et:
