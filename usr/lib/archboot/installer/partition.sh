#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_check_gpt() {
    _GUID_DETECTED=""
    [[ "$(${_LSBLK} PTTYPE -d "${_DISK}")" == "gpt" ]] && _GUID_DETECTED=1
    if [[ -z "${_GUID_DETECTED}" ]]; then
        _dialog --defaultno --yesno "Setup detected no GUID (gpt) partition table on ${_DISK}.\n\nDo you want to create a new GUID (gpt) table now on ${_DISK}?\n\n${_DISK} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 || return 1
        _clean_disk "${_DISK}"
        # create fresh GPT
        echo "label: gpt" | sfdisk --wipe always "${_DISK}" &>"${_LOG}"
        _RUN_CFDISK=1
        _GUID_DETECTED=1
    fi
    if [[ -n "${_GUID_DETECTED}" ]]; then
        if [[ -n "${_CHECK_BIOS_BOOT_GRUB}" ]]; then
            if ! ${_LSBLK} PARTTYPE "${_DISK}" | grep -q '21686148-6449-6E6F-744E-656564454649'; then
                _dialog --msgbox "Setup detected no BIOS BOOT PARTITION in ${_DISK}. Please create a >=1M BIOS BOOT PARTITION for grub BIOS GPT support." 0 0
                _RUN_CFDISK=1
            fi
        fi
    fi
    if [[ -n "${_RUN_CFDISK}" ]]; then
        _dialog --msgbox "$(cat /usr/lib/archboot/installer/help/guid-partition.txt)" 0 0
        clear
        cfdisk "${_DISK}"
        _RUN_CFDISK=""
    fi
}

_partition() {
    # stop special devices, else weird things can happen during partitioning
    _stopluks
    _stoplvm
    _stopmd
    _set_guid
    # Select disk to partition
    _DISKS=$(_finddisks)
    _DISK=""
    while true; do
        # Prompt the user with a list of known disks
        #shellcheck disable=SC2086
        _dialog --title " Partition Device " --no-cancel --menu "" 13 45 6 ${_DISKS} "> CUSTOM" "Custom Device" "< Back" "Return To Previous Menu" 2>"${_ANSWER}" || return 1
        _DISK=$(cat "${_ANSWER}")
        if [[ "${_DISK}" == "> CUSTOM" ]]; then
            _dialog --inputbox "Enter the full path to the device you wish to partition" 8 65 "/dev/sda" 2>"${_ANSWER}" || _DISK=""
            _DISK=$(cat "${_ANSWER}")
        fi
        # Leave our loop if the user is done partitioning
        [[ "${_DISK}" == "< Back" ]] && break
        _MSDOS_DETECTED=""
        if [[ -n "${_DISK}" ]]; then
            if [[ -n "${_GUIDPARAMETER}" ]]; then
                _CHECK_BIOS_BOOT_GRUB=""
                _RUN_CFDISK=1
                _check_gpt
            else
                [[ "$(${_LSBLK} PTTYPE -d "${_DISK}")" == "dos" ]] && _MSDOS_DETECTED=1
                if [[ -z "${_MSDOS_DETECTED}" ]]; then
                    _dialog --defaultno --yesno "Setup detected no MBR/BIOS partition table on ${_DISK}.\nDo you want to create a MBR/BIOS partition table now on ${_DISK}?\n\n${_DISK} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 || return 1
                    _clean_disk "${_DISK}"
                    echo "label: dos" | sfdisk --wipe always "${_DISK}" >"${_LOG}"
                fi
                # Partition disc
                _dialog --msgbox "$(cat /usr/lib/archboot/installer/help/mbr-partition.txt)" 0 0
                clear
                cfdisk "${_DISK}"
            fi
        fi
    done
    _NEXTITEM="3"
}
# vim: set ft=sh ts=4 sw=4 et:
