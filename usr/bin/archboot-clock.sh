#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# written by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_TITLE="Archboot ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | Clock Configuration"

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
        if _dialog  --title " Timezone " --menu "" 21 30 16 ${_ZONES} 2>${_ANSWER}; then
            _SET_ZONE="1"
            _ZONE=$(cat ${_ANSWER})
            [[ "${_ZONE}" == "${_REGION}" ]] || _ZONE="${_REGION}/${_ZONE}"
        else
            _SET_ZONE=""
        fi
    done
    _dialog --title " Clock Configuration " --no-mouse --infobox "Setting Timezone to ${_ZONE}..." 3 50
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
    _dialog --title " Clock Configuration " --no-mouse --infobox "Clock configuration completed successfully." 3 50
    sleep 2
}

_task_clock() {
    timedatectl set-timezone "${_ZONE}"
    _hwclock
    # sync immediatly with standard pool
    systemctl restart systemd-timesyncd
    # enable background syncing
    timedatectl set-ntp 1
    rm /.archboot
}

_auto_clock() {
    : > /.archboot
    _task_clock &
    _progress_wait "0" "99" "Using ${_ZONE} and enable NTP timesyncd..." "0.005"
    _progress "100" "${_ZONE} configuration completed successfully."
    sleep 2
}

_check
_SET_TIME=""
# automatic setup
if ping -c1 www.google.com &>"${_NO_LOG}"; then
    _ZONE="$(${_DLPROG} "http://ip-api.com/csv/?fields=timezone")"
    _auto_clock |  _dialog --title " Clock Configuration " --no-mouse --gauge "Using ${_ZONE} and enable NTP timesyncd..." 6 70 0
    _SET_TIME="1"
fi
while [[ -z "${_SET_TIME}" ]]; do
    _timezone
    _timeset
done
_cleanup
# vim: set ts=4 sw=4 et:
