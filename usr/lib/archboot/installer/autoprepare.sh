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
    _dialog --infobox "Scanning blockdevices ... This may need some time." 3 60
    sleep 2
    _DISKS=$(_blockdevices)
    if [[ "$(echo "${_DISKS}" | wc -w)" -gt 1 ]]; then
        _dialog --cr-wrap --msgbox "Available Disks:\n\n$(_getavaildisks)\n" 0 0
        #shellcheck disable=SC2046
        _dialog --menu "Select the storage drive to use:" 14 55 7 $(_blockdevices _) 2>"${_ANSWER}" || return 1
        _DISK=$(cat "${_ANSWER}")
    else
        _DISK="${_DISKS}"
        if [[ -z "${_DISK}" ]]; then
            _dialog --msgbox "ERROR: Setup cannot find available disk device, please use normal installation routine for partitioning and mounting devices." 0 0
            return 1
        fi
    fi
    _BOOT_DEVICE_SIZE=""
    _GUID_DEVICE_SIZE=""
    _UEFISYS_DEVICE_SIZE=""
    _DEFAULTFS=""
    _UEFISYS_BOOTDEV=""
    _UEFISYS_MP=""
    _UEFISYS_DEVICE_SET=""
    _BOOT_DEVICE_SET=""
    _SWAP_DEVICE_SET=""
    _ROOT_DEVICE_SET=""
    _CHOSEN_FS=""
    # get just the disk size in 1000*1000 MB
    _DISK_SIZE="$(($(${_LSBLK} SIZE -d -b "${_DISK}")/1000000))"
    if [[ -z "${_DISK_SIZE}" ]]; then
        _dialog --msgbox "ERROR: Setup cannot detect size of your device, please use normal installation routine for partitioning and mounting devices." 0 0
        return 1
    fi
    if [[ -z "${_NAME_SCHEME_PARAMETER_RUN}" ]]; then
        _set_device_name_scheme || return 1
    fi
    if [[ -n "${_GUIDPARAMETER}" ]]; then
        _dialog --inputbox "Enter the mountpoint of your UEFI SYSTEM PARTITION (Default is /boot) : " 10 60 "/boot" 2>"${_ANSWER}" || return 1
        _UEFISYS_MP="$(cat "${_ANSWER}")"
    fi
    if [[ "${_UEFISYS_MP}" == "/boot" ]]; then
        _dialog --msgbox "You have chosen to use /boot as the UEFISYS Mountpoint. The minimum partition size is 260 MiB and only FAT32 FS is supported." 0 0
        _UEFISYS_BOOTDEV=1
    fi
    while [[ -z "${_DEFAULTFS}" ]]; do
        _FSOPTS=""
        command -v mkfs.btrfs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} btrfs Btrfs"
        command -v mkfs.ext4 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} ext4 Ext4"
        command -v mkfs.ext3 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} ext3 Ext3"
        command -v mkfs.ext2 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} ext2 Ext2"
        command -v mkfs.xfs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} xfs XFS"
        command -v mkfs.f2fs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} f2fs F2FS"
        command -v mkfs.nilfs2 > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} nilfs2 Nilfs2"
        command -v mkfs.jfs > /dev/null 2>&1 && _FSOPTS="${_FSOPTS} jfs JFS"
        # create 1 MB bios_grub partition for grub BIOS GPT support
        if [[ -n "${_GUIDPARAMETER}" ]]; then
            _GUID_DEVICE_SIZE="2"
            _GPT_BIOS_GRUB_DEVICE_SIZE="${_GUID_DEVICE_SIZE}"
            _DEVICE_NUM=1
            _GPT_BIOS_GRUB_DEVICE_NUM="${_DEVICE_NUM}"
            _DISK_SIZE="$((_DISK_SIZE-_GUID_DEVICE_SIZE))"
        fi
        if [[ -n "${_GUIDPARAMETER}" ]]; then
            if [[ -n "${_UEFISYS_BOOTDEV}" ]]; then
                while [[ -z "${_UEFISYS_DEVICE_SET}" ]]; do
                    _dialog --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 260.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "512" 2>"${_ANSWER}" || return 1
                    _UEFISYS_DEVICE_SIZE="$(cat "${_ANSWER}")"
                    if [[ -z "${_UEFISYS_DEVICE_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                    else
                        if [[ "${_UEFISYS_DEVICE_SIZE}" -ge "${_DISK_SIZE}" || "${_UEFISYS_DEVICE_SIZE}" -lt "260" || "${_UEFISYS_DEVICE_SIZE}" == "${_DISK_SIZE}" ]]; then
                            _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                        else
                            _BOOT_DEVICE_SET=1
                            _UEFISYS_DEVICE_SET=1
                            _DEVICE_NUM="$((_DEVICE_NUM+1))"
                            _UEFISYS_DEVICE_NUM="${_DEVICE_NUM}"
                        fi
                    fi
                done
            else
                while [[ -z "${_UEFISYS_DEVICE_SET}" ]]; do
                    _dialog --inputbox "Enter the size (MB) of your UEFI SYSTEM PARTITION,\nMinimum value is 260.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "1024" 2>"${_ANSWER}" || return 1
                    _UEFISYS_DEVICE_SIZE="$(cat "${_ANSWER}")"
                    if [[ -z "${_UEFISYS_DEVICE_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                    else
                        if [[ "${_UEFISYS_DEVICE_SIZE}" -ge "${_DISK_SIZE}" || "${_UEFISYS_DEVICE_SIZE}" -lt "260" || "${_UEFISYS_DEVICE_SIZE}" == "${_DISK_SIZE}" ]]; then
                            _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                        else
                            _UEFISYS_DEVICE_SET=1
                            _DEVICE_NUM="$((_DEVICE_NUM+1))"
                            _UEFISYS_DEVICE_NUM="${_DEVICE_NUM}"
                        fi
                    fi
                done
            fi
            _DISK_SIZE="$((_DISK_SIZE-_UEFISYS_DEVICE_SIZE))"
            while [[ -z "${_BOOT_DEVICE_SET}" ]]; do
                _dialog --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 100.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "512" 2>"${_ANSWER}" || return 1
                _BOOT_DEVICE_SIZE="$(cat "${_ANSWER}")"
                if [[ -z "${_BOOT_DEVICE_SIZE}" ]]; then
                    _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${_BOOT_DEVICE_SIZE}" -ge "${_DISK_SIZE}" || "${_BOOT_DEVICE_SIZE}" -lt "100" || "${_BOOT_DEVICE_SIZE}" == "${_DISK_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                    else
                        _BOOT_DEVICE_SET=1
                        _DEVICE_NUM="$((_UEFISYS_DEVICE_NUM+1))"
                        _BOOT_DEVICE_NUM="${_DEVICE_NUM}"
                        _DISK_SIZE="$((_DISK_SIZE-_BOOT_DEVICE_SIZE))"
                    fi
                fi
            done
        else
            while [[ -z "${BOOT_DEVICE_SET}" ]]; do
                _dialog --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 100.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "512" 2>"${_ANSWER}" || return 1
                _BOOT_DEVICE_SIZE="$(cat "${_ANSWER}")"
                if [[ -z "${_BOOT_DEVICE_SIZE}" ]]; then
                    _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${_BOOT_DEVICE_SIZE}" -ge "${_DISK_SIZE}" || "${_BOOT_DEVICE_SIZE}" -lt "100" || "${_BOOT_DEVICE_SIZE}" == "${_DISK_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                    else
                        _BOOT_DEVICE_SET=1
                        _DEVICE_NUM=1
                        _BOOT_DEVICE_NUM="${_DEVICE_NUM}"
                        _DISK_SIZE="$((_DISK_SIZE-_BOOT_DEVICE_SIZE))"
                    fi
                fi
            done
        fi
        _SWAP_SIZE="256"
        [[ "${_DISK_SIZE}" -lt "256" ]] && _SWAP_SIZE="${_DISK_SIZE}"
        while [[ -z "${_SWAP_DEVICE_SET}" ]]; do
            _dialog --inputbox "Enter the size (MB) of your swap partition,\nMinimum value is > 0.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "${_SWAP_SIZE}" 2>"${_ANSWER}" || return 1
            _SWAP_DEVICE_SIZE=$(cat "${_ANSWER}")
            if [[ -z "${_SWAP_DEVICE_SIZE}" || "${_SWAP_DEVICE_SIZE}" == 0 ]]; then
                _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
            else
                if [[ "${_SWAP_DEVICE_SIZE}" -ge "${_DISK_SIZE}" ]]; then
                    _dialog --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                else
                    _SWAP_DEVICE_SET=1
                    _DEVICE_NUM="$((_DEVICE_NUM+1))"
                    _SWAP_DEVICE_NUM="${_DEVICE_NUM}"
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
            _DISK_SIZE="$((_DISK_SIZE-_SWAP_DEVICE_SIZE))"
            _ROOT_SIZE="7500"
            [[ "${_DISK_SIZE}" -lt "7500" ]] && _ROOT_SIZE="${_DISK_SIZE}"
            while [[ -z "${_ROOT_DEVICE_SET}" ]]; do
            _dialog --inputbox "Enter the size (MB) of your / partition\nMinimum value is 2000,\nthe /home partition will use the remaining space.\n\nDisk space left:  ${_DISK_SIZE} MB" 10 65 "${_ROOT_SIZE}" 2>"${_ANSWER}" || return 1
            _ROOT_DEVICE_SIZE=$(cat "${_ANSWER}")
                if [[ -z "${_ROOT_DEVICE_SIZE}" || "${_ROOT_DEVICE_SIZE}" == 0 || "${_ROOT_DEVICE_SIZE}" -lt "2000" ]]; then
                    _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                else
                    if [[ "${_ROOT_DEVICE_SIZE}" -ge "${_DISK_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                    else
                        _dialog --yesno "$((_DISK_SIZE-_ROOT_DEVICE_SIZE)) MB will be used for your /home partition. Is this OK?" 0 0 && _ROOT_DEVICE_SET=1
                    fi
                fi
            done
        fi
        _DEVICE_NUM="$((_DEVICE_NUM+1))"
        _ROOT_DEVICE_NUM="${_DEVICE_NUM}"
        if ! [[ "${_FSTYPE}" == "btrfs" ]]; then
            _DEVICE_NUM="$((_DEVICE_NUM+1))"
        fi
        _HOME_DEVICE_NUM="${_DEVICE_NUM}"
        _DEFAULTFS=1
    done
    _dialog --defaultno --yesno "${_DISK} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 \
    || return 1
    # validate DEVICE
    if [[ ! -b "${_DISK}" ]]; then
      _dialog --msgbox "Error: Device '${_DISK}' is not valid." 0 0
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
    if [[ -n "${_GUIDPARAMETER}" ]]; then
        # GPT (GUID) is supported only by 'parted' or 'sgdisk'
        _printk off
        _dialog --infobox "Partitioning ${_DISK} ..." 0 0
        # clean partition table to avoid issues!
        sgdisk --zap "${_DISK}" &>/dev/null
        # clear all magic strings/signatures - mdadm, lvm, partition tables etc.
        dd if=/dev/zero of="${_DISK}" bs=512 count=2048 &>/dev/null
        wipefs -a "${_DISK}" &>/dev/null
        # create fresh GPT
        sgdisk --clear "${_DISK}" &>/dev/null
        # create actual partitions
        sgdisk --set-alignment="2048" --new="${_GPT_BIOS_GRUB_DEVICE_NUM}":0:+"${_GPT_BIOS_GRUB_DEVICE_SIZE}"M --typecode="${_GPT_BIOS_GRUB_DEVICE_NUM}":EF02 --change-name="${_GPT_BIOS_GRUB_DEVICE_NUM}":BIOS_GRUB "${_DISK}" > "${_LOG}"
        sgdisk --set-alignment="2048" --new="${_UEFISYS_DEVICE_NUM}":0:+"${_UEFISYS_DEVICE_SIZE}"M --typecode="${_UEFISYS_DEVICE_NUM}":EF00 --change-name="${_UEFISYS_DEVICE_NUM}":UEFI_SYSTEM "${_DISK}" > "${_LOG}"
        if [[ -n "${_UEFISYS_BOOTDEV}" ]]; then
            sgdisk --attributes="${_UEFISYS_DEVICE_NUM}":set:2 "${_DISK}" > "${_LOG}"
        else
            sgdisk --set-alignment="2048" --new="${_BOOT_DEVICE_NUM}":0:+"${_BOOT_DEVICE_SIZE}"M --typecode="${_BOOT_DEVICE_NUM}":8300 --attributes="${_BOOT_DEVICE_NUM}":set:2 --change-name="${_BOOT_DEVICE_NUM}":ARCHLINUX_BOOT "${_DISK}" > "${_LOG}"
        fi
        sgdisk --set-alignment="2048" --new="${_SWAP_DEVICE_NUM}":0:+"${_SWAP_DEVICE_SIZE}"M --typecode="${_SWAP_DEVICE_NUM}":8200 --change-name="${_SWAP_DEVICE_NUM}":ARCHLINUX_SWAP "${_DISK}" > "${_LOG}"
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            sgdisk --set-alignment="2048" --new="${_ROOT_DEVICE_NUM}":0:0 --typecode="${_ROOT_DEVICE_NUM}":8300 --change-name="${_ROOT_DEVICE_NUM}":ARCHLINUX_ROOT "${_DISK}" > "${_LOG}"
        else
            sgdisk --set-alignment="2048" --new="${_ROOT_DEVICE_NUM}":0:+"${_ROOT_DEVICE_SIZE}"M --typecode="${_ROOT_DEVICE_NUM}":8300 --change-name="${_ROOT_DEVICE_NUM}":ARCHLINUX_ROOT "${_DISK}" > "${_LOG}"
            sgdisk --set-alignment="2048" --new="${_HOME_DEVICE_NUM}":0:0 --typecode="${_HOME_DEVICE_NUM}":8302 --change-name="${_HOME_DEVICE_NUM}":ARCHLINUX_HOME "${_DISK}" > "${_LOG}"
        fi
        sgdisk --print "${_DISK}" > "${_LOG}"
    else
        # start at sector 1 for 4k drive compatibility and correct alignment
        _printk off
        _dialog --infobox "Partitioning ${_DISK}" 0 0
        # clean partitiontable to avoid issues!
        dd if=/dev/zero of="${_DISK}" bs=512 count=2048 >/dev/null 2>&1
        wipefs -a "${_DISK}" &>/dev/null
        # create DOS MBR with parted
        parted -a optimal -s "${_DISK}" unit MiB mktable msdos >/dev/null 2>&1
        parted -a optimal -s "${_DISK}" unit MiB mkpart primary 1 $((_GUID_DEVICE_SIZE+_BOOT_DEVICE_SIZE)) >"${_LOG}"
        parted -a optimal -s "${_DISK}" unit MiB set 1 boot on >"${_LOG}"
        parted -a optimal -s "${_DISK}" unit MiB mkpart primary $((_GUID_DEVICE_SIZE+_BOOT_DEVICE_SIZE)) $((_GUID_DEVICE_SIZE+_BOOT_DEVICE_SIZE+_SWAP_DEVICE_SIZE)) >"${_LOG}"
        # $(sgdisk -E ${DEVICE}) | grep ^[0-9] as end of last partition to keep the possibilty to convert to GPT later, instead of 100%
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            parted -a optimal -s "${_DISK}" unit MiB mkpart primary $((_GUID_DEVICE_SIZE+_BOOT_DEVICE_SIZE+_SWAP_DEVICE_SIZE)) "$(sgdisk -E "${_DISK}" | grep "^[0-9]")S" >"${_LOG}"
        else
            parted -a optimal -s "${_DISK}" unit MiB mkpart primary $((_GUID_DEVICE_SIZE+_BOOT_DEVICE_SIZE+_SWAP_DEVICE_SIZE)) $((_GUID_DEVICE_SIZE+_BOOT_DEVICE_SIZE+_SWAP_DEVICE_SIZE+_ROOT_DEVICE_SIZE)) >"${_LOG}"
            parted -a optimal -s "${_DISK}" unit MiB mkpart primary $((_GUID_DEVICE_SIZE+_BOOT_DEVICE_SIZE+_SWAP_DEVICE_SIZE+_ROOT_DEVICE_SIZE)) "$(sgdisk -E "${_DISK}" | grep "^[0-9]")S" >"${_LOG}"
        fi
    fi
    #shellcheck disable=SC2181
    if [[ $? -gt 0 ]]; then
        _dialog --msgbox "Error: Partitioning ${_DISK} (see ${_LOG} for details)." 0 0
        _printk on
        return 1
    fi
    # reread partitiontable for kernel
    partprobe "${_DISK}"
    _printk on
    ## wait until /dev initialized correct devices
    udevadm settle
    ## FSSPECS - default filesystem specs
    ## <partnum>:<mountpoint>:<fstype>:<fsoptions>:labelname
    ## The partitions in FSSPECS list should be listed in the "mountpoint" order.
    ## Make sure the "root" partition is defined first in the FSSPECS list
    _FSSPEC_ROOT_DEVICE="${_ROOT_DEVICE_NUM}:/:${_FSTYPE}::ROOT_ARCH"
    _FSSPEC_HOME_DEVICE="${_HOME_DEVICE_NUM}:/home:${_FSTYPE}::HOME_ARCH"
    _FSSPEC_SWAP_DEVICE="${_SWAP_DEVICE_NUM}:swap:swap::SWAP_ARCH"
    _FSSPEC_BOOT_DEVICE="${_BOOT_DEVICE_NUM}:/boot:ext2::BOOT_ARCH"
    _FSSPEC_UEFISYS_DEVICE="${_UEFISYS_DEVICE_NUM}:${_UEFISYS_MP}:vfat::EFISYS"
    if [[ -n "${_GUIDPARAMETER}" ]]; then
        if [[ -n "${_UEFISYS_BOOTDEV}" ]]; then
            _FSSPECS="${_FSSPEC_ROOT_DEVICE} ${_FSSPEC_UEFISYS_DEVICE} ${_FSSPEC_HOME_DEVICE} ${_FSSPEC_SWAP_DEVICE}"
        else
            _FSSPECS="${_FSSPEC_ROOT_DEVICE} ${_FSSPEC_BOOT_DEVICE} ${_FSSPEC_UEFISYS_DEVICE} ${_FSSPEC_HOME_DEVICE} ${_FSSPEC_SWAP_DEVICE}"
        fi
    else
        _FSSPECS="${_FSSPEC_ROOT_DEVICE} ${_FSSPEC_BOOT_DEVICE} ${_FSSPEC_HOME_DEVICE} ${_FSSPEC_SWAP_DEVICE}"
    fi
    ## make and mount filesystems
    for fsspec in ${_FSSPECS}; do
        _DOMKFS=1
        _DEVICE="${_DISK}$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d:)"
        # Add check on nvme or mmc controller:
        # NVME uses /dev/nvme0n1pX name scheme
        # MMC uses /dev/mmcblk0pX
        if echo "${_DISK}" | grep -q "nvme" || echo "${_DISK}" | grep -q "mmc"; then
            _DEVICE="${_DISK}p$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d:)"
        fi
        _MP="$(echo "${fsspec}" | tr -d ' ' | cut -f2 -d:)"
        _FSTYPE="$(echo "${fsspec}" | tr -d ' ' | cut -f3 -d:)"
        _FS_OPTIONS="$(echo "${fsspec}" | tr -d ' ' | cut -f4 -d:)"
        _LABEL_NAME="$(echo "${fsspec}" | tr -d ' ' | cut -f5 -d:)"
        _BTRFS_DEVICES="${_DEVICE}"
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            _BTRFS_COMPRESS="compress=zstd"
            [[ "${_MP}" == "/" ]] && _BTRFS_SUBVOLUME="root"
            [[ "${_MP}" == "/home" ]] && _BTRFS_SUBVOLUME="home" && _DOMKFS=""
        else
            _BTRFS_COMPRESS=""
            _BTRFS_SUBVOLUME=""
        fi
        _BTRFS_LEVEL=""
        _mkfs "${_DEVICE}" "${_FSTYPE}" "${_DESTDIR}" "${_DOMKFS}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" \
              "${_BTRFS_DEVICES}" "${_BTRFS_LEVEL}" "${_BTRFS_SUBVOLUME}" "${_BTRFS_COMPRESS}" || return 1
        sleep 1
    done
    _dialog --infobox "Auto-Prepare was successful. Continuing in 3 seconds ..." 3 70
    sleep 3
    _S_MKFSAUTO=1
}
