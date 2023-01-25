#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# _destdir_mounts()
# check if _ROOTDEV is set and if something is mounted on ${_DESTDIR}
_destdir_mounts(){
    # Don't ask for filesystem and create new filesystems
    _ASK_MOUNTPOINTS=""
    _ROOTDEV=""
    # check if something is mounted on ${_DESTDIR}
    _ROOTDEV="$(mount | grep "${_DESTDIR} " | cut -d' ' -f 1)"
    # Run mountpoints, if nothing is mounted on ${_DESTDIR}
    if [[ -z "${_ROOTDEV}" ]]; then
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
    _BTRFS_DEVS=""
    _BTRFS_LEVEL=""
    _BTRFS_SUBVOLUME=""
    _BTRFS_COMPRESS=""
}

# add ssd mount options
_ssd_optimization() {
    # ext4, jfs, xfs, btrfs, nilfs2, f2fs  have ssd mount option support
    _SSD_MOUNT_OPTIONS=""
    if echo "${_FSTYPE}" | grep -Eq 'ext4|jfs|btrfs|xfs|nilfs2|f2fs'; then
        # check all underlying devices on ssd
        for i in $(${_LSBLK} NAME,TYPE "${_DEV}" -s | grep "disk$" | cut -d' ' -f 1); do
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
    command -v mkfs.btrfs &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} btrfs Btrfs"
    command -v mkfs.ext4 &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} ext4 Ext4"
    command -v mkfs.xfs &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} xfs XFS"
    command -v mkfs.ext2 &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} ext2 Ext2"
    command -v mkfs.vfat &>"${_NO_LOG}" && [[ -n "${_ROOT_DONE}" ]] && _FSOPTS="${_FSOPTS} vfat FAT32"
    command -v mkfs.f2fs &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} f2fs F2FS"
    command -v mkfs.nilfs2 &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} nilfs2 Nilfs2"
    command -v mkfs.ext3 &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} ext3 Ext3"
    command -v mkfs.jfs &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} jfs JFS"
    #shellcheck disable=SC2086
    _dialog --menu "Select a filesystem for ${_DEV}:" 16 50 13 ${_FSOPTS} 2>"${_ANSWER}" || return 1
    _FSTYPE=$(cat "${_ANSWER}")
}

_enter_mountpoint() {
    if [[ -z "${_SWAP_DONE}" ]]; then
        _MP="swap"
        # create swap if not already swap formatted
        if [[ -n "${_ASK_MOUNTPOINTS}" && ! "${_FSTYPE}" == "swap" ]]; then
            _DOMKFS=1
            _FSTYPE="swap"
        fi
        _SWAP_DONE=1
    elif [[ -z "${_ROOT_DONE}" ]]; then
        _MP="/"
        _ROOT_DONE="1"
    elif [[ -z "${_UEFISYSDEV_DONE}" ]]; then
        _dialog --menu "Select the mountpoint of your\nEFI SYSTEM PARTITION (ESP) on ${_DEV}:" 10 50 7 "/efi" "MULTIBOOT" "/boot" "SINGLEBOOT" 2>"${_ANSWER}" || return 1
        _MP=$(cat "${_ANSWER}")
        _UEFISYSDEV_DONE=""
    else
        _MP=""
        while [[ -z "${_MP}" ]]; do
            _MP=/boot
            grep -qw "/boot" /tmp/.parts && _MP=/home
            grep -qw "/home" /tmp/.parts && _MP=/srv
            grep -qw "/srv" /tmp/.parts && _MP=/var
            _dialog --inputbox "Enter the mountpoint for ${_DEV}" 8 65 "${_MP}" 2>"${_ANSWER}" || return 1
            _MP=$(cat "${_ANSWER}")
            if grep ":${_MP}:" /tmp/.parts; then
                _dialog --msgbox "ERROR: You have defined 2 identical mountpoints! Please select another mountpoint." 8 65
                _MP=""
            fi
        done
    fi
}

_check_filesystem_fstab() {
    if [[ "${2}" == "swap" || "${2}" == "btrfs" ]]; then
        echo 0 >>/tmp/.fstab
    else
        echo 1 >>/tmp/.fstab
    fi
}

# set sane values for paramaters, if not already set
_check_mkfs_values() {
    # Set values, to not confuse mkfs call!
    [[ -z "${_FS_OPTIONS}" ]] && _FS_OPTIONS="NONE"
    [[ -z "${_BTRFS_DEVS}" ]] && _BTRFS_DEVS="NONE"
    [[ -z "${_BTRFS_LEVEL}" ]] && _BTRFS_LEVEL="NONE"
    [[ -z "${_BTRFS_SUBVOLUME}" ]] && _BTRFS_SUBVOLUME="NONE"
    [[ -z "${_LABEL_NAME}" && -n "$(${_LSBLK} LABEL "${_DEV}")" ]] && _LABEL_NAME="$(${_LSBLK} LABEL "${_DEV}")"
    [[ -z "${_LABEL_NAME}" ]] && _LABEL_NAME="NONE"
}

_create_filesystem() {
    _LABEL_NAME=""
    _FS_OPTIONS=""
    _BTRFS_DEVS=""
    _BTRFS_LEVEL=""
    _SKIP_FILESYSTEM=""
    [[ -z "${_DOMKFS}" ]] && _dialog --yesno "Would you like to create a filesystem on ${_DEV}?\n\n(This will overwrite existing data!)" 0 0 && _DOMKFS=1
    if [[ -n "${_DOMKFS}" ]]; then
        [[ "${_FSTYPE}" == "swap" || "${_FSTYPE}" == "vfat" ]] || _select_filesystem || return 1
        while [[ -z "${_LABEL_NAME}" ]]; do
            _dialog --inputbox "Enter the LABEL name for the device, keep it short\n(not more than 12 characters) and use no spaces or special\ncharacters." 10 65 \
            "$(${_LSBLK} LABEL "${_DEV}")" 2>"${_ANSWER}" || return 1
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
    _DEVFINISH=""
    while [[ "${_DEVFINISH}" != "DONE" ]]; do
        _activate_special_devices
        : >/tmp/.device-names
        : >/tmp/.fstab
        : >/tmp/.parts
        if [[ -z "${_NAME_SCHEME_PARAMETER_RUN}" ]]; then
            _set_device_name_scheme || return 1
        fi
        _DEV=""
        _dialog --infobox "Scanning blockdevices... This may need some time." 3 60
        _DEVS=$(_finddevices)
        _SWAP_DONE=""
        _ROOT_DONE=""
        [[ -n ${_UEFI_BOOT} ]] && _UEFISYSDEV_DONE=""
        while [[ "${_DEV}" != "DONE" ]]; do
            _MP_DONE=""
            while [[ -z "${_MP_DONE}" ]]; do
                #shellcheck disable=SC2086
                if [[ -z "${_SWAP_DONE}" ]]; then
                    _dialog --menu "Select the SWAP PARTITION:" 15 45 12 NONE - ${_DEVS} 2>"${_ANSWER}" || return 1
                elif [[ -z "${_ROOT_DONE}" ]]; then
                    _dialog --menu "Select the ROOT DEVICE /:" 15 45 12 ${_DEVS} 2>"${_ANSWER}" || return 1
                elif [[ -z "${_UEFISYSDEV_DONE}" ]]; then
                    _dialog --menu "Select the EFI SYSTEM PARTITION (ESP):" 15 45 12 ${_DEVS} 2>"${_ANSWER}" || return 1
                else
                    _dialog --menu "Select any additional devices:" 15 45 12 ${_DEVS} DONE _ 2>"${_ANSWER}" || return 1
                fi
                _DEV=$(cat "${_ANSWER}")
                if [[ "${_DEV}" != "DONE" ]]; then
                    # clear values first!
                    _clear_fs_values
                    _check_btrfs_filesystem_creation
                    [[ ! "${_DEV}" == "NONE" ]] && _FSTYPE="$(${_LSBLK} FSTYPE "${_DEV}")"
                    if [[ -z "${_SWAP_DONE}" && "${_FSTYPE}" == "swap" || "${_DEV}" == "NONE" ]]; then
                        _SKIP_FILESYSTEM=1
                    fi
                    # _ASK_MOUNTPOINTS switch for create filesystem and only mounting filesystem
                    if [[  -n "${_ASK_MOUNTPOINTS}" ]]; then
                        _MP_DONE=1
                        # reformat device, if already swap partition format
                        if [[  "${_FSTYPE}" == "swap" && -n "${_SWAP_DONE}" ]]; then
                            _FSTYPE=""
                            _DOMKFS=1
                        fi
                        # reformat vfat, root cannot be vfat format
                        if [[ -z "${_ROOT_DONE}" && -n "${_SWAP_DONE}" ]]; then
                            if [[ "${_FSTYPE}" == "vfat" ]]; then
                                _FSTYPE=""
                                _DOMKFS=1
                            fi
                        fi
                        # create vfat on ESP, if not already vfat format
                        if [[ ! "${_FSTYPE}" == "vfat" && -z "${_UEFISYSDEV_DONE}" && -n "${_ROOT_DONE}" ]]; then
                            _FSTYPE="vfat"
                            _DOMKFS=1
                        fi
                        # don't format ESP, if already vfat format
                        if [[ "${_FSTYPE}" == "vfat" && -z "${_UEFISYSDEV_DONE}" && -n "${_ROOT_DONE}" ]]; then
                            _SKIP_FILESYSTEM="1"
                        fi
                        # allow reformat. if already vfat format
                        if [[ -n "${_UEFISYSDEV_DONE}" && -n "${_ROOT_DONE}" ]]; then
                            [[ "${_FSTYPE}" == "vfat" ]] && _FSTYPE=""
                        fi
                    else
                        if [[ -z "${_SWAP_DONE}" ]]; then
                            if ! [[ "${_DEV}" == "NONE" ]]; then
                                if ! [[ "${_FSTYPE}" == "swap" ]]; then
                                    _dialog --msgbox "Error: SWAP PARTITION has not a swap filesystem." 5 50
                                    _MP_DONE=""
                                else
                                    _MP_DONE=1
                                fi
                            else
                                _MP_DONE=1
                            fi
                        elif [[ -z "${_ROOT_DONE}" ]]; then
                            if [[ "${_FSTYPE}" == "vfat" ]]; then
                                _dialog --msgbox "Error: ROOT DEVICE has a vfat filesystem." 5 50
                                _MP_DONE=""
                            else
                                _MP_DONE=1
                            fi
                        elif [[ -z "${_UEFISYSDEV_DONE}" ]]; then
                            if ! [[ "${_FSTYPE}" == "vfat" ]]; then
                                _dialog --msgbox "Error: EFI SYSTEM PARTITION has not a vfat filesystem." 5 50
                                _MP_DONE=""
                            else
                                _MP_DONE=1
                            fi
                        fi
                        _SKIP_FILESYSTEM=1
                    fi
                else
                    break
                fi
            done
            if [[ "${_DEV}" != "DONE" ]]; then
                # _ASK_MOUNTPOINTS switch for create filesystem and only mounting filesystem
                if [[ -n "${_ASK_MOUNTPOINTS}" && -z "${_SKIP_FILESYSTEM}" ]]; then
                    _enter_mountpoint || return 1
                    _create_filesystem || return 1
                else
                    _enter_mountpoint || return 1
                    if [[ "${_FSTYPE}" == "btrfs" ]]; then
                        _btrfs_subvolume || return 1
                    fi
                fi
                _find_btrfsraid_devices
                _btrfs_parts
                _check_mkfs_values
                if ! [[ "${_DEV}" == "NONE" ]]; then
                    echo "${_DEV}:${_FSTYPE}:${_MP}:${_DOMKFS}:${_LABEL_NAME}:${_FS_OPTIONS}:${_BTRFS_DEVS}:${_BTRFS_LEVEL}:${_BTRFS_SUBVOLUME}:${_BTRFS_COMPRESS}" >>/tmp/.parts
                    # always remove root device
                    [[ ! "${_FSTYPE}" == "btrfs" || -z "${_ROOT_DONE}" ]] && _DEVS="${_DEVS//$(${_LSBLK} NAME,SIZE -d "${_DEV}")/}"
                fi
            fi
        done
        #shellcheck disable=SC2028
        if [[  -n "${_ASK_MOUNTPOINTS}" ]]; then
            _MOUNT_TEXT="create and mount"
        else
            _MOUNT_TEXT="mount"
        fi
        _dialog --yesno "Would you like to ${_MOUNT_TEXT} the filesytems like this?\n\nSyntax\n------\nDEVICE:FSTYPE:MOUNTPOINT:FORMAT:LABEL:FSOPTIONS:BTRFS_DETAILS\n\n$(while read -r i;do echo "${i}\n" | sed -e 's, ,#,g';done </tmp/.parts)" 0 0 && _DEVFINISH="DONE"
    done
    # disable swap and all mounted devices
    _umountall
    _printk off
    while read -r line; do
        _DEV=$(echo "${line}" | cut -d: -f 1)
        _FSTYPE=$(echo "${line}" | cut -d: -f 2)
        _MP=$(echo "${line}" | cut -d: -f 3)
        _DOMKFS=$(echo "${line}" | cut -d: -f 4)
        _LABEL_NAME=$(echo "${line}" | cut -d: -f 5)
        _FS_OPTIONS=$(echo "${line}" | cut -d: -f 6)
        [[ "${_FS_OPTIONS}" == "NONE" ]] && _FS_OPTIONS=""
        _BTRFS_DEVS=$(echo "${line}" | cut -d: -f 7)
        # remove # from array
        _BTRFS_DEVS="${_BTRFS_DEVS//#/\ }"
        _BTRFS_LEVEL=$(echo "${line}" | cut -d: -f 8)
        [[ ! "${_BTRFS_LEVEL}" == "NONE" && "${_FSTYPE}" == "btrfs" ]] && _BTRFS_LEVEL="${_FS_OPTIONS} -m ${_BTRFS_LEVEL} -d ${_BTRFS_LEVEL}"
        _BTRFS_SUBVOLUME=$(echo "${line}" | cut -d: -f 9)
        [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]] && _BTRFS_SUBVOLUME=""
        _BTRFS_COMPRESS=$(echo "${line}" | cut -d: -f 10)
        [[ "${_BTRFS_COMPRESS}" == "NONE" ]] && _BTRFS_COMPRESS=""
        _mkfs "${_DEV}" "${_FSTYPE}" "${_DESTDIR}" "${_DOMKFS}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" \
              "${_BTRFS_DEVS}" "${_BTRFS_LEVEL}" "${_BTRFS_SUBVOLUME}" "${_BTRFS_COMPRESS}" || return 1
        sleep 1
    done < /tmp/.parts
    _printk on
     _ROOTDEV="$(mount | grep "${_DESTDIR} " | cut -d' ' -f 1)"
    _dialog --infobox "Partitions were mounted successfully.\nContinuing in 5 seconds..." 0 0
    sleep 5
    _NEXTITEM="5"
    _S_MKFS=1
}

# _mkfs()
# Create and mount filesystems in our destination system directory.
# returns: 1 on failure
_mkfs() {
    if [[ -n "${4}" ]]; then
        if [[ "${2}" == "swap" ]]; then
            _dialog --infobox "Creating and activating \nswapspace on \n${1}..." 0 0
        else
            _dialog --infobox "Creating ${2} on ${1},\nmounting to ${3}${5}..." 0 0
        fi
    else
        if [[ "${2}" == "swap" ]]; then
            _dialog --infobox "Activating swapspace \non ${1}..." 0 0
        else
            _dialog --infobox "Mounting ${2} \non ${1} \nto ${3}${5}..." 0 0
        fi
    fi
    # add btrfs raid level, if needed
    # we have two main cases: "swap" and everything else.
    _MOUNTOPTIONS=""
    if [[ "${2}" == "swap" ]]; then
        swapoff -a &>"${_NO_LOG}"
        if [[ -n "${4}" ]]; then
            mkswap -L "${6}" "${1}" &>"${_LOG}"
            sleep 2
            #shellcheck disable=SC2181
            if [[ $? != 0 ]]; then
                _dialog --msgbox "Error creating swap: mkswap ${1}" 0 0
                return 1
            fi
        fi
        swapon "${1}" &>"${_LOG}"
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
                xfs)      mkfs.xfs ${7} -L "${6}" -f ${1} &>"${_LOG}"; ret=$? ;;
                jfs)      yes | mkfs.jfs ${7} -L "${6}" ${1} &>"${_LOG}"; ret=$? ;;
                ext2)     mkfs.ext2 -F -L ${7} "${6}" ${1} &>"${_LOG}"; ret=$? ;;
                ext3)     mke2fs -F ${7} -L "${6}" -t ext3 ${1} &>"${_LOG}"; ret=$? ;;
                ext4)     mke2fs -F ${7} -L "${6}" -t ext4 ${1} &>"${_LOG}"; ret=$? ;;
                f2fs)     mkfs.f2fs ${7} -f -l "${6}" \
                                    -O extra_attr,inode_checksum,sb_checksum ${1} &>"${_LOG}"; ret=$? ;;
                btrfs)    mkfs.btrfs -f ${7} -L "${6}" ${8} &>"${_LOG}"; ret=$? ;;
                nilfs2)   mkfs.nilfs2 -f ${7} -L "${6}" ${1} &>"${_LOG}"; ret=$? ;;
                vfat)     mkfs.vfat -F32 ${7} -n "${6}" ${1} &>"${_LOG}"; ret=$? ;;
                # don't handle anything else here, we will error later
            esac
            if [[ ${ret} != 0 ]]; then
                _dialog --msgbox "Error creating filesystem ${2} on ${1}" 0 0
                return 1
            fi
            sleep 2
        fi
        if [[ "${2}" == "btrfs" && -n "${10}" ]]; then
            _create_btrfs_subvolume
        fi
        _btrfs_scan
        sleep 2
        # create our mount directory
        mkdir -p "${3}""${5}"
        # add ssd optimization before mounting
        _ssd_optimization
        _F2FS_MOUNTOPTIONS=""
        ### f2fs mount options, taken from wiki:
        # compress_algorithm=zstd:6 tells F2FS to use zstd for compression at level 6, which should give pretty good compression ratio.
        # compress_chksum tells the filesystem to verify compressed blocks with a checksum (to avoid corruption)
        # atgc,gc_merge Enable better garbage collector, and enable some foreground garbage collections to be asynchronous.
        # lazytime Do not synchronously update access or modification times. Improves IO performance and flash durability.
        [[ "${2}" == "f2fs" ]] && _F2FS_MOUNTOPTIONS="compress_algorithm=zstd:6,compress_chksum,atgc,gc_merge,lazytime"
        # prepare btrfs mount options
        [[ -n "${10}" ]] && _MOUNTOPTIONS="${_MOUNTOPTIONS} subvol=${10}"
        [[ -n "${11}" ]] && _MOUNTOPTIONS="${_MOUNTOPTIONS} ${11}"
        _MOUNTOPTIONS="${_MOUNTOPTIONS} ${_SSD_MOUNT_OPTIONS} ${_F2FS_MOUNTOPTIONS}"
        # eleminate spaces at beginning and end, replace other spaces with ,
        _MOUNTOPTIONS="$(echo "${_MOUNTOPTIONS}" | sed -e 's#^ *##g' -e 's# *$##g' | sed -e 's# #,#g')"
        # mount the bad boy
        mount -t "${2}" -o "${_MOUNTOPTIONS}" "${1}" "${3}""${5}" &>"${_LOG}"
        #shellcheck disable=SC2181
        if [[ $? != 0 ]]; then
            _dialog --msgbox "Error mounting ${3}${5}" 0 0
            return 1
        fi
        # btrfs needs balancing on fresh created raid, else weird things could happen
        [[ "${2}" == "btrfs" && -n "${4}" ]] && btrfs balance start --full-balance "${3}""${5}" &>"${_LOG}"
    fi
    # add to .device-names for config files
    #shellcheck disable=SC2155
    _FSUUID="$(_getfsuuid "${1}")"
    #shellcheck disable=SC2155
    _FSLABEL="$(_getfslabel "${1}")"
    if [[ -n "${_UEFI_BOOT}" ]]; then
        #shellcheck disable=SC2155
        _PARTUUID="$(_getpartuuid "${1}")"
        #shellcheck disable=SC2155
        _PARTLABEL="$(_getpartlabel "${1}")"
        echo "# DEVICE DETAILS: ${1} PARTUUID=${_PARTUUID} PARTLABEL=${_PARTLABEL} UUID=${_FSUUID} LABEL=${_FSLABEL}" >> /tmp/.device-names
    else
        echo "# DEVICE DETAILS: ${1} UUID=${_FSUUID} LABEL=${_FSLABEL}" >> /tmp/.device-names
    fi
    # add to temp fstab
    if [[ "${_NAME_SCHEME_PARAMETER}" == "FSUUID" ]]; then
        if [[ -n "${_FSUUID}" ]]; then
            _DEV="UUID=${_FSUUID}"
        fi
    elif [[ "${_NAME_SCHEME_PARAMETER}" == "FSLABEL" ]]; then
        if [[ -n "${_FSLABEL}" ]]; then
            _DEV="LABEL=${_FSLABEL}"
        fi
    else
        if [[ -n "${_UEFI_BOOT}" ]]; then
           if [[ "${_NAME_SCHEME_PARAMETER}" == "PARTUUID" ]]; then
               if [[ -n "${_PARTUUID}" ]]; then
                   _DEV="PARTUUID=${_PARTUUID}"
               fi
           elif [[ "${_NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]]; then
               if [[ -n "${_PARTLABEL}" ]]; then
                    _DEV="PARTLABEL=${_PARTLABEL}"
               fi
           fi
        else
            # fallback to device name
            _DEV="${1}"
        fi
    fi
    # / root is not needed in fstab, it's mounted automatically
    # https://www.freedesktop.org/software/systemd/man/systemd-gpt-auto-generator.html
    # systemd supports detection on GPT disks:
    # GRUB and rEFInd don't support /efi automount!
    # disabled for now this check: "${_GUID_VALUE}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" && "${5}" == "/efi"
    # /boot or /efi as ESP: c12a7328-f81f-11d2-ba4b-00a0c93ec93b
    # /boot as Extended Boot Loader Partition: bc13c2ff-59e6-4262-a352-b275fd6f7172
    # swap:  0657fd6d-a4ab-43c4-84e5-0933c84b4f4f
    # /home: 933ac7e1-2eb4-4f13-b844-0e14e2aef915
    # Complex devices, like mdadm, encrypt or lvm are not supported
    # _GUID_VALUE:
    # get real device name from lsblk first to get GUID_VALUE from blkid
    if [[ -z "${_MOUNTOPTIONS}" ]]; then
        _GUID_VALUE="$(${_BLKID} -p -i -s PART_ENTRY_TYPE -o value "$(${_LSBLK} NAME,UUID,LABEL,PARTLABEL,PARTUUID |\
                    grep "$(echo "${1}" | cut -d"=" -f2)" | cut -d" " -f 1)")"
        if ! [[ "${_GUID_VALUE}" == "933ac7e1-2eb4-4f13-b844-0e14e2aef915" && "${5}" == "/home" ||\
                "${_GUID_VALUE}" == "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f" && "${5}" == "swap" ||\
                "${_GUID_VALUE}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" && "${5}" == "/boot" ||\
                "${_GUID_VALUE}" == "bc13c2ff-59e6-4262-a352-b275fd6f7172" && "${5}" == "/boot" ||\
                "${5}" == "/" ]]; then
            echo -n "${_DEV} ${5} ${2} defaults 0 " >>/tmp/.fstab
            _check_filesystem_fstab "$@"
        fi
    else
        echo -n "${_DEV} ${5} ${2} defaults,${_MOUNTOPTIONS} 0 " >>/tmp/.fstab
        _check_filesystem_fstab "$@"
    fi
}
