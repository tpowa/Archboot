#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
_TITLE="Archboot ${_RUNNING_ARCH} | Basic Setup | Launcher"
. /usr/lib/archboot/basic-common.sh

_show_login() {
    [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
    clear
    echo ""
    agetty --show-issue
    echo ""
    cat /etc/motd
}

_check_desktop() {
    _DESKTOP=()
    update | grep -q Gnome && _DESKTOP+=( "GNOME" "Simple Beautiful Elegant" )
    update | grep -q KDE && _DESKTOP+=( "PLASMA" "Simple By Default" )
    update | grep -q Sway && _DESKTOP+=( "SWAY" "Tiling Wayland Compositor" )
    update | grep -q Xfce && _DESKTOP+=( "XFCE" "Leightweight Desktop" )
}

_check_manage() {
    _MANAGE=()
    update | grep -q full && _MANAGE+=( "FULL" "Switch To Full Arch Linux System" )
    update | grep -q latest && _MANAGE+=( "UPDATE" "Update Archboot Environment" )
    update | grep -q image && _MANAGE+=( "IMAGE" "Create New Archboot Images" )
}

_desktop () {
    _dialog --cancel-label "Back" --title " Desktop Menu " --menu "" 10 40 6 "${_DESKTOP[@]}" 2>${_ANSWER} || return 1
    [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
    _EXIT="$(cat ${_ANSWER})"
    if [[ "${_EXIT}" == "GNOME" ]]; then
        if _dialog --defaultno --yesno "Gnome Desktop:\nDo you want to use the Wayland Backend?" 6 45; then
            clear
            update -gnome-wayland
        else
            clear
            update -gnome
        fi
    elif [[ "${_EXIT}" == "PLASMA" ]]; then
        if _dialog --defaultno --yesno "KDE/Plasma Desktop:\nDo you want to use the Wayland Backend?" 6 45; then
            clear
            update -plasma-wayland
        else
            clear
            update -plasma
        fi
    elif [[ "${_EXIT}" == "SWAY" ]]; then
        clear
        update -sway
    elif [[ "${_EXIT}" == "XFCE" ]]; then
        clear
        update -xfce
    fi
    exit 0
}

_manage() {
    _dialog --cancel-label "Back" --title " Manage Archboot Menu " --menu "" 9 50 5 "${_MANAGE[@]}" 2>${_ANSWER} || return 1
    clear
    [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
    _EXIT="$(cat ${_ANSWER})"
    if [[ "${_EXIT}" == "FULL" ]]; then
        update -full-system
    elif [[ "${_EXIT}" == "UPDATE" ]]; then
        if update | grep -q latest-install; then
            update -latest-install
        else
            update -latest
        fi
    elif [[ "${_EXIT}" == "IMAGE" ]]; then
        update -latest-image
    fi
    exit 0
}

_exit() {
    #shellcheck disable=SC2086
    _dialog --cancel-label "Back" --title " Exit Menu " --menu "" 9 30 5 \
    "1" "Exit Program" \
    "2" "Reboot System" \
    "3" "Poweroff System" 2>${_ANSWER} || return 1
        _EXIT="$(cat ${_ANSWER})"
    if [[ "${_EXIT}" == "1" ]]; then
        [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
        _show_login
        exit 0
    elif [[ "${_EXIT}" == "2" ]]; then
        _dialog --infobox "Rebooting in 10 seconds...\nDon't forget to remove the boot medium!" 4 50
        sleep 10
        clear
        reboot
    elif [[ "${_EXIT}" == "3" ]]; then
        _dialog --infobox "Powering off in 10 seconds...\nDon't forget to remove the boot medium!" 4 50
        sleep 10
        clear
        poweroff
    fi
}

_launcher() {
    _MENU=()
    if [[ -n "${_DESKTOP[@]}" ]]; then
        _MENU+=( "2" "Launch Desktop Environment" )
    fi
    if [[ -n "${_MANAGE[@]}" ]]; then
        _MENU+=( "3" "Manage Archboot Environment" )
    fi
    _dialog --cancel-label "Exit" --title " Main Menu " --menu "" 9 40 5 \
    "1" "Launch Archboot Setup" "${_MENU[@]}" 2>${_ANSWER}
    case $(cat ${_ANSWER}) in
        "1")
            [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
            setup
            exit 0 ;;
        "2")
            _desktop
            ;;
        "3")
            _manage
            ;;
        *)
            _exit
            ;;
    esac
}

_check
while true; do
    _check_desktop
    _check_manage
    _launcher
done
# vim: set ts=4 sw=4 et:
