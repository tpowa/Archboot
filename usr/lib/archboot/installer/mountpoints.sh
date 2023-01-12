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
    _SKIP_FILESYSTEM=""
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
    # don't allow vfat as / filesystem, it will not work!
    _FSOPTS=""
    command -v mkfs.btrfs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} btrfs Btrfs"
    command -v mkfs.ext4 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} ext4 Ext4"
    command -v mkfs.ext3 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} ext3 Ext3"
    command -v mkfs.ext2 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} ext2 Ext2"
    command -v mkfs.vfat > /dev/null 2>&1 && [[ -z "${_DO_ROOT}" ]] && _FSOPTS="${_FSOPTS} vfat FAT32"
    command -v mkfs.xfs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} xfs XFS"
    command -v mkfs.f2fs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} f2fs F2FS"
    command -v mkfs.nilfs2 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} nilfs2 Nilfs2"
    command -v mkfs.jfs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} jfs JFS"
    #shellcheck disable=SC2086
    _dialog --menu "Select a filesystem for ${_DEVICE}:" 16 50 13 ${_FSOPTS} 2>"${_ANSWER}" || return 1
    _FSTYPE=$(cat "${_ANSWER}")
}

_enter_mountpoint() {
    if [[ -n "${_DO_ROOT}" ]]; then
        _MP="/"
    else
        _MP=""
        while [[ -z "${_MP}" ]]; do
            _dialog --inputbox "Enter the mountpoint for ${_DEVICE}" 8 65 "/boot" 2>"${_ANSWER}" || return 1
            _MP=$(cat "${_ANSWER}")
            if grep ":${_MP}:" /tmp/.parts; then
                _dialog --msgbox "ERROR: You have defined 2 identical mountpoints! Please select another mountpoint." 8 65
                _MP=""
            fi
        done
    fi
}

# set sane values for paramaters, if not already set
_check_mkfs_values() {
    # Set values, to not confuse mkfs call!
    [[ -z "${_FS_OPTIONS}" ]] && _FS_OPTIONS="NONE"
    [[ -z "${_BTRFS_DEVICES}" ]] && _BTRFS_DEVICES="NONE"
    [[ -z "${_BTRFS_LEVEL}" ]] && _BTRFS_LEVEL="NONE"
    [[ -z "${_BTRFS_SUBVOLUME}" ]] && _BTRFS_SUBVOLUME="NONE"
    [[ -z "${_LABEL_NAME}" && -n "$(${_LSBLK} LABEL "${_DEVICE}")" ]] && _LABEL_NAME="$(${_LSBLK} LABEL "${_DEVICE}")"
    [[ -z "${_LABEL_NAME}" ]] && _LABEL_NAME="NONE"
}

_create_filesystem() {
    _LABEL_NAME=""
    _FS_OPTIONS=""
    _BTRFS_DEVICES=""
    _BTRFS_LEVEL=""
    _SKIP_FILESYSTEM=""
    _dialog --yesno "Would you like to create a filesystem on ${_DEVICE}?\n\n(This will overwrite existing data!)" 0 0 && _DOMKFS=1
    if [[ -n "${_DOMKFS}" ]]; then
        while [[ -z "${_LABEL_NAME}" ]]; do
            _dialog --inputbox "Enter the LABEL name for the device, keep it short\n(not more than 12 characters) and use no spaces or special\ncharacters." 10 65 \
            "$(${_LSBLK} LABEL "${_DEVICE}")" 2>"${_ANSWER}" || return 1
            _LABEL_NAME=$(cat "${_ANSWER}")
            if grep ":${_LABEL_NAME}$" /tmp/.parts; then
                _dialog --msgbox "ERROR: You have defined 2 identical LABEL names! Please enter another name." 8 65
                _LABEL_NAME=""
            fi
        done
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            _prepare_btrfs || return 1
        fi
        _dialog --inputbox "Enter additional options to the filesystem creation utility.\nUse this field only, if the defaults are not matching your needs,\nelse just leave it empty." 10 70  2>"${_ANSWER}" || return 1
        _FS_OPTIONS=$(cat "${_ANSWER}")
    else
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            _SKIP_FILESYSTEM="1"
            _btrfs_subvolume || return 1
        fi
    fi
}

_mountpoints() {
    _NAME_SCHEME_PARAMETER_RUN=""
    while [[ "${_DEVICEFINISH}" != "DONE" ]]; do
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
        _dialog --infobox "Scanning blockdevices for sizes ..." 3 60
        _dialog --cr-wrap --msgbox "Available partitions:\n\n$(_getavailpartitions)\n" 0 0
        _dialog --infobox "Scanning blockdevices for selection ..." 3 60
        _DEVICES=$(_findpartitions _)
        #
        # swap setting
        #
        _FSTYPE="swap"
        #shellcheck disable=SC2086
        _dialog --menu "Select the partition to use as swap:" 15 50 12 NONE - ${_DEVICES} 2>"${_ANSWER}" || return 1
        _DEVICE=$(cat "${_ANSWER}")
        if [[ "${_DEVICE}" != "NONE" ]]; then
            _clear_fs_values
            if [[ -n "${_ASK_MOUNTPOINTS}" ]]; then
                _create_filesystem || return 1
            fi
        fi
        _check_mkfs_values
        if [[ "${_DEVICE}" != "NONE" ]]; then
            #shellcheck disable=SC2001,SC2086
            _DEVICES="$(echo ${_DEVICES} | sed -e "s#${_DEVICE} _##g")"
            echo "${_DEVICE}:swap:swap:${_DOMKFS}:${_LABEL_NAME}:${_FS_OPTIONS}:${_BTRFS_DEVICES}:${_BTRFS_LEVEL}:${_BTRFS_SUBVOLUME}:${_DOSUBVOLUME}:${_BTRFS_COMPRESS}" >>/tmp/.parts
        fi
        #
        # mountpoints setting
        #
         _DO_ROOT="1"
        while [[ "${_DEVICE}" != "DONE" ]]; do
            #shellcheck disable=SC2086
            if [[ -n ${_DO_ROOT} ]]; then
                _dialog --menu "Select the partition to mount as /:" 15 50 12 ${_DEVICES} 2>"${_ANSWER}" || return 1
            else
                _dialog --menu "Select any additional partitions to mount under your new root:" 15 52 12 ${_DEVICES} DONE _ 2>"${_ANSWER}" || return 1
            fi
            _DEVICE=$(cat "${_ANSWER}")
            [[ -n ${_DO_ROOT} ]] && _DEVICE_ROOT=${_DEVICE}
            if [[ "${_DEVICE}" != "DONE" ]]; then
                _FSTYPE="$(${_LSBLK} FSTYPE "${_DEVICE}")"
                # clear values first!
                _clear_fs_values
                _check_btrfs_filesystem_creation
                # _ASK_MOUNTPOINTS switch for create filesystem and only mounting filesystem
                # _SKIP_FILESYSTEM for btrfs
                if [[ -n "${_ASK_MOUNTPOINTS}" && -z "${_SKIP_FILESYSTEM}" ]]; then
                    _enter_mountpoint && _select_filesystem && _create_filesystem || return 1
                else
                    _enter_mountpoint
                    if [[ "${_FSTYPE}" == "btrfs" ]]; then
                        _btrfs_subvolume || return 1
                    fi
                fi
                _find_btrfs_raid_devices
                _btrfs_parts
                _check_mkfs_values
                echo "${_DEVICE}:${_FSTYPE}:${_MP}:${_DOMKFS}:${_LABEL_NAME}:${_FS_OPTIONS}:${_BTRFS_DEVICES}:${_BTRFS_LEVEL}:${_BTRFS_SUBVOLUME}:${_DOSUBVOLUME}:${_BTRFS_COMPRESS}" >>/tmp/.parts
                #shellcheck disable=SC2001,SC2086
                ! [[ "${_FSTYPE}" == "btrfs" ]] && _DEVICES="$(echo ${_DEVICES} | sed -e "s#${_DEVICE} _##g")"
            fi
            _DO_ROOT=""
        done
        #shellcheck disable=SC2028
        _dialog --yesno "Would you like to create and mount the filesytems like this?\n\nSyntax\n------\nDEVICE:TYPE:MOUNTPOINT:FORMAT:LABEL:FSOPTIONS:BTRFS_DETAILS\n\n$(while read -r i;do echo "${i}\n" | sed -e 's, ,#,g';done </tmp/.parts)" 0 0 && _DEVICEFINISH="DONE"
    done
    # disable swap and all mounted partitions
    _umountall
    _printk off
    while read -r line; do
        _DEVICE=$(echo "${line}" | cut -d: -f 1)
        _FSTYPE=$(echo "${line}" | cut -d: -f 2)
        _MP=$(echo "${line}" | cut -d: -f 3)
        _DOMKFS=$(echo "${line}" | cut -d: -f 4)
        _LABEL_NAME=$(echo "${line}" | cut -d: -f 5)
        _FS_OPTIONS=$(echo "${line}" | cut -d: -f 6)
        _BTRFS_DEVICES=$(echo "${line}" | cut -d: -f 7)
        # remove # from array
        _BTRFS_DEVICES="${_BTRFS_DEVICES//#/\ }"
        _BTRFS_LEVEL=$(echo "${line}" | cut -d: -f 8)
        _BTRFS_SUBVOLUME=$(echo "${line}" | cut -d: -f 9)
        _DOSUBVOLUME=$(echo "${line}" | cut -d: -f 10)
        _BTRFS_COMPRESS=$(echo "${line}" | cut -d: -f 11)
        if [[ -n "${_DOMKFS}" ]]; then
            if [[ "${_FSTYPE}" == "swap" ]]; then
                _dialog --infobox "Creating and activating \nswapspace on \n${_DEVICE} ..." 0 0
            else
                _dialog --infobox "Creating ${_FSTYPE} on ${_DEVICE},\nmounting to ${_DESTDIR}${_MP} ..." 0 0
            fi
        else
            if [[ "${_FSTYPE}" == "swap" ]]; then
                _dialog --infobox "Activating swapspace \non ${_DEVICE} ..." 0 0
            else
                _dialog --infobox "Mounting ${_FSTYPE} \non ${_DEVICE} \nto ${_DESTDIR}${_MP} ..." 0 0
            fi
        fi
        _mkfs "${_DEVICE}" "${_FSTYPE}" "${_DESTDIR}" "${_DOMKFS}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" "${_BTRFS_DEVICES}" "${_BTRFS_LEVEL}" "${_BTRFS_SUBVOLUME}" "${_DOSUBVOLUME}" "${_BTRFS_COMPRESS}" || return 1
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
    # correct empty entries
    [[ "${7}" == "NONE" ]] && 7=""
    [[ "${12}" == "NONE" ]] && 12=""
    [[ "${10}" == "NONE" ]] && 10=""
    # add btrfs raid level, if needed
    [[ ! "${9}" == "NONE" && "${2}" == "btrfs" ]] && 7="${7} -m ${9} -d ${9}"
    # we have two main cases: "swap" and everything else.
    if [[ "${2}" == "swap" ]]; then
        swapoff "${1}" >/dev/null 2>&1
        if [[ -n "${4}" ]]; then
            mkswap -L "${6}" "${1}" >"${_LOG}" 2>&1
            #shellcheck disable=SC2181
            if [[ $? != 0 ]]; then
                _dialog --msgbox "Error creating swap: mkswap ${1}" 0 0
                return 1
            fi
        fi
        swapon "${1}" >"${_LOG}" 2>&1
        #shellcheck disable=SC2181
        if [[ $? != 0 ]]; then
            _dialog --msgbox "Error activating swap: swapon ${1}" 0 0
            return 1
        fi
    else
        # make sure the fstype is one we can handle
        local _KNOWNFS=0
        for fs in xfs jfs ext2 ext3 ext4 f2fs btrfs nilfs2 vfat; do
            [[ "${2}" == "${fs}" ]] && _KNOWNFS=1 && break
        done
        if [[ ${_KNOWNFS} -eq 0 ]]; then
            _dialog --msgbox "unknown fstype ${2} for ${1}" 0 0
            return 1
        fi
        # if we were tasked to create the filesystem, do so
        if [[ -n "${4}" ]]; then
            local ret
            #shellcheck disable=SC2086
            case ${2} in
                xfs)      mkfs.xfs ${7} -L "${6}" -f ${1} >"${_LOG}" 2>&1; ret=$? ;;
                jfs)      yes | mkfs.jfs ${7} -L "${6}" ${1} >"${_LOG}" 2>&1; ret=$? ;;
                ext2)     mkfs.ext2 -F -L ${7} "${6}" ${1} >"${_LOG}" 2>&1; ret=$? ;;
                ext3)     mke2fs -F ${7} -L "${6}" -t ext3 ${1} >"${_LOG}" 2>&1; ret=$? ;;
                ext4)     mke2fs -F ${7} -L "${6}" -t ext4 ${1} >"${_LOG}" 2>&1; ret=$? ;;
                f2fs)     mkfs.f2fs ${7} -f -l "${6}" \
                                    -O extra_attr,inode_checksum,sb_checksum ${1} >"${_LOG}" 2>&1; ret=$? ;;
                btrfs)    mkfs.btrfs -f ${7} -L "${6}" ${8} >"${_LOG}" 2>&1; ret=$? ;;
                nilfs2)   mkfs.nilfs2 -f ${7} -L "${6}" ${1} >"${_LOG}" 2>&1; ret=$? ;;
                vfat)     mkfs.vfat -F32 ${7} -n "${6}" ${1} >"${_LOG}" 2>&1; ret=$? ;;
                # don't handle anything else here, we will error later
            esac
            if [[ ${ret} != 0 ]]; then
                _dialog --msgbox "Error creating filesystem ${2} on ${1}" 0 0
                return 1
            fi
            sleep 2
        fi
        if [[ "${2}" == "btrfs" && -n "${10}" && -n "${_DOSUBVOLUME}" ]]; then
            _create_btrfs_subvolume
        fi
        _btrfs_scan
        sleep 2
        # create our mount directory
        mkdir -p "${3}""${5}"
        # add ssd optimization before mounting
        _ssd_optimization
        _MOUNTOPTIONS=""
        ### f2fs mount options, taken from wiki:
        # compress_algorithm=zstd:6 tells F2FS to use zstd for compression at level 6, which should give pretty good compression ratio.
        # compress_chksum tells the filesystem to verify compressed blocks with a checksum (to avoid corruption)
        # atgc,gc_merge Enable better garbage collector, and enable some foreground garbage collections to be asynchronous.
        # lazytime Do not synchronously update access or modification times. Improves IO performance and flash durability.
        [[ "${2}" == "f2fs" ]] && _MOUNTOPTIONS="compress_algorithm=zstd:6,compress_chksum,atgc,gc_merge,lazytime"
        # prepare btrfs mount options
        [[ -n "${10}" ]] && _MOUNTOPTIONS="${_MOUNTOPTIONS} subvol=${10}"
        [[ -n "${12}" ]] && _MOUNTOPTIONS="${_MOUNTOPTIONS} ${12}"
        _MOUNTOPTIONS="${_MOUNTOPTIONS} ${_SSD_MOUNT_OPTIONS}"
        # eleminate spaces at beginning and end, replace other spaces with ,
        _MOUNTOPTIONS="$(echo "${_MOUNTOPTIONS}" | sed -e 's#^ *##g' -e 's# *$##g' | sed -e 's# #,#g')"
        # mount the bad boy
        mount -t "${2}" -o "${_MOUNTOPTIONS}" "${1}" "${3}""${5}" >"${_LOG}" 2>&1
        #shellcheck disable=SC2181
        if [[ $? != 0 ]]; then
            _dialog --msgbox "Error mounting ${3}${5}" 0 0
            return 1
        fi
	# btrfs needs balancing on fresh created raid, else weird things could happen
        [[ "${2}" == "btrfs" && -n "${4}" ]] && btrfs balance start --full-balance "${3}""${5}" >"${_LOG}" 2>&1
        # change permission of base directories to correct permission
        # to avoid btrfs issues
        if [[ "${5}" == "/tmp" ]]; then
            chmod 1777 "${3}""${5}"
        elif [[ "${5}" == "/root" ]]; then
            chmod 750 "${3}""${5}"
        else
            chmod 755 "${3}""${5}"
        fi
    fi
    # add to .device-names for config files
    #shellcheck disable=SC2155
    local _FSUUID="$(_getfsuuid "${1}")"
    #shellcheck disable=SC2155
    local _FSLABEL="$(_getfslabel "${1}")"

    if [[ -n "${_UEFI_BOOT}" ]]; then
        #shellcheck disable=SC2155
        local _PARTUUID="$(_getpartuuid "${1}")"
        #shellcheck disable=SC2155
        local _PARTLABEL="$(_getpartlabel "${1}")"

        echo "# DEVICE DETAILS: ${1} PARTUUID=${_PARTUUID} PARTLABEL=${_PARTLABEL} UUID=${_FSUUID} LABEL=${_FSLABEL}" >> /tmp/.device-names
    else
        echo "# DEVICE DETAILS: ${1} UUID=${_FSUUID} LABEL=${_FSLABEL}" >> /tmp/.device-names
    fi

    # add to temp fstab
    if [[ "${_NAME_SCHEME_PARAMETER}" == "FSUUID" ]]; then
        if [[ -n "${_FSUUID}" ]]; then
            1="UUID=${_FSUUID}"
        fi
    elif [[ "${_NAME_SCHEME_PARAMETER}" == "FSLABEL" ]]; then
        if [[ -n "${_FSLABEL}" ]]; then
            1="LABEL=${_FSLABEL}"
        fi
    else
        if [[ -n "${_UEFI_BOOT}" ]]; then
           if [[ "${_NAME_SCHEME_PARAMETER}" == "PARTUUID" ]]; then
               if [[ -n "${_PARTUUID}" ]]; then
                   1="PARTUUID=${_PARTUUID}"
               fi
           elif [[ "${_NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]]; then
               if [[ -n "${_PARTLABEL}" ]]; then
                   1="PARTLABEL=${_PARTLABEL}"
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
    _GUID_VALUE="$(${_BLKID} -p -i -s _PART_ENTRY_TYPE -o value "$(${_LSBLK} NAME,UUID,LABEL,PARTLABEL,PARTUUID | grep "$(echo "${1}" | cut -d"=" -f2)" | cut -d" " -f 1)")"
    if ! [[ "${_GUID_VALUE}" == "933ac7e1-2eb4-4f13-b844-0e14e2aef915" &&  "${5}" == "/home" || "${_GUID_VALUE}" == "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f" && "${5}" == "swap" || "${_GUID_VALUE}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" && "${5}" == "/boot" && -n "${_UEFI_BOOT}" || "${5}" == "/" ]]; then
        if [[ -z "${_MOUNTOPTIONS}" ]]; then
            echo -n "${1} ${5} ${2} defaults 0 " >>/tmp/.fstab
        else
            echo -n "${1} ${5} ${2} defaults,${_MOUNTOPTIONS} 0 " >>/tmp/.fstab
        fi
        if [[ "${2}" == "swap" || "${2}" == "btrfs" ]]; then
            echo 0 >>/tmp/.fstab
        else
            echo 1 >>/tmp/.fstab
        fi
    fi
}
