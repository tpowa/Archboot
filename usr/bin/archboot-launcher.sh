#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# written by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.launcher"
_RUNNING_ARCH="$(uname -m)"
_TITLE="Archboot ${_RUNNING_ARCH} | Arch Linux Setup | Launcher"
# _dialog()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dialog() {
    dialog --backtitle "${_TITLE}" --aspect 15 "$@"
    return $?
}

_dolauncher() {
    _dialog --title " Main Menu " --menu "" 10 40 6 \
    "1" "Launch Archboot Setup" \
    "2" "Launch Desktop Environment" \
    "3" "Manage Archboot Environment" \
    "4" "Exit Program" 2>${_ANSWER}
    case $(cat ${_ANSWER}) in
        "1")
            [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
            setup
            exit 0 ;;
        "2")
            _LAUNCHER=()
            update | grep -q Gnome && _LAUNCHER+=( "GNOME" "Gnome - Simple Beautiful Elegant" )
            update | grep -q KDE && _LAUNCHER+=( "PLASMA" "KDE/Plasma - Simple By Default" )
            update | grep -q Sway && _LAUNCHER+=( "SWAY" "Sway - Tiling Wayland Compositor" )
            update | grep -q Xfce && _LAUNCHER+=( "XFCE" "Xfce - Leightweight Desktop" )
            _ABORT=""
            if [[ -n "${_LAUNCHER[@]}" ]]; then
                _dialog --title " Desktop Menu " --menu "" 10 50 6 "${_LAUNCHER[@]}" 2>${_ANSWER} || _ABORT=1
            else
                _dialog --msgbox "Error:\nNo Desktop Environments available." 0 0
                _ABORT=1
            fi
            [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
            if [[ -n "${_ABORT}"  ]]; then
                clear
                exit 1
            fi
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
            ;;
        "3")
            _LAUNCHER=()
            update | grep -q full && _LAUNCHER+=( "FULL" "Switch To Full Arch Linux System" )
            update | grep -q latest && _LAUNCHER+=( "UPDATE" "Update Archboot Environment" )
            update | grep -q image && _LAUNCHER+=( "IMAGE" "Create New Images" )
            _ABORT=""
            if [[ -n "${_LAUNCHER[@]}" ]]; then
                _dialog --title " Manage Archboot Menu " --menu "" 9 60 5 "${_LAUNCHER[@]}" 2>${_ANSWER} || _ABORT=1
            else
                _dialog --msgbox "Error:\nNo management options available." 0 0
                _ABORT=1
            fi
            clear
            [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
            if [[ -n "${_ABORT}"  ]]; then
                exit 1
            fi
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
            ;;
        "4")
            #shellcheck disable=SC2086
            _dialog --title " EXIT MENU " --menu "" 9 30 5 \
            "1" "Exit Program" \
            "2" "Reboot System" \
            "3" "Poweroff System" 2>${_ANSWER}
            _EXIT="$(cat ${_ANSWER})"
            if [[ "${_EXIT}" == "1" ]]; then
                return 0
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
            ;;
        *)
            if _dialog --yesno "Abort Program?" 6 40; then
                return 1
            fi
            ;;
    esac
}

if [[ -e /tmp/.launcher-running ]]; then
    echo "launcher already runs on a different console!"
    echo "Please remove /tmp/.launcher-running first to launch launcher!"
    exit 1
fi
: >/tmp/.launcher
: >/tmp/.launcher-running
if ! _dolauncher; then
    [[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
    clear
    exit 1
fi
[[ -e /tmp/.launcher-running ]] && rm /tmp/.launcher-running
clear
# show like normal login
echo ""
agetty --show-issue
echo ""
cat /etc/motd
exit 0
# vim: set ts=4 sw=4 et:
