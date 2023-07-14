#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.localize"
_RUNNING_ARCH="$(uname -m)"
_TITLE="Archboot ${_RUNNING_ARCH} | Arch Linux Setup | Locale Configuration"
# _dialog()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dialog() {
    dialog --backtitle "${_TITLE}" --aspect 15 "$@"
    return $?
}

_abort() {
    _dialog --yesno "Abort Arch Linux System Wide Locale Setting?" 5 60 || return 0
    [[ -e /tmp/.localize-running ]] && rm /tmp/.localize-running
    [[ -e /tmp/.localize ]] && rm /tmp/.localize
    clear
    exit 1
}

_localize_menu() {
    _LOCALE=""
    _LOCALES="en_US English de_DE German es_ES Spanish fr_FR French pt_PT Portuguese OTHER Other"
    _OTHER_LOCALES="be_BY Belarusian bg_BG Bulgarian cs_CZ Czech da_DK Dansk fi_FI Finnish el_GR Greek hu_HU Hungarian it_IT Italian lt_LT Lithuanian lv_LV Latvian mk_MK Macedonian nl_NL Dutch nn_NO Norwegian pl_PL Polish ro_RO Romanian  ru_RU Russian sk_SK Slovak sr_RS Serbian sv_SE Swedish uk_UA Ukrainian"
    _CANCEL=""
    #shellcheck disable=SC2086
    _dialog --title " Locale Menu " --menu "" 12 35 5 ${_LOCALES} 2>${_ANSWER} || _abort
    _LOCALE=$(cat ${_ANSWER})
    if [[ "${_LOCALE}" == "OTHER" ]]; then
        #shellcheck disable=SC2086
        _dialog --title " Other Locale Menu " --menu "" 17 35 11 ${_OTHER_LOCALES} 2>${_ANSWER} || _abort
        _LOCALE=$(cat ${_ANSWER})
    fi
}

_localize() {
    _dialog --infobox "Locale configuration set to ${_LOCALE}.UTF-8..." 3 50
    echo "LANG=${_LOCALE}.UTF-8" > /etc/localize.conf
    echo "LANG=${_LOCALE}.UTF-8" > /tmp/.localize
    echo LC_COLLATE=C >> /etc/localize.conf
    localizectl set-localize "${_LOCALE}.UTF-8" &>/dev/null
    sed -i -e "s:^[a-z]:#&:g" /etc/localize.gen
    sed -i -e "s:^#${_LOCALE}.UTF-8:${_LOCALE}.UTF-8:g" /etc/localize.gen
    localize-gen &>/dev/null
    sleep 2
}

if [[ -e /tmp/.localize-running ]]; then
    echo "Locale configuration already runs on a different console!"
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