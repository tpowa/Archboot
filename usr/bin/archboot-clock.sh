#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.clock"
_RUNNING_ARCH="$(uname -m)"
_TITLE="Archboot ${_RUNNING_ARCH} | Arch Linux Setup | Clock Configuration"
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
    if _dialog --yesno "Abort Arch Linux Clock Configuration?" 5 50; then
        [[ -e /tmp/.clock-running ]] && rm /tmp/.clock-running
        [[ -e /tmp/.clock ]] && rm /tmp/.clock
        clear
        exit 1
    else
        _CONTINUE=""
    fi
}

_dohwclock() {
    echo 0.0 0 0.0 > /etc/adjtime
    echo 0 >> /etc/adjtime
    [[ "${_HARDWARECLOCK}" = "UTC" ]] && echo UTC >> /etc/adjtime
    [[ "${_HARDWARECLOCK}" = "" ]] && echo LOCAL >> /etc/adjtime
    if [[ "${_HARDWARECLOCK}" = "UTC" ]]; then
        timedatectl set-local-rtc 0
        _DATE_PROGRAM=timedatectl
    else
        timedatectl set-local-rtc 1
        #shellcheck disable=SC2209
        _DATE_PROGRAM=date
    fi
}

_dotimezone () {
    _SET_ZONE=""
    while [[ -z "${_SET_ZONE}" ]]; do
        _CONTINUE=""
        while [[ -z "${_CONTINUE}" ]]; do
            _REGIONS="America - Europe - Africa - Asia - Australia -"
            #shellcheck disable=SC2086
            if _dialog --title " Region Menu " --menu "" 11 30 6 ${_REGIONS} 2>${_ANSWER}; then
                _REGION=$(cat ${_ANSWER})
                _ZONES=""
                _CONTINUE=1
            else
                _abort
            fi
        done
        _CONTINUE=""
        while [[ -z "${_CONTINUE}" ]]; do
            for i in $(timedatectl --no-pager list-timezones | grep -w "${_REGION}" | cut -d '/' -f 2 | sort -u); do
                _ZONES="${_ZONES} ${i} -"
            done
            #shellcheck disable=SC2086
            if _dialog --title " Timezone Menu " --menu "" 21 30 16 ${_ZONES} 2>${_ANSWER}; then
                _SET_ZONE="1"
                _ZONE=$(cat ${_ANSWER})
                [[ "${_ZONE}" == "${_REGION}" ]] || _ZONE="${_REGION}/${_ZONE}"
                if [[ -n "${_SET_ZONE}" ]]; then
                    _dialog --infobox "Setting Timezone to ${_ZONE}..." 3 60
                    timedatectl set-timezone "${_ZONE}"
                    sleep 2
                else
                    return 1
                fi
                _CONTINUE=1
            else
                _abort
            fi
        done
    done
}

_dotimeset() {
    _SET_TIME=""
    while [[ -z "${_SET_TIME}" ]]; do
        _HARDWARECLOCK=""
        _DATE_PROGRAM=""
        _dialog --yesno "Do you want to use UTC for your clock?\n\nIf you choose 'YES' UTC (recommended default) is used,\nwhich ensures daylightsaving is set automatically.\n\nIf you choose 'NO' Localtime is used, which means\nthe system will not change the time automatically.\nLocaltime is also prefered on dualboot machines,\nwhich also run Windows, because UTC may confuse it." 14 60 && _HARDWARECLOCK="UTC"
        _dohwclock
        # check internet connection
        if ping -c1 www.google.com &>/dev/null; then
            if _dialog --yesno \
            "Do you want to use the Network Time Protocol (NTP) for syncing your clock, by using the internet clock pool?" 6 60; then
                _dialog --infobox "Syncing clock with NTP pool..." 3 45
                # sync immediatly with standard pool
                if ! systemctl restart systemd-timesyncd; then
                    _dialog --msgbox "An error has occured, time was not changed!" 0 0
                    return 1
                fi
                # enable background syncing
                timedatectl set-ntp 1
                _SET_TIME="1"
            fi
        fi
        if [[ -z "${_SET_TIME}" ]]; then
            timedatectl set-ntp 0
            _CONTINUE=""
            while [[ -z "${_CONTINUE}" ]]; do
                # display and ask to set date/time
                if _dialog --title ' Date Setting' --calendar "Use <TAB> to navigate and arrow keys to change values." 0 0 0 0 0 2> ${_ANSWER}; then
                    _DATE="$(cat ${_ANSWER})"
                    _CONTINUE=1
                else
                    _abort
                fi
            done
            _CONTINUE=""
            while [[ -z "${_CONTINUE}" ]]; do
                if _dialog --title ' Time Setting ' --timebox "Use <TAB> to navigate and up/down to change values." 0 0 2> ${_ANSWER}; then
                    _TIME="$(cat ${_ANSWER})"
                    _CONTINUE=1
                else
                    _abort
                fi
            done
            # save the time
            # DD/MM/YYYY hh:mm:ss -> YYYY-MM-DD hh:mm:ss
            _DATETIME="$(echo "${_DATE}" "${_TIME}" | sed 's#\(..\)/\(..\)/\(....\) \(..\):\(..\):\(..\)#\3-\2-\1 \4:\5:\6#g')"
            timedatectl set-time "${_DATETIME}"
            _SET_TIME="1"
        fi
        if _dialog --cr-wrap --defaultno --yesno "Your current time and date is:\n$(${_DATE_PROGRAM})\n\nDo you want to change it?" 0 0; then
            _SET_TIME=""
        else
            _dialog --infobox "Clock configuration completed successfully.\nContinuing in 5 seconds..." 4 60
            sleep 5
            return 0
        fi
    done
}

if [[ -e /tmp/.clock-running ]]; then
    echo "clock already runs on a different console!"
    echo "Please remove /tmp/.clock-running first to launch clock!"
    exit 1
fi
: >/tmp/.clock-running
if ! _dotimezone; then
    [[ -e /tmp/.clock ]] && rm /tmp/.clock
    [[ -e /tmp/.clock-running ]] && rm /tmp/.clock-running
    clear
    exit 1
fi
if ! _dotimeset; then
    [[ -e /tmp/.clock ]] && rm /tmp/.clock
    [[ -e /tmp/.clock-running ]] && rm /tmp/.clock-running
    clear
    exit 1
fi
[[ -e /tmp/.clock ]] && rm /tmp/.clock
[[ -e /tmp/.clock-running ]] && rm /tmp/.clock-running
clear
exit 0
# vim: set ts=4 sw=4 et: