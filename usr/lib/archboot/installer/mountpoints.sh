#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# _destdir_mounts()
# check if _PART_ROOT is set and if something is mounted on ${_DESTDIR}
_destdir_mounts(){
    # Don't ask for filesystem and create new filesystems
    _ASK_MOUNTPOINTS=""
    _PART_ROOT=""
    # check if something is mounted on ${_DESTDIR}
    _PART_ROOT="$(mount | grep "${_DESTDIR} " | cut -d' ' -f 1)"
    # Run mountpoints, if nothing is mounted on ${_DESTDIR}
    if [[ -z "${_PART_ROOT}" ]]; then
        _dialog --msgbox "Setup couldn't detect mounted partition(s) in ${_DESTDIR}, please set mountpoints first." 0 0
        _mountpoints || return 1
    fi
}

# values that are needed for fs creation
_clear_fs_values() {
    : >/tmp/.btrfs-devices
    _DOMKFS=""
    _LABEL_NAME=""
    _FS_OPTIONS=""
    _BTRFS_DEVICES=""
    _BTRFS_LEVEL=""
    _BTRFS_SUBVOLUME=""
    _DOSUBVOLUME=""
    _BTRFS_COMPRESS=""
}

# add ssd mount options
_ssd_optimization() {
    # ext4, jfs, xfs, btrfs, nilfs2, f2fs  have ssd mount option support
    _SSD_MOUNT_OPTIONS=""
    if echo "${_FSTYPE}" | grep -Eq 'ext4|jfs|btrfs|xfs|nilfs2|f2fs'; then
        # check all underlying devices on ssd
        for i in $(${_LSBLK} NAME,TYPE "${_DEVICE}" -s | grep "disk$" | cut -d' ' -f 1); do
            # check for ssd
            if [[ "$(cat /sys/block/"$(basename "${i}")"/queue/rotational)" == 0 ]]; then
                _SSD_MOUNT_OPTIONS="noatime"
            fi
        done
    fi
}

_select_filesystem() {
    _FILESYSTEM_FINISH=""
    # don't allow vfat as / filesystem, it will not work!
    _FSOPTS=""
    command -v mkfs.btrfs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} btrfs Btrfs"
    command -v mkfs.ext4 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} ext4 Ext4"
    command -v mkfs.ext3 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} ext3 Ext3"
    command -v mkfs.ext2 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} ext2 Ext2"
    command -v mkfs.vfat > /dev/null 2>&1 && [[ "${_DO_ROOT}" == "DONE" ]] && _FSOPTS="${_FSOPTS} vfat FAT32"
    command -v mkfs.xfs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} xfs XFS"
    command -v mkfs.f2fs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} f2fs F2FS"
    command -v mkfs.nilfs2 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} nilfs2 Nilfs2"
    command -v mkfs.jfs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} jfs JFS"
    #shellcheck disable=SC2086
    _dialog --menu "Select a filesystem for ${_PART}:" 15 50 12 ${_FSOPTS} 2>"${_ANSWER}" || return 1
    _FSTYPE=$(cat "${_ANSWER}")
}

_enter_mountpoint() {
    _FILESYSTEM_FINISH=""
    _MP=""
    while [[ -z "${_MP}" ]]; do
        _dialog --inputbox "Enter the mountpoint for ${_PART}" 8 65 "/boot" 2>"${_ANSWER}" || return 1
        _MP=$(cat "${_ANSWER}")
        if grep ":${_MP}:" /tmp/.parts; then
            _dialog --msgbox "ERROR: You have defined 2 identical mountpoints! Please select another mountpoint." 8 65
            _MP=""
        fi
    done
}

# set sane values for paramaters, if not already set
_check_mkfs_values() {
    # Set values, to not confuse mkfs call!
    [[ -z "${_FS_OPTIONS}" ]] && _FS_OPTIONS="NONE"
    [[ -z "${_BTRFS_DEVICES}" ]] && _BTRFS_DEVICES="NONE"
    [[ -z "${_BTRFS_LEVEL}" ]] && _BTRFS_LEVEL="NONE"
    [[ -z "${_BTRFS_SUBVOLUME}" ]] && _BTRFS_SUBVOLUME="NONE"
    [[ -z "${_LABEL_NAME}" && -n "$(${_LSBLK} LABEL "${_PART}")" ]] && _LABEL_NAME="$(${_LSBLK} LABEL "${_PART}")"
    [[ -z "${_LABEL_NAME}" ]] && _LABEL_NAME="NONE"
}

_create_filesystem() {
    _FILESYSTEM_FINISH=""
    _LABEL_NAME=""
    _FS_OPTIONS=""
    _BTRFS_DEVICES=""
    _BTRFS_LEVEL=""
    _dialog --yesno "Would you like to create a filesystem on ${_PART}?\n\n(This will overwrite existing data!)" 0 0 && _DOMKFS=1
    if [[ -n "${_DOMKFS}" ]]; then
        while [[ -z "${_LABEL_NAME}" ]]; do
            _dialog --inputbox "Enter the LABEL name for the device, keep it short\n(not more than 12 characters) and use no spaces or special\ncharacters." 10 65 \
            "$(${_LSBLK} LABEL "${_PART}")" 2>"${_ANSWER}" || return 1
            _LABEL_NAME=$(cat "${_ANSWER}")
            if grep ":${_LABEL_NAME}$" /tmp/.parts; then
                _dialog --msgbox "ERROR: You have defined 2 identical LABEL names! Please enter another name." 8 65
                _LABEL_NAME=""
            fi
        done
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            _prepare_btrfs || return 1
            _btrfs_compress
        fi
        _dialog --inputbox "Enter additional options to the filesystem creation utility.\nUse this field only, if the defaults are not matching your needs,\nelse just leave it empty." 10 70  2>"${_ANSWER}" || return 1
        _FS_OPTIONS=$(cat "${_ANSWER}")
    fi
    _FILESYSTEM_FINISH=1
}

_mountpoints() {
    _NAME_SCHEME_PARAMETER_RUN=""
    while [[ "${_PARTFINISH}" != "DONE" ]]; do
        _activate_special_devices
        : >/tmp/.device-names
        : >/tmp/.fstab
        : >/tmp/.parts
        #
        # Select mountpoints
        #
        if [[ -z "${_NAME_SCHEME_PARAMETER_RUN}" ]]; then
            _set_device_name_scheme || return 1
        fi
        _dialog --cr-wrap --msgbox "Available partitions:\n\n$(_getavailpartitions)\n" 0 0
        _PARTS=$(_findpartitions _)
        _DO_SWAP=""
        while [[ "${_DO_SWAP}" != "DONE" ]]; do
            _FSTYPE="swap"
            #shellcheck disable=SC2086
            _dialog --menu "Select the partition to use as swap:" 15 50 12 NONE - ${_PARTS} 2>"${_ANSWER}" || return 1
            _PART=$(cat "${_ANSWER}")
            if [[ "${_PART}" != "NONE" ]]; then
                _clear_fs_values
                if [[ -n "${_ASK_MOUNTPOINTS}" ]]; then
                    _create_filesystem
                else
                    _FILESYSTEM_FINISH=1
                fi
            else
                _FILESYSTEM_FINISH=1
            fi
            [[ -n "${_FILESYSTEM_FINISH}" ]] && _DO_SWAP=DONE
        done
        _check_mkfs_values
        if [[ "${_PART}" != "NONE" ]]; then
            #shellcheck disable=SC2001,SC2086
            _PARTS="$(echo ${_PARTS} | sed -e "s#${_PART} _##g")"
            echo "${_PART}:swap:swap:${_DOMKFS}:${_LABEL_NAME}:${_FS_OPTIONS}:${_BTRFS_DEVICES}:${_BTRFS_LEVEL}:${_BTRFS_SUBVOLUME}:${_DOSUBVOLUME}:${_BTRFS_COMPRESS}" >>/tmp/.parts
        fi
        _DO_ROOT=""
        while [[ "${_DO_ROOT}" != "DONE" ]]; do
            #shellcheck disable=SC2086
            _dialog --menu "Select the partition to mount as /:" 15 50 12 ${_PARTS} 2>"${_ANSWER}" || return 1
            _PART=$(cat "${_ANSWER}")
            _PART_ROOT=${_PART}
            # Select root filesystem type
            _FSTYPE="$(${_LSBLK} FSTYPE "${_PART}")"
            # clear values first!
            _clear_fs_values
            _check_btrfs_filesystem_creation
            if [[ -n "${_ASK_MOUNTPOINTS}" && -z "${_SKIP_FILESYSTEM}" ]]; then
                _select_filesystem && _create_filesystem && _btrfs_subvolume
            else
                _btrfs_subvolume
            fi
            [[ -n "${_FILESYSTEM_FINISH}" ]] && _DO_ROOT=DONE
        done
        _find_btrfs_raid_devices
        _btrfs_parts
        _check_mkfs_values
        echo "${_PART}:${_FSTYPE}:/:${_DOMKFS}:${_LABEL_NAME}:${_FS_OPTIONS}:${_BTRFS_DEVICES}:${_BTRFS_LEVEL}:${_BTRFS_SUBVOLUME}:${_DOSUBVOLUME}:${_BTRFS_COMPRESS}" >>/tmp/.parts
        #shellcheck disable=SC2001,SC2086
        ! [[ "${_FSTYPE}" == "btrfs" ]] && _PARTS="$(echo ${_PARTS} | sed -e "s#${_PART} _##g")"
        #
        # Additional partitions
        #
        while [[ "${_PART}" != "DONE" ]]; do
            _DO_ADDITIONAL=""
            while [[ "${_DO_ADDITIONAL}" != "DONE" ]]; do
                #shellcheck disable=SC2086
                _dialog --menu "Select any additional partitions to mount under your new root:" 15 52 12 ${_PARTS} DONE _ 2>"${_ANSWER}" || return 1
                _PART=$(cat "${_ANSWER}")
                if [[ "${_PART}" != "DONE" ]]; then
                    _FSTYPE="$(${_LSBLK} FSTYPE "${_PART}")"
                    # clear values first!
                    _clear_fs_values
                    _check_btrfs_filesystem_creation
                    # Select a filesystem type
                    if [[ -n "${_ASK_MOUNTPOINTS}" && -z "${_SKIP_FILESYSTEM}" ]]; then
                        _enter_mountpoint && _select_filesystem && _create_filesystem && _btrfs_subvolume
                    else
                        _enter_mountpoint
                        _btrfs_subvolume
                    fi
                else
                    _FILESYSTEM_FINISH=1
                fi
                [[ -n "${_FILESYSTEM_FINISH}" ]] && _DO_ADDITIONAL="DONE"
            done
            if [[ "${_PART}" != "DONE" ]]; then
                _find_btrfs_raid_devices
                _btrfs_parts
                _check_mkfs_values
                echo "${_PART}:${_FSTYPE}:${_MP}:${_DOMKFS}:${_LABEL_NAME}:${_FS_OPTIONS}:${_BTRFS_DEVICES}:${_BTRFS_LEVEL}:${_BTRFS_SUBVOLUME}:${_DOSUBVOLUME}:${_BTRFS_COMPRESS}" >>/tmp/.parts
                #shellcheck disable=SC2001,SC2086
                ! [[ "${_FSTYPE}" == "btrfs" ]] && _PARTS="$(echo ${_PARTS} | sed -e "s#${_PART} _##g")"
            fi
        done
        #shellcheck disable=SC2028
        _dialog --yesno "Would you like to create and mount the filesytems like this?\n\nSyntax\n------\nDEVICE:TYPE:MOUNTPOINT:FORMAT:LABEL:FSOPTIONS:BTRFS_DETAILS\n\n$(while read -r i;do echo "${i}\n" | sed -e 's, ,#,g';done </tmp/.parts)" 0 0 && _PARTFINISH="DONE"
    done
    # disable swap and all mounted partitions
    _umountall
    _printk off
    while read -r line; do
        _PART=$(echo "${line}" | cut -d: -f 1)
        _FSTYPE=$(echo "${line}" | cut -d: -f 2)
        _MP=$(echo "${line}" | cut -d: -f 3)
        _DOMKFS=$(echo "${line}" | cut -d: -f 4)
        _LABEL_NAME=$(echo "${line}" | cut -d: -f 5)
        _FS_OPTIONS=$(echo "${line}" | cut -d: -f 6)
        _BTRFS_DEVICES=$(echo "${line}" | cut -d: -f 7)
        _BTRFS_LEVEL=$(echo "${line}" | cut -d: -f 8)
        _BTRFS_SUBVOLUME=$(echo "${line}" | cut -d: -f 9)
        _DOSUBVOLUME=$(echo "${line}" | cut -d: -f 10)
        _BTRFS_COMPRESS=$(echo "${line}" | cut -d: -f 11)
        if [[ -n "${_DOMKFS}" ]]; then
            if [[ "${_FSTYPE}" == "swap" ]]; then
                _dialog --infobox "Creating and activating \nswapspace on \n${_PART} ..." 0 0
            else
                _dialog --infobox "Creating ${_FSTYPE} on ${_PART},\nmounting to ${_DESTDIR}${_MP} ..." 0 0
            fi
            _mkfs yes "${_PART}" "${_FSTYPE}" "${_DESTDIR}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" "${_BTRFS_DEVICES}" "${_BTRFS_LEVEL}" "${_BTRFS_SUBVOLUME}" "${_DOSUBVOLUME}" "${_BTRFS_COMPRESS}" || return 1
        else
            if [[ "${_FSTYPE}" == "swap" ]]; then
                _dialog --infobox "Activating swapspace \non ${_PART} ..." 0 0
            else
                _dialog --infobox "Mounting ${_FSTYPE} \non ${_PART} \nto ${_DESTDIR}${_MP} ..." 0 0
            fi
            _mkfs no "${_PART}" "${_FSTYPE}" "${_DESTDIR}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" "${_BTRFS_DEVICES}" "${_BTRFS_LEVEL}" "${_BTRFS_SUBVOLUME}" "${_DOSUBVOLUME}" "${_BTRFS_COMPRESS}" || return 1
        fi
        sleep 1
    done < /tmp/.parts
    _printk on
    _dialog --infobox "Partitions were successfully mounted.\nContinuing in 3 seconds ..." 0 0
    sleep 3
    _NEXTITEM="5"
    _S_MKFS=1
}

# _mkfs()
# Create and mount filesystems in our destination system directory.
#
# args:
#  DOMK: Whether to make the filesystem or use what is already there
#  device: Device filesystem is on
#  fstype: type of filesystem located at the device (or what to create)
#  dest: Mounting location for the destination system
#  mountpoint: Mount point inside the destination system, e.g. '/boot'

# returns: 1 on failure
_mkfs() {
    local _DOMK=${1}
    local _DEVICE=${2}
    local _FSTYPE=${3}
    local _DEST=${4}
    local _MOUNTPOINT=${5}
    local _LABELNAME=${6}
    local _FSOPTIONS=${7}
    local _BTRFSDEVICES="${8//#/\ }"
    local _BTRFSLEVEL=${9}
    local _BTRFS_SUBVOLUME=${10}
    local _DOSUBVOLUME=${11}
    local _BTRFSCOMPRESS=${12}
    # correct empty entries
    [[ "${_FSOPTIONS}" == "NONE" ]] && _FSOPTIONS=""
    [[ "${_BTRFSCOMPRESS}" == "NONE" ]] && _BTRFSCOMPRESS=""
    [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]] && _BTRFS_SUBVOLUME=""
    # add btrfs raid level, if needed
    [[ ! "${_BTRFSLEVEL}" == "NONE" && "${_FSTYPE}" == "btrfs" ]] && _FSOPTIONS="${_FSOPTIONS} -m ${_BTRFSLEVEL} -d ${_BTRFSLEVEL}"
    # we have two main cases: "swap" and everything else.
    if [[ "${_FSTYPE}" == "swap" ]]; then
        swapoff "${_DEVICE}" >/dev/null 2>&1
        if [[ -n "${_DOMK}" ]]; then
            mkswap -L "${_LABELNAME}" "${_DEVICE}" >"${_LOG}" 2>&1
            #shellcheck disable=SC2181
            if [[ $? != 0 ]]; then
                _dialog --msgbox "Error creating swap: mkswap ${_DEVICE}" 0 0
                return 1
            fi
        fi
        swapon "${_DEVICE}" >"${_LOG}" 2>&1
        #shellcheck disable=SC2181
        if [[ $? != 0 ]]; then
            _dialog --msgbox "Error activating swap: swapon ${_DEVICE}" 0 0
            return 1
        fi
    else
        # make sure the fstype is one we can handle
        local _KNOWNFS=0
        for fs in xfs jfs ext2 ext3 ext4 f2fs btrfs nilfs2 ntfs3 vfat; do
            [[ "${_FSTYPE}" == "${fs}" ]] && _KNOWNFS=1 && break
        done
        if [[ ${_KNOWNFS} -eq 0 ]]; then
            _dialog --msgbox "unknown fstype ${_FSTYPE} for ${_DEVICE}" 0 0
            return 1
        fi
        # if we were tasked to create the filesystem, do so
        if [[ -n "${_DOMK}" ]]; then
            local ret
            #shellcheck disable=SC2086
            case ${_FSTYPE} in
                xfs)      mkfs.xfs ${_FSOPTIONS} -L "${_LABELNAME}" -f ${_DEVICE} >"${_LOG}" 2>&1; ret=$? ;;
                jfs)      yes | mkfs.jfs ${_FSOPTIONS} -L "${_LABELNAME}" ${_DEVICE} >"${_LOG}" 2>&1; ret=$? ;;
                ext2)     mkfs.ext2 -F -L ${_FSOPTIONS} "${_LABELNAME}" ${_DEVICE} >"${_LOG}" 2>&1; ret=$? ;;
                ext3)     mke2fs -F ${_FSOPTIONS} -L "${_LABELNAME}" -t ext3 ${_DEVICE} >"${_LOG}" 2>&1; ret=$? ;;
                ext4)     mke2fs -F ${_FSOPTIONS} -L "${_LABELNAME}" -t ext4 ${_DEVICE} >"${_LOG}" 2>&1; ret=$? ;;
                f2fs)     mkfs.f2fs ${_FSOPTIONS} -f -l "${_LABELNAME}" \
                                    -O extra_attr,inode_checksum,sb_checksum ${_DEVICE} >"${_LOG}" 2>&1; ret=$? ;;
                btrfs)    mkfs.btrfs -f ${_FSOPTIONS} -L "${_LABELNAME}" ${_BTRFSDEVICES} >"${_LOG}" 2>&1; ret=$? ;;
                nilfs2)   mkfs.nilfs2 -f ${_FSOPTIONS} -L "${_LABELNAME}" ${_DEVICE} >"${_LOG}" 2>&1; ret=$? ;;
                vfat)     mkfs.vfat -F32 ${_FSOPTIONS} -n "${_LABELNAME}" ${_DEVICE} >"${_LOG}" 2>&1; ret=$? ;;
                # don't handle anything else here, we will error later
            esac
            if [[ ${ret} != 0 ]]; then
                _dialog --msgbox "Error creating filesystem ${_FSTYPE} on ${_DEVICE}" 0 0
                return 1
            fi
            sleep 2
        fi
        if [[ "${_FSTYPE}" == "btrfs" && -n "${_BTRFS_SUBVOLUME}" && -n "${_DOSUBVOLUME}" ]]; then
            _create_btrfs_subvolume
        fi
        _btrfs_scan
        sleep 2
        # create our mount directory
        mkdir -p "${_DEST}""${_MOUNTPOINT}"
        # add ssd optimization before mounting
        _ssd_optimization
        _MOUNTOPTIONS=""
        ### f2fs mount options, taken from wiki:
        # compress_algorithm=zstd:6 tells F2FS to use zstd for compression at level 6, which should give pretty good compression ratio.
        # compress_chksum tells the filesystem to verify compressed blocks with a checksum (to avoid corruption)
        # atgc,gc_merge Enable better garbage collector, and enable some foreground garbage collections to be asynchronous.
        # lazytime Do not synchronously update access or modification times. Improves IO performance and flash durability.
        [[ "${_FSTYPE}" == "f2fs" ]] && _MOUNTOPTIONS="compress_algorithm=zstd:6,compress_chksum,atgc,gc_merge,lazytime"
        # prepare btrfs mount options
        [[ -n "${_BTRFS_SUBVOLUME}" ]] && _MOUNTOPTIONS="${_MOUNTOPTIONS} subvol=${_BTRFS_SUBVOLUME}"
        [[ -n "${_BTRFSCOMPRESS}" ]] && _MOUNTOPTIONS="${_MOUNTOPTIONS} ${_BTRFSCOMPRESS}"
        _MOUNTOPTIONS="${_MOUNTOPTIONS} ${_SSD_MOUNT_OPTIONS}"
        # eleminate spaces at beginning and end, replace other spaces with ,
        _MOUNTOPTIONS="$(echo "${_MOUNTOPTIONS}" | sed -e 's#^ *##g' -e 's# *$##g' | sed -e 's# #,#g')"
        # mount the bad boy
        mount -t "${_FSTYPE}" -o "${_MOUNTOPTIONS}" "${_DEVICE}" "${_DEST}""${_MOUNTPOINT}" >"${_LOG}" 2>&1
        #shellcheck disable=SC2181
        if [[ $? != 0 ]]; then
            _dialog --msgbox "Error mounting ${_DEST}${_MOUNTPOINT}" 0 0
            return 1
        fi
	# btrfs needs balancing on fresh created raid, else weird things could happen
        [[ "${_FSTYPE}" == "btrfs" && -n "${_DOMK}" ]] && btrfs balance start --full-balance "${_DEST}""${_MOUNTPOINT}" >"${_LOG}" 2>&1
        # change permission of base directories to correct permission
        # to avoid btrfs issues
        if [[ "${_MOUNTPOINT}" == "/tmp" ]]; then
            chmod 1777 "${_DEST}""${_MOUNTPOINT}"
        elif [[ "${_MOUNTPOINT}" == "/root" ]]; then
            chmod 750 "${_DEST}""${_MOUNTPOINT}"
        else
            chmod 755 "${_DEST}""${_MOUNTPOINT}"
        fi
    fi
    # add to .device-names for config files
    #shellcheck disable=SC2155
    local _FSUUID="$(_getfsuuid "${_DEVICE}")"
    #shellcheck disable=SC2155
    local _FSLABEL="$(_getfslabel "${_DEVICE}")"

    if [[ -n "${_UEFI_BOOT}" ]]; then
        #shellcheck disable=SC2155
        local _PARTUUID="$(_getpartuuid "${_DEVICE}")"
        #shellcheck disable=SC2155
        local _PARTLABEL="$(_getpartlabel "${_DEVICE}")"

        echo "# DEVICE DETAILS: ${_DEVICE} PARTUUID=${_PARTUUID} PARTLABEL=${_PARTLABEL} UUID=${_FSUUID} LABEL=${_FSLABEL}" >> /tmp/.device-names
    else
        echo "# DEVICE DETAILS: ${_DEVICE} UUID=${_FSUUID} LABEL=${_FSLABEL}" >> /tmp/.device-names
    fi

    # add to temp fstab
    if [[ "${_NAME_SCHEME_PARAMETER}" == "FSUUID" ]]; then
        if [[ -n "${_FSUUID}" ]]; then
            _DEVICE="UUID=${_FSUUID}"
        fi
    elif [[ "${_NAME_SCHEME_PARAMETER}" == "FSLABEL" ]]; then
        if [[ -n "${_FSLABEL}" ]]; then
            _DEVICE="LABEL=${_FSLABEL}"
        fi
    else
        if [[ -n "${_UEFI_BOOT}" ]]; then
           if [[ "${_NAME_SCHEME_PARAMETER}" == "PARTUUID" ]]; then
               if [[ -n "${_PARTUUID}" ]]; then
                   _DEVICE="PARTUUID=${_PARTUUID}"
               fi
           elif [[ "${_NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]]; then
               if [[ -n "${_PARTLABEL}" ]]; then
                   _DEVICE="PARTLABEL=${_PARTLABEL}"
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
    _GUID_VALUE="$(${_BLKID} -p -i -s _PART_ENTRY_TYPE -o value "$(${_LSBLK} NAME,UUID,LABEL,PARTLABEL,PARTUUID | grep "$(echo "${_DEVICE}" | cut -d"=" -f2)" | cut -d" " -f 1)")"
    if ! [[ "${_GUID_VALUE}" == "933ac7e1-2eb4-4f13-b844-0e14e2aef915" &&  "${_MOUNTPOINT}" == "/home" || "${_GUID_VALUE}" == "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f" && "${_MOUNTPOINT}" == "swap" || "${_GUID_VALUE}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" && "${_MOUNTPOINT}" == "/boot" && -n "${_UEFI_BOOT}" || "${_MOUNTPOINT}" == "/" ]]; then
        if [[ -z "${_MOUNTOPTIONS}" ]]; then
            echo -n "${_DEVICE} ${_MOUNTPOINT} ${_FSTYPE} defaults 0 " >>/tmp/.fstab
        else
            echo -n "${_DEVICE} ${_MOUNTPOINT} ${_FSTYPE} defaults,${_MOUNTOPTIONS} 0 " >>/tmp/.fstab
        fi
        if [[ "${_FSTYPE}" == "swap" || "${_FSTYPE}" == "btrfs" ]]; then
            echo 0 >>/tmp/.fstab
        else
            echo 1 >>/tmp/.fstab
        fi
    fi
    unset _MOUNTOPTIONS
    unset _BTRFS_SUBVOLUME
    unset _BTRFSCOMPRESS
}
