#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
# _destdir_mounts()
# check if _ROOTDEV is set and if something is mounted on ${_DESTDIR}
_destdir_mounts(){
    # Don't ask for filesystem and create new filesystems
    _CREATE_MOUNTPOINTS=""
    _ROOTDEV=""
    # check if something is mounted on ${_DESTDIR}
    _ROOTDEV="$(mount | grep "${_DESTDIR} " | cut -d ' ' -f 1)"
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
    _BCACHEFS_COMPRESS=""
}

# add ssd mount options
_ssd_optimization() {
    # bcachefs, btrfs, ext4 and xfs have ssd mount option support
    _SSD_MOUNT_OPTIONS=""
    if echo "${_FSTYPE}" | grep -Eq 'bcachefs|btrfs|ext4|xfs'; then
        # check all underlying devices on ssd
        for i in $(${_LSBLK} NAME,TYPE "${_DEV}" -s 2>"${_NO_LOG}" | grep "disk$" | cut -d ' ' -f 1); do
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
    command -v mkfs.vfat &>"${_NO_LOG}" && [[ ! ${_MP} == "/" ]] && _FSOPTS="${_FSOPTS} vfat FAT32"
    command -v mkfs.bcachefs &>"${_NO_LOG}" && modinfo bcachefs >"${_NO_LOG}" && _FSOPTS="${_FSOPTS} bcachefs Bcachefs"
    #shellcheck disable=SC2086
    _dialog --title " Filesystem on ${_DEV} " --no-cancel --menu "" 12 50 10 ${_FSOPTS} 2>"${_ANSWER}" || return 1
    _FSTYPE=$(cat "${_ANSWER}")
}

_enter_mountpoint() {
    if [[ -z "${_SWAP_DONE}" ]]; then
        _MP="swap"
        # create swap if not already swap formatted
        if [[ -n "${_CREATE_MOUNTPOINTS}" && ! "${_FSTYPE}" == "swap" ]]; then
            _DOMKFS=1
            _FSTYPE="swap"
        fi
        _SWAP_DONE=1
    elif [[ -z "${_ROOT_DONE}" ]]; then
        _MP="/"
        _ROOT_DONE=1
    elif [[ -z "${_UEFISYSDEV_DONE}" ]]; then
        _dialog --no-cancel --title " EFI SYSTEM PARTITION (ESP) " --menu "" 8 50 2 "/efi" "MULTIBOOT" "/boot" "SINGLEBOOT" 2>"${_ANSWER}" || return 1
        _MP=$(cat "${_ANSWER}")
        if [[ ${_MP} == "/efi" ]]; then
            _XBOOTLDR=1
        fi
        _UEFISYSDEV_DONE=1
    elif [[ -n "${_XBOOTLDR}" ]]; then
        _MP=/boot
        _XBOOTLDR=""
    else
        _MP=""
        while [[ -z "${_MP}" ]]; do
            _MP=/boot
            grep -qw "/boot" /tmp/.parts && _MP=/home
            grep -qw "/home" /tmp/.parts && _MP=/srv
            grep -qw "/srv" /tmp/.parts && _MP=/var
            _dialog --no-cancel --title " Mountpoint for ${_DEV} " --inputbox "" 7 65 "${_MP}" 2>"${_ANSWER}" || return 1
            _MP=$(cat "${_ANSWER}")
            if grep "|${_MP}|" /tmp/.parts; then
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
    [[ -z "${_LABEL_NAME}" && -n "$(${_LSBLK} LABEL "${_DEV}")" ]] && _LABEL_NAME="$(${_LSBLK} LABEL "${_DEV}" 2>"${_NO_LOG}")"
    [[ -z "${_LABEL_NAME}" ]] && _LABEL_NAME="NONE"
}

_run_mkfs() {
    while read -r line; do
        # basic parameters
        _DEV=$(echo "${line}" | cut -d '|' -f 1)
        _FSTYPE=$(echo "${line}" | cut -d '|' -f 2)
        _MP=$(echo "${line}" | cut -d '|' -f 3)
        _DOMKFS=$(echo "${line}" | cut -d '|' -f 4)
        _LABEL_NAME=$(echo "${line}" | cut -d '|' -f 5)
        _FS_OPTIONS=$(echo "${line}" | cut -d '|' -f 6)
        [[ "${_FS_OPTIONS}" == "NONE" ]] && _FS_OPTIONS=""
        # bcachefs, btrfs and other parameters
        if [[ ${_FSTYPE} == "bcachefs" ]]; then
            _BCACHEFS_COMPRESS=$(echo "${line}" | cut -d '|' -f 7)
            if [[ "${_BCACHEFS_COMPRESS}" == "NONE" ]];then
                _BCACHEFS_COMPRESS=""
            else
                _BCACHEFS_COMPRESS="--compression=${_BCACHEFS_COMPRESS}"
            fi
            _mkfs "${_DEV}" "${_FSTYPE}" "${_DESTDIR}" "${_DOMKFS}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" \
                  "${_BCACHEFS_COMPRESS}" || return 1
        elif [[ ${_FSTYPE} == "btrfs" ]]; then
            _BTRFS_DEVS=$(echo "${line}" | cut -d '|' -f 7)
            # remove # from array
            _BTRFS_DEVS="${_BTRFS_DEVS//#/\ }"
            _BTRFS_LEVEL=$(echo "${line}" | cut -d '|' -f 8)
            [[ ! "${_BTRFS_LEVEL}" == "NONE" && "${_FSTYPE}" == "btrfs" ]] && _BTRFS_LEVEL="-m ${_BTRFS_LEVEL} -d ${_BTRFS_LEVEL}"
            _BTRFS_SUBVOLUME=$(echo "${line}" | cut -d '|' -f 9)
            [[ "${_BTRFS_SUBVOLUME}" == "NONE" ]] && _BTRFS_SUBVOLUME=""
            _BTRFS_COMPRESS=$(echo "${line}" | cut -d '|' -f 10)
            [[ "${_BTRFS_COMPRESS}" == "NONE" ]] && _BTRFS_COMPRESS=""
            _mkfs "${_DEV}" "${_FSTYPE}" "${_DESTDIR}" "${_DOMKFS}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" \
                  "${_BTRFS_DEVS}" "${_BTRFS_LEVEL}" "${_BTRFS_SUBVOLUME}" "${_BTRFS_COMPRESS}" || return 1
        else
            _mkfs "${_DEV}" "${_FSTYPE}" "${_DESTDIR}" "${_DOMKFS}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" || return 1
        fi
        sleep 1
        _COUNT=$((_COUNT+_PROGRESS_COUNT))
    done < /tmp/.parts
    _progress "100" "Mountpoints finished successfully."
    sleep 2
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
            _dialog --no-cancel --title " LABEL Name on ${_DEV} " --inputbox "Keep it short and use no spaces or special characters." 8 60 \
            "$(${_LSBLK} LABEL "${_DEV}" 2>"${_NO_LOG}")" 2>"${_ANSWER}" || return 1
            _LABEL_NAME=$(cat "${_ANSWER}")
            if grep "|${_LABEL_NAME}$" /tmp/.parts; then
                _dialog --title " ERROR " --no-mouse --infobox "You have defined 2 identical LABEL names! Please enter another name." 3 60
                sleep 5
                _LABEL_NAME=""
            fi
        done
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            _prepare_btrfs || return 1
        fi
        if [[ "${_FSTYPE}" == "bcachefs" ]]; then
            _bcachefs_compress || return 1
        fi
        _dialog --no-cancel --title " Custom Options " --inputbox "Options passed to filesystem creator, else just leave it empty." 8 70  2>"${_ANSWER}" || return 1
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
    # switch for mbr usage
    _set_guid
    while [[ "${_DEVFINISH}" != "DONE" ]]; do
        _activate_special_devices
        : >/tmp/.device-names
        : >/tmp/.fstab
        : >/tmp/.parts
        if [[ -z "${_NAME_SCHEME_PARAMETER_RUN}" ]]; then
            _set_device_name_scheme || return 1
        fi
        _DEV=""
        _dialog --no-mouse --infobox "Scanning blockdevices... This may need some time." 3 60
        _DEVS=$(_finddevices)
        _SWAP_DONE=""
        _ROOT_DONE=""
        _ROOT_BTRFS=""
        if [[ -n ${_UEFI_BOOT} ]];then
            _UEFISYSDEV_DONE=""
        else
            _UEFISYSDEV_DONE=1
        fi
        while [[ "${_DEV}" != "DONE" ]]; do
            _MP_DONE=""
            while [[ -z "${_MP_DONE}" ]]; do
                #shellcheck disable=SC2086
                if [[ -z "${_SWAP_DONE}" ]]; then
                    _dialog --title " Swap Partition " --menu "" 14 55 8 NONE - ${_DEVS} 2>"${_ANSWER}" || return 1
                elif [[ -z "${_ROOT_DONE}" ]]; then
                    _dialog --title " Root Partition " --no-cancel --menu "" 14 55 8 ${_DEVS} 2>"${_ANSWER}" || return 1
                elif [[ -z "${_UEFISYSDEV_DONE}" ]]; then
                    _dialog --title " EFI SYSTEM PARTITION (ESP) " --no-cancel --menu "" 14 55 8 ${_DEVS} 2>"${_ANSWER}" || return 1
                elif [[ -n "${_XBOOTLDR}" ]]; then
                    _dialog --title " Extended Boot Loader Partition (XBOOTLDR) " --no-cancel --menu "" 14 55 8 ${_DEVS} 2>"${_ANSWER}" || return 1
                else
                    _dialog --title " Additional Partitions " --no-cancel --menu "" 14 55 8 ${_DEVS} DONE _ 2>"${_ANSWER}" || return 1
                fi
                _DEV=$(cat "${_ANSWER}")
                if [[ "${_DEV}" != "DONE" ]]; then
                    # clear values first!
                    _clear_fs_values
                    _check_btrfs_filesystem_creation
                    [[ ! "${_DEV}" == "NONE" ]] && _FSTYPE="$(${_LSBLK} FSTYPE "${_DEV}" 2>"${_NO_LOG}")"
                    if [[ -z "${_SWAP_DONE}" && "${_FSTYPE}" == "swap" ]] || [[ "${_DEV}" == "NONE" ]]; then
                        _SKIP_FILESYSTEM=1
                    fi
                    # _CREATE_MOUNTPOINTS switch for create filesystem and only mounting filesystem
                    if [[  -n "${_CREATE_MOUNTPOINTS}" ]]; then
                        _MP_DONE=1
                        # reformat device, if already swap partition format
                        if [[  "${_FSTYPE}" == "swap" && -n "${_SWAP_DONE}" ]]; then
                            _FSTYPE=""
                            _LABEL_NAME="SWAP"
                            _DOMKFS=1
                        fi
                        # reformat vfat, root cannot be vfat format
                        if [[ -z "${_ROOT_DONE}" && -n "${_SWAP_DONE}" ]]; then
                            if [[ "${_FSTYPE}" == "vfat" ]]; then
                                _FSTYPE=""
                                _DOMKFS=1
                            fi
                        fi
                        if [[ -z "${_UEFISYSDEV_DONE}" && -n "${_ROOT_DONE}" ]]; then
                            # create vfat on ESP, if not already vfat format
                            if [[ ! "${_FSTYPE}" == "vfat" ]]; then
                                _FSTYPE="vfat"
                                _LABEL_NAME="ESP"
                                _DOMKFS=1
                            else
                                # don't format ESP, if already vfat format
                                _SKIP_FILESYSTEM="1"
                            fi
                        fi
                        if [[ -n "${_UEFISYSDEV_DONE}" && -n "${_XBOOTLDR}" ]]; then
                            # create vfat on XBOOTLDR, if not already vfat format
                            if [[ ! "${_FSTYPE}" == "vfat" ]]; then
                                _FSTYPE="vfat"
                                _LABEL_NAME="XBOOTLDR"
                                _DOMKFS=1
                            else
                                # don't format XBOOTLDR, if already vfat format
                                _SKIP_FILESYSTEM="1"
                            fi
                        fi
                        # allow reformat. if already vfat format
                        if [[ -n "${_UEFISYSDEV_DONE}" && -n "${_ROOT_DONE}" && -z "${_XBOOTLDR}" ]]; then
                            [[ "${_FSTYPE}" == "vfat" ]] && _FSTYPE=""
                        fi
                    else
                        if [[ -z "${_SWAP_DONE}" ]]; then
                            if ! [[ "${_DEV}" == "NONE" ]]; then
                                if ! [[ "${_FSTYPE}" == "swap" ]]; then
                                    _dialog --title " ERROR " --no-mouse --infobox "SWAP PARTITION has not a swap filesystem." 3 60
                                    sleep 5
                                    _MP_DONE=""
                                else
                                    _MP_DONE=1
                                fi
                            else
                                _MP_DONE=1
                            fi
                        elif [[ -z "${_ROOT_DONE}" ]]; then
                            if [[ "${_FSTYPE}" == "vfat" ]]; then
                                _dialog --title " ERROR " --no-mouse --infobox "ROOT DEVICE has a vfat filesystem." 3 60
                                sleep 5
                                _MP_DONE=""
                            elif [[ "${_FSTYPE}" == "swap" ]]; then
                                _dialog --title " ERROR " --no-mouse --infobox "ROOT DEVICE has a swap filesystem." 3 60
                                sleep 5
                                _MP_DONE=""
                            else
                                _MP_DONE=1
                            fi
                        elif [[ -z "${_UEFISYSDEV_DONE}" ]]; then
                            if ! [[ "${_FSTYPE}" == "vfat" ]]; then
                                _dialog --title " ERROR " --no-mouse --infobox "EFI SYSTEM PARTITION has not a vfat filesystem." 3 60
                                sleep 5
                                _MP_DONE=""
                            else
                                _MP_DONE=1
                            fi
                         elif [[ -n "${_XBOOTLDR}" ]]; then
                            if ! [[ "${_FSTYPE}" == "vfat" ]]; then
                                _dialog --title " ERROR " --no-mouse --infobox "EXTENDED BOOT LOADER PARTITION has not a vfat filesystem." 3 70
                                sleep 5
                                _MP_DONE=""
                            else
                                _MP_DONE=1
                            fi
                        else
                            _MP_DONE=1
                        fi
                        _SKIP_FILESYSTEM=1
                    fi
                else
                    break
                fi
            done
            if [[ "${_DEV}" != "DONE" ]]; then
                # _CREATE_MOUNTPOINTS switch for create filesystem and only mounting filesystem
                if [[ -n "${_CREATE_MOUNTPOINTS}" && -z "${_SKIP_FILESYSTEM}" ]]; then
                    _enter_mountpoint || return 1
                    _create_filesystem || return 1
                else
                    _enter_mountpoint || return 1
                    if [[ "${_FSTYPE}" == "btrfs" && ! "${_DEV}" == "NONE" ]]; then
                        _btrfs_subvolume || return 1
                    fi
                fi
                if ! [[ "${_DEV}" == "NONE" ]]; then
                    _find_btrfsraid_devices
                    _btrfs_parts
                    _check_mkfs_values
                    if [[ "${_FSTYPE}" == "btrfs" ]]; then
                        echo "${_DEV}|${_FSTYPE}|${_MP}|${_DOMKFS}|${_LABEL_NAME}|${_FS_OPTIONS}|${_BTRFS_DEVS}|${_BTRFS_LEVEL}|${_BTRFS_SUBVOLUME}|${_BTRFS_COMPRESS}" >>/tmp/.parts
                    elif [[ "${_FSTYPE}" == "bcachefs" ]]; then
                        echo "${_DEV}|${_FSTYPE}|${_MP}|${_DOMKFS}|${_LABEL_NAME}|${_FS_OPTIONS}|${_BCACHEFS_COMPRESS}" >>/tmp/.parts
                    else
                        echo "${_DEV}|${_FSTYPE}|${_MP}|${_DOMKFS}|${_LABEL_NAME}|${_FS_OPTIONS}" >>/tmp/.parts
                    fi
                    # btrfs is a special case! not really elegant
                    # remove root btrfs on ESP selection menu, readd it on top aftwerwards
                    if [[ ! "${_FSTYPE}" == "btrfs" ]]; then
                        _DEVS="${_DEVS//$(${_LSBLK} NAME,SIZE -d "${_DEV}" 2>"${_NO_LOG}")/}"
                        if [[ -n "${_UEFISYSDEV_DONE}" && -z "${_XBOOTLDR}" && -n ${_ROOT_BTRFS} ]]; then
                            _DEVS="${_ROOT_BTRFS} ${_DEVS}"
                            _ROOT_BTRFS=""
                        fi
                    else
                        if [[ "${_FSTYPE}" == "btrfs" && "${_MP}" == "/" ]]; then
                            _DEVS="${_DEVS//$(${_LSBLK} NAME,SIZE -d "${_DEV}" 2>"${_NO_LOG}")/}"
                            _ROOT_BTRFS="$(${_LSBLK} NAME,SIZE -d "${_DEV}")"
                        fi
                    fi
                fi
            fi
        done
        #shellcheck disable=SC2028
        if [[  -n "${_CREATE_MOUNTPOINTS}" ]]; then
            _MOUNT_TEXT="create and mount"
        else
            _MOUNT_TEXT="mount"
        fi
        #shellcheck disable=SC2028
        _dialog --title " Summary " --yesno "Syntax\n------\nDEVICE|FSTYPE|MOUNTPOINT|FORMAT|LABEL|FSOPTIONS|FS_DETAILS\n\n$(while read -r i;do echo "${i}\n" | sed -e 's, ,#,g';done </tmp/.parts)" 0 0 && _DEVFINISH="DONE"
    done
    # disable swap and all mounted devices
    _umountall
    _printk off
    _MAX_COUNT=$(wc -l < /tmp/.parts)
    _PROGRESS_COUNT=$((100/_MAX_COUNT))
    _COUNT=0
    _run_mkfs | _dialog --title " Mountpoints " --no-mouse --gauge "Mountpoints..." 6 75 0
    _printk on
     _ROOTDEV="$(mount | grep "${_DESTDIR} " | cut -d ' ' -f 1)"
    _NEXTITEM="5"
}

# _mkfs()
# Create and mount filesystems in our destination system directory.
# returns: 1 on failure
_mkfs() {
    if [[ -n "${4}" ]]; then
        if [[ "${2}" == "swap" ]]; then
            _progress "${_COUNT}" "Creating and activating swapspace on ${1}..."
        else
            _progress "${_COUNT}" "Creating ${2} on ${1}, mounting to ${3}${5}..."
        fi
    else
        if [[ "${2}" == "swap" ]]; then
            _progress "${_COUNT}" "Activating swapspace on ${1}..."
        else
            _progress "${_COUNT}" "Mounting ${2} on ${1} to ${3}${5}..." 0 0
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
                _dialog --title " ERROR " --no-mouse --infobox "Creating swap: mkswap ${1}" 0 0
                sleep 5
                return 1
            fi
        fi
        swapon "${1}" &>"${_LOG}"
        #shellcheck disable=SC2181
        if [[ $? != 0 ]]; then
            _dialog --title " ERROR " --no-mouse --infobox "Activating swap: swapon ${1}" 0 0
            sleep 5
            return 1
        fi
    else
        # make sure the fstype is one we can handle
        local _KNOWNFS=0
        for fs in xfs ext4 bcachefs btrfs vfat; do
            [[ "${2}" == "${fs}" ]] && _KNOWNFS=1 && break
        done
        if [[ ${_KNOWNFS} -eq 0 ]]; then
            _dialog --title " ERROR " --no-mouse --infobox "Unknown fstype ${2} for ${1}" 0 0
            sleep 5
            return 1
        fi
        # if we were tasked to create the filesystem, do so
        if [[ -n "${4}" ]]; then
            local ret
            #shellcheck disable=SC2086
            case ${2} in
                # don't handle anything else here, we will error later
                bcachefs) mkfs.bcachefs -f ${7} -L "${6}" ${8} ${1} &>"${_LOG}"; ret=$? ;;
                btrfs)    mkfs.btrfs -f ${7} -L "${6}" ${8} &>"${_LOG}"; ret=$? ;;
                ext4)     mke2fs -F ${7} -L "${6}" -t ext4 ${1} &>"${_LOG}"; ret=$? ;;
                vfat)     mkfs.vfat -F32 ${7} -n "${6}" ${1} &>"${_LOG}"; ret=$? ;;
                xfs)      mkfs.xfs ${7} -L "${6}" -f ${1} &>"${_LOG}"; ret=$? ;;
            esac
            if [[ ${ret} != 0 ]]; then
                _dialog --title " ERROR " --no-mouse --infobox "Creating filesystem ${2} on ${1}" 0 0
                sleep 5
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
            _dialog --title " ERROR " --no-mouse --infobox "Mounting ${3}${5}" 0 0
            sleep 5
            return 1
        fi
        # create /EFI directory on ESP
        if [[ -n "${_CREATE_MOUNTPOINTS}" && "${5}" = "/efi" && ! -d "${3}${5}/EFI" ]]; then
            mkdir "${3}${5}/EFI"
        fi
        if [[ -n "${_CREATE_MOUNTPOINTS}" && "${5}" = "/boot" && -n "${_UEFI_BOOT}" && ! -d "${3}${5}/EFI" ]]; then
            mountpoint -q "${3}/efi" || mkdir "${3}${5}/EFI"
        fi
        # check if /boot exists on ROOT DEVICE
        if [[ -z "${_CREATE_MOUNTPOINTS}" && "${5}" = "/" && ! -d "${3}${5}/boot" ]]; then
            _dialog --title " ERROR " --no-mouse --infobox "ROOT DEVICE ${3}${5} does not contain /boot directory." 0 0
            sleep 5
            _umountall
            return 1
        fi
        # check on /EFI on /efi mountpoint
        if [[ -z "${_CREATE_MOUNTPOINTS}" && "${5}" = "/efi" && ! -d "${3}${5}/EFI" ]]; then
            _dialog --title " ERROR " --no-mouse --infobox "EFI SYSTEM PARTITION (ESP) ${3}${5} does not contain /EFI directory." 0 0
            sleep 5
            _umountall
            return 1
        fi
        # check on /EFI on /boot
        if [[ -z "${_CREATE_MOUNTPOINTS}" && "${5}" = "/boot" && -n "${_UEFI_BOOT}" && ! -d "${3}${5}/EFI" ]]; then
            if ! mountpoint -q "${3}/efi"; then
                _dialog --title " ERROR " --no-mouse --infobox "EFI SYSTEM PARTITION (ESP) ${3}${5} does not contain /EFI directory." 0 0
                sleep 5
                _umountall
                return 1
            fi
        fi
        # btrfs needs balancing on fresh created raid, else weird things could happen
        [[ "${2}" == "btrfs" && -n "${4}" ]] && btrfs balance start --full-balance "${3}""${5}" &>"${_LOG}"
    fi
    # add to .device-names for config files
    #shellcheck disable=SC2155
    _FSUUID="$(_getfsuuid "${1}")"
    #shellcheck disable=SC2155
    _FSLABEL="$(_getfslabel "${1}")"
    #shellcheck disable=SC2155
    _PARTUUID="$(_getpartuuid "${1}")"
    #shellcheck disable=SC2155
    _PARTLABEL="$(_getpartlabel "${1}")"
    echo "# DEVICE DETAILS: ${1} PARTUUID=${_PARTUUID} PARTLABEL=${_PARTLABEL} UUID=${_FSUUID} LABEL=${_FSLABEL}" >> /tmp/.device-names
    # add to temp fstab
    if [[ "${_NAME_SCHEME_PARAMETER}" == "FSUUID" ]]; then
        if [[ -n "${_FSUUID}" ]]; then
            _DEV="UUID=${_FSUUID}"
        fi
    elif [[ "${_NAME_SCHEME_PARAMETER}" == "FSLABEL" ]]; then
        if [[ -n "${_FSLABEL}" ]]; then
            _DEV="LABEL=${_FSLABEL}"
        fi
    elif [[ "${_NAME_SCHEME_PARAMETER}" == "PARTUUID" ]]; then
            if [[ -n "${_PARTUUID}" ]]; then
                _DEV="PARTUUID=${_PARTUUID}"
            fi
    elif [[ "${_NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]]; then
        if [[ -n "${_PARTLABEL}" ]]; then
            _DEV="PARTLABEL=${_PARTLABEL}"
        fi
    fi
    if [[ -z "${_DEV}" ]]; then
        # fallback to device name
        _DEV="${1}"
    fi
    # / root is not needed in fstab, it's mounted automatically
    # https://www.freedesktop.org/software/systemd/man/systemd-gpt-auto-generator.html
    # systemd supports detection on GPT disks:
    # /boot or /efi as ESP: c12a7328-f81f-11d2-ba4b-00a0c93ec93b
    # /boot as Extended Boot Loader Partition: bc13c2ff-59e6-4262-a352-b275fd6f7172
    # only as vfat supported by auto-generator!
    ### TODO: limine and refind do not support this! STATUS on 10.04.2024
    # firmware, grub and systemd-boot work!
    # "${_GUID_VALUE}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" && "${5}" == "/efi"
    # "${_GUID_VALUE}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" && "${5}" == "/boot"
    # "${_GUID_VALUE}" == "bc13c2ff-59e6-4262-a352-b275fd6f7172" && "${5}" == "/boot" && "${2}" == "vfat"
    # swap:  0657fd6d-a4ab-43c4-84e5-0933c84b4f4f
    # /home: 933ac7e1-2eb4-4f13-b844-0e14e2aef915
    # Complex devices, like mdadm, encrypt or lvm are not supported
    if [[ -z "${_MOUNTOPTIONS}" ]]; then
        _GUID_VALUE="$(${_LSBLK} PARTTYPE "${1}")"
        if ! [[ "${_GUID_VALUE}" == "933ac7e1-2eb4-4f13-b844-0e14e2aef915" && "${5}" == "/home" ||\
                "${_GUID_VALUE}" == "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f" && "${5}" == "swap" ||\
                "${5}" == "/" ]]; then
            if [[ "${_NAME_SCHEME_PARAMETER}" == "SYSTEMD_AUTO_GENERATOR" ]] && \
            ! [[ "${_GUID_VALUE}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" && "${5}" == "/efi" ||\
                 "${_GUID_VALUE}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" && "${5}" == "/boot" ||\
                 "${_GUID_VALUE}" == "bc13c2ff-59e6-4262-a352-b275fd6f7172" && "${5}" == "/boot" ]]; then
                echo -n "${_DEV} ${5} ${2} defaults 0 " >>/tmp/.fstab
                _check_filesystem_fstab "$@"
            else
                echo -n "${_DEV} ${5} ${2} defaults 0 " >>/tmp/.fstab
                _check_filesystem_fstab "$@"
            fi
        fi
    else
        echo -n "${_DEV} ${5} ${2} defaults,${_MOUNTOPTIONS} 0 " >>/tmp/.fstab
        _check_filesystem_fstab "$@"
    fi
}
# vim: set ft=sh ts=4 sw=4 et:
