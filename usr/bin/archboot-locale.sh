#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.locale"
_RUNNING_ARCH="$(uname -m)"
_TITLE="Archboot ${_RUNNING_ARCH} | Arch Linux Setup | System Wide Locale Setting"
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
    [[ -e /tmp/.locale-running ]] && rm /tmp/.locale-running
    [[ -e /tmp/.locale ]] && rm /tmp/.locale
    clear
    exit 1
}

_do_locale() {
    _dialog --infobox "Setting System Wide Locale ${_LOCALE}.UTF-8..." 3 50
    echo "LANG=${_LOCALE}.UTF-8" > /etc/locale.conf
    echo "LANG=${_LOCALE}.UTF-8" > /tmp/.locale
    echo LC_COLLATE=C >> /etc/locale.conf
    localectl set-locale "${_LOCALE}.UTF-8" &>/dev/null
    sed -i -e "s:^[a-z]:#&:g" /etc/locale.gen
    sed -i -e "s:^#${_LOCALE}.UTF-8:${_LOCALE}.UTF-8:g" /etc/locale.gen
    locale-gen &>/dev/null
    sleep 2
}

_set_locale() {
    _LOCALE=""
    _LOCALES="en_US English de_DE German es_ES Spanish fr_FR French pt_PT Portuguese OTHER Other"
    _OTHER_LOCALES="be_BY Belarusian bg_BG Bulgarian cs_CZ Czech da_DK Dansk fi_FI Finnish el_GR Greek hu_HU Hungarian it_IT Italian lt_LT Lithuanian lv_LV Latvian mk_MK Macedonian nl_NL Dutch nn_NO Norwegian pl_PL Polish ro_RO Romanian  ru_RU Russian sk_SK Slovak sr_RS Serbian sv_SE Swedish uk_UA Ukrainian"
    _CANCEL=""
    #shellcheck disable=SC2086
    _dialog --menu "Select A System Wide Locale:" 13 35 6 ${_LOCALES} 2>${_ANSWER} || _abort
    _LOCALE=$(cat ${_ANSWER})
    if [[ "${_LOCALE}" == "OTHER" ]]; then
        #shellcheck disable=SC2086
        _dialog --menu "Select A System Wide Locale:" 18 35 12 ${_OTHER_LOCALES} 2>${_ANSWER} || _abort
        _LOCALE=$(cat ${_ANSWER})
    fi
}

if [[ -e /tmp/.locale-running ]]; then
    echo "System Wide Locale Setting already runs on a different console!"
    echo "Please remove /tmp/.locale-running first!"
    exit 1
fi 
: >/tmp/.locale-running
while [[ -z ${_LOCALE} ]]; do
    _set_locale
done
_do_locale
[[ -e /tmp/.locale-running ]] && rm /tmp/.locale-running
clear
exit 0
# vim: set ts=4 sw=4 et:
