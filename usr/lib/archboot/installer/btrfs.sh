#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# scan and update btrfs devices
_btrfs_scan() {
    btrfs device scan >/dev/null 2>&1
}

# mount btrfs for checks
_mount_btrfs() {
    _btrfs_scan
    _BTRFSMP="$(mktemp -d /tmp/brtfsmp.XXXX)"
    mount "${_PART}" "${_BTRFSMP}"
}

# unmount btrfs after checks done
_umount_btrfs() {
    umount "${_BTRFSMP}"
    rm -r "${_BTRFSMP}"
}

# Set _BTRFS_DEVICES on detected btrfs devices
_find_btrfs_raid_devices() {
    _btrfs_scan
    if [[ -z "${_DETECT_CREATE_FILESYSTEM}" && "${_FSTYPE}" == "btrfs" ]]; then
        for i in $(btrfs filesystem show "${_PART}" | cut -d " " -f 11); do
            _BTRFS_DEVICES="${_BTRFS_DEVICES}#${i}"
        done
    fi
}

_find_btrfs_raid_bootloader_devices() {
    _btrfs_scan
    _BTRFS_COUNT=1
    if [[ "$(${_LSBLK} FSTYPE "${_BOOTDEV}")" == "btrfs" ]]; then
        _BTRFS_DEVICES=""
        for i in $(btrfs filesystem show "${_BOOTDEV}" | cut -d " " -f 11); do
            _BTRFS_DEVICES="${_BTRFS_DEVICES}#${i}"
            _BTRFS_COUNT=$((_BTRFS_COUNT+1))
        done
    fi
}

# find btrfs subvolume
_find_btrfs_subvolume() {
    if [[ -z "${_DETECT_CREATE_FILESYSTEM}" ]]; then
        # existing btrfs subvolumes
        _mount_btrfs
        for i in $(btrfs subvolume list "${_BTRFSMP}" | cut -d " " -f 9 | grep -v 'var/lib/machines' | grep -v '/var/lib/portables'); do
            echo "${i}"
            [[ "${1}" ]] && echo "${1}"
        done
        _umount_btrfs
    fi
}

_find_btrfs_bootloader_subvolume() {
    if [[ "$(${_LSBLK} FSTYPE "${_BOOTDEV}")" == "btrfs" ]]; then
        _BTRFS_SUBVOLUMES=""
        _PART="${_BOOTDEV}"
        _mount_btrfs
        for i in $(btrfs subvolume list "${_BTRFSMP}" | cut -d " " -f 7); do
            _BTRFS_SUBVOLUMES="${_BTRFS_SUBVOLUMES}#${i}"
        done
        _umount_btrfs
    fi
}

# subvolumes already in use
_subvolumes_in_use() {
    _SUBVOLUME_IN_USE=""
    while read -r i; do
        echo "${i}" | grep -q ":btrfs:" && _SUBVOLUME_IN_USE="${_SUBVOLUME_IN_USE} $(echo "${i}" | cut -d: -f 9)"
    done < /tmp/.parts
}

# do not ask for btrfs filesystem creation, if already prepared for creation!
_check_btrfs_filesystem_creation() {
    _DETECT_CREATE_FILESYSTEM=""
    _SKIP_FILESYSTEM=""
    _SKIP_ASK_SUBVOLUME=""
    #shellcheck disable=SC2013
    for i in $(grep "${_PART}[:#]" /tmp/.parts); do
        if echo "${i}" | grep -q ":btrfs:"; then
            _FSTYPE="btrfs"
            _SKIP_FILESYSTEM=1
            # check on filesystem creation, skip subvolume asking then!
            echo "${i}" | cut -d: -f 4 | grep -q yes && _DETECT_CREATE_FILESYSTEM=1
            [[ -n "${_DETECT_CREATE_FILESYSTEM}" ]] && _SKIP_ASK_SUBVOLUME=1
        fi
    done
}

# remove devices with no subvolume from list and generate raid device list
_btrfs_parts() {
     if [[ -s /tmp/.btrfs-devices ]]; then
         _BTRFS_DEVICES=""
         while read -r i; do
             _BTRFS_DEVICES="${_BTRFS_DEVICES}#${i}"
             # remove device if no subvolume is used!
             [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]] && _PARTS="${_PARTS//${i}\ _/}"
         done < /tmp/.btrfs-devices
     else
         [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]] && _PARTS="${_PARTS//${_PART}\ _/}"
     fi
}

# choose raid level to use on btrfs device
_btrfs_raid_level() {
    _BTRFS_RAIDLEVELS="NONE - raid0 - raid1 - raid5 - raid6 - raid10 - single -"
    _BTRFS_RAID_FINISH=""
    _BTRFS_LEVEL=""
    _BTRFS_DEVICE="${_PART}"
    : >/tmp/.btrfs-devices
    while [[ "${_BTRFS_RAID_FINISH}" != "DONE" ]]; do
        #shellcheck disable=SC2086
        _dialog --menu "Select the raid data level you want to use:" 14 50 10 ${_BTRFS_RAIDLEVELS} 2>"${_ANSWER}" || return 1
        _BTRFS_LEVEL=$(cat "${_ANSWER}")
        if [[ "${_BTRFS_LEVEL}" == "NONE" ]]; then
            echo "${_BTRFS_DEVICE}" >>/tmp/.btrfs-devices
            break
        else
            if [[ "${_BTRFS_LEVEL}" == "raid5" || "${_BTRFS_LEVEL}" == "raid6" ]]; then
                _dialog --msgbox "BTRFS DATA RAID OPTIONS:\n\nRAID5/6 are for testing purpose. Use with extreme care!" 0 0
            fi
            # take selected device as 1st device, add additional devices in part below.
            _select_btrfs_raid_devices
        fi
    done
}

# select btrfs raid devices
_select_btrfs_raid_devices () {
    # select the second device to use, no missing option available!
    : >/tmp/.btrfs-devices
    echo "${_BTRFS_DEVICE}" >>/tmp/.btrfs-devices
    #shellcheck disable=SC2001,SC2086
    _BTRFS_PARTS=$(echo ${_PARTS} | sed -e "s#${_BTRFS_DEVICE}\ _##g")
    _RAIDNUMBER=2
    #shellcheck disable=SC2086
    _dialog --menu "Select device ${_RAIDNUMBER}:" 13 50 10 ${_BTRFS_PARTS} 2>"${_ANSWER}" || return 1
    _BTRFS_PART=$(cat "${_ANSWER}")
    echo "${_BTRFS_PART}" >>/tmp/.btrfs-devices
    while [[ "${_BTRFS_PART}" != "DONE" ]]; do
        _BTRFS_DONE=""
        _RAIDNUMBER=$((_RAIDNUMBER + 1))
        # RAID5 needs 3 devices
        # RAID6, RAID10 need 4 devices!
        [[ "${_RAIDNUMBER}" -ge 3 && ! "${_BTRFS_LEVEL}" == "raid10" && ! "${_BTRFS_LEVEL}" == "raid6" && ! "${_BTRFS_LEVEL}" == "raid5" ]] && _BTRFS_DONE="DONE _"
        [[ "${_RAIDNUMBER}" -ge 4 && "${_BTRFS_LEVEL}" == "raid5" ]] && _BTRFS_DONE="DONE _"
        [[ "${_RAIDNUMBER}" -ge 5 && "${_BTRFS_LEVEL}" == "raid10" || "${_BTRFS_LEVEL}" == "raid6" ]] && _BTRFS_DONE="DONE _"
        # clean loop from used partition and options
        #shellcheck disable=SC2001,SC2086
        _BTRFS_PARTS=$(echo ${_BTRFS_PARTS} | sed -e "s#${_BTRFS_PART}\ _##g")
        # add more devices
        #shellcheck disable=SC2086
        _dialog --menu "Select device ${_RAIDNUMBER}:" 13 50 10 ${_BTRFS_PARTS} ${_BTRFS_DONE} 2>"${_ANSWER}" || return 1
        _BTRFS_PART=$(cat "${_ANSWER}")
        [[ "${_BTRFS_PART}" == "DONE" ]] && break
        echo "${_BTRFS_PART}" >>/tmp/.btrfs-devices
     done
     # final step ask if everything is ok?
     #shellcheck disable=SC2028
     _dialog --yesno "Would you like to create btrfs raid data like this?\n\nLEVEL:\n${_BTRFS_LEVEL}\n\nDEVICES:\n$(while read -r i; do echo "${i}\n"; done </tmp/.btrfs-devices)" 0 0 && _BTRFS_RAID_FINISH="DONE"
}

# prepare new btrfs device
_prepare_btrfs() {
    _btrfs_raid_level || return 1
    _prepare_btrfs_subvolume || return 1
}

# prepare btrfs subvolume
_prepare_btrfs_subvolume() {
    _BTRFS_SUBVOLUME="NONE"
    while [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]]; do
        _DOSUBVOLUME=""
        _dialog --inputbox "Enter the SUBVOLUME name on ${_PART}, keep it short\nand use no spaces or special ncharacters." 9 60 2>"${_ANSWER}" || return 1
        _BTRFS_SUBVOLUME=$(cat "${_ANSWER}")
        _check_btrfs_subvolume
        _DOSUBVOLUME=1
    done
}

# check btrfs subvolume
_check_btrfs_subvolume(){
    [[ -n "${_DOMKFS}" && "${_FSTYPE}" == "btrfs" ]] && _DETECT_CREATE_FILESYSTEM=1
    if [[ -z "$(cat "${_ANSWER}")" ]]; then
        _dialog --msgbox "ERROR: You have defined an empty name!\nPlease enter another name." 6 50
        _BTRFS_SUBVOLUME="NONE"
    fi
    if [[ -z "${_DETECT_CREATE_FILESYSTEM}" && -z "${_ASK_MOUNTPOINTS}" ]]; then
        _mount_btrfs
        for i in $(btrfs subvolume list "${_BTRFSMP}" | cut -d " " -f 9); do
            if echo "${i}" | grep -q "${_BTRFS_SUBVOLUME}"; then
                _dialog --msgbox "ERROR: You have defined 2 identical SUBVOLUME names!\nPlease enter another name." 6 60
                _BTRFS_SUBVOLUME="NONE"
            fi
        done
        _umount_btrfs
    else
        # existing subvolumes
        _subvolumes_in_use
        if echo "${_SUBVOLUME_IN_USE}" | grep -Eq "${_BTRFS_SUBVOLUME}"; then
            _dialog --msgbox "ERROR: You have defined 2 identical SUBVOLUME names!\nPlease enter another name." 6 60
            _BTRFS_SUBVOLUME="NONE"
        fi
    fi
}

# create btrfs subvolume
_create_btrfs_subvolume() {
    _mount_btrfs
    btrfs subvolume create "${_BTRFSMP}"/"${_BTRFS_SUBVOLUME}" > "${_LOG}"
    # change permission from 700 to 755
    # to avoid warnings during package installation
    chmod 755 "${_BTRFSMP}"/"${_BTRFS_SUBVOLUME}"
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
    for i in ${_SUBVOLUME_IN_USE}; do
        #shellcheck disable=SC2001,SC2086
        _SUBVOLUMES="$(echo ${_SUBVOLUMES} | sed -e "s#${i} _##g")"
    done
    if [[ -n "${_SUBVOLUMES}" ]]; then
    #shellcheck disable=SC2086
        _dialog --menu "Select the subvolume to mount:" 15 50 13 ${_SUBVOLUMES} 2>"${_ANSWER}" || return 1
        _BTRFS_SUBVOLUME=$(cat "${_ANSWER}")
    else
        if [[ -n "${_SUBVOLUMES_DETECTED}" ]]; then
            _dialog --msgbox "ERROR: All subvolumes of the device are already in use. Switching to create a new one now." 8 65
            _SKIP_ASK_SUBVOLUME=1
            _prepare_btrfs_subvolume || return 1
        fi
    fi
}

# btrfs subvolume menu
_btrfs_subvolume() {
    _FILESYSTEM_FINISH=""
    if [[ "${_FSTYPE}" == "btrfs" && -n "${_SKIP_FILESYSTEM}" && -z "${_ASK_MOUNTPOINTS}" ]]; then
        _choose_btrfs_subvolume || return 1
    else
        _prepare_btrfs_subvolume || return 1
    fi
    _btrfs_compress || return 1
    _FILESYSTEM_FINISH=1
}

# ask for btrfs compress option
_btrfs_compress() {
    _BTRFS_COMPRESSLEVELS="zstd - lzo - zlib - NONE -"
    #shellcheck disable=SC2086
    _dialog --menu "Select the compression method you want to use:\nDevice -> ${_PART} subvolume=${_BTRFS_SUBVOLUME}" 12 50 10 ${_BTRFS_COMPRESSLEVELS} 2>"${_ANSWER}" || return 1
    if [[ "$(cat "${_ANSWER}")" == "NONE" ]]; then
        _BTRFS_COMPRESS="NONE"
    else
        _BTRFS_COMPRESS="compress=$(cat "${_ANSWER}")"
    fi
}
