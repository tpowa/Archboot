#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/basic-common.sh
_TITLE="Archboot ${_RUNNING_ARCH} | Basic Setup | Localization"

_localize_menu() {
    _LOCALE=""
    _LOCALES="en_US English de_DE German es_ES Spanish fr_FR French pt_PT Portuguese OTHER Other"
    _OTHER_LOCALES="be_BY Belarusian bg_BG Bulgarian cs_CZ Czech da_DK Dansk fi_FI Finnish el_GR Greek hu_HU Hungarian it_IT Italian lt_LT Lithuanian lv_LV Latvian mk_MK Macedonian nl_NL Dutch nn_NO Norwegian pl_PL Polish ro_RO Romanian  ru_RU Russian sk_SK Slovak sr_RS Serbian sv_SE Swedish uk_UA Ukrainian"
    _CANCEL=""
    #shellcheck disable=SC2086
    _dialog --cancel-label "Exit" --title " Locale Menu " --menu "" 12 35 5 ${_LOCALES} 2>${_ANSWER} || _abort
    _LOCALE=$(cat ${_ANSWER})
    if [[ "${_LOCALE}" == "OTHER" ]]; then
        #shellcheck disable=SC2086
        if _dialog --cancel-label "Back" --title " Other Locale Menu " --menu "" 17 35 11 ${_OTHER_LOCALES} 2>${_ANSWER}; then
            _LOCALE=$(cat ${_ANSWER})
        else
            _LOCALE=""
        fi
    fi
}

_localize() {
    _dialog --infobox "Localization set to ${_LOCALE}.UTF-8..." 3 50
    echo "LANG=${_LOCALE}.UTF-8" > /etc/locale.conf
    echo "LANG=${_LOCALE}.UTF-8" > /tmp/.localize
    echo LC_COLLATE=C >> /etc/locale.conf
    localectl set-locale "${_LOCALE}.UTF-8" &>/dev/null
    sed -i -e "s:^[a-z]:#&:g" /etc/locale.gen
    sed -i -e "s:^#${_LOCALE}.UTF-8:${_LOCALE}.UTF-8:g" /etc/locale.gen
    locale-gen &>/dev/null
    sleep 3
    _dialog --infobox "Localization completed successfully." 3 40
    sleep 3
}

if [[ -e /tmp/.localize-running ]]; then
    echo "localize already runs on a different console!"
    echo "Please remove /tmp/.localize-running first!"
    exit 1
fi 
: >/tmp/.localize-running
while [[ -z ${_LOCALE} ]]; do
    _localize_menu
done
_localize
[[ -e /tmp/.localize-running ]] && rm /tmp/.localize-running
clear
exit 0
# vim: set ts=4 sw=4 et:
