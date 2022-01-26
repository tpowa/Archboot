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
if [[ ! -f /etc/adjtime ]]; then
    echo "0.0 0 0.0" > /etc/adjtime
    echo "0" >> /etc/adjtime
    [[ "${HARDWARECLOCK}" = "UTC" ]] && echo UTC >> /etc/adjtime
    [[ "${HARDWARECLOCK}" = "" ]] && echo LOCAL >> /etc/adjtime
fi
if [[ "${HARDWARECLOCK}" = "UTC" ]]; then
    timedatectl set-local-rtc 0
    DATE_PROGRAM=timedatectl
    # for setup script
    echo UTC > /tmp/.hardwareclock
else
    timedatectl set-local-rtc 1
    DATE_PROGRAM="$(date)"
    # for setup script
    echo LOCAL > /tmp/.hardwareclock
fi
}

dotimezone () {
SET_ZONE=""
while ! [[ "${SET_ZONE}" = "1" ]]; do
    ZONES=""
    for i in $(timedatectl --no-pager list-timezones); do
        ZONES="${ZONES} ${i} -"
    done
    #shellcheck disable=SC2086
    DIALOG --menu "Please Select A Timezone:" 22 60 16 ${ZONES} 2>${ANSWER} && SET_ZONE="1"
    zone=$(cat ${ANSWER})
    if [[ "${SET_ZONE}" = "1" ]]; then
        DIALOG --infobox "Setting Timezone to ${zone} ..." 0 0
        echo "${zone}" > /tmp/.timezone
        timedatectl set-timezone "${zone}"
        S_NEXTITEM="2"
    else
        S_NEXTITEM="1"
        break
    fi
done
}

dotimeset() {
SET_TIME=""
USE_NTPD=""
HARDWARECLOCK=""
DATE_PROGRAM=""
if [[ ! -s /tmp/.timezone ]]; then
    DIALOG --msgbox "Error:\nYou have to select timezone first." 0 0
    S_NEXTITEM="1"
    dotimezone || return 1
fi
DIALOG --yesno "Do you want to use UTC for your clock?\n\nIf you choose 'YES' UTC (recommended default) is used,\nwhich ensures daylightsaving is set automatically.\n\nIf you choose 'NO' Localtime is used, which means\nthe system will not change the time automatically.\nLocaltime is also prefered on dualboot machines,\nwhich also run Windows, because UTC confuses it." 15 65 && HARDWARECLOCK="UTC"
dohwclock
DIALOG --cr-wrap --yesno "Your current time and date is:\n$(${DATE_PROGRAM})\n\nDo you want to change it?" 0 0 && SET_TIME="1"
if [[ "${SET_TIME}" = "1" ]]; then
    timedatectl set-ntp 0
    [[ $(which ntpd) ]] &&  DIALOG --defaultno --yesno "'ntpd' was detected on your system.\n\nDo you want to use 'ntpd' for syncing your clock,\nby using the internet clock pool?\n(You need a working internet connection for doing this!)" 0 0 && USE_NTPD="1"
    if [[ "${USE_NTPD}" = "1" ]]; then
        # sync immediatly with standard pool
        if [[ ! $(ntpdate pool.ntp.org) ]]; then 
            DIALOG --msgbox "An error has occured, time was not changed!" 0 0
            S_NEXTITEM="2" 
            return 1
        fi
        # enable background syncing
        timedatectl set-ntp 1
        DIALOG --cr-wrap --msgbox "Synced clock with internet pool successfully.\n\nYour current time is now:\n$(${DATE_PROGRAM})" 0 0
    else
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
        DIALOG --cr-wrap --msgbox "Your current time is now:\n$(${DATE_PROGRAM})" 0 0
    fi
fi
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
                --menu "Use the UP and DOWN arrows to navigate menus.\nUse TAB to switch between buttons and ENTER to select." 17 58 13 \
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
