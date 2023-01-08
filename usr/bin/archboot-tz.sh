#!/usr/bin/env bash
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.tz"
_TITLE="Arch Linux Time And Date Setting"

if [[ "${1}" = "--setup" ]]; then
    _EXIT="Return to Main Menu"
else
    _EXIT="Exit"
fi

abort()
{
    DIALOG --yesno "Abort Time And Date Setting?" 6 40 || return 0
    [[ -e /tmp/.time_zone ]] && rm -f /tmp/.time_zone
    [[ -e /tmp/.hardwareclock ]] && rm -f /tmp/.hardwareclock
    [[ -e /tmp/.tz ]] && rm -f /tmp/.tz
    [[ -e /etc/localtime ]] && rm -f /etc/localtime
    [[ -e /etc/adjtime ]] && rm -f /etc/adjtime
    [[ -e /tmp/.tz-running ]] && rm /tmp/.tz-running
    clear
    exit 1
}

# DIALOG()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
DIALOG() {
    dialog --backtitle "${_TITLE}" --aspect 15 "$@"
    return $?
}

dohwclock() {
echo "0.0 0 0.0" > /etc/adjtime
echo "0" >> /etc/adjtime
[[ "${_HARDWARECLOCK}" = "UTC" ]] && echo UTC >> /etc/adjtime
[[ "${_HARDWARECLOCK}" = "" ]] && echo LOCAL >> /etc/adjtime
if [[ "${_HARDWARECLOCK}" = "UTC" ]]; then
    timedatectl set-local-rtc 0
    DATE_PROGRAM=timedatectl
    # for setup script
    echo UTC > /tmp/.hardwareclock
else
    timedatectl set-local-rtc 1
    #shellcheck disable=SC2209
    DATE_PROGRAM=date
    # for setup script
    echo LOCAL > /tmp/.hardwareclock
fi
}

dotime_zone () {
_SET_ZONE=""
while ! [[ "${_SET_ZONE}" = "1" ]]; do
    _REGIONS="America - Europe - Africa - Asia - Australia -"
    #shellcheck disable=SC2086
    DIALOG --menu "Please Select A Region:" 12 40 7 ${_REGIONS} 2>${_ANSWER}
    _REGION=$(cat ${_ANSWER})
    _ZONES=""
    for i in $(timedatectl --no-pager list-time_ZONEs | grep -w "${_REGION}" | cut -d '/' -f 2 | sort -u); do
        _ZONES="${_ZONES} ${i} -"
    done
    #shellcheck disable=SC2086
    DIALOG --menu "Please Select A Time_ZONE:" 22 40 16 ${_ZONES} 2>${_ANSWER} && _SET_ZONE="1"
    _ZONE=$(cat ${_ANSWER})
    [[ "${_ZONE}" == "${_REGION}" ]] || _ZONE="${_REGION}/${_ZONE}"
    if [[ "${_SET_ZONE}" = "1" ]]; then
        DIALOG --infobox "Setting Time_ZONE to ${_ZONE} ..." 0 0
        echo "${_ZONE}" > /tmp/.time_zone
        timedatectl set-time_ZONE "${_ZONE}"
        _S_NEXTITEM="2"
    else
        _S_NEXTITEM="1"
        return 1
    fi
done
}

dotimeset() {
if [[ ! -s /tmp/.time_zone ]]; then
    DIALOG --msgbox "Error:\nYou have to select time_ZONE first." 0 0
    _S_NEXTITEM="1"
    dotime_zone || return 1
fi
_SET_TIME=""
while [[ "${_SET_TIME}" == "" ]]; do
    _HARDWARECLOCK=""
    DATE_PROGRAM=""
    DIALOG --yesno "Do you want to use UTC for your clock?\n\nIf you choose 'YES' UTC (recommended default) is used,\nwhich ensures daylightsaving is set automatically.\n\nIf you choose 'NO' Localtime is used, which means\nthe system will not change the time automatically.\nLocaltime is also prefered on dualboot machines,\nwhich also run Windows, because UTC may confuse it." 14 60 && _HARDWARECLOCK="UTC"
    dohwclock
    # check internet connection
    if ping -c1 www.google.com >/dev/null 2>&1; then
        if DIALOG --yesno \
        "Do you want to use the Network Time Protocol (NTP) for syncing your clock, by using the internet clock pool?" 6 60; then
            DIALOG --infobox "Syncing clock with NTP pool ..." 3 45
            # sync immediatly with standard pool
            if ! systemctl restart systemd-timesyncd; then
                DIALOG --msgbox "An error has occured, time was not changed!" 0 0
                _S_NEXTITEM="2"
                return 1
            fi
            # enable background syncing
            timedatectl set-ntp 1
            _SET_TIME="1"
        fi
    fi
    if [[ "${_SET_TIME}" == "" ]]; then
        timedatectl set-ntp 0
        # display and ask to set date/time
        _CANCEL=""
        dialog --calendar "Set the date.\nUse <TAB> to navigate and arrow keys to change values." 0 0 0 0 0 2> ${_ANSWER} || _CANCEL="1"
        if [[ "${_CANCEL}" = "1" ]]; then
            _S_NEXTITEM="2"
            return 1
        fi
        _DATE="$(cat ${_ANSWER})"
        dialog --timebox "Set the time.\nUse <TAB> to navigate and up/down to change values." 0 0 2> ${_ANSWER} || _CANCEL="1"
        if [[ "${_CANCEL}" = "1" ]]; then
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
    DIALOG --cr-wrap --defaultno --yesno "Your current time and date is:\n$(${DATE_PROGRAM})\n\nDo you want to change it?" 0 0 && _SET_TIME=""
done
_S_NEXTITEM="3"
}

mainmenu() {
    if [[ -n "${_S_NEXTITEM}" ]]; then
        DEFAULT="--default-item ${_S_NEXTITEM}"
    else
        DEFAULT=""
    fi
    #shellcheck disable=SC2086
    DIALOG ${DEFAULT} --backtitle "${_TITLE}" --title " MAIN MENU " \
                --menu "Use the UP and DOWN arrows to navigate menus.\nUse TAB to switch between buttons and ENTER to select." 11 58 13 \
        "1" "Select Time_ZONE" \
        "2" "Set Time and Date" \
        "3" "${_EXIT}" 2>${_ANSWER}
    case $(cat ${_ANSWER}) in
        "1")
            dotime_zone
            ;;
        "2")
            dotimeset
            ;;
        "3")
            [[ -e /tmp/.tz-running ]] && rm /tmp/.tz-running
            clear
            exit 0 ;;
        *)
            abort ;;
    esac
}

: >/tmp/.hardwareclock
: >/tmp/.time_zone
: >/tmp/.tz

if [[ -e /tmp/.tz-running ]]; then
    echo "tz already runs on a different console!"
    echo "Please remove /tmp/.tz-running first to launch tz!"
    exit 1
fi 
: >/tmp/.tz-running

while true; do
    mainmenu
done

clear
exit 0

# vim: set ts=4 sw=4 et:
