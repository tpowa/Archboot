#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_bcfs_raid_options() {
    # add durability
    _DURABILITY=""
    _dialog --no-cancel --title " Durability " --menu "" 9 40 5 \
        "1" "Normal Device" \
        "0" "Cache Device" \
        "> CUSTOM" "Custom Durability" 2>"${_ANSWER}" || return 1
    _BCFS_DURABILITY=$(cat "${_ANSWER}")
    if [[ ${_BCFS_DURABILITY} == 1 ]]; then
        _DURABILITY=""
    elif [[ ${_BCFS_DURABILITY} == 0 ]]; then
        _DURABILITY="--durability=0"
        _DUR_COUNT=$((_DUR_COUNT - 1))
    else
        if [[ ${_BCFS_DURABILITY} == "> CUSTOM" ]]; then
            _dialog  --inputbox "Enter custom durability level (number):" 8 65 \
                "2" 2>"${_ANSWER}" || return 1
                _BCFS_DURABILITY="$(cat "${_ANSWER}")"
                _DURABILITY="--durability=${_BCFS_DURABILITY}"
        fi
        _DUR_COUNT=$((_DUR_COUNT + _BCFS_DURABILITY))
    fi
    if [[ "$(cat /sys/block/"$(basename "${_BCFS_DEV}")"/queue/rotational 2>"${_NO_LOG}")" == 0 ]]; then
        _BCFS_SSD_COUNT=$((_BCFS_SSD_COUNT + 1))
        _BCFS_LABEL="--label ssd.ssd${_BCFS_SSD_COUNT}"
        _BCFS_SSD_OPTIONS=1
    else
        _BCFS_HDD_COUNT=$((_BCFS_HDD_COUNT + 1))
        _BCFS_LABEL="--label hdd.hdd${_BCFS_HDD_COUNT}"
        _BCFS_HDD_OPTIONS=1
    fi
}

_bcfs_options() {
    if [[ -n ${_DURABILITY} ]]; then
        echo "${_DURABILITY} ${_BCFS_LABEL} ${_BCFS_DEV}" >>/tmp/.bcfs-raid-devices
    else
        echo "${_BCFS_LABEL} ${_BCFS_DEV}" >>/tmp/.bcfs-raid-devices
    fi
}

# select bcfs raid devices
_bcfs_select_raid_devices () {
    # select the second device to use, no missing option available!
    _BCFS_RAID_DEVS=()
    for i in "${_DEVS[@]}"; do
        _BCFS_RAID_DEVS+=("${i}")
    done
    IFS=" " read -r -a _BCFS_RAID_DEVS <<< "$(sd "$(${_LSBLK} NAME,SIZE -d "${_BCFS_DEV}")" "" <<< "${_BCFS_RAID_DEVS[@]}")"
    _RAIDNUMBER=1
    while [[ "${_BCFS_DEV}" != "> DONE" ]]; do
        _BCFS_DONE=""
        _RAIDNUMBER=$((_RAIDNUMBER + 1))
        # clean loop from used partition and options
        IFS=" " read -r -a _BCFS_RAID_DEVS <<< "$(sd "$(${_LSBLK} NAME,SIZE -d "${_BCFS_DEV}")" "" <<< "${_BCFS_RAID_DEVS[@]}")"
        ### RAID5/6 is not ready atm 23052024
        # RAID5/6 need ec option!
        # RAID5 needs 3 devices
        # RAID6 and RAID10 need 4 devices!
        if [[ "$((_RAIDNUMBER + _DUR_COUNT))" -ge "$((_BCFS_REP_COUNT + 1))" &&\
                ! "${_BCFS_LEVEL}" == "raid10" && ! "${_BCFS_LEVEL}" == "raid6" &&\
                ! "${_BCFS_LEVEL}" == "raid5" ]] ||\
            [[ "$((_RAIDNUMBER + _DUR_COUNT))" -ge "$((_BCFS_REP_COUNT + 2))" &&\
                "${_BCFS_LEVEL}" == "raid5" ]] ||\
            [[ "$((_RAIDNUMBER + _DUR_COUNT))" -ge "$((_BCFS_REP_COUNT + 3))" &&\
                "${_BCFS_LEVEL}" == "raid10" || "${_BCFS_LEVEL}" == "raid6" ]]; then
            # add more devices
            _dialog --title " Device  ${_RAIDNUMBER} " --no-cancel --menu "" 12 50 6 \
                "${_BCFS_RAID_DEVS[@]}" "> DONE" "Proceed To Summary" 2>"${_ANSWER}" || return 1
        else
            _dialog --title " Device  ${_RAIDNUMBER} " --no-cancel --menu "" 12 50 6 \
                "${_BCFS_RAID_DEVS[@]}" 2>"${_ANSWER}" || return 1
        fi
        _BCFS_DEV=$(cat "${_ANSWER}")
        [[ "${_BCFS_DEV}" == "> DONE" ]] && break
        _bcfs_raid_options || return 1
        _bcfs_options
    done
    echo "--replicas=${_BCFS_REP_COUNT}" >> /tmp/.bcfs-raid-devices
    if [[ -n "${_BCFS_SSD_OPTIONS}" ]]; then
        echo "--foreground_target=ssd --promote_target=ssd" >> /tmp/.bcfs-raid-devices
    fi
    if [[ -n "${_BCFS_HDD_OPTIONS}" ]]; then
        echo "--background_target=hdd" >> /tmp/.bcfs-raid-devices
    fi
}

# choose raid level to use on bcfs device
_bcfs_raid_level() {
    while true ; do
        : >/tmp/.bcfs-raid-devices
        _BCFS_DEV="${_DEV}"
        _BCFS_LEVEL=""
        _DUR_COUNT=0
        _BCFS_HDD_COUNT=0
        _BCFS_HDD_OPTIONS=""
        _BCFS_SSD_COUNT=0
        _BCFS_SSD_OPTIONS=""
        _dialog --no-cancel --title " Raid Data Level " --menu "" 11 30 7 \
            "> NONE" "No Raid Setup" \
            "raid1" "Raid 1 Device" \
            "raid10" "Raid 10 Device" 2>"${_ANSWER}" || return 1
        _BCFS_LEVEL=$(cat "${_ANSWER}")
        if [[ "${_BCFS_LEVEL}" == "> NONE" ]]; then
            _BCFS_DEVS=("${_DEV}")
            break
        else
            # replicas
            _dialog --no-cancel --title " Replication Level " --menu "" 9 30 5 \
                "2" "Level 2" \
                "3" "Level 3" \
                "> CUSTOM" "Custom Level" 2>"${_ANSWER}" || return 1
            _BCFS_REP_COUNT=$(cat "${_ANSWER}")
            if [[ ${_BCFS_REP_COUNT} == "> CUSTOM" ]]; then
                _dialog  --inputbox "Enter custom replication level (number):" 8 65 \
                        "4" 2>"${_ANSWER}" || return 1
                    _BCFS_REP_COUNT="$(cat "${_ANSWER}")"
            fi
            _bcfs_raid_options || return 1
            _bcfs_options
            _bcfs_select_raid_devices || return 1
            # final step ask if everything is ok?
            mapfile -t _BCFS_DEVS < <(cat /tmp/.bcfs-raid-devices)
            if _dialog --title " Summary " --yesno \
                "LEVEL:\n${_BCFS_LEVEL}\nDEVICES:\n${_BCFS_DEVS[*]}" 0 0; then
                    # remove raid devices from _DEVS
                    for i in $(rg -o '.* (/dev.*)' -r '$1' /tmp/.bcfs-raid-devices); do
                        _remove_from_devs "${i}"
                    done
                break
            fi
        fi
    done
}

# ask for bcfs compress option
_bcfs_compress() {
    _dialog --no-cancel --title " Compression on ${_BCFS_DEV} " --menu "" 10 50 4 \
        "> NONE" "No Compression" \
        "zstd" "Use ZSTD Compression" \
        "lz4" "Use LZ4 Compression" \
        "gzip" "Use GZIP Compression" 2>"${_ANSWER}" || return 1
    if [[ "$(cat "${_ANSWER}")" == "> NONE" ]]; then
        _BCFS_COMPRESS="NONE"
    else
        _BCFS_COMPRESS="$(cat "${_ANSWER}")"
    fi
}

# prepare new btrfs device
_prepare_bcfs() {
    _bcfs_raid_level || return 1
    _bcfs_compress || return 1
    #_prepare_bcfs_subvolume || return 1
}
