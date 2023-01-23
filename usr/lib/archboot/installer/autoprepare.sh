#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_autoprepare() {
    # check on special devices and stop them, else weird things can happen during partitioning!
    _stopluks
    _stopmd
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
        if [[ -z "${_DISK}" ]]; then
            _dialog --msgbox "ERROR: Setup cannot find available disk device, please use normal installation routine for partitioning and mounting devices." 0 0
            return 1
        fi
    fi
    _DEFAULTFS=""
    _CHOSENFS=""
    _UEFISYS_BOOTDEV=""
    _UEFISYS_MP=""
    _UEFISYSDEV_SET=""
    _BOOTDEV_SET=""
    _SWAPDEV_SET=""
    _ROOTDEV_SET=""
    _BOOTDEV_SIZE=""
    _UEFISYSDEV_SIZE=""
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
        _dialog --inputbox "Enter the mountpoint of your EFI SYSTEM PARTITION (Default is /boot or use /efi for a separate partition): " 10 60 "/boot" 2>"${_ANSWER}" || return 1
        _UEFISYS_MP="$(cat "${_ANSWER}")"
    fi
    if [[ "${_UEFISYS_MP}" == "/boot" ]]; then
        _dialog --msgbox "You have chosen to use /boot as the ESP Mountpoint. The minimum partition size is 260 MiB and only FAT32 FS is supported." 0 0
        _UEFISYS_BOOTDEV=1
    fi
    while [[ -z "${_DEFAULTFS}" ]]; do
        _FSOPTS=""
        command -v mkfs.btrfs &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} btrfs Btrfs"
        command -v mkfs.ext4 &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} ext4 Ext4"
        command -v mkfs.ext3 &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} ext3 Ext3"
        command -v mkfs.ext2 &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} ext2 Ext2"
        command -v mkfs.xfs &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} xfs XFS"
        command -v mkfs.f2fs &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} f2fs F2FS"
        command -v mkfs.nilfs2 &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} nilfs2 Nilfs2"
        command -v mkfs.jfs &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} jfs JFS"
        # create 1 MB bios_grub partition for grub BIOS GPT support
        if [[ -n "${_GUIDPARAMETER}" ]]; then
            _GPT_BIOS_GRUB_DEV_SIZE="2"
            _DEV_NUM=1
            _GPT_BIOS_GRUB_DEV_NUM="${_DEV_NUM}"
            _DISK_SIZE="$((_DISK_SIZE-_GPT_BIOS_GRUB_DEV_SIZE))"
            if [[ -n "${_UEFISYS_BOOTDEV}" ]]; then
                while [[ -z "${_UEFISYSDEV_SET}" ]]; do
                    _dialog --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 260.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "512" 2>"${_ANSWER}" || return 1
                    _UEFISYSDEV_SIZE="$(cat "${_ANSWER}")"
                    if [[ -z "${_UEFISYSDEV_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                    else
                        if [[ "${_UEFISYSDEV_SIZE}" -ge "${_DISK_SIZE}" || "${_UEFISYSDEV_SIZE}" -lt "260" || "${_UEFISYSDEV_SIZE}" == "${_DISK_SIZE}" ]]; then
                            _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                        else
                            _BOOTDEV_SET=1
                            _UEFISYSDEV_SET=1
                            _DEV_NUM="$((_DEV_NUM+1))"
                            _UEFISYSDEV_NUM="${_DEV_NUM}"
                        fi
                    fi
                done
            else
                while [[ -z "${_UEFISYSDEV_SET}" ]]; do
                    _dialog --inputbox "Enter the size (MB) of your EFI SYSTEM PARTITION,\nMinimum value is 260.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "1024" 2>"${_ANSWER}" || return 1
                    _UEFISYSDEV_SIZE="$(cat "${_ANSWER}")"
                    if [[ -z "${_UEFISYSDEV_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                    else
                        if [[ "${_UEFISYSDEV_SIZE}" -ge "${_DISK_SIZE}" || "${_UEFISYSDEV_SIZE}" -lt "260" || "${_UEFISYSDEV_SIZE}" == "${_DISK_SIZE}" ]]; then
                            _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                        else
                            _UEFISYSDEV_SET=1
                            _DEV_NUM="$((_DEV_NUM+1))"
                            _UEFISYSDEV_NUM="${_DEV_NUM}"
                        fi
                    fi
                done
            fi
            _DISK_SIZE="$((_DISK_SIZE-_UEFISYSDEV_SIZE))"
            while [[ -z "${_BOOTDEV_SET}" ]]; do
                _dialog --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 100.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "512" 2>"${_ANSWER}" || return 1
                _BOOTDEV_SIZE="$(cat "${_ANSWER}")"
                if [[ -z "${_BOOTDEV_SIZE}" ]]; then
                    _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${_BOOTDEV_SIZE}" -ge "${_DISK_SIZE}" || "${_BOOTDEV_SIZE}" -lt "100" || "${_BOOTDEV_SIZE}" == "${_DISK_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                    else
                        _BOOTDEV_SET=1
                        _DEV_NUM="$((_UEFISYSDEV_NUM+1))"
                        _BOOTDEV_NUM="${_DEV_NUM}"
                        _DISK_SIZE="$((_DISK_SIZE-_BOOTDEV_SIZE))"
                    fi
                fi
            done
        else
            while [[ -z "${_BOOTDEV_SET}" ]]; do
                _dialog --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 100.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "512" 2>"${_ANSWER}" || return 1
                _BOOTDEV_SIZE="$(cat "${_ANSWER}")"
                if [[ -z "${_BOOTDEV_SIZE}" ]]; then
                    _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${_BOOTDEV_SIZE}" -ge "${_DISK_SIZE}" || "${_BOOTDEV_SIZE}" -lt "100" || "${_BOOTDEV_SIZE}" == "${_DISK_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                    else
                        _BOOTDEV_SET=1
                        _DEV_NUM=1
                        _BOOTDEV_NUM="${_DEV_NUM}"
                        _DISK_SIZE="$((_DISK_SIZE-_BOOTDEV_SIZE))"
                    fi
                fi
            done
        fi
        _SWAP_SIZE="256"
        [[ "${_DISK_SIZE}" -lt "256" ]] && _SWAP_SIZE="${_DISK_SIZE}"
        while [[ -z "${_SWAPDEV_SET}" ]]; do
            _dialog --inputbox "Enter the size (MB) of your swap partition,\nMinimum value is > 0.\n\nDisk space left: ${_DISK_SIZE} MB" 10 65 "${_SWAP_SIZE}" 2>"${_ANSWER}" || return 1
            _SWAPDEV_SIZE=$(cat "${_ANSWER}")
            if [[ -z "${_SWAPDEV_SIZE}" || "${_SWAPDEV_SIZE}" == 0 ]]; then
                _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
            else
                if [[ "${_SWAPDEV_SIZE}" -ge "${_DISK_SIZE}" ]]; then
                    _dialog --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                else
                    _SWAPDEV_SET=1
                    _DEV_NUM="$((_DEV_NUM+1))"
                    _SWAPDEV_NUM="${_DEV_NUM}"
                fi
            fi
        done
        while [[ -z "${_CHOSENFS}" ]]; do
            #shellcheck disable=SC2086
            _dialog --menu "Select a filesystem for / and /home:" 16 45 9 ${_FSOPTS} 2>"${_ANSWER}" || return 1
            _FSTYPE=$(cat "${_ANSWER}")
            _dialog --yesno "${_FSTYPE} will be used for\n/ and /home. Is this OK?" 0 0 && _CHOSENFS=1
        done
        # / and /home are subvolumes on btrfs
        if ! [[ "${_FSTYPE}" == "btrfs" ]]; then
            _DISK_SIZE="$((_DISK_SIZE-_SWAPDEV_SIZE))"
            _ROOT_SIZE="7500"
            [[ "${_DISK_SIZE}" -lt "7500" ]] && _ROOT_SIZE="${_DISK_SIZE}"
            while [[ -z "${_ROOTDEV_SET}" ]]; do
            _dialog --inputbox "Enter the size (MB) of your / partition\nMinimum value is 2000,\nthe /home partition will use the remaining space.\n\nDisk space left:  ${_DISK_SIZE} MB" 10 65 "${_ROOT_SIZE}" 2>"${_ANSWER}" || return 1
            _ROOTDEV_SIZE=$(cat "${_ANSWER}")
                if [[ -z "${_ROOTDEV_SIZE}" || "${_ROOTDEV_SIZE}" == 0 || "${_ROOTDEV_SIZE}" -lt "2000" ]]; then
                    _dialog --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                else
                    if [[ "${_ROOTDEV_SIZE}" -ge "${_DISK_SIZE}" ]]; then
                        _dialog --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                    else
                        _dialog --yesno "$((_DISK_SIZE-_ROOTDEV_SIZE)) MB will be used for your /home partition. Is this OK?" 0 0 && _ROOTDEV_SET=1
                    fi
                fi
            done
        fi
        _DEV_NUM="$((_DEV_NUM+1))"
        _ROOTDEV_NUM="${_DEV_NUM}"
        if ! [[ "${_FSTYPE}" == "btrfs" ]]; then
            _DEV_NUM="$((_DEV_NUM+1))"
        fi
        _HOMEDEV_NUM="${_DEV_NUM}"
        _DEFAULTFS=1
    done
    _dialog --defaultno --yesno "${_DISK} will be COMPLETELY ERASED!\nALL DATA ON ${_DISK} WILL BE LOST.\n\nAre you absolutely sure?" 0 0 || return 1
    [[ -e /tmp/.fstab ]] && rm -f /tmp/.fstab
    _umountall
    # disable swap and all mounted partitions, umount / last!
    _printk off
    _dialog --infobox "Partitioning ${_DISK}..." 0 0
    _clean_disk "${_DISK}"
    # we assume a /dev/sdX,/dev/vdX or /dev/nvmeXnY format
    if [[ -n "${_GUIDPARAMETER}" ]]; then
        # GPT (GUID) is supported only by 'parted' or 'sgdisk'
        # create fresh GPT
        sgdisk --clear "${_DISK}" &>"${_NO_LOG}"
        # create actual partitions
        sgdisk --new="${_GPT_BIOS_GRUB_DEV_NUM}":0:+"${_GPT_BIOS_GRUB_DEV_SIZE}"M --typecode="${_GPT_BIOS_GRUB_DEV_NUM}":EF02 --change-name="${_GPT_BIOS_GRUB_DEV_NUM}":BIOS_GRUB "${_DISK}" >"${_LOG}"
        sgdisk --new="${_UEFISYSDEV_NUM}":0:+"${_UEFISYSDEV_SIZE}"M --typecode="${_UEFISYSDEV_NUM}":EF00 --change-name="${_UEFISYSDEV_NUM}":EFI_SYSTEM_PARTITION "${_DISK}" >"${_LOG}"
        if [[ -n "${_UEFISYS_BOOTDEV}" ]]; then
            # set the legacy BIOS boot 2bit attribute
            sgdisk --attributes="${_UEFISYSDEV_NUM}":set:2 "${_DISK}" >"${_LOG}"
        else
            sgdisk --new="${_BOOTDEV_NUM}":0:+"${_BOOTDEV_SIZE}"M --typecode="${_BOOTDEV_NUM}":EA00 --attributes="${_BOOTDEV_NUM}":set:2 --change-name="${_BOOTDEV_NUM}":ARCHLINUX_BOOT "${_DISK}" >"${_LOG}"
        fi
        sgdisk --new="${_SWAPDEV_NUM}":0:+"${_SWAPDEV_SIZE}"M --typecode="${_SWAPDEV_NUM}":8200 --change-name="${_SWAPDEV_NUM}":ARCHLINUX_SWAP "${_DISK}" >"${_LOG}"
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            sgdisk --new="${_ROOTDEV_NUM}":0:0 --typecode="${_ROOTDEV_NUM}":8304 --change-name="${_ROOTDEV_NUM}":ARCHLINUX_ROOT "${_DISK}" >"${_LOG}"
        else
            sgdisk --new="${_ROOTDEV_NUM}":0:+"${_ROOTDEV_SIZE}"M --typecode="${_ROOTDEV_NUM}":8304 --change-name="${_ROOTDEV_NUM}":ARCHLINUX_ROOT "${_DISK}" >"${_LOG}"
            sgdisk --new="${_HOMEDEV_NUM}":0:0 --typecode="${_HOMEDEV_NUM}":8302 --change-name="${_HOMEDEV_NUM}":ARCHLINUX_HOME "${_DISK}" >"${_LOG}"
        fi
        sgdisk --print "${_DISK}" >"${_LOG}"
    else
        # start at sector 1 for 4k drive compatibility and correct alignment
        # create DOS MBR with parted
        parted -a optimal -s "${_DISK}" unit MiB mktable msdos &>"${_NO_LOG}"
        parted -a optimal -s "${_DISK}" unit MiB mkpart primary 1 $((_BOOTDEV_SIZE)) >"${_LOG}"
        parted -a optimal -s "${_DISK}" unit MiB set 1 boot on >"${_LOG}"
        parted -a optimal -s "${_DISK}" unit MiB mkpart primary $((_BOOTDEV_SIZE)) $((_BOOTDEV_SIZE+_SWAPDEV_SIZE)) >"${_LOG}"
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            parted -a optimal -s "${_DISK}" unit MiB mkpart primary $((_BOOTDEV_SIZE+_SWAPDEV_SIZE)) "$(sgdisk -E "${_DISK}" | grep "^[0-9]")S" >"${_LOG}"
        else
            parted -a optimal -s "${_DISK}" unit MiB mkpart primary $((_BOOTDEV_SIZE+_SWAPDEV_SIZE)) $((_BOOTDEV_SIZE+_SWAPDEV_SIZE+_ROOTDEV_SIZE)) >"${_LOG}"
            parted -a optimal -s "${_DISK}" unit MiB mkpart primary $((_BOOTDEV_SIZE+_SWAPDEV_SIZE+_ROOTDEV_SIZE)) "$(sgdisk -E "${_DISK}" | grep "^[0-9]")S" >"${_LOG}"
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
    ## <partnum>:<fstype>:<mountpoint>:<labelname>
    ## The partitions in FSSPECS list should be listed in the "mountpoint" order.
    ## Make sure the "root" partition is defined first in the FSSPECS list
    _FSSPEC_ROOTDEV="${_ROOTDEV_NUM}:${_FSTYPE}:/:ARCHLINUX_ROOT"
    _FSSPEC_HOMEDEV="${_HOMEDEV_NUM}:${_FSTYPE}:/home:ARCHLINUX_HOME"
    _FSSPEC_SWAPDEV="${_SWAPDEV_NUM}:swap:swap:ARCHLINUX_SWAP"
    _FSSPEC_BOOTDEV="${_BOOTDEV_NUM}:ext2:/boot:ARCHLINUX_BOOT"
    _FSSPEC_UEFISYSDEV="${_UEFISYSDEV_NUM}:vfat:${_UEFISYS_MP}:EFI_SYSTEM_PARTITION"
    if [[ -n "${_GUIDPARAMETER}" ]]; then
        if [[ -n "${_UEFISYS_BOOTDEV}" ]]; then
            _FSSPECS="${_FSSPEC_ROOTDEV} ${_FSSPEC_UEFISYSDEV} ${_FSSPEC_HOMEDEV} ${_FSSPEC_SWAPDEV}"
        else
            _FSSPECS="${_FSSPEC_ROOTDEV} ${_FSSPEC_BOOTDEV} ${_FSSPEC_UEFISYSDEV} ${_FSSPEC_HOMEDEV} ${_FSSPEC_SWAPDEV}"
        fi
    else
        _FSSPECS="${_FSSPEC_ROOTDEV} ${_FSSPEC_BOOTDEV} ${_FSSPEC_HOMEDEV} ${_FSSPEC_SWAPDEV}"
    fi
    ## make and mount filesystems
    for fsspec in ${_FSSPECS}; do
        _DEV="${_DISK}$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d:)"
        # Add check on nvme or mmc controller:
        # NVME uses /dev/nvme0n1pX name scheme
        # MMC uses /dev/mmcblk0pX
        if echo "${_DISK}" | grep -q "nvme" || echo "${_DISK}" | grep -q "mmc"; then
            _DEV="${_DISK}p$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d:)"
        fi
        _FSTYPE="$(echo "${fsspec}" | tr -d ' ' | cut -f2 -d:)"
        _DOMKFS=1
        _MP="$(echo "${fsspec}" | tr -d ' ' | cut -f3 -d:)"
        _LABEL_NAME="$(echo "${fsspec}" | tr -d ' ' | cut -f4 -d:)"
        _FS_OPTIONS=""
        _BTRFS_DEVS="${_DEV}"
        _BTRFS_LEVEL=""
        _BTRFS_SUBVOLUME=""
        _BTRFS_COMPRESS=""
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            [[ "${_MP}" == "/" ]] && _BTRFS_SUBVOLUME="root"
            [[ "${_MP}" == "/home" ]] && _BTRFS_SUBVOLUME="home" && _DOMKFS=""
            _BTRFS_COMPRESS="compress=zstd"
        fi
        _mkfs "${_DEV}" "${_FSTYPE}" "${_DESTDIR}" "${_DOMKFS}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" \
              "${_BTRFS_DEVS}" "${_BTRFS_LEVEL}" "${_BTRFS_SUBVOLUME}" "${_BTRFS_COMPRESS}" || return 1
        sleep 1
    done
    _dialog --infobox "Auto-Prepare was successful.\nContinuing in 5 seconds..." 4 40
    sleep 5
    _S_MKFSAUTO=1
}
