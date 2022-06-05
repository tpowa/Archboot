#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# destdir_mounts()
# check if PART_ROOT is set and if something is mounted on ${DESTDIR}
destdir_mounts(){
    # Don't ask for filesystem and create new filesystems
    ASK_MOUNTPOINTS=""
    PART_ROOT=""
    # check if something is mounted on ${DESTDIR}
    PART_ROOT="$(mount | grep "${DESTDIR} " | cut -d' ' -f 1)"
    # Run mountpoints, if nothing is mounted on ${DESTDIR}
    if [[ "${PART_ROOT}" = "" ]]; then
        DIALOG --msgbox "Setup couldn't detect mounted partition(s) in ${DESTDIR}, please set mountpoints first." 0 0
        detect_uefi_boot
        mountpoints || return 1
    fi
}

# values that are needed for fs creation
clear_fs_values() {
    : >/tmp/.btrfs-devices
    DOMKFS="no"
    LABEL_NAME=""
    FS_OPTIONS=""
    BTRFS_DEVICES=""
    BTRFS_LEVEL=""
    BTRFS_SUBVOLUME=""
    DOSUBVOLUME=""
    BTRFS_COMPRESS=""
}

# add ssd mount options
ssd_optimization() {
    # ext4, jfs, xfs, btrfs, nilfs2, f2fs  have ssd mount option support
    ssd_mount_options=""
    if echo "${_fstype}" | grep -Eq 'ext4|jfs|btrfs|xfs|nilfs2|f2fs'; then
        # check all underlying devices on ssd
        for i in $(${_LSBLK} NAME,TYPE "${_device}" -s | grep "disk$" | cut -d' ' -f 1); do
            # check for ssd
            if [[ "$(cat /sys/block/"$(basename "${i}")"/queue/rotational)" == "0" ]]; then
                ssd_mount_options="noatime"
            fi
        done
    fi
}

select_filesystem() {
    FILESYSTEM_FINISH=""
    # don't allow vfat as / filesystem, it will not work!
    FSOPTS=""
    [[ "$(which mkfs.btrfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} btrfs Btrfs"
    [[ "$(which mkfs.ext4 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext4 Ext4"
    [[ "$(which mkfs.ext3 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext3 Ext3"
    [[ "$(which mkfs.ext2 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext2 Ext2"
    [[ "$(which mkfs.vfat 2>/dev/null)" && "${DO_ROOT}" = "DONE" ]] && FSOPTS="${FSOPTS} vfat FAT32"
    [[ "$(which mkfs.xfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} xfs XFS"
    [[ "$(which mkfs.f2fs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} f2fs F2FS"
    [[ "$(which mkfs.nilfs2 2>/dev/null)" ]] && FSOPTS="${FSOPTS} nilfs2 Nilfs2"
    [[ "$(which mkfs.jfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} jfs JFS"


    #shellcheck disable=SC2086
    DIALOG --menu "Select a filesystem for ${PART}" 15 50 12 ${FSOPTS} 2>"${ANSWER}" || return 1
    FSTYPE=$(cat "${ANSWER}")
}

enter_mountpoint() {
    FILESYSTEM_FINISH=""
    MP=""
    while [[ "${MP}" = "" ]]; do
        DIALOG --inputbox "Enter the mountpoint for ${PART}" 8 65 "/boot" 2>"${ANSWER}" || return 1
        MP=$(cat "${ANSWER}")
        if grep ":${MP}:" /tmp/.parts; then
            DIALOG --msgbox "ERROR: You have defined 2 identical mountpoints! Please select another mountpoint." 8 65
            MP=""
        fi
    done
}

# set sane values for paramaters, if not already set
check_mkfs_values() {
    # Set values, to not confuse mkfs call!
    [[ "${FS_OPTIONS}" = "" ]] && FS_OPTIONS="NONE"
    [[ "${BTRFS_DEVICES}" = "" ]] && BTRFS_DEVICES="NONE"
    [[ "${BTRFS_LEVEL}" = "" ]] && BTRFS_LEVEL="NONE"
    [[ "${BTRFS_SUBVOLUME}" = "" ]] && BTRFS_SUBVOLUME="NONE"
    [[ "${DOSUBVOLUME}" = "" ]] && DOSUBVOLUME="no"
    [[ "${LABEL_NAME}" = "" && -n "$(${_LSBLK} LABEL "${PART}")" ]] && LABEL_NAME="$(${_LSBLK} LABEL "${PART}")"
    [[ "${LABEL_NAME}" = "" ]] && LABEL_NAME="NONE"
}

create_filesystem() {
    FILESYSTEM_FINISH=""
    LABEL_NAME=""
    FS_OPTIONS=""
    BTRFS_DEVICES=""
    BTRFS_LEVEL=""
    DIALOG --yesno "Would you like to create a filesystem on ${PART}?\n\n(This will overwrite existing data!)" 0 0 && DOMKFS="yes"
    if [[ "${DOMKFS}" = "yes" ]]; then
        while [[ "${LABEL_NAME}" = "" ]]; do
            DIALOG --inputbox "Enter the LABEL name for the device, keep it short\n(not more than 12 characters) and use no spaces or special\ncharacters." 10 65 \
            "$(${_LSBLK} LABEL "${PART}")" 2>"${ANSWER}" || return 1
            LABEL_NAME=$(cat "${ANSWER}")
            if grep ":${LABEL_NAME}$" /tmp/.parts; then
                DIALOG --msgbox "ERROR: You have defined 2 identical LABEL names! Please enter another name." 8 65
                LABEL_NAME=""
            fi
        done
        if [[ "${FSTYPE}" = "btrfs" ]]; then
            prepare_btrfs || return 1
            btrfs_compress
        fi
        DIALOG --inputbox "Enter additional options to the filesystem creation utility.\nUse this field only, if the defaults are not matching your needs,\nelse just leave it empty." 10 70  2>"${ANSWER}" || return 1
        FS_OPTIONS=$(cat "${ANSWER}")
    fi
    FILESYSTEM_FINISH="yes"
}

mountpoints() {
    NAME_SCHEME_PARAMETER_RUN=""
    while [[ "${PARTFINISH}" != "DONE" ]]; do
        activate_special_devices
        : >/tmp/.device-names
        : >/tmp/.fstab
        : >/tmp/.parts
        #
        # Select mountpoints
        #
        DIALOG --cr-wrap --msgbox "Available partitions:\n\n$(_getavailpartitions)\n" 0 0
        PARTS=$(findpartitions _)
        DO_SWAP=""
        while [[ "${DO_SWAP}" != "DONE" ]]; do
            FSTYPE="swap"
            #shellcheck disable=SC2086
            DIALOG --menu "Select the partition to use as swap" 15 50 12 NONE - ${PARTS} 2>"${ANSWER}" || return 1
            PART=$(cat "${ANSWER}")
            if [[ "${PART}" != "NONE" ]]; then
                clear_fs_values
                if [[ "${ASK_MOUNTPOINTS}" = "1" ]]; then
                    create_filesystem
                else
                    FILESYSTEM_FINISH="yes"
                fi
            else
                FILESYSTEM_FINISH="yes"
            fi
            [[ "${FILESYSTEM_FINISH}" = "yes" ]] && DO_SWAP=DONE
        done
        check_mkfs_values
        if [[ "${PART}" != "NONE" ]]; then
            #shellcheck disable=SC2001,SC2086
            PARTS="$(echo ${PARTS} | sed -e "s#${PART} _##g")"
            echo "${PART}:swap:swap:${DOMKFS}:${LABEL_NAME}:${FS_OPTIONS}:${BTRFS_DEVICES}:${BTRFS_LEVEL}:${BTRFS_SUBVOLUME}:${DOSUBVOLUME}:${BTRFS_COMPRESS}" >>/tmp/.parts
        fi
        DO_ROOT=""
        while [[ "${DO_ROOT}" != "DONE" ]]; do
            #shellcheck disable=SC2086
            DIALOG --menu "Select the partition to mount as /" 15 50 12 ${PARTS} 2>"${ANSWER}" || return 1
            PART=$(cat "${ANSWER}")
            PART_ROOT=${PART}
            # Select root filesystem type
            FSTYPE="$(${_LSBLK} FSTYPE "${PART}")"
            # clear values first!
            clear_fs_values
            check_btrfs_filesystem_creation
            if [[ "${ASK_MOUNTPOINTS}" = "1" && "${SKIP_FILESYSTEM}" = "no" ]]; then
                select_filesystem && create_filesystem && btrfs_subvolume
            else
                btrfs_subvolume
            fi
            [[ "${FILESYSTEM_FINISH}" = "yes" ]] && DO_ROOT=DONE
        done
        find_btrfs_raid_devices
        btrfs_parts
        check_mkfs_values
        echo "${PART}:${FSTYPE}:/:${DOMKFS}:${LABEL_NAME}:${FS_OPTIONS}:${BTRFS_DEVICES}:${BTRFS_LEVEL}:${BTRFS_SUBVOLUME}:${DOSUBVOLUME}:${BTRFS_COMPRESS}" >>/tmp/.parts
        #shellcheck disable=SC2001,SC2086
        ! [[ "${FSTYPE}" = "btrfs" ]] && PARTS="$(echo ${PARTS} | sed -e "s#${PART} _##g")"
        #
        # Additional partitions
        #
        while [[ "${PART}" != "DONE" ]]; do
            DO_ADDITIONAL=""
            while [[ "${DO_ADDITIONAL}" != "DONE" ]]; do
                #shellcheck disable=SC2086
                DIALOG --menu "Select any additional partitions to mount under your new root (select DONE when finished)" 15 52 12 ${PARTS} DONE _ 2>"${ANSWER}" || return 1
                PART=$(cat "${ANSWER}")
                if [[ "${PART}" != "DONE" ]]; then
                    FSTYPE="$(${_LSBLK} FSTYPE "${PART}")"
                    # clear values first!
                    clear_fs_values
                    check_btrfs_filesystem_creation
                    # Select a filesystem type
                    if [[ "${ASK_MOUNTPOINTS}" = "1" && "${SKIP_FILESYSTEM}" = "no" ]]; then
                        enter_mountpoint && select_filesystem && create_filesystem && btrfs_subvolume
                    else
                        enter_mountpoint
                        btrfs_subvolume
                    fi
                else
                    FILESYSTEM_FINISH="yes"
                fi
                [[ "${FILESYSTEM_FINISH}" = "yes" ]] && DO_ADDITIONAL="DONE"
            done
            if [[ "${PART}" != "DONE" ]]; then
                find_btrfs_raid_devices
                btrfs_parts
                check_mkfs_values
                echo "${PART}:${FSTYPE}:${MP}:${DOMKFS}:${LABEL_NAME}:${FS_OPTIONS}:${BTRFS_DEVICES}:${BTRFS_LEVEL}:${BTRFS_SUBVOLUME}:${DOSUBVOLUME}:${BTRFS_COMPRESS}" >>/tmp/.parts
                #shellcheck disable=SC2001,SC2086
                ! [[ "${FSTYPE}" = "btrfs" ]] && PARTS="$(echo ${PARTS} | sed -e "s#${PART} _##g")"
            fi
        done
        #shellcheck disable=SC2028
        DIALOG --yesno "Would you like to create and mount the filesytems like this?\n\nSyntax\n------\nDEVICE:TYPE:MOUNTPOINT:FORMAT:LABEL:FSOPTIONS:BTRFS_DETAILS\n\n$(while read -r i;do echo "${i}\n" | sed -e 's, ,#,g';done </tmp/.parts)" 0 0 && PARTFINISH="DONE"
    done
    # disable swap and all mounted partitions
    _umountall
    if [[ "${NAME_SCHEME_PARAMETER_RUN}" = "" ]]; then
        set_device_name_scheme || return 1
    fi
    printk off
    while read -r line; do
        PART=$(echo "${line}" | cut -d: -f 1)
        FSTYPE=$(echo "${line}" | cut -d: -f 2)
        MP=$(echo "${line}" | cut -d: -f 3)
        DOMKFS=$(echo "${line}" | cut -d: -f 4)
        LABEL_NAME=$(echo "${line}" | cut -d: -f 5)
        FS_OPTIONS=$(echo "${line}" | cut -d: -f 6)
        BTRFS_DEVICES=$(echo "${line}" | cut -d: -f 7)
        BTRFS_LEVEL=$(echo "${line}" | cut -d: -f 8)
        BTRFS_SUBVOLUME=$(echo "${line}" | cut -d: -f 9)
        DOSUBVOLUME=$(echo "${line}" | cut -d: -f 10)
        BTRFS_COMPRESS=$(echo "${line}" | cut -d: -f 11)
        if [[ "${DOMKFS}" = "yes" ]]; then
            if [[ "${FSTYPE}" = "swap" ]]; then
                DIALOG --infobox "Creating and activating swapspace on ${PART}" 0 0
            else
                DIALOG --infobox "Creating ${FSTYPE} on ${PART},\nmounting to ${DESTDIR}${MP}" 0 0
            fi
            _mkfs yes "${PART}" "${FSTYPE}" "${DESTDIR}" "${MP}" "${LABEL_NAME}" "${FS_OPTIONS}" "${BTRFS_DEVICES}" "${BTRFS_LEVEL}" "${BTRFS_SUBVOLUME}" "${DOSUBVOLUME}" "${BTRFS_COMPRESS}" || return 1
        else
            if [[ "${FSTYPE}" = "swap" ]]; then
                DIALOG --infobox "Activating swapspace on ${PART}" 0 0
            else
                DIALOG --infobox "Mounting ${FSTYPE} on ${PART} to ${DESTDIR}${MP}" 0 0
            fi
            _mkfs no "${PART}" "${FSTYPE}" "${DESTDIR}" "${MP}" "${LABEL_NAME}" "${FS_OPTIONS}" "${BTRFS_DEVICES}" "${BTRFS_LEVEL}" "${BTRFS_SUBVOLUME}" "${DOSUBVOLUME}" "${BTRFS_COMPRESS}" || return 1
        fi
        sleep 1
    done < /tmp/.parts
    printk on
    DIALOG --infobox "Partitions were successfully mounted.\nContinuing in 3 seconds..." 0 0
    sleep 3
    NEXTITEM="5"
    S_MKFS=1
}

# _mkfs()
# Create and mount filesystems in our destination system directory.
#
# args:
#  domk: Whether to make the filesystem or use what is already there
#  device: Device filesystem is on
#  fstype: type of filesystem located at the device (or what to create)
#  dest: Mounting location for the destination system
#  mountpoint: Mount point inside the destination system, e.g. '/boot'

# returns: 1 on failure
_mkfs() {
    local _domk=${1}
    local _device=${2}
    local _fstype=${3}
    local _dest=${4}
    local _mountpoint=${5}
    local _labelname=${6}
    local _fsoptions=${7}
    local _btrfsdevices="${8//#/\ }"
    local _btrfslevel=${9}
    local _btrfssubvolume=${10}
    local _dosubvolume=${11}
    local _btrfscompress=${12}
    # correct empty entries
    [[ "${_fsoptions}" = "NONE" ]] && _fsoptions=""
    [[ "${_btrfscompress}" = "NONE" ]] && _btrfscompress=""
    [[ "${_btrfssubvolume}" = "NONE" ]] && _btrfssubvolume=""
    # add btrfs raid level, if needed
    [[ ! "${_btrfslevel}" = "NONE" && "${_fstype}" = "btrfs" ]] && _fsoptions="${_fsoptions} -m ${_btrfslevel} -d ${_btrfslevel}"
    # add btrfs options, minimum requirement linux 3.14 -O no-holes
    [[ "${_fstype}" = "btrfs" ]] && _fsoptions="${_fsoptions} -O no-holes"
    # we have two main cases: "swap" and everything else.
    if [[ "${_fstype}" = "swap" ]]; then
        swapoff "${_device}" >/dev/null 2>&1
        if [[ "${_domk}" = "yes" ]]; then
            mkswap -L "${_labelname}" "${_device}" >"${LOG}" 2>&1
            #shellcheck disable=SC2181
            if [[ $? != 0 ]]; then
                DIALOG --msgbox "Error creating swap: mkswap ${_device}" 0 0
                return 1
            fi
        fi
        swapon "${_device}" >"${LOG}" 2>&1
        #shellcheck disable=SC2181
        if [[ $? != 0 ]]; then
            DIALOG --msgbox "Error activating swap: swapon ${_device}" 0 0
            return 1
        fi
    else
        # make sure the fstype is one we can handle
        local knownfs=0
        for fs in xfs jfs ext2 ext3 ext4 f2fs btrfs nilfs2 ntfs3 vfat; do
            [[ "${_fstype}" = "${fs}" ]] && knownfs=1 && break
        done
        if [[ ${knownfs} -eq 0 ]]; then
            DIALOG --msgbox "unknown fstype ${_fstype} for ${_device}" 0 0
            return 1
        fi
        # if we were tasked to create the filesystem, do so
        if [[ "${_domk}" = "yes" ]]; then
            local ret
            #shellcheck disable=SC2086
            case ${_fstype} in
                xfs)      mkfs.xfs ${_fsoptions} -L "${_labelname}" -f ${_device} >"${LOG}" 2>&1; ret=$? ;;
                jfs)      yes | mkfs.jfs ${_fsoptions} -L "${_labelname}" ${_device} >"${LOG}" 2>&1; ret=$? ;;
                ext2)     mkfs.ext2 -F -L ${_fsoptions} "${_labelname}" ${_device} >"${LOG}" 2>&1; ret=$? ;;
                ext3)     mke2fs -F ${_fsoptions} -L "${_labelname}" -t ext3 ${_device} >"${LOG}" 2>&1; ret=$? ;;
                ext4)     mke2fs -F ${_fsoptions} -L "${_labelname}" -t ext4 ${_device} >"${LOG}" 2>&1; ret=$? ;;
                f2fs)     mkfs.f2fs ${_fsoptions} -f -l "${_labelname}" \
                                    -O extra_attr,inode_checksum,sb_checksum ${_device} >"${LOG}" 2>&1; ret=$? ;;
                btrfs)    mkfs.btrfs -f ${_fsoptions} -L "${_labelname}" ${_btrfsdevices} >"${LOG}" 2>&1; ret=$? ;;
                nilfs2)   mkfs.nilfs2 -f ${_fsoptions} -L "${_labelname}" ${_device} >"${LOG}" 2>&1; ret=$? ;;
                vfat)     mkfs.vfat -F32 ${_fsoptions} -n "${_labelname}" ${_device} >"${LOG}" 2>&1; ret=$? ;;
                # don't handle anything else here, we will error later
            esac
            if [[ ${ret} != 0 ]]; then
                DIALOG --msgbox "Error creating filesystem ${_fstype} on ${_device}" 0 0
                return 1
            fi
            sleep 2
        fi
        if [[ "${_fstype}" = "btrfs" && -n "${_btrfssubvolume}" && "${_dosubvolume}" = "yes" ]]; then
            create_btrfs_subvolume
        fi
        btrfs_scan
        sleep 2
        # create our mount directory
        mkdir -p "${_dest}""${_mountpoint}"
        # add ssd optimization before mounting
        ssd_optimization
        _mountoptions=""
        ### f2fs mount options, taken from wiki:
        # compress_algorithm=zstd:6 tells F2FS to use zstd for compression at level 6, which should give pretty good compression ratio.
        # compress_chksum tells the filesystem to verify compressed blocks with a checksum (to avoid corruption)
        # whint_mode=fs-based[7] Try to optimize fs-log management depending on file "hotness", meaning how often this data will be read/written to.
        # atgc,gc_merge Enable better garbage collector, and enable some foreground garbage collections to be asynchronous.
        # lazytime Do not synchronously update access or modification times. Improves IO performance and flash durability.
        [[ "${_fstype}" = "f2fs" ]] && _mountoptions="compress_algorithm=zstd:6,compress_chksum,whint_mode=fs-based,atgc,gc_merge,lazytime"
        # prepare btrfs mount options
        [[ -n "${_btrfssubvolume}" ]] && _mountoptions="${_mountoptions} subvol=${_btrfssubvolume}"
        [[ -n "${_btrfscompress}" ]] && _mountoptions="${_mountoptions} ${_btrfscompress}"
        _mountoptions="${_mountoptions} ${ssd_mount_options}"
        # eleminate spaces at beginning and end, replace other spaces with ,
        _mountoptions="$(echo "${_mountoptions}" | sed -e 's#^ *##g' -e 's# *$##g' | sed -e 's# #,#g')"
        # mount the bad boy
        mount -t "${_fstype}" -o "${_mountoptions}" "${_device}" "${_dest}""${_mountpoint}" >"${LOG}" 2>&1
        #shellcheck disable=SC2181
        if [[ $? != 0 ]]; then
            DIALOG --msgbox "Error mounting ${_dest}${_mountpoint}" 0 0
            return 1
        fi
	# btrfs needs balancing on fresh created raid, else weird things could happen
        [[ "${_fstype}" = "btrfs" && "${_domk}" = "yes" ]] && btrfs balance start --full-balance "${_dest}""${_mountpoint}" >"${LOG}" 2>&1
        # change permission of base directories to correct permission
        # to avoid btrfs issues
        if [[ "${_mountpoint}" = "/tmp" ]]; then
            chmod 1777 "${_dest}""${_mountpoint}"
        elif [[ "${_mountpoint}" = "/root" ]]; then
            chmod 750 "${_dest}""${_mountpoint}"
        else
            chmod 755 "${_dest}""${_mountpoint}"
        fi
    fi
    # add to .device-names for config files
    #shellcheck disable=SC2155
    local _fsuuid="$(getfsuuid "${_device}")"
    #shellcheck disable=SC2155
    local _fslabel="$(getfslabel "${_device}")"

    if [[ "${GUID_DETECTED}" == "1" ]]; then
        #shellcheck disable=SC2155
        local _partuuid="$(getpartuuid "${_device}")"
        #shellcheck disable=SC2155
        local _partlabel="$(getpartlabel "${_device}")"

        echo "# DEVICE DETAILS: ${_device} PARTUUID=${_partuuid} PARTLABEL=${_partlabel} UUID=${_fsuuid} LABEL=${_fslabel}" >> /tmp/.device-names
    else
        echo "# DEVICE DETAILS: ${_device} UUID=${_fsuuid} LABEL=${_fslabel}" >> /tmp/.device-names
    fi

    # add to temp fstab
    if [[ "${NAME_SCHEME_PARAMETER}" == "FSUUID" ]]; then
        if [[ -n "${_fsuuid}" ]]; then
            _device="UUID=${_fsuuid}"
        fi
    elif [[ "${NAME_SCHEME_PARAMETER}" == "FSLABEL" ]]; then
        if [[ -n "${_fslabel}" ]]; then
            _device="LABEL=${_fslabel}"
        fi
    else
        if [[ "${GUID_DETECTED}" == "1" ]]; then
           if [[ "${NAME_SCHEME_PARAMETER}" == "PARTUUID" ]]; then
               if [[ -n "${_partuuid}" ]]; then
                   _device="PARTUUID=${_partuuid}"
               fi
           elif [[ "${NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]]; then
               if [[ -n "${_partlabel}" ]]; then
                   _device="PARTLABEL=${_partlabel}"
               fi
           fi
        fi
    fi
    # / root is not needed in fstab, it's mounted automatically
    # systemd supports detection on GPT disks:
    # /boot as ESP: c12a7328-f81f-11d2-ba4b-00a0c93ec93b
    # swap:  0657fd6d-a4ab-43c4-84e5-0933c84b4f4f
    # /home: 933ac7e1-2eb4-4f13-b844-0e14e2aef915
    # Complex devices, like mdadm, encrypt or lvm are not supported
    # _GUID_VALUE:
    # get real device name from lsblk first to get GUID_VALUE from blkid
    _GUID_VALUE="$(${_BLKID} -p -i -s PART_ENTRY_TYPE -o value "$(${_LSBLK} NAME,UUID,LABEL,PARTLABEL,PARTUUID | grep "$(echo "${_device}" | cut -d"=" -f2)" | cut -d" " -f 1)")"
    if ! [[ "${_GUID_VALUE}" == "933ac7e1-2eb4-4f13-b844-0e14e2aef915" &&  "${_mountpoint}" == "/home" || "${_GUID_VALUE}" == "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f" && "${_mountpoint}" == "swap" || "${_GUID_VALUE}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" && "${_mountpoint}" == "/boot" && "${_DETECTED_UEFI_BOOT}" == "1" || "${_mountpoint}" == "/" ]]; then
        if [[ "${_mountoptions}" == "" ]]; then
            echo -n "${_device} ${_mountpoint} ${_fstype} defaults 0 " >>/tmp/.fstab
        else
            echo -n "${_device} ${_mountpoint} ${_fstype} defaults,${_mountoptions} 0 " >>/tmp/.fstab
        fi
        if [[ "${_fstype}" = "swap" || "${_fstype}" = "btrfs" ]]; then
            echo "0" >>/tmp/.fstab
        else
            echo "1" >>/tmp/.fstab
        fi
    fi
    unset _mountoptions
    unset _btrfssubvolume
    unset _btrfscompress
}
