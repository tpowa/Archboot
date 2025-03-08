#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# written by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | Clock Configuration"

_hwclock() {
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
        for i in $(timedatectl --no-pager list-timezones | rg "${_REGION}" | sd '.*/' '' | sort -u); do
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
    # write to template
    echo "timedatectl set-timezone \"${_ZONE}\"" >> "${_TEMPLATE}"
}

_timeset() {
    _hwclock
    if [[ -z "${_SET_TIME}" ]]; then
        timedatectl set-ntp 0
        # display and ask to set date/time
        _dialog --title " Date " --no-cancel --date-format '%F' --calendar "Use <TAB> to navigate and arrow keys to change values." 0 0 0 0 0 2>"${_ANSWER}"
        _DATE="$(cat "${_ANSWER}")"
        _dialog --title " Time " --no-cancel --timebox "Use <TAB> to navigate and up/down to change values." 0 0 2>"${_ANSWER}"
        _TIME="$(cat "${_ANSWER}")"
        # save the time
        #shellcheck disable=SC2027
        _DATETIME=""${_DATE}" "${_TIME}""
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
    # write to template
    { echo "### clock start"
    echo "echo Clock..."
    echo "timedatectl set-timezone \"${_ZONE}\""
    echo "echo 0.0 0 0.0 > /etc/adjtime"
    echo "echo 0 >> /etc/adjtime"
    echo "echo UTC >> /etc/adjtime"
    echo "timedatectl set-local-rtc 0"
    echo "systemctl restart systemd-timesyncd"
    echo "timedatectl set-ntp 1"
    echo ": > /.clock"
    echo "### clock end"
    echo ""
    } >> "${_TEMPLATE}"
    rm /.archboot
}

_auto_clock() {
    : > /.archboot
    _task_clock &
    _progress_wait "0" "99" "Using ${_ZONE} and enable NTP timesyncd..." "1"
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
