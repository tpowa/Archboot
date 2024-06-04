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
    if [[ "$(cat /sys/block/"$(basename "${_BCFS_RAID_DEV}")"/queue/rotational)" == 0 ]]; then
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
        echo "${_DURABILITY} ${_BCFS_LABEL} ${_BCFS_RAID_DEV}" >>/tmp/.bcfs-raid-device
    else
        echo "${_BCFS_LABEL} ${_BCFS_RAID_DEV}" >>/tmp/.bcfs-raid-device
    fi
}

# select bcfs raid devices
_bcfs_select_raid_devices () {
    # select the second device to use, no missing option available!
    _BCFS_RAID_DEVS=""
    #shellcheck disable=SC2001,SC2086
    for i in ${_DEVS}; do
        echo "${i}" | grep -q /dev && _BCFS_RAID_DEVS="${_BCFS_RAID_DEVS} ${i} _ "
    done
    _BCFS_RAID_DEVS=${_BCFS_RAID_DEVS//${_BCFS_RAID_DEV} _/}
    _RAIDNUMBER=1
    while [[ "${_BCFS_RAID_DEV}" != "> DONE" ]]; do
        _BCFS_DONE=""
        _RAIDNUMBER=$((_RAIDNUMBER + 1))
        ### RAID5/6 is not ready atm 23052024
        # RAID5/6 need ec option!
        # RAID5 needs 3 devices
        # RAID6 and RAID10 need 4 devices!
        [[ "$((_RAIDNUMBER + _DUR_COUNT))" -ge "$((_BCFS_REP_COUNT + 1))" &&\
            ! "${_BCFS_LEVEL}" == "raid10" && ! "${_BCFS_LEVEL}" == "raid6" &&\
            ! "${_BCFS_LEVEL}" == "raid5" ]] && _BCFS_DONE="DONE _"
        [[ "$((_RAIDNUMBER + _DUR_COUNT))" -ge "$((_BCFS_REP_COUNT + 2))" &&\
            "${_BCFS_LEVEL}" == "raid5" ]] && _BCFS_DONE="DONE _"
        [[ "$((_RAIDNUMBER + _DUR_COUNT))" -ge "$((_BCFS_REP_COUNT + 3))" &&\
            "${_BCFS_LEVEL}" == "raid10" || "${_BCFS_LEVEL}" == "raid6" ]] && _BCFS_DONE="DONE _"
        # clean loop from used partition and options
        _BCFS_RAID_DEVS=${_BCFS_RAID_DEVS//${_BCFS_RAID_DEV} _/}
        # add more devices
        #shellcheck disable=SC2086
        _dialog --title " Device  ${_RAIDNUMBER} " --no-cancel --menu "" 12 50 6 ${_BCFS_RAID_DEVS} ${_BCFS_DONE} 2>"${_ANSWER}" || return 1
        _BCFS_RAID_DEV=$(cat "${_ANSWER}")
        [[ "${_BCFS_RAID_DEV}" == "> DONE" ]] && break
        _bcfs_raid_options || return 1
        _bcfs_options
     done
    echo "--replicas=${_BCFS_REP_COUNT}" >> /tmp/.bcfs-raid-device
    [[ -n "${_BCFS_SSD_OPTIONS}" ]] && echo "--foreground_target=ssd --promote_target=ssd" >> /tmp/.bcfs-raid-device
    [[ -n "${_BCFS_HDD_OPTIONS}" ]] && echo "--background_target=hdd" >> /tmp/.bcfs-raid-device
    break
}

# choose raid level to use on bcfs device
_bcfs_raid_level() {
    _BCFS_DEVICE_FINISH=""
    while true ; do
        : >/tmp/.bcfs-raid-device
        _BCFS_RAIDLEVELS="raid1 - raid10 -"
        _BCFS_RAID_DEV="${_DEV}"
        _BCFS_RAID_FINISH=""
        _BCFS_LEVEL=""
        _DUR_COUNT="0"
        _BCFS_HDD_COUNT="0"
        _BCFS_HDD_OPTIONS=""
        _BCFS_SSD_COUNT="0"
        _BCFS_SSD_OPTIONS=""
        #shellcheck disable=SC2086
        _dialog --no-cancel --title " Raid Data Level " --menu "" 11 30 7 "> NONE" "No Raid Setup" ${_BCFS_RAIDLEVELS} 2>"${_ANSWER}" || return 1
        _BCFS_LEVEL=$(cat "${_ANSWER}")
        if [[ "${_BCFS_LEVEL}" == "> NONE" ]]; then
            _BCFS_DEVS="${_DEV}"
            break
        else
            # replicas
            _BCFS_REPLICATION="2 - 3 -"
            #shellcheck disable=SC2086
            _dialog --no-cancel --title " Replication Level " --menu "" 9 30 5 ${_BCFS_REPLICATION} "> CUSTOM" "Custom Level" 2>"${_ANSWER}" || return 1
            _BCFS_REP_COUNT=$(cat "${_ANSWER}")
            if [[ ${_BCFS_REP_COUNT} == "> CUSTOM" ]]; then
                _dialog  --inputbox "Enter custom replication level (number):" 8 65 \
                        "4" 2>"${_ANSWER}" || return 1
                    _BCFS_REP_COUNT="$(cat "${_ANSWER}")"
            fi
            while true; do
                _bcfs_raid_options || return 1
                _bcfs_options
                _bcfs_select_raid_devices || return 1
            done
            # final step ask if everything is ok?
            #shellcheck disable=SC2028,SC2027,SC2086
            _dialog --title " Summary " --yesno \
                "LEVEL:\n${_BCFS_LEVEL}\nDEVICES:\n$(while read -r i; do echo ""${i}"\n"; done </tmp/.bcfs-raid-device)" \
                0 0 && break
            while read -r i; do
                _BCFS_DEVS="${_BCFS_DEVS} ${i}"
            done </tmp/.bcfs-raid-device
        fi
    done
}

# ask for bcfs compress option
_bcfs_compress() {
    _BCFS_COMPRESSLEVELS="NONE - zstd - lz4 - gzip -"
    #shellcheck disable=SC2086
    _dialog --no-cancel --title " Compression on ${_DEV} " --menu "" 10 50 4 ${_BCFS_COMPRESSLEVELS} 2>"${_ANSWER}" || return 1
    if [[ "$(cat "${_ANSWER}")" == "NONE" ]]; then
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
