#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# scan and update btrfs devices
btrfs_scan() {
    btrfs device scan >/dev/null 2>&1
}

# mount btrfs for checks
mount_btrfs() {
    btrfs_scan
    BTRFSMP="$(mktemp -d /tmp/brtfsmp.XXXX)"
    mount "${PART}" "${BTRFSMP}"
}

# unmount btrfs after checks done
umount_btrfs() {
    umount "${BTRFSMP}"
    rm -r "${BTRFSMP}"
}

# Set BTRFS_DEVICES on detected btrfs devices
find_btrfs_raid_devices() {
    btrfs_scan
    if [[ "${DETECT_CREATE_FILESYSTEM}" = "no" && "${FSTYPE}" = "btrfs" ]]; then
        for i in $(btrfs filesystem show "${PART}" | cut -d " " -f 11); do
            BTRFS_DEVICES="${BTRFS_DEVICES}#${i}"
        done
    fi
}

find_btrfs_raid_bootloader_devices() {
    btrfs_scan
    BTRFS_COUNT=1
    if [[ "$(${_LSBLK} FSTYPE "${bootdev}")" = "btrfs" ]]; then
        BTRFS_DEVICES=""
        for i in $(btrfs filesystem show "${bootdev}" | cut -d " " -f 11); do
            BTRFS_DEVICES="${BTRFS_DEVICES}#${i}"
            BTRFS_COUNT=$((BTRFS_COUNT+1))
        done
    fi
}

# find btrfs subvolume
find_btrfs_subvolume() {
    if [[ "${DETECT_CREATE_FILESYSTEM}" = "no" ]]; then
        # existing btrfs subvolumes
        mount_btrfs
        for i in $(btrfs subvolume list "${BTRFSMP}" | cut -d " " -f 9 | grep -v 'var/lib/machines' -v '/var/lib/portables'); do
            echo "${i}"
            [[ "${1}" ]] && echo "${1}"
        done
        umount_btrfs
    fi
}

find_btrfs_bootloader_subvolume() {
    if [[ "$(${_LSBLK} FSTYPE "${bootdev}")" = "btrfs" ]]; then
        BTRFS_SUBVOLUMES=""
        PART="${bootdev}"
        mount_btrfs
        for i in $(btrfs subvolume list "${BTRFSMP}" | cut -d " " -f 7); do
            BTRFS_SUBVOLUMES="${BTRFS_SUBVOLUMES}#${i}"
        done
        umount_btrfs
    fi
}

# subvolumes already in use
subvolumes_in_use() {
    SUBVOLUME_IN_USE=""
    while read -r i; do
        echo "${i}" | grep -q ":btrfs:" && SUBVOLUME_IN_USE="${SUBVOLUME_IN_USE} $(echo "${i}" | cut -d: -f 9)"
    done < /tmp/.parts
}

# do not ask for btrfs filesystem creation, if already prepared for creation!
check_btrfs_filesystem_creation() {
    DETECT_CREATE_FILESYSTEM="no"
    SKIP_FILESYSTEM="no"
    SKIP_ASK_SUBVOLUME="no"
    #shellcheck disable=SC2013
    for i in $(grep "${PART}[:#]" /tmp/.parts); do
        if echo "${i}" | grep -q ":btrfs:"; then
            FSTYPE="btrfs"
            SKIP_FILESYSTEM="yes"
            # check on filesystem creation, skip subvolume asking then!
            echo "${i}" | cut -d: -f 4 | grep -q yes && DETECT_CREATE_FILESYSTEM="yes"
            [[ "${DETECT_CREATE_FILESYSTEM}" = "yes" ]] && SKIP_ASK_SUBVOLUME="yes"
        fi
    done
}

# remove devices with no subvolume from list and generate raid device list
btrfs_parts() {
     if [[ -s /tmp/.btrfs-devices ]]; then
         BTRFS_DEVICES=""
         while read -r i; do
             BTRFS_DEVICES="${BTRFS_DEVICES}#${i}"
             # remove device if no subvolume is used!
             [[ "${BTRFS_SUBVOLUME}" = "NONE" ]] && PARTS="${PARTS//${i}\ _/}"
         done < /tmp/.btrfs-devices
     else
         [[ "${BTRFS_SUBVOLUME}" = "NONE" ]] && PARTS="${PARTS//${PART}\ _/}"
     fi
}

# choose raid level to use on btrfs device
btrfs_raid_level() {
    BTRFS_RAIDLEVELS="NONE - raid0 - raid1 - raid5 - raid6 - raid10 - single -"
    BTRFS_RAID_FINISH=""
    BTRFS_LEVEL=""
    BTRFS_DEVICE="${PART}"
    : >/tmp/.btrfs-devices
    DIALOG --msgbox "BTRFS DATA RAID OPTIONS:\n\nRAID5/6 are for testing purpose. Use with extreme care!\n\nIf you don't need this feature select NONE." 0 0
    while [[ "${BTRFS_RAID_FINISH}" != "DONE" ]]; do
        #shellcheck disable=SC2086
        DIALOG --menu "Select the raid data level you want to use" 21 50 9 ${BTRFS_RAIDLEVELS} 2>"${ANSWER}" || return 1
        BTRFS_LEVEL=$(cat "${ANSWER}")
        if [[ "${BTRFS_LEVEL}" = "NONE" ]]; then
            echo "${BTRFS_DEVICE}" >>/tmp/.btrfs-devices
            break
        else
            # take selected device as 1st device, add additional devices in part below.
            select_btrfs_raid_devices
        fi
    done
}

# select btrfs raid devices
select_btrfs_raid_devices () {
    # show all devices with sizes
    # DIALOG --msgbox "DISKS:\n$(_getavaildisks)\n\nPARTITIONS:\n$(_getavailpartitions)" 0 0
    # select the second device to use, no missing option available!
    : >/tmp/.btrfs-devices
    BTRFS_PART="${BTRFS_DEVICE}"
    BTRFS_PARTS="${PARTS}"
    echo "${BTRFS_PART}" >>/tmp/.btrfs-devices
    BTRFS_PARTS="${BTRFS_PARTS//${BTRFS_PART}\ _/}"
    RAIDNUMBER=2
    #shellcheck disable=SC2086
    DIALOG --menu "Select device ${RAIDNUMBER}" 21 50 13 ${BTRFS_PARTS} 2>"${ANSWER}" || return 1
    BTRFS_PART=$(cat "${ANSWER}")
    echo "${BTRFS_PART}" >>/tmp/.btrfs-devices
    while [[ "${BTRFS_PART}" != "DONE" ]]; do
        BTRFS_DONE=""
        RAIDNUMBER=$((RAIDNUMBER + 1))
        # RAID5 needs 3 devices
        # RAID6, RAID10 need 4 devices!
        [[ "${RAIDNUMBER}" -ge 3 && ! "${BTRFS_LEVEL}" = "raid10" && ! "${BTRFS_LEVEL}" = "raid6" && ! "${BTRFS_LEVEL}" = "raid5" ]] && BTRFS_DONE="DONE _"
        [[ "${RAIDNUMBER}" -ge 4 && "${BTRFS_LEVEL}" = "raid5" ]] && BTRFS_DONE="DONE _"
        [[ "${RAIDNUMBER}" -ge 5 && "${BTRFS_LEVEL}" = "raid10" || "${BTRFS_LEVEL}" = "raid6" ]] && BTRFS_DONE="DONE _"
        # clean loop from used partition and options
        BTRFS_PARTS="${BTRFS_PARTS//${BTRFS_PART}\ _/}"
        # add more devices
        #shellcheck disable=SC2086
        DIALOG --menu "Select device ${RAIDNUMBER}" 21 50 13 ${BTRFS_PARTS} ${BTRFS_DONE} 2>"${ANSWER}" || return 1
        BTRFS_PART=$(cat "${ANSWER}")
        [[ "${BTRFS_PART}" = "DONE" ]] && break
        echo "${BTRFS_PART}" >>/tmp/.btrfs-devices
     done
     # final step ask if everything is ok?
     #shellcheck disable=SC2028
     DIALOG --yesno "Would you like to create btrfs raid data like this?\n\nLEVEL:\n${BTRFS_LEVEL}\n\nDEVICES:\n$(while read -r i; do echo "${i}\n"; done </tmp/.btrfs-devices)" 0 0 && BTRFS_RAID_FINISH="DONE"
}

# prepare new btrfs device
prepare_btrfs() {
    btrfs_raid_level || return 1
    prepare_btrfs_subvolume || return 1
}

# prepare btrfs subvolume
prepare_btrfs_subvolume() {
    DOSUBVOLUME="no"
    BTRFS_SUBVOLUME="NONE"
    if [[ "${SKIP_ASK_SUBVOLUME}" = "no" ]]; then
        DIALOG --defaultno --yesno "Would you like to create a new subvolume on ${PART}?" 0 0 && DOSUBVOLUME="yes"
    else
        DOSUBVOLUME="yes"
    fi
    if [[ "${DOSUBVOLUME}" = "yes" ]]; then
        BTRFS_SUBVOLUME="NONE"
        while [[ "${BTRFS_SUBVOLUME}" = "NONE" ]]; do
            DIALOG --inputbox "Enter the SUBVOLUME name for the device, keep it short\nand use no spaces or special\ncharacters." 10 65 2>"${ANSWER}" || return 1
            BTRFS_SUBVOLUME=$(cat "${ANSWER}")
            check_btrfs_subvolume
        done
    else
        BTRFS_SUBVOLUME="NONE"
    fi
}

# check btrfs subvolume
check_btrfs_subvolume(){
    [[ "${DOMKFS}" = "yes" && "${FSTYPE}" = "btrfs" ]] && DETECT_CREATE_FILESYSTEM="yes"
    if [[ "${DETECT_CREATE_FILESYSTEM}" = "no" ]]; then
        mount_btrfs
        for i in $(btrfs subvolume list "${BTRFSMP}" | cut -d " " -f 7); do
            if echo "${i}" | grep -q "${BTRFS_SUBVOLUME}"; then
                DIALOG --msgbox "ERROR: You have defined 2 identical SUBVOLUME names or an empty name! Please enter another name." 8 65
                BTRFS_SUBVOLUME="NONE"
            fi
        done
        umount_btrfs
    else
        subvolumes_in_use
        if echo "${SUBVOLUME_IN_USE}" | grep -Eq "${BTRFS_SUBVOLUME}"; then
            DIALOG --msgbox "ERROR: You have defined 2 identical SUBVOLUME names or an empty name! Please enter another name." 8 65
            BTRFS_SUBVOLUME="NONE"
        fi
    fi
}

# create btrfs subvolume
create_btrfs_subvolume() {
    mount_btrfs
    btrfs subvolume create "${BTRFSMP}"/"${_btrfssubvolume}" > "${LOG}"
    # change permission from 700 to 755
    # to avoid warnings during package installation
    chmod 755 "${BTRFSMP}"/"${_btrfssubvolume}"
    umount_btrfs
}

# choose btrfs subvolume from list
choose_btrfs_subvolume () {
    BTRFS_SUBVOLUME="NONE"
    SUBVOLUMES_DETECTED="no"
    SUBVOLUMES=$(find_btrfs_subvolume _)
    # check if subvolumes are present
    [[ -n "${SUBVOLUMES}" ]] && SUBVOLUMES_DETECTED="yes"
    subvolumes_in_use
    for i in ${SUBVOLUME_IN_USE}; do
        SUBVOLUMES=${SUBVOLUMES//${i}\ _/}
    done
    if [[ -n "${SUBVOLUMES}" ]]; then
    #shellcheck disable=SC2086
        DIALOG --menu "Select the subvolume to mount" 21 50 13 ${SUBVOLUMES} 2>"${ANSWER}" || return 1
        BTRFS_SUBVOLUME=$(cat "${ANSWER}")
    else
        if [[ "${SUBVOLUMES_DETECTED}" = "yes" ]]; then
            DIALOG --msgbox "ERROR: All subvolumes of the device are already in use. Switching to create a new one now." 8 65
            SKIP_ASK_SUBVOLUME=yes
            prepare_btrfs_subvolume || return 1
        fi
    fi
}

# btrfs subvolume menu
btrfs_subvolume() {
    FILESYSTEM_FINISH=""
    if [[ "${FSTYPE}" = "btrfs" && "${DOMKFS}" = "no" ]]; then
        if [[ "${ASK_MOUNTPOINTS}" = "1" ]]; then
            # create subvolume if requested
            # choose btrfs subvolume if present
            prepare_btrfs_subvolume || return 1
            if [[ "${BTRFS_SUBVOLUME}" = "NONE" ]]; then
                choose_btrfs_subvolume || return 1
            fi
        else
            # use device if no subvolume is present
            choose_btrfs_subvolume || return 1
        fi
        btrfs_compress
    fi
    FILESYSTEM_FINISH="yes"
}

# ask for btrfs compress option
btrfs_compress() {
    BTRFS_COMPRESS="NONE"
    BTRFS_COMPRESSLEVELS="lzo - zlib - zstd -"
    if [[ "${BTRFS_SUBVOLUME}" = "NONE" ]]; then
        DIALOG --yesno "Would you like to compress the data on ${PART}?" 0 0 && BTRFS_COMPRESS="compress"
    else
        DIALOG --yesno "Would you like to compress the data on ${PART} subvolume=${BTRFS_SUBVOLUME}?" 0 0 && BTRFS_COMPRESS="compress"
    fi
    if [[ "${BTRFS_COMPRESS}" = "compress" ]]; then
        #shellcheck disable=SC2086
        DIALOG --menu "Select the compression method you want to use" 21 50 9 ${BTRFS_COMPRESSLEVELS} 2>"${ANSWER}" || return 1
        BTRFS_COMPRESS="compress=$(cat "${ANSWER}")"
    fi
}
