#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_create_raid_menu() {
    _NEXTITEM=""
    _MDDONE=""
    while [[ -z "${_MDDONE}" ]]; do
        if [[ -n "${_NEXTITEM}" ]]; then
            _DEFAULT=(--default-item "${_NEXTITEM}")
        else
            _DEFAULT=()
        fi
        _CANCEL=""
        _dialog --title " Manage Software Raid " --no-cancel "${_DEFAULT[@]}" --menu "" 11 60 5 \
            "1" "Create Software Raid" \
            "2" "Create Partitionable Software Raid" \
            "3" "Reset Software Raid" \
            "4" "Raid Help" \
            "<" "Return To Previous Menu" 2>"${_ANSWER}" || _CANCEL=1
        _NEXTITEM="$(cat "${_ANSWER}")"
        case $(cat "${_ANSWER}") in
            "1") _RAID_PARTITION=""
                 _createmd ;;
            "2") _RAID_PARTITION=1
                 _createmd ;;
            "3") _stopmd ;;
            "4") _helpmd ;;
              *) _MDDONE=1 ;;
        esac
    done
    _NEXTITEM=1
}

_create_lvm_menu() {
    _NEXTITEM=""
    _LVMDONE=""
    while [[ -z "${_LVMDONE}" ]]; do
        if [[ -n "${_NEXTITEM}" ]]; then
            _DEFAULT=(--default-item "${_NEXTITEM}")
        else
            _DEFAULT=()
        fi
        _CANCEL=""
        _dialog --title " Manage Physical Volume, Volume Group Or Logical Volume " --no-cancel "${_DEFAULT[@]}" --menu "" 12 60 6 \
            "1" "Create Physical Volume" \
            "2" "Create Volume Group" \
            "3" "Create Logical Volume" \
            "4" "Reset Logical Volume" \
            "5" "LVM Help" \
            "<" "Return To Previous Menu" 2>"${_ANSWER}" || _CANCEL=1
        _NEXTITEM="$(cat "${_ANSWER}")"
        case $(cat "${_ANSWER}") in
            "1") _createpv ;;
            "2") _createvg ;;
            "3") _createlv ;;
            "4") _stoplvm ;;
            "5") _helplvm ;;
              *) _LVMDONE=1 ;;
        esac
    done
    _NEXTITEM=2
}

_create_luks_menu() {
    _NEXTITEM=""
    _LUKSDONE=""
    while [[ -z "${_LUKSDONE}" ]]; do
        if [[ -n "${_NEXTITEM}" ]]; then
            _DEFAULT=(--default-item "${_NEXTITEM}")
        else
            _DEFAULT=()
        fi
        _CANCEL=""
        _dialog --title " Manage Luks Encryption " --no-cancel "${_DEFAULT[@]}" --menu "" 10 60 4 \
            "1" "Create Luks" \
            "2" "Reset Luks Encryption" \
            "3" "Luks Help" \
            "<" "Return To Previous Menu" 2>"${_ANSWER}" || _CANCEL=1
        _NEXTITEM="$(cat "${_ANSWER}")"
        case $(cat "${_ANSWER}") in
            "1") _createluks ;;
            "2") _stopluks ;;
            "3") _helpluks ;;
              *) _LUKSDONE=1 ;;
        esac
    done
    _NEXTITEM=3
}

_create_special() {
    _NEXTITEM=""
    _SPECIALDONE=""
    while [[ -z "${_SPECIALDONE}" ]]; do
        if [[ -n "${_NEXTITEM}" ]]; then
            _DEFAULT=(--default-item "${_NEXTITEM}")
        else
            _DEFAULT=()
        fi
        _CANCEL=""
        _dialog --title " Manage Software Raid, LVM2 And LUKS Encryption " --no-cancel "${_DEFAULT[@]}" --menu "" 10 60 4 \
            "1" "Manage Software Raid" \
            "2" "Manage Logical Volume Manager" \
            "3" "Manage LUKS Encryption" \
            "<" "Return To Previous Menu" 2>"${_ANSWER}" || _CANCEL=1
        _NEXTITEM="$(cat "${_ANSWER}")"
        case $(cat "${_ANSWER}") in
            "1") _create_raid_menu ;;
            "2") _create_lvm_menu ;;
            "3") _create_luks_menu ;;
              *) _SPECIALDONE=1 ;;
        esac
    done
    if [[ -n "${_CANCEL}" ]]; then
        _NEXTITEM=3
    else
        _NEXTITEM=4
    fi
}
