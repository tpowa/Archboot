#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# written by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | Launcher"

_check_desktop() {
    _DESKTOP=()
    update | rg -q 'Gnome' && _DESKTOP+=( "gnome" "Simple Beautiful Elegant" )
    update | rg -q 'KDE' && _DESKTOP+=( "plasma" "Simple By Default" )
    update | rg -q 'Sway' && _DESKTOP+=( "sway" "Tiling Wayland Compositor" )
    update | rg -q 'Xfce' && _DESKTOP+=( "xfce" "Leightweight Desktop" )
}

_check_manage() {
    _MANAGE=()
    update | rg -q 'full' && _MANAGE+=( "FULL" "Switch To Full Arch Linux System" )
    update | rg -q 'latest archboot' && _MANAGE+=( "UPDATE" "Update Archboot Environment" )
    update | rg -q 'image' && _MANAGE+=( "IMAGE" "Create Archboot Images" )
}

_desktop () {
    _dialog  --title " Desktop Menu " --menu "" 10 40 6 "${_DESKTOP[@]}" 2>"${_ANSWER}" || return 1
    [[ -e /.launcher-running ]] && rm /.launcher-running
    _EXIT=$(cat "${_ANSWER}")
    #shellcheck disable=SC2086
    _dialog  --title " Internet Browser " --menu "" 8 40 4 \
    "chromium" "Browser From Google" \
    "firefox" "Browser From Mozilla" 2>${_ANSWER} || return 1
    _BROWSER="$(cat ${_ANSWER})"
    sd "STANDARD_BROWSER=.*" "STANDARD_BROWSER=${_BROWSER}" /etc/archboot/defaults
    source /etc/locale.conf
    clear
    update -${_EXIT} || exit 1
    exit 0
}

_manage() {
    _dialog  --title " Manage Archboot Menu " --menu "" 9 50 5 "${_MANAGE[@]}" 2>"${_ANSWER}" || return 1
    clear
    [[ -e /.launcher-running ]] && rm /.launcher-running
    _EXIT=$(cat "${_ANSWER}")
    if [[ "${_EXIT}" == "FULL" ]]; then
        update -full-system
    elif [[ "${_EXIT}" == "UPDATE" ]]; then
        _run_update_environment
    elif [[ "${_EXIT}" == "IMAGE" ]]; then
        update -latest-image
    fi
    exit 0
}

_exit() {
    #shellcheck disable=SC2086
    _dialog  --title " Exit Menu " --menu "" 9 30 5 \
    "1" "Exit Program" \
    "2" "Reboot System" \
    "3" "Poweroff System" 2>${_ANSWER} || return 1
        _EXIT=$(cat "${_ANSWER}")
    if [[ "${_EXIT}" == "1" ]]; then
        [[ -e /.launcher-running ]] && rm /.launcher-running
        _show_login
        exit 0
    elif [[ "${_EXIT}" == "2" ]]; then
        _COUNT=0
        while true; do
            sleep 1
            _COUNT=$((_COUNT+1))
            # abort after 10 seconds
            _progress "$((_COUNT*10))" "Rebooting in $((10-_COUNT)) second(s). Don't forget to remove the boot medium!"
            [[ "${_COUNT}" == 10 ]] && break
        done | _dialog --title " System Reboot " --no-mouse --gauge "Rebooting in 10 seconds. Don't forget to remove the boot medium!" 6 75 0
        reboot
    elif [[ "${_EXIT}" == "3" ]]; then
        _COUNT=0
        while true; do
            sleep 1
            _COUNT=$((_COUNT+1))
            # abort after 10 seconds
            _progress "$((_COUNT*10))" "Powering off in $((10-_COUNT)) second(s). Don't forget to remove the boot medium!"
            [[ "${_COUNT}" == 10 ]] && break
        done | _dialog --title " System Shutdown " --no-mouse --gauge "Powering off in 10 seconds. Don't forget to remove the boot medium!" 6 75 0
        poweroff
    fi
}

_launcher() {
    _MENU=()
    if [[ -n "${_DESKTOP[*]}" ]]; then
        _MENU+=( "2" "Launch Desktop Environment" )
    fi
    if [[ -n "${_MANAGE[*]}" ]]; then
        _MENU+=( "3" "Manage Archboot Environment" )
    fi
    _dialog  --default-item "${_DEFAULTITEM}" --cancel-label "${_LABEL}" --title " Launcher Menu " --menu "" 9 40 5 \
    "1" "Launch Archboot Setup" "${_MENU[@]}" 2>"${_ANSWER}"
    case $(cat "${_ANSWER}") in
        "1") [[ -e /.launcher-running ]] && rm /.launcher-running
             setup
             exit 0 ;;
        "2") _DEFAULTITEM=2
             _desktop ;;
        "3") _DEFAULTITEM=3
             _manage ;;
        *) _exit ;;
    esac
}

_check
_DEFAULTITEM=1
while true; do
    _check_desktop
    _check_manage
    _launcher
done
# vim: set ts=4 sw=4 et:
