#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_bcfs_raid_options() {
    # add durability
    _DURABILITY=""
    _BCFS_DURABILITY="1 'Normal Device' 0 'Cache Device' Custom _"
    _dialog --no-cancel --title " Durability " --menu "" 9 30 5 ${_BCFS_DURABILITY} 2>"${_ANSWER}" || return 1
    _BCFS_DURABILITY_SELECTED=$(cat "${_ANSWER}")
    if [[ ${_BCFS_DURABILITY_SELECTED} == 1 ]]; then
        _DURABILITY=""
    elif [[ ${_BCFS_DURABILITY_SELECTED} == 0 ]]; then
        _DURABILITY="--durability=0"
        _DUR_COUNT=$((_DUR_COUNT - 1))
    else
        if [[ ${_BCFS_DURABILITY_SELECTED} == "Custom" ]]; then
            _dialog  --inputbox "Enter custom durability level (number):" 8 65 \
                "2" 2>"${_ANSWER}" || return 1
                _BCFS_DURABILITY_SELECTED="$(cat "${_ANSWER}")"
                _DURABILITY="--durability=${_BCFS_DURABILITY_SELECTED}"
        fi
        _DUR_COUNT=$((_DUR_COUNT + _BCFS_DURABILITY_SELECTED))
    fi
    if [[ "$(cat /sys/block/"$(basename "${_BCFS_DEV}")"/queue/rotational)" == 0 ]]; then
        _BCFS_SSD_COUNT=$((_BCFS_SSD_COUNT + 1))
        _BCFS_LABEL="--label ssd.ssd${_BCFS_SSD_COUNT}"
        _BCFS_SSD_OPTIONS="--foreground_target=ssd --promote_target=ssd"
    else
        _BCFS_HDD_COUNT=$((_BCFS_HDD_COUNT + 1))
        _BCFS_LABEL="--label hdd.hdd${_BCFS_HDD_COUNT}"
        _BCFS_HDD_OPTIONS="--background_target=hdd"
    fi
    echo "${_DURABILITY}":"${_BCFS_LABEL}":"${_BCFS_DEV}" >>/tmp/.bcfs-devices
}

# select bcfs raid devices
_bcfs_select_raid_devices () {
    # select the second device to use, no missing option available!
    _BCFS_DEVS=""
    #shellcheck disable=SC2001,SC2086
    for i in ${_DEVS}; do
        echo "${i}" | grep -q /dev && _BCFS_DEVS="${_BCFS_DEVS} ${i} _ "
    done
    _BCFS_DEVS=${_BCFS_DEVS//${_BCFS_DEV}\ _/}
    _RAIDNUMBER=1
    while [[ "${_BCFS_DEV}" != "DONE" ]]; do
        _BCFS_DONE=""
        _RAIDNUMBER=$((_RAIDNUMBER + 1))
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
        _BCFS_DEVS=${_BCFS_DEVS//${_BCFS_DEV}\ _/}
        # add more devices
        #shellcheck disable=SC2086
        _dialog --title " Device  ${_RAIDNUMBER} " --no-cancel --menu "" 12 50 6 ${_BCFS_DEVS} ${_BCFS_DONE} 2>"${_ANSWER}" || return 1
        _BCFS_DEV=$(cat "${_ANSWER}")
        [[ "${_BCFS_DEV}" == "DONE" ]] && break
        _bcfs_raid_options || return 1
     done
     # final step ask if everything is ok?
     #shellcheck disable=SC2028
     _dialog --title " Summary " --yesno "LEVEL:\n${_BCFS_LEVEL}\n\nDEVICES:\n$(while read -r i; do echo "${i}\n"; done </tmp/.bcfs-devices)" 0 0 && _BCFS_RAID_FINISH="DONE"
}

# choose raid level to use on bcfs device
_bcfs_raid_level() {
    : >/tmp/.bcfs-devices
    _BCFS_RAIDLEVELS="NONE - raid1 - raid5 - raid6 - raid10 -"
    _BCFS_RAID_FINISH=""
    _BCFS_LEVEL=""
    _BCFS_DEV="${_DEV}"
    _DUR_COUNT="0"
    _BCFS_HDD_COUNT="0"
    _BCFS_SSD_COUNT="0"
    : >/tmp/.bcfs-devices
    while [[ "${_BCFS_RAID_FINISH}" != "DONE" ]]; do
        #shellcheck disable=SC2086
        _dialog --no-cancel --title " Raid Data Level " --menu "" 11 30 7 ${_BCFS_RAIDLEVELS} 2>"${_ANSWER}" || return 1
        _BCFS_LEVEL=$(cat "${_ANSWER}")
        if [[ "${_BCFS_LEVEL}" == "NONE" ]]; then
            echo "${_BCFS_DEV}" >>/tmp/.bcfs-devices
            break
        else
            # replicas
            _BCFS_REPLICATION="2 - 3 - Custom _"
            _dialog --no-cancel --title " Replication Level " --menu "" 9 30 5 ${_BCFS_REPLICATION} 2>"${_ANSWER}" || return 1
            _BCFS_REP_COUNT="$(cat ${_ANSWER})"
            if [[ ${_BCFS_REP_COUNT} == "Custom" ]]; then
                _dialog  --inputbox "Enter custom replication level (number):" 8 65 \
                        "4" 2>"${_ANSWER}" || return 1
                    _BCFS_REP_COUNT="$(cat "${_ANSWER}")"
            fi
            _bcfs_raid_options
            _bcfs_select_raid_devices
        fi
    done
}

# ask for bcfs compress option
_bcfs_compress() {
    _BCFS_COMPRESSLEVELS="zstd - lz4 - gzip - NONE -"
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
    #_prepare_bcfs_subvolume || return 1
}
