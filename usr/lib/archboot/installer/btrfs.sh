#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
# scan and update btrfs devices
_btrfs_scan() {
    btrfs device scan &>"${_NO_LOG}"
}

# mount btrfs for checks
_mount_btrfs() {
    _btrfs_scan
    _BTRFSMP="$(mktemp -d /tmp/btrfsmp.XXXX)"
    mount "${_DEV}" "${_BTRFSMP}"
}

# unmount btrfs after checks done
_umount_btrfs() {
    umount "${_BTRFSMP}"
    rm -r "${_BTRFSMP}"
}

# Set _BTRFS_DEVS on detected btrfs devices
_find_btrfsraid_devices() {
    _btrfs_scan
    if [[ -z "${_DETECT_CREATE_FILESYSTEM}" && "${_FSTYPE}" == "btrfs" ]]; then
        for i in $(btrfs filesystem show "${_DEV}" | cut -d ' ' -f 11); do
            _BTRFS_DEVS="${_BTRFS_DEVS}#${i}"
        done
    fi
}

_find_btrfsraid_bootloader_devices() {
    _btrfs_scan
    _BTRFS_COUNT=1
    if [[ "$(${_LSBLK} FSTYPE "${_BOOTDEV}")" == "btrfs" ]]; then
        _BTRFS_DEVS=""
        for i in $(btrfs filesystem show "${_BOOTDEV}" | cut -d ' ' -f 11); do
            _BTRFS_DEVS="${_BTRFS_DEVS}#${i}"
            _BTRFS_COUNT=$((_BTRFS_COUNT+1))
        done
    fi
}

# find btrfs subvolume
_find_btrfs_subvolume() {
    if [[ -z "${_DETECT_CREATE_FILESYSTEM}" ]]; then
        # existing btrfs subvolumes
        _mount_btrfs
        for i in $(btrfs subvolume list "${_BTRFSMP}" | cut -d ' ' -f 9 | grep -v 'var/lib/machines' | grep -v 'var/lib/portables'); do
            echo "${i}"
            [[ "${1}" ]] && echo "${1}"
        done
        _umount_btrfs
    fi
}

_find_btrfs_bootloader_subvolume() {
    if [[ "$(${_LSBLK} FSTYPE "${_BOOTDEV}")" == "btrfs" ]]; then
        _BTRFS_SUBVOLUMES=""
        _DEV="${_BOOTDEV}"
        _mount_btrfs
        for i in $(btrfs subvolume list "${_BTRFSMP}" | cut -d ' ' -f 7); do
            _BTRFS_SUBVOLUMES="${_BTRFS_SUBVOLUMES}#${i}"
        done
        _umount_btrfs
    fi
}

# subvolumes already in use
_subvolumes_in_use() {
    _SUBVOLUME_IN_USE=""
    while read -r i; do
        echo "${i}" | grep -q "|btrfs|" && _SUBVOLUME_IN_USE="${_SUBVOLUME_IN_USE} $(echo "${i}" | cut -d '|' -f 9)"
    done < /tmp/.parts
}

# do not ask for btrfs filesystem creation, if already prepared for creation!
_check_btrfs_filesystem_creation() {
    _DETECT_CREATE_FILESYSTEM=""
    _SKIP_FILESYSTEM=""
    #shellcheck disable=SC2013
    for i in $(grep "${_DEV}[|#]" /tmp/.parts); do
        if echo "${i}" | grep -q "|btrfs|"; then
            _FSTYPE="btrfs"
            _SKIP_FILESYSTEM=1
            # check on filesystem creation, skip subvolume asking then!
            echo "${i}" | cut -d '|' -f 4 | grep -q 1 && _DETECT_CREATE_FILESYSTEM=1
        fi
    done
}

# remove devices with no subvolume from list and generate raid device list
_btrfs_parts() {
     if [[ -s /tmp/.btrfs-devices ]]; then
         _BTRFS_DEVS=""
         while read -r i; do
             _BTRFS_DEVS="${_BTRFS_DEVS}#${i}"
             # remove device if no subvolume is used!
             [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]] && _DEVS="${_DEVS//${i}\ _/}"
         done < /tmp/.btrfs-devices
     else
         [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]] && _DEVS="${_DEVS//${_DEV}\ _/}"
     fi
}

# choose raid level to use on btrfs device
_btrfsraid_level() {
    _BTRFS_RAIDLEVELS="NONE - raid0 - raid1 - raid5 - raid6 - raid10 - single -"
    _BTRFS_RAID_FINISH=""
    _BTRFS_LEVEL=""
    _BTRFS_DEV="${_DEV}"
    : >/tmp/.btrfs-devices
    while [[ "${_BTRFS_RAID_FINISH}" != "DONE" ]]; do
        #shellcheck disable=SC2086
        _dialog --no-cancel --title " Raid Data Level  " --menu "" 13 50 7 ${_BTRFS_RAIDLEVELS} 2>"${_ANSWER}" || return 1
        _BTRFS_LEVEL=$(cat "${_ANSWER}")
        if [[ "${_BTRFS_LEVEL}" == "NONE" ]]; then
            echo "${_BTRFS_DEV}" >>/tmp/.btrfs-devices
            break
        else
            if [[ "${_BTRFS_LEVEL}" == "raid5" || "${_BTRFS_LEVEL}" == "raid6" ]]; then
                _dialog --no-mouse --infobox "BTRFS DATA RAID OPTIONS:\n\nRAID5/6 are for testing purpose. Use with extreme care!" 0 0
                sleep 5
            fi
            # take selected device as 1st device, add additional devices in part below.
            _select_btrfsraid_devices
        fi
    done
}

# select btrfs raid devices
_select_btrfsraid_devices () {
    # select the second device to use, no missing option available!
    : >/tmp/.btrfs-devices
    echo "${_BTRFS_DEV}" >>/tmp/.btrfs-devices
    _BTRFS_DEVS=""
    #shellcheck disable=SC2001,SC2086
    for i in ${_DEVS}; do
        echo "${i}" | grep -q /dev && _BTRFS_DEVS="${_BTRFS_DEVS} ${i} _ "
    done
    _BTRFS_DEVS=${_BTRFS_DEVS//${_BTRFS_DEV}\ _/}
    _RAIDNUMBER=2
    #shellcheck disable=SC2086
    _dialog --title " Device ${_RAIDNUMBER} " --no-cancel --menu "" 12 50 6 ${_BTRFS_DEVS} 2>"${_ANSWER}" || return 1
    _BTRFS_DEV=$(cat "${_ANSWER}")
    echo "${_BTRFS_DEV}" >>/tmp/.btrfs-devices
    while [[ "${_BTRFS_DEV}" != "DONE" ]]; do
        _BTRFS_DONE=""
        _RAIDNUMBER=$((_RAIDNUMBER + 1))
        # RAID5 needs 3 devices
        # RAID6, RAID10 need 4 devices!
        [[ "${_RAIDNUMBER}" -ge 3 && ! "${_BTRFS_LEVEL}" == "raid10" && ! "${_BTRFS_LEVEL}" == "raid6" && ! "${_BTRFS_LEVEL}" == "raid5" ]] && _BTRFS_DONE="DONE _"
        [[ "${_RAIDNUMBER}" -ge 4 && "${_BTRFS_LEVEL}" == "raid5" ]] && _BTRFS_DONE="DONE _"
        [[ "${_RAIDNUMBER}" -ge 5 && "${_BTRFS_LEVEL}" == "raid10" || "${_BTRFS_LEVEL}" == "raid6" ]] && _BTRFS_DONE="DONE _"
        # clean loop from used partition and options
        _BTRFS_DEVS=${_BTRFS_DEVS//${_BTRFS_DEV}\ _/}
        # add more devices
        #shellcheck disable=SC2086
        _dialog --title " Device  ${_RAIDNUMBER} " --no-cancel --menu "" 12 50 6 ${_BTRFS_DEVS} ${_BTRFS_DONE} 2>"${_ANSWER}" || return 1
        _BTRFS_DEV=$(cat "${_ANSWER}")
        [[ "${_BTRFS_DEV}" == "DONE" ]] && break
        echo "${_BTRFS_DEV}" >>/tmp/.btrfs-devices
     done
     # final step ask if everything is ok?
     #shellcheck disable=SC2028
     _dialog --title " Summary " --yesno "LEVEL:\n${_BTRFS_LEVEL}\n\nDEVICES:\n$(while read -r i; do echo "${i}\n"; done </tmp/.btrfs-devices)" 0 0 && _BTRFS_RAID_FINISH="DONE"
}

# prepare new btrfs device
_prepare_btrfs() {
    _btrfsraid_level || return 1
    _prepare_btrfs_subvolume || return 1
}

# prepare btrfs subvolume
_prepare_btrfs_subvolume() {
    _BTRFS_SUBVOLUME="NONE"
    while [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]]; do
        _dialog --title " Subvolume Name on ${_DEV} " --no-cancel --inputbox "Keep it short and use no spaces or special characters." 8 60 2>"${_ANSWER}" || return 1
        _BTRFS_SUBVOLUME=$(cat "${_ANSWER}")
        _check_btrfs_subvolume
    done
    _btrfs_compress || return 1
}

# check btrfs subvolume
_check_btrfs_subvolume(){
    [[ -n "${_DOMKFS}" && "${_FSTYPE}" == "btrfs" ]] && _DETECT_CREATE_FILESYSTEM=1
    if [[ -z "$(cat "${_ANSWER}")" ]]; then
        _dialog --title " ERROR " --no-mouse --infobox "You have defined an empty name! Please enter another name." 3 70
        sleep 3
        _BTRFS_SUBVOLUME="NONE"
    fi
    if [[ -z "${_DETECT_CREATE_FILESYSTEM}" && -z "${_CREATE_MOUNTPOINTS}" ]]; then
        _mount_btrfs
        for i in $(btrfs subvolume list "${_BTRFSMP}" | cut -d ' ' -f 9); do
            if echo "${i}" | grep -q "${_BTRFS_SUBVOLUME}"; then
                _dialog --title " ERROR " --no-mouse --infobox "You have defined 2 identical SUBVOLUMES! Please enter another name." 3 75
                sleep 3
                _BTRFS_SUBVOLUME="NONE"
            fi
        done
        _umount_btrfs
    else
        # existing subvolumes
        _subvolumes_in_use
        if echo "${_SUBVOLUME_IN_USE}" | grep -Eq "${_BTRFS_SUBVOLUME}"; then
            _dialog --title " ERROR " --no-mouse --infobox "You have defined 2 identical SUBVOLUMES! Please enter another name." 3 75
            sleep 3
            _BTRFS_SUBVOLUME="NONE"
        fi
    fi
}

# create btrfs subvolume
_create_btrfs_subvolume() {
    _mount_btrfs
    if ! btrfs subvolume list "${_BTRFSMP}" | grep -q "${_BTRFS_SUBVOLUME}$"; then
        btrfs subvolume create "${_BTRFSMP}"/"${_BTRFS_SUBVOLUME}" >"${_LOG}"
    fi
    _umount_btrfs
}

# choose btrfs subvolume from list
_choose_btrfs_subvolume () {
    _BTRFS_SUBVOLUME="NONE"
    _SUBVOLUMES_DETECTED=""
    _SUBVOLUMES=$(_find_btrfs_subvolume _)
    # check if subvolumes are present
    [[ -n "${_SUBVOLUMES}" ]] && _SUBVOLUMES_DETECTED=1
    _subvolumes_in_use
    # add echo to kill hidden escapes from btrfs call
    #shellcheck disable=SC2116,2086
    _SUBVOLUMES="$(echo ${_SUBVOLUMES})"
    for i in ${_SUBVOLUME_IN_USE}; do
        _SUBVOLUMES="${_SUBVOLUMES//${i} _/}"
    done
    if [[ -n "${_SUBVOLUMES}" ]]; then
        #shellcheck disable=SC2086
        _dialog --title " Subvolume " --no-cancel --menu "" 15 50 13 ${_SUBVOLUMES} 2>"${_ANSWER}" || return 1
        _BTRFS_SUBVOLUME=$(cat "${_ANSWER}")
        _btrfs_compress || return 1
    else
        if [[ -n "${_SUBVOLUMES_DETECTED}" ]]; then
            _dialog --title " ERROR " --no-mouse --infobox "All subvolumes of the device are already in use.\nSwitching to create a new one now." 4 50f
            sleep 5
            _prepare_btrfs_subvolume || return 1
        fi
    fi
}

# btrfs subvolume menu
_btrfs_subvolume() {
    if [[ "${_FSTYPE}" == "btrfs" && -z "${_CREATE_MOUNTPOINTS}" ]]; then
        _choose_btrfs_subvolume || return 1
    else
        if [[ -n "${_SKIP_FILESYSTEM}" && -z ${_DETECT_CREATE_FILESYSTEM}"" ]]; then
            _choose_btrfs_subvolume || return 1
        else
            _prepare_btrfs_subvolume || return 1
        fi
    fi
}

# ask for btrfs compress option
_btrfs_compress() {
    _BTRFS_COMPRESSLEVELS="zstd - lzo - zlib - NONE -"
    #shellcheck disable=SC2086
    _dialog --no-cancel --title " Compression on ${_DEV} subvolume=${_BTRFS_SUBVOLUME} " --menu "" 10 50 4 ${_BTRFS_COMPRESSLEVELS} 2>"${_ANSWER}" || return 1
    if [[ "$(cat "${_ANSWER}")" == "NONE" ]]; then
        _BTRFS_COMPRESS="NONE"
    else
        _BTRFS_COMPRESS="compress=$(cat "${_ANSWER}")"
    fi
}
# vim: set ft=sh ts=4 sw=4 et:
