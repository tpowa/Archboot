#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.locale"
_TITLE="Arch Linux System Wide Locale Setting"
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
    _dialog --yesno "Abort Arch Linux System Wide Locale Setting" 6 42 || return 0
    [[ -e /tmp/.locale-running ]] && rm /tmp/.locale-running
    clear
    exit 1
}

_do_locale() {
    _dialog --infobox "Setting System Wide Locale ${_LOCALE}..." 3 80
    echo "LANG=${_LOCALE}.UTF-8" > /etc/locale.conf
    echo "LANG=${_LOCALE}.UTF-8" > /tmp/.locale
    echo LC_COLLATE=C >> /etc/locale.conf
    localectl set-locale "${_LOCALE}.UTF-8" &>/dev/null
    echo "${_LOCALE}.UTF-8" >> /etc/locale.gen
    locale-gen &>/dev/null
    sleep 2
}

_set_locale() {
    _LOCALE=""
    _LOCALES="en_US English de_DE German es_ES Spanish fr_FR French pt_PT Portuguese ru_RU Russian"
    _CANCEL=""
    #shellcheck disable=SC2086
    _dialog --menu "Select A System Wide Locale:" 13 35 8 ${_LOCALES} 2>${_ANSWER} || _abort
    _LOCALE=$(cat ${_ANSWER})
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
