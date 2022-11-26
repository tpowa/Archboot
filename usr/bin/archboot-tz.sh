#!/usr/bin/env bash
# written by Tobias Powalowski <tpowa@archlinux.org>

ANSWER="/tmp/.tz"
TITLE="Arch Linux Time And Date Setting"
BASEDIR="/usr/share/zoneinfo"

if [[ "${1}" = "--setup" ]]; then
    EXIT="Return to Main Menu"
else
    EXIT="Exit"
fi

abort()
{
    DIALOG --yesno "Abort Time And Date Setting?" 6 40 || return 0
    [[ -e /tmp/.timezone ]] && rm -f /tmp/.timezone
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
    dialog --backtitle "${TITLE}" --aspect 15 "$@"
    return $?
}

dohwclock() {
echo "0.0 0 0.0" > /etc/adjtime
echo "0" >> /etc/adjtime
[[ "${HARDWARECLOCK}" = "UTC" ]] && echo UTC >> /etc/adjtime
[[ "${HARDWARECLOCK}" = "" ]] && echo LOCAL >> /etc/adjtime
if [[ "${HARDWARECLOCK}" = "UTC" ]]; then
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

dotimezone () {
SET_ZONE=""
while ! [[ "${SET_ZONE}" = "1" ]]; do
    REGIONS=""
    for i in $(timedatectl --no-pager list-timezones | cut -d '/' -f 1 | grep -v "[A-Z]$" -v "[0-9]$" -v "Zulu" | sort -u); do
        REGIONS="${REGIONS} ${i} -"
    done
    #shellcheck disable=SC2086
    DIALOG --menu "Please Select A Region/Timezone:" 22 40 16 ${REGIONS} 2>${ANSWER}
    region=$(cat ${ANSWER})
    ZONES=""
    for i in $(timedatectl --no-pager list-timezones | grep -w "${region}" | cut -d '/' -f 2 | sort -u); do
        ZONES="${ZONES} ${i} -"
    done
    #shellcheck disable=SC2086
    DIALOG --menu "Please Select A Timezone:" 22 40 16 ${ZONES} 2>${ANSWER} && SET_ZONE="1"
    zone=$(cat ${ANSWER})
    [[ "${zone}" == "${region}" ]] || zone="${region}/${zone}"
    if [[ "${SET_ZONE}" = "1" ]]; then
        DIALOG --infobox "Setting Timezone to ${zone} ..." 0 0
        echo "${zone}" > /tmp/.timezone
        timedatectl set-timezone "${zone}"
        S_NEXTITEM="2"
    else
        S_NEXTITEM="1"
        return 1
    fi
done
}

dotimeset() {
if [[ ! -s /tmp/.timezone ]]; then
    DIALOG --msgbox "Error:\nYou have to select timezone first." 0 0
    S_NEXTITEM="1"
    dotimezone || return 1
fi
SET_TIME=""
while [[ "${SET_TIME}" == "" ]]; do
    HARDWARECLOCK=""
    DATE_PROGRAM=""
    DIALOG --yesno "Do you want to use UTC for your clock?\n\nIf you choose 'YES' UTC (recommended default) is used,\nwhich ensures daylightsaving is set automatically.\n\nIf you choose 'NO' Localtime is used, which means\nthe system will not change the time automatically.\nLocaltime is also prefered on dualboot machines,\nwhich also run Windows, because UTC may confuse it." 14 60 && HARDWARECLOCK="UTC"
    dohwclock
    # check internet connection
    if ping -c1 www.google.com >/dev/null 2>&1; then
        if DIALOG --yesno \
        "Do you want to use the Network Time Protocol (NTP) for syncing your clock, by using the internet clock pool?" 6 60; then
            DIALOG --infobox "Syncing clock with NTP pool ..." 3 45
            # sync immediatly with standard pool
            if [[ ! $(ntpdate pool.ntp.org) ]]; then
                DIALOG --msgbox "An error has occured, time was not changed!" 0 0
                S_NEXTITEM="2"
                return 1
            fi
            # enable background syncing
            timedatectl set-ntp 1
            SET_TIME="1"
        fi
    fi
    if [[ "${SET_TIME}" == "" ]]; then
        timedatectl set-ntp 0
        # display and ask to set date/time
        CANCEL=""
        dialog --calendar "Set the date.\nUse <TAB> to navigate and arrow keys to change values." 0 0 0 0 0 2> ${ANSWER} || CANCEL="1"
        if [[ "${CANCEL}" = "1" ]]; then
            S_NEXTITEM="2"
            return 1
        fi
        _date="$(cat ${ANSWER})"
        dialog --timebox "Set the time.\nUse <TAB> to navigate and up/down to change values." 0 0 2> ${ANSWER} || CANCEL="1"
        if [[ "${CANCEL}" = "1" ]]; then
            S_NEXTITEM="2"
            return 1
        fi
        _time="$(cat ${ANSWER})"
        # save the time
        # DD/MM/YYYY hh:mm:ss -> YYYY-MM-DD hh:mm:ss
        _datetime="$(echo "${_date}" "${_time}" | sed 's#\(..\)/\(..\)/\(....\) \(..\):\(..\):\(..\)#\3-\2-\1 \4:\5:\6#g')"
        timedatectl set-time "${_datetime}"
        SET_TIME="1"
    fi
    DIALOG --cr-wrap --defaultno --yesno "Your current time and date is:\n$(${DATE_PROGRAM})\n\nDo you want to change it?" 0 0 && SET_TIME=""
done
S_NEXTITEM="3"
}

mainmenu() {
    if [[ -n "${S_NEXTITEM}" ]]; then
        DEFAULT="--default-item ${S_NEXTITEM}"
    else
        DEFAULT=""
    fi
    #shellcheck disable=SC2086
    DIALOG ${DEFAULT} --backtitle "${TITLE}" --title " MAIN MENU " \
                --menu "Use the UP and DOWN arrows to navigate menus.\nUse TAB to switch between buttons and ENTER to select." 11 58 13 \
        "1" "Select Timezone" \
        "2" "Set Time and Date" \
        "3" "${EXIT}" 2>${ANSWER}
    case $(cat ${ANSWER}) in
        "1")
            dotimezone
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
: >/tmp/.timezone
: >/tmp/.tz

if [[ ! -d ${BASEDIR} ]]; then
    echo "Cannot load timezone data, as none were found in ${BASEDIR}" >&2
    exit 1
fi

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
