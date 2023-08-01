#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/basic-common.sh
_TITLE="Archboot ${_RUNNING_ARCH} | Basic Setup | Clock Configuration"

_hwclock() {
    _DATE_PROGRAM=timedatectl
    echo 0.0 0 0.0 > /etc/adjtime
    echo 0 >> /etc/adjtime
    echo UTC >> /etc/adjtime
    timedatectl set-local-rtc 0
}

_timezone () {
    _SET_ZONE=""
    while [[ -z "${_SET_ZONE}" ]]; do
        _CONTINUE=""
        while [[ -z "${_CONTINUE}" ]]; do
            _REGIONS="America - Europe - Africa - Asia - Australia -"
            #shellcheck disable=SC2086
            if _dialog --cancel-label "${_LABEL}" --title " Timezone Region " --menu "" 11 30 6 ${_REGIONS} 2>${_ANSWER}; then
                _REGION=$(cat ${_ANSWER})
                _ZONES=""
                _CONTINUE=1
            else
                _abort
            fi
        done
        _ZONES=""
        for i in $(timedatectl --no-pager list-timezones | grep -w "${_REGION}" | cut -d '/' -f 2 | sort -u); do
            _ZONES="${_ZONES} ${i} -"
        done
        #shellcheck disable=SC2086
        if _dialog --cancel-label "Back" --title " Timezone " --menu "" 21 30 16 ${_ZONES} 2>${_ANSWER}; then
            _SET_ZONE="1"
            _ZONE=$(cat ${_ANSWER})
            [[ "${_ZONE}" == "${_REGION}" ]] || _ZONE="${_REGION}/${_ZONE}"
        else
            _SET_ZONE=""
        fi
    done
    _dialog --no-mouse --infobox "Setting Timezone to ${_ZONE}..." 3 50
    timedatectl set-timezone "${_ZONE}"
    sleep 2
}

_timeset() {
    _hwclock
    if [[ -z "${_SET_TIME}" ]]; then
        timedatectl set-ntp 0
        # display and ask to set date/time
        _dialog --title " Date " --no-cancel --calendar "Use <TAB> to navigate and arrow keys to change values." 0 0 0 0 0 2>"${_ANSWER}"
        _DATE="$(cat "${_ANSWER}")"
        _dialog --title " Time " --no-cancel --timebox "Use <TAB> to navigate and up/down to change values." 0 0 2>"${_ANSWER}"
        _TIME="$(cat "${_ANSWER}")"
        # save the time
        # DD/MM/YYYY hh:mm:ss -> YYYY-MM-DD hh:mm:ss
        _DATETIME="$(echo "${_DATE}" "${_TIME}" | sed 's#\(..\)/\(..\)/\(....\) \(..\):\(..\):\(..\)#\3-\2-\1 \4:\5:\6#g')"
        timedatectl set-time "${_DATETIME}"
        _SET_TIME="1"
    fi
    _dialog --no-mouse --infobox "Clock configuration completed successfully." 3 50
    sleep 2
}

_auto_clock() {
    timedatectl set-timezone "${_ZONE}"
    _hwclock
    sleep 1
    _progress "50" "Syncing clock with NTP pool and enable timesyncd..."
    sleep 1
    # sync immediatly with standard pool
    systemctl restart systemd-timesyncd
    # enable background syncing
    timedatectl set-ntp 1
    _SET_TIME="1"
    _progress "100" "Clock configuration completed successfully."
    sleep 1
}

_check
_SET_TIME=""
# automatic setup
if ping -c1 www.google.com &>/dev/null; then
    _ZONE="$(curl -s "http://ip-api.com/csv/?fields=timezone")"
    _auto_clock |  _dialog --no-mouse --gauge "Setting Timezone to ${_ZONE}..." 6 60 0
fi
while [[ -z "${_SET_TIME}" ]]; do
    _timezone
    _timeset
done
_cleanup
# vim: set ts=4 sw=4 et:
