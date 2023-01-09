#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_autoprepare() {
    # check on encrypted devices, else weird things can happen!
    _stopluks
    # check on raid devices, else weird things can happen during partitioning!
    _stopmd
    # check on lvm devices, else weird things can happen during partitioning!
    _stoplvm
    _NAME_SCHEME_PARAMETER_RUN=""
    # switch for mbr usage
    _set_guid
    : >/tmp/.device-names
    _DISKS=$(_blockdevices)
    if [[ "$(echo "${_DISKS}" | wc -w)" -gt 1 ]]; then
        _dialog --cr-wrap --msgbox "Available Disks:\n\n$(_getavaildisks)\n" 0 0
        #shellcheck disable=SC2046
        _dialog --menu "Select the storage drive to use:" 14 55 7 $(_blockdevices _) 2>"${_ANSWER}" || return 1
        _DISK=$(cat "${_ANSWER}")
    else
        _DISK="${_DISKS}"
        if [[ "${_DISK}" == "" ]]; then
            _dialog --msgbox "ERROR: Setup cannot find available disk device, please use normal installation routine for partitioning and mounting devices." 0 0
            return 1
        fi
    fi
    _BOOT_PART_SIZE=""
    _GUID_PART_SIZE=""
    _UEFISYS_PART_SIZE=""
    _DEFAULTFS=""
    _UEFISYS_BOOTPART=""
    _UEFISYS_MP=""
    _UEFISYS_PART_SET=""
    _BOOT_PART_SET=""
    _SWAP_PART_SET=""
    _ROOT_PART_SET=""
    _CHOSEN_FS=""
    # get just the disk size in 1000*1000 MB
    _DISK_SIZE="$(($(${_LSBLK} SIZE -d -b "${_DISK}")/1000000))"
    if [[ "${_DISK_SIZE}" == "" ]]; then
        _dialog --msgbox "ERROR: Setup cannot detect size of your device, please use normal installation routine for partitioning and mounting devices." 0 0
        return 1
    fi
    if [[ -z "${_NAME_SCHEME_PARAMETER_RUN}" ]]; then
        _set_device_name_scheme || return 1
    fi
    if [[  "${_GUIDPARAMETER}" == "1" ]]; then
        _dialog --inputbox "Enter the mountpoint of your UEFI SYSTEM PARTITION (Default is /boot) : " 10 60 "/boot" 2>"${_ANSWER}" || return 1
        _UEFISYS_MP="$(cat "${_ANSWER}")"
    fi
    if [[ "${_UEFISYS_MP}" == "/boot" ]]; then
        _dialog --msgbox "You have chosen to use /boot as the UEFISYS Mountpoint. The minimum partition size is 260 MiB and only FAT32 FS is supported." 0 0
        _UEFISYS_BOOTPART="1"
    fi
    while [[ "${_DEFAULTFS}" == "" ]]; do
        _FSOPTS=""
        command -v mkfs.btrfs 2>/dev/null && _FSOPTS="${_FSOPTS} btrfs Btrfs"
        command -v mkfs.ext4 2>/dev/null && _FSOPTS="${_FSOPTS} ext4 Ext4"
        command -v mkfs.ext3 2>/dev/null && _FSOPTS="${_FSOPTS} ext3 Ext3"
        command -v mkfs.ext2 2>/dev/null && _FSOPTS="${_FSOPTS} ext2 Ext2"
        command -v mkfs.xfs 2>/dev/null && _FSOPTS="${_FSOPTS} xfs XFS"
        command -v mkfs.f2fs 2>/dev/null && _FSOPTS="${_FSOPTS} f2fs F2FS"
        command -v mkfs.nilfs2 2>/dev/null && _FSOPTS="${_FSOPTS} nilfs2 Nilfs2"
        command -v mkfs.jfs 2>/dev/null && _FSOPTS="${_FSOPTS} jfs JFS"
        # create 1 MB bios_grub partition for grub BIOS GPT support
        if [[ "${_GUIDPARAMETER}" == "1" ]]; then
            _GUID_PART_SIZE="2"
            _GPT_BIOS_GRUB_PART_SIZE="${_GUID_PART_SIZE}"
            _PART_NUM="1"
            _GPT_BIOS_GRUB_PART_NUM="${_PART_NUM}"
            _DISK_SIZE="$((_DISK_SIZE-_GUID_PART_SIZE))"
        fi
        if [[ "${_GUIDPARAMETER}" == "1" ]]; then
            if [[ "${_UEFISYS_BOOTPART}" == "1" ]]; then
                while [[ -z "${_UEFISYS_PART_SET}" ]]; do
                    _dialog --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 260.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "512" 2>"${_ANSWER}" || return 1
                    _UEFISYS_PART_SIZE="$(cat "${_ANSWER}")"
                    if [[ -z "${_UEFISYS_PART_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                    else
                        if [[ "${_UEFISYS_PART_SIZE}" -ge "${_DISK_SIZE}" || "${_UEFISYS_PART_SIZE}" -lt "260" || "${_UEFISYS_PART_SIZE}" == "${_DISK_SIZE}" ]]; then
                            _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                        else
                            _BOOT_PART_SET=1
                            _UEFISYS_PART_SET=1
                            _PART_NUM="$((_PART_NUM+1))"
                            _UEFISYS_PART_NUM="${_PART_NUM}"
                        fi
                    fi
                done
            else
                while [[ -z "${_UEFISYS_PART_SET}" ]]; do
                    _dialog --inputbox "Enter the size (MB) of your UEFI SYSTEM PARTITION,\nMinimum value is 260.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "1024" 2>"${_ANSWER}" || return 1
                    _UEFISYS_PART_SIZE="$(cat "${_ANSWER}")"
                    if [[ -z "${_UEFISYS_PART_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                    else
                        if [[ "${_UEFISYS_PART_SIZE}" -ge "${_DISK_SIZE}" || "${_UEFISYS_PART_SIZE}" -lt "260" || "${_UEFISYS_PART_SIZE}" == "${_DISK_SIZE}" ]]; then
                            _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                        else
                            _UEFISYS_PART_SET=1
                            _PART_NUM="$((_PART_NUM+1))"
                            _UEFISYS_PART_NUM="${_PART_NUM}"
                        fi
                    fi
                done
            fi
            _DISK_SIZE="$((_DISK_SIZE-_UEFISYS_PART_SIZE))"
            while [[ -z "${_BOOT_PART_SET}" ]]; do
                _dialog --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 16.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "512" 2>"${_ANSWER}" || return 1
                _BOOT_PART_SIZE="$(cat "${_ANSWER}")"
                if [[ -z "${_BOOT_PART_SIZE}" ]]; then
                    _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${_BOOT_PART_SIZE}" -ge "${_DISK_SIZE}" || "${_BOOT_PART_SIZE}" -lt "16" || "${_BOOT_PART_SIZE}" == "${_DISK_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                    else
                        _BOOT_PART_SET=1
                        _PART_NUM="$((_UEFISYS_PART_NUM+1))"
                        _BOOT_PART_NUM="${_PART_NUM}"
                        _DISK_SIZE="$((_DISK_SIZE-_BOOT_PART_SIZE))"
                    fi
                fi
            done
        else
            while [[ -z "${BOOT_PART_SET}" ]]; do
                _dialog --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 16.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "512" 2>"${_ANSWER}" || return 1
                _BOOT_PART_SIZE="$(cat "${_ANSWER}")"
                if [[ -z "${_BOOT_PART_SIZE}" ]]; then
                    _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${_BOOT_PART_SIZE}" -ge "${_DISK_SIZE}" || "${_BOOT_PART_SIZE}" -lt "16" || "${_BOOT_PART_SIZE}" == "${_DISK_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                    else
                        _BOOT_PART_SET=1
                        _PART_NUM="1"
                        _BOOT_PART_NUM="${_PART_NUM}"
                        _DISK_SIZE="$((_DISK_SIZE-_BOOT_PART_SIZE))"
                    fi
                fi
            done
        fi
        _SWAP_SIZE="256"
        [[ "${_DISK_SIZE}" -lt "256" ]] && _SWAP_SIZE="${_DISK_SIZE}"
        while [[ -z "${_SWAP_PART_SET}" ]]; do
            _dialog --inputbox "Enter the size (MB) of your swap partition,\nMinimum value is > 0.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "${_SWAP_SIZE}" 2>"${_ANSWER}" || return 1
            _SWAP_PART_SIZE=$(cat "${_ANSWER}")
            if [[ -z "${_SWAP_PART_SIZE}" || "${_SWAP_PART_SIZE}" == "0" ]]; then
                _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
            else
                if [[ "${_SWAP_PART_SIZE}" -ge "${_DISK_SIZE}" ]]; then
                    _dialog --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                else
                    _SWAP_PART_SET=1
                    _PART_NUM="$((_PART_NUM+1))"
                    _SWAP_PART_NUM="${_PART_NUM}"
                fi
            fi
        done
        while [[ -z "${_CHOSEN_FS}" ]]; do
            #shellcheck disable=SC2086
            _dialog --menu "Select a filesystem for / and /home:" 16 45 9 ${_FSOPTS} 2>"${_ANSWER}" || return 1
            _FSTYPE=$(cat "${_ANSWER}")
            _dialog --yesno "${_FSTYPE} will be used for / and /home. Is this OK?" 0 0 && _CHOSEN_FS=1
        done
        # / and /home are subvolumes on btrfs
        if ! [[ "${_FSTYPE}" == "btrfs" ]]; then
            _DISK_SIZE="$((_DISK_SIZE-_SWAP_PART_SIZE))"
            _ROOT_SIZE="7500"
            [[ "${_DISK_SIZE}" -lt "7500" ]] && _ROOT_SIZE="${_DISK_SIZE}"
            while [[ -z "${_ROOT_PART_SET}" ]]; do
            _dialog --inputbox "Enter the size (MB) of your / partition\nMinimum value is 2000,\nthe /home partition will use the remaining space.\n\nDisk space left:  ${_DISK_SIZE} MB" 10 65 "${_ROOT_SIZE}" 2>"${_ANSWER}" || return 1
            _ROOT_PART_SIZE=$(cat "${_ANSWER}")
                if [[ -z "${_ROOT_PART_SIZE}" || "${_ROOT_PART_SIZE}" == "0" || "${_ROOT_PART_SIZE}" -lt "2000" ]]; then
                    _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                else
                    if [[ "${_ROOT_PART_SIZE}" -ge "${_DISK_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                    else
                        _dialog --yesno "$((_DISK_SIZE-_ROOT_PART_SIZE)) MB will be used for your /home partition. Is this OK?" 0 0 && _ROOT_PART_SET=1
                    fi
                fi
            done
        fi
        _PART_NUM="$((_PART_NUM+1))"
        _ROOT_PART_NUM="${_PART_NUM}"
        if ! [[ "${_FSTYPE}" == "btrfs" ]]; then
            _PART_NUM="$((_PART_NUM+1))"
        fi
        _HOME_PART_NUM="${_PART_NUM}"
        _DEFAULTFS=1
    done
    _dialog --defaultno --yesno "${_DISK} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 \
    || return 1
    _DEVICE=${_DISK}
    # validate DEVICE
    if [[ ! -b "${_DEVICE}" ]]; then
      _dialog --msgbox "Error: Device '${_DEVICE}' is not valid." 0 0
      return 1
    fi
    # validate DEST
    if [[ ! -d "${_DESTDIR}" ]]; then
        _dialog --msgbox "Error: Destination directory '${_DESTDIR}' is not valid." 0 0
        return 1
    fi
    [[ -e /tmp/.fstab ]] && rm -f /tmp/.fstab
    # disable swap and all mounted partitions, umount / last!
    _umountall
    # we assume a /dev/sdX,/dev/vdX or /dev/nvmeXnY format
    if [[ "${_GUIDPARAMETER}" == "1" ]]; then
        # GPT (GUID) is supported only by 'parted' or 'sgdisk'
        _printk off
        _dialog --infobox "Partitioning ${_DEVICE} ..." 0 0
        # clean partition table to avoid issues!
        sgdisk --zap "${_DEVICE}" &>/dev/null
        # clear all magic strings/signatures - mdadm, lvm, partition tables etc.
        dd if=/dev/zero of="${_DEVICE}" bs=512 count=2048 &>/dev/null
        wipefs -a "${_DEVICE}" &>/dev/null
        # create fresh GPT
        sgdisk --clear "${_DEVICE}" &>/dev/null
        # create actual partitions
        sgdisk --set-alignment="2048" --new="${_GPT_BIOS_GRUB_PART_NUM}":0:+"${_GPT_BIOS_GRUB_PART_SIZE}"M --typecode="${_GPT_BIOS_GRUB_PART_NUM}":EF02 --change-name="${_GPT_BIOS_GRUB_PART_NUM}":BIOS_GRUB "${_DEVICE}" > "${_LOG}"
        sgdisk --set-alignment="2048" --new="${_UEFISYS_PART_NUM}":0:+"${_UEFISYS_PART_SIZE}"M --typecode="${_UEFISYS_PART_NUM}":EF00 --change-name="${_UEFISYS_PART_NUM}":UEFI_SYSTEM "${_DEVICE}" > "${_LOG}"
        if [[ "${_UEFISYS_BOOTPART}" == "1" ]]; then
            sgdisk --attributes="${_UEFISYS_PART_NUM}":set:2 "${_DEVICE}" > "${_LOG}"
        else
            sgdisk --set-alignment="2048" --new="${_BOOT_PART_NUM}":0:+"${_BOOT_PART_SIZE}"M --typecode="${_BOOT_PART_NUM}":8300 --attributes="${_BOOT_PART_NUM}":set:2 --change-name="${_BOOT_PART_NUM}":ARCHLINUX_BOOT "${_DEVICE}" > "${_LOG}"
        fi
        sgdisk --set-alignment="2048" --new="${_SWAP_PART_NUM}":0:+"${_SWAP_PART_SIZE}"M --typecode="${_SWAP_PART_NUM}":8200 --change-name="${_SWAP_PART_NUM}":ARCHLINUX_SWAP "${_DEVICE}" > "${_LOG}"
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            sgdisk --set-alignment="2048" --new="${_ROOT_PART_NUM}":0:0 --typecode="${_ROOT_PART_NUM}":8300 --change-name="${_ROOT_PART_NUM}":ARCHLINUX_ROOT "${_DEVICE}" > "${_LOG}"
        else
            sgdisk --set-alignment="2048" --new="${_ROOT_PART_NUM}":0:+"${_ROOT_PART_SIZE}"M --typecode="${_ROOT_PART_NUM}":8300 --change-name="${_ROOT_PART_NUM}":ARCHLINUX_ROOT "${_DEVICE}" > "${_LOG}"
            sgdisk --set-alignment="2048" --new="${_HOME_PART_NUM}":0:0 --typecode="${_HOME_PART_NUM}":8302 --change-name="${_HOME_PART_NUM}":ARCHLINUX_HOME "${_DEVICE}" > "${_LOG}"
        fi
        sgdisk --print "${_DEVICE}" > "${_LOG}"
    else
        # start at sector 1 for 4k drive compatibility and correct alignment
        _printk off
        _dialog --infobox "Partitioning ${_DEVICE}" 0 0
        # clean partitiontable to avoid issues!
        dd if=/dev/zero of="${_DEVICE}" bs=512 count=2048 >/dev/null 2>&1
        wipefs -a "${_DEVICE}" &>/dev/null
        # create DOS MBR with parted
        parted -a optimal -s "${_DEVICE}" unit MiB mktable msdos >/dev/null 2>&1
        parted -a optimal -s "${_DEVICE}" unit MiB mkpart primary 1 $((_GUID_PART_SIZE+_BOOT_PART_SIZE)) >"${_LOG}"
        parted -a optimal -s "${_DEVICE}" unit MiB set 1 boot on >"${_LOG}"
        parted -a optimal -s "${_DEVICE}" unit MiB mkpart primary $((_GUID_PART_SIZE+_BOOT_PART_SIZE)) $((_GUID_PART_SIZE+_BOOT_PART_SIZE+_SWAP_PART_SIZE)) >"${_LOG}"
        # $(sgdisk -E ${DEVICE}) | grep ^[0-9] as end of last partition to keep the possibilty to convert to GPT later, instead of 100%
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            parted -a optimal -s "${_DEVICE}" unit MiB mkpart primary $((_GUID_PART_SIZE+_BOOT_PART_SIZE+_SWAP_PART_SIZE)) "$(sgdisk -E "${_DEVICE}" | grep "^[0-9]")S" >"${_LOG}"
        else
            parted -a optimal -s "${_DEVICE}" unit MiB mkpart primary $((_GUID_PART_SIZE+_BOOT_PART_SIZE+_SWAP_PART_SIZE)) $((_GUID_PART_SIZE+_BOOT_PART_SIZE+_SWAP_PART_SIZE+_ROOT_PART_SIZE)) >"${_LOG}"
            parted -a optimal -s "${_DEVICE}" unit MiB mkpart primary $((_GUID_PART_SIZE+_BOOT_PART_SIZE+_SWAP_PART_SIZE+_ROOT_PART_SIZE)) "$(sgdisk -E "${_DEVICE}" | grep "^[0-9]")S" >"${_LOG}"
        fi
    fi
    #shellcheck disable=SC2181
    if [[ $? -gt 0 ]]; then
        _dialog --msgbox "Error: Partitioning ${_DEVICE} (see ${_LOG} for details)." 0 0
        _printk on
        return 1
    fi
    # reread partitiontable for kernel
    partprobe "${_DEVICE}"
    _printk on
    ## wait until /dev initialized correct devices
    udevadm settle
    ## FSSPECS - default filesystem specs (the + is bootable flag)
    ## <partnum>:<mountpoint>:<partsize>:<fstype>[:<fsoptions>][:+]:labelname
    ## The partitions in FSSPECS list should be listed in the "mountpoint" order.
    ## Make sure the "root" partition is defined first in the FSSPECS list
    _FSSPEC_ROOT_PART="${_ROOT_PART_NUM}:/:${_FSTYPE}::ROOT_ARCH"
    _FSSPEC_HOME_PART="${_HOME_PART_NUM}:/home:${_FSTYPE}::HOME_ARCH"
    _FSSPEC_SWAP_PART="${_SWAP_PART_NUM}:swap:swap::SWAP_ARCH"
    _FSSPEC_BOOT_PART="${_BOOT_PART_NUM}:/boot:ext2::BOOT_ARCH"
    _FSSPEC_UEFISYS_PART="${_UEFISYS_PART_NUM}:${_UEFISYS_MP}:vfat:-F32:EFISYS"
    if [[ "${_GUIDPARAMETER}" == "1" ]]; then
        if [[ "${_UEFISYS_BOOTPART}" == "1" ]]; then
            _FSSPECS="${_FSSPEC_ROOT_PART} ${_FSSPEC_UEFISYS_PART} ${_FSSPEC_HOME_PART} ${_FSSPEC_SWAP_PART}"
        else
            _FSSPECS="${_FSSPEC_ROOT_PART} ${_FSSPEC_BOOT_PART} ${_FSSPEC_UEFISYS_PART} ${_FSSPEC_HOME_PART} ${_FSSPEC_SWAP_PART}"
        fi
    else
        _FSSPECS="${_FSSPEC_ROOT_PART} ${_FSSPEC_BOOT_PART} ${_FSSPEC_HOME_PART} ${_FSSPEC_SWAP_PART}"
    fi
    ## make and mount filesystems
    for fsspec in ${_FSSPECS}; do
        _DOMKFS="yes"
        _PART="${_DEVICE}$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d:)"
        # Add check on nvme or mmc controller:
        # NVME uses /dev/nvme0n1pX name scheme
        # MMC uses /dev/mmcblk0pX
        if echo "${_DEVICE}" | grep -q "nvme" || echo "${_DEVICE}" | grep -q "mmc"; then
            _PART="${_DEVICE}p$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d:)"
        fi
        _MP="$(echo "${fsspec}" | tr -d ' ' | cut -f2 -d:)"
        _FSTYPE="$(echo "${fsspec}" | tr -d ' ' | cut -f3 -d:)"
        _FS_OPTIONS="$(echo "${fsspec}" | tr -d ' ' | cut -f4 -d:)"
        [[ -z "${_FS_OPTIONS}" ]] && _FS_OPTIONS="NONE"
        _LABEL_NAME="$(echo "${fsspec}" | tr -d ' ' | cut -f5 -d:)"
        _BTRFS_DEVICES="${_PART}"
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            _BTRFS_COMPRESS="compress=zstd"
            [[ "${_MP}" == "/" ]] && _BTRFS_SUBVOLUME="root"
            [[ "${_MP}" == "/home" ]] && _BTRFS_SUBVOLUME="home" && _DOMKFS="no"
            _DOSUBVOLUME="yes"
        else
            _BTRFS_COMPRESS="NONE"
            _BTRFS_SUBVOLUME="NONE"
            _DOSUBVOLUME="no"
        fi
        _BTRFS_LEVEL="NONE"
        if ! [[ "${_FSTYPE}" == "swap" ]]; then
            _dialog --infobox "Creating ${_FSTYPE} on ${_PART}\nwith FSLABEL ${_LABEL_NAME} ,\nmounting to ${_DESTDIR}${_MP} ..." 0 0
        else
            _dialog --infobox "Creating and activating\nswapspace on\n${_PART} ..." 0 0
        fi
        _mkfs "${_DOMKFS}" "${_PART}" "${_FSTYPE}" "${_DESTDIR}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" "${_BTRFS_DEVICES}" ${_BTRFS_LEVEL} "${_BTRFS_SUBVOLUME}" ${_DOSUBVOLUME} ${_BTRFS_COMPRESS} || return 1
        sleep 1
    done
    _dialog --infobox "Auto-Prepare was successful. Continuing in 3 seconds ..." 3 70
    sleep 3
    _S_MKFSAUTO=1
}
