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
        for i in $(btrfs filesystem show "${_DEV}" | rg -o ' (/dev/.*)' -r '$1'); do
            _BTRFS_DEVS="${_BTRFS_DEVS}#${i}"
        done
    fi
}

_find_btrfsraid_bootloader_devices() {
    _btrfs_scan
    _BTRFS_COUNT=1
    if [[ "$(${_LSBLK} FSTYPE "${_BOOTDEV}")" == "btrfs" ]]; then
        _BTRFS_DEVS=""
        for i in $(btrfs filesystem show "${_BOOTDEV}" | rg -o ' (/dev/.*)' -r '$1'); do
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
        for i in $(btrfs subvolume list "${_BTRFSMP}" | choose 8 | rg -v 'var/lib/machines|var/lib/portables'); do
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
        for i in $(btrfs subvolume list "${_BTRFSMP}" | choose 7); do
            _BTRFS_SUBVOLUMES="${_BTRFS_SUBVOLUMES}#${i}"
        done
        _umount_btrfs
    fi
}

# subvolumes already in use
_subvolumes_in_use() {
    _SUBVOLUME_IN_USE=""
    while read -r i; do
        echo "${i}" | rg -F -q "|btrfs|" && _SUBVOLUME_IN_USE="${_SUBVOLUME_IN_USE} $(echo "${i}" | choose -f '\|' 8)"
    done < /tmp/.parts
}

# do not ask for btrfs filesystem creation, if already prepared for creation!
_check_btrfs_filesystem_creation() {
    _DETECT_CREATE_FILESYSTEM=""
    _SKIP_FILESYSTEM=""
    #shellcheck disable=SC2013
    for i in $(rg "${_DEV}[|#]" /tmp/.parts); do
        if echo "${i}" | rg -F -q "|btrfs|"; then
            _FSTYPE="btrfs"
            _SKIP_FILESYSTEM=1
            # check on filesystem creation, skip subvolume asking then!
            echo "${i}" | choose -f '\|' 3 | rg -q 1 && _DETECT_CREATE_FILESYSTEM=1
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
             [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]] && _DEVS="${_DEVS//${i} _/}"
         done < /tmp/.btrfs-devices
     else
         [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]] && _DEVS="${_DEVS//${_DEV} _/}"
     fi
}

# choose raid level to use on btrfs device
_btrfsraid_level() {
    _BTRFS_RAID_FINISH=""
    _BTRFS_LEVEL=""
    : >/tmp/.btrfs-devices
    while [[ "${_BTRFS_RAID_FINISH}" != "DONE" ]]; do
        #shellcheck disable=SC2086
        _dialog --no-cancel --title " Raid Data Level " --menu "" 13 50 7 \
            "> NONE" "No Raid Device" \
            "single" "Single Device" \
            "raid1" "Raid 1 Device, 2 copies" \
            "raid1c3" "Raid 1 Device, 3 copies" \
            "raid1c4" "Raid 1 Device, 4 copies" \
            "raid10" "Raid 10 Device" 2>"${_ANSWER}" || return 1
        _BTRFS_LEVEL=$(cat "${_ANSWER}")
        if [[ "${_BTRFS_LEVEL}" == "> NONE" ]]; then
            _BTRFS_LEVEL="NONE"
            echo "${_DEV}" >>/tmp/.btrfs-devices
            break
        else
            # take selected device as 1st device, add additional devices in part below.
            _select_btrfsraid_devices
        fi
    done
}

# select btrfs raid devices
_select_btrfsraid_devices () {
    while true; do
        _BTRFS_DEV="${_DEV}"
        # select the second device to use, no missing option available!
        : >/tmp/.btrfs-devices
        echo "${_BTRFS_DEV}" >>/tmp/.btrfs-devices
        _BTRFS_DEVS=""
        #shellcheck disable=SC2001,SC2086
        for i in ${_DEVS}; do
            echo "${i}" | rg -q '/dev' && _BTRFS_DEVS="${_BTRFS_DEVS} ${i} _ "
        done
        _BTRFS_DEVS=${_BTRFS_DEVS//${_BTRFS_DEV} _/}
        _RAIDNUMBER=2
        #shellcheck disable=SC2086
        _dialog --title " Select Device ${_RAIDNUMBER} " --no-cancel --menu "" 12 50 6 ${_BTRFS_DEVS} 2>"${_ANSWER}" || return 1
        _BTRFS_DEV=$(cat "${_ANSWER}")
        echo "${_BTRFS_DEV}" >>/tmp/.btrfs-devices
        while true; do
            _BTRFS_DONE=""
            _RAIDNUMBER=$((_RAIDNUMBER + 1))
            # clean loop from used partition and options
            _BTRFS_DEVS=${_BTRFS_DEVS//${_BTRFS_DEV} _/}
            # add more devices
            # raid1c3 and RAID5 need 3 devices
            # raid1c4, RAID6 and RAID10 need 4 devices!
            if [[ "${_RAIDNUMBER}" -ge 3 && ! "${_BTRFS_LEVEL}" == raid1c[3,4] && ! "${_BTRFS_LEVEL}" == raid[5,6] && ! "${_BTRFS_LEVEL}" == "raid10" ]] ||\
                [[ "${_RAIDNUMBER}" -ge 4 && "${_BTRFS_LEVEL}" == "raid5" ]] || [[ "${_RAIDNUMBER}" -ge 4 && "${_BTRFS_LEVEL}" == "raid1c3" ]] ||\
                [[ "${_RAIDNUMBER}" -ge 5 && "${_BTRFS_LEVEL}" == "raid6" ]] || [[ "${_RAIDNUMBER}" -ge 5 && "${_BTRFS_LEVEL}" == raid1? ]]; then
                    #shellcheck disable=SC2086
                    _dialog --title " Device ${_RAIDNUMBER} " --no-cancel --menu "" 12 50 6 \
                        ${_BTRFS_DEVS} "> DONE" "Proceed To Summary" 2>"${_ANSWER}" || return 1
            else
                #shellcheck disable=SC2086
                _dialog --title " Device ${_RAIDNUMBER} " --no-cancel --menu "" 12 50 6 \
                    ${_BTRFS_DEVS} 2>"${_ANSWER}" || return 1
            fi
            _BTRFS_DEV=$(cat "${_ANSWER}")
            [[ "${_BTRFS_DEV}" == "> DONE" ]] && break
            echo "${_BTRFS_DEV}" >>/tmp/.btrfs-devices
        done
        # final step ask if everything is ok?
        #shellcheck disable=SC2028
        _dialog --title " Summary " --yesno "LEVEL:\n${_BTRFS_LEVEL}\n\nDEVICES:\n$(while read -r i; do echo "${i}\n"; done </tmp/.btrfs-devices)" 0 0 && break
    done
    _BTRFS_RAID_FINISH="DONE"
     while read -r i; do
        # cleanup _DEVS array from used devices
        _DEVS="${_DEVS//$(${_LSBLK} NAME,SIZE -d "${i}" 2>"${_NO_LOG}")/}"
     done </tmp/.btrfs-devices
}

# prepare new btrfs device
_prepare_btrfs() {
    _btrfsraid_level || return 1
    _prepare_btrfs_subvolume || return 1
}

# prepare btrfs subvolume
_prepare_btrfs_subvolume() {
    _BTRFS_SUBVOLUME=""
    while [[ -z "${_BTRFS_SUBVOLUME}" ]]; do
        _dialog --title " Subvolume Name on ${_DEV} " --no-cancel --inputbox "Keep it short and use no spaces or special characters." 8 60 2>"${_ANSWER}" || return 1
        _BTRFS_SUBVOLUME=$(cat "${_ANSWER}")
        [[ -n "${_BTRFS_SUBVOLUME}" ]] && _check_btrfs_subvolume
    done
    _btrfs_compress || return 1
}

# check btrfs subvolume
_check_btrfs_subvolume(){
    [[ -n "${_DOMKFS}" && "${_FSTYPE}" == "btrfs" ]] && _DETECT_CREATE_FILESYSTEM=1
    if [[ -z "${_DETECT_CREATE_FILESYSTEM}" && -z "${_CREATE_MOUNTPOINTS}" ]]; then
        _mount_btrfs
        for i in $(btrfs subvolume list "${_BTRFSMP}" | choose 8); do
            if echo "${i}" | rg -q "${_BTRFS_SUBVOLUME}"; then
                _dialog --title " ERROR " --no-mouse --infobox "You have defined 2 identical SUBVOLUMES!\nPlease enter another name." 4 45
                sleep 3
                _BTRFS_SUBVOLUME=""
            fi
        done
        _umount_btrfs
    else
        # existing subvolumes
        _subvolumes_in_use
        if echo "${_SUBVOLUME_IN_USE}" | rg -q "${_BTRFS_SUBVOLUME}"; then
            _dialog --title " ERROR " --no-mouse --infobox "You have defined 2 identical SUBVOLUMES!\nPlease enter another name." 4 45
            sleep 3
            _BTRFS_SUBVOLUME=""
        fi
    fi
}

# create btrfs subvolume
_create_btrfs_subvolume() {
    _mount_btrfs
    if ! btrfs subvolume list "${_BTRFSMP}" | rg -q "${_BTRFS_SUBVOLUME}$"; then
        btrfs subvolume create "${_BTRFSMP}"/"${_BTRFS_SUBVOLUME}" &>"${_LOG}"
    fi
    _umount_btrfs
}

# choose btrfs subvolume from list
_choose_btrfs_subvolume () {
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
    # clear end spaces
    _SUBVOLUMES="$(echo "${_SUBVOLUMES}" | sd ' +$' '')"
    if [[ -n "${_SUBVOLUMES}" ]]; then
        #shellcheck disable=SC2086
        _dialog --title " Subvolume " --no-cancel --menu "" 15 50 13 ${_SUBVOLUMES} 2>"${_ANSWER}" || return 1
        _BTRFS_SUBVOLUME=$(cat "${_ANSWER}")
        _btrfs_compress || return 1
    else
        if [[ -n "${_SUBVOLUMES_DETECTED}" ]]; then
            _dialog --title " ERROR " --no-mouse --infobox "All subvolumes of the device are already in use.\nSwitching to create a new subvolume..." 4 60
            sleep 3
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
    #shellcheck disable=SC2086
    _dialog --no-cancel --title " ${_DEV} subvolume=${_BTRFS_SUBVOLUME} " --menu "" 10 50 4 \
    "zstd" "Use ZSTD Compression" \
    "lzo" "Use LZO Compression" \
    "zlib" "Use ZLIB Compression" \
    "> NONE" "No Compression" \
    2>"${_ANSWER}" || return 1
    if [[ "$(cat "${_ANSWER}")" == "> NONE" ]]; then
        _BTRFS_COMPRESS="NONE"
    else
        _BTRFS_COMPRESS="compress=$(cat "${_ANSWER}")"
    fi
}
