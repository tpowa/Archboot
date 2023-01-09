#!/usr/bin/env bash
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.tz"
_TITLE="Arch Linux Time And Date Setting"

if [[ "${1}" = "--setup" ]]; then
    _EXIT="Return to Main Menu"
else
    _EXIT="Exit"
fi

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
    _dialog --yesno "Abort Time And Date Setting?" 6 40 || return 0
    [[ -e /tmp/.timezone ]] && rm -f /tmp/.timezone
    [[ -e /tmp/.hardwareclock ]] && rm -f /tmp/.hardwareclock
    [[ -e /tmp/.tz ]] && rm -f /tmp/.tz
    [[ -e /etc/localtime ]] && rm -f /etc/localtime
    [[ -e /etc/adjtime ]] && rm -f /etc/adjtime
    [[ -e /tmp/.tz-running ]] && rm /tmp/.tz-running
    clear
    exit 1
}

_dohwclock() {
    echo 0.0 0 0.0 > /etc/adjtime
    echo 0 >> /etc/adjtime
    [[ "${_HARDWARECLOCK}" = "UTC" ]] && echo UTC >> /etc/adjtime
    [[ "${_HARDWARECLOCK}" = "" ]] && echo LOCAL >> /etc/adjtime
    if [[ "${_HARDWARECLOCK}" = "UTC" ]]; then
        timedatectl set-local-rtc 0
        _DATE_PROGRAM=timedatectl
        # for setup script
        echo UTC > /tmp/.hardwareclock
    else
        timedatectl set-local-rtc 1
        #shellcheck disable=SC2209
        _DATE_PROGRAM=date
        # for setup script
        echo LOCAL > /tmp/.hardwareclock
    fi
}

_dotimezone () {
    _SET_ZONE=""
    while [[ -z "${_SET_ZONE}" ]]; do
        _REGIONS="America - Europe - Africa - Asia - Australia -"
        #shellcheck disable=SC2086
        _dialog --menu "Please Select A Region:" 12 40 7 ${_REGIONS} 2>${_ANSWER}
        _REGION=$(cat ${_ANSWER})
        _ZONES=""
        for i in $(timedatectl --no-pager list-timezones | grep -w "${_REGION}" | cut -d '/' -f 2 | sort -u); do
            _ZONES="${_ZONES} ${i} -"
        done
        #shellcheck disable=SC2086
        _dialog --menu "Please Select A Timezone:" 22 40 16 ${_ZONES} 2>${_ANSWER} && _SET_ZONE="1"
        _ZONE=$(cat ${_ANSWER})
        [[ "${_ZONE}" == "${_REGION}" ]] || _ZONE="${_REGION}/${_ZONE}"
        if [[ -n "${_SET_ZONE}" ]]; then
            _dialog --infobox "Setting Timezone to ${_ZONE} ..." 0 0
            echo "${_ZONE}" > /tmp/.timezone
            timedatectl set-timezone "${_ZONE}"
            _S_NEXTITEM="2"
        else
            _S_NEXTITEM="1"
            return 1
        fi
    done
}

_dotimeset() {
    if [[ ! -s /tmp/.timezone ]]; then
        _dialog --msgbox "Error:\nYou have to select timezone first." 0 0
        _S_NEXTITEM="1"
        dotimezone || return 1
    fi
    _SET_TIME=""
    while [[ -z "${_SET_TIME}" ]]; do
        _HARDWARECLOCK=""
        _DATE_PROGRAM=""
        _dialog --yesno "Do you want to use UTC for your clock?\n\nIf you choose 'YES' UTC (recommended default) is used,\nwhich ensures daylightsaving is set automatically.\n\nIf you choose 'NO' Localtime is used, which means\nthe system will not change the time automatically.\nLocaltime is also prefered on dualboot machines,\nwhich also run Windows, because UTC may confuse it." 14 60 && _HARDWARECLOCK="UTC"
        _dohwclock
        # check internet connection
        if ping -c1 www.google.com >/dev/null 2>&1; then
            if _dialog --yesno \
            "Do you want to use the Network Time Protocol (NTP) for syncing your clock, by using the internet clock pool?" 6 60; then
                _dialog --infobox "Syncing clock with NTP pool ..." 3 45
                # sync immediatly with standard pool
                if ! systemctl restart systemd-timesyncd; then
                    _dialog --msgbox "An error has occured, time was not changed!" 0 0
                    _S_NEXTITEM="2"
                    return 1
                fi
                # enable background syncing
                timedatectl set-ntp 1
                _SET_TIME="1"
            fi
        fi
        if [[ -z "${_SET_TIME}" ]]; then
            timedatectl set-ntp 0
            # display and ask to set date/time
            _CANCEL=""
            dialog --calendar "Set the date.\nUse <TAB> to navigate and arrow keys to change values." 0 0 0 0 0 2> ${_ANSWER} || _CANCEL="1"
            if [[ -n "${_CANCEL}" ]]; then
                _S_NEXTITEM="2"
                return 1
            fi
            _DATE="$(cat ${_ANSWER})"
            dialog --timebox "Set the time.\nUse <TAB> to navigate and up/down to change values." 0 0 2> ${_ANSWER} || _CANCEL="1"
            if [[ -n "${_CANCEL}" ]]; then
                _S_NEXTITEM="2"
                return 1
            fi
            _TIME="$(cat ${_ANSWER})"
            # save the time
            # DD/MM/YYYY hh:mm:ss -> YYYY-MM-DD hh:mm:ss
            _DATETIME="$(echo "${_DATE}" "${_TIME}" | sed 's#\(..\)/\(..\)/\(....\) \(..\):\(..\):\(..\)#\3-\2-\1 \4:\5:\6#g')"
            timedatectl set-time "${_DATETIME}"
            _SET_TIME="1"
        fi
        _dialog --cr-wrap --defaultno --yesno "Your current time and date is:\n$(${_DATE_PROGRAM})\n\nDo you want to change it?" 0 0 && _SET_TIME=""
    done
    _S_NEXTITEM="3"
}

_mainmenu() {
    if [[ -n "${_S_NEXTITEM}" ]]; then
        _DEFAULT="--default-item ${_S_NEXTITEM}"
    else
        _DEFAULT=""
    fi
    #shellcheck disable=SC2086
    _dialog ${_DEFAULT} --backtitle "${_TITLE}" --title " MAIN MENU " \
                --menu "Use the UP and DOWN arrows to navigate menus.\nUse TAB to switch between buttons and ENTER to select." 11 58 13 \
        "1" "Select Timezone" \
        "2" "Set Time and Date" \
        "3" "${_EXIT}" 2>${_ANSWER}
    case $(cat ${_ANSWER}) in
        "1")
            _dotimezone
            ;;
        "2")
            _dotimeset
            ;;
        "3")
            [[ -e /tmp/.tz-running ]] && rm /tmp/.tz-running
            clear
            exit 0 ;;
        *)
            _abort ;;
    esac
}

: >/tmp/.hardwareclock
: >/tmp/.timezone
: >/tmp/.tz

if [[ -e /tmp/.tz-running ]]; then
    echo "tz already runs on a different console!"
    echo "Please remove /tmp/.tz-running first to launch tz!"
    exit 1
fi 
: >/tmp/.tz-running

while true; do
    _mainmenu
done

clear
exit 0

# vim: set ts=4 sw=4 et:
