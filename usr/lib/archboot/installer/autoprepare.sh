#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
autoprepare() {
    # check on encrypted devices, else weird things can happen!
    _stopluks
    # check on raid devices, else weird things can happen during partitioning!
    _stopmd
    # check on lvm devices, else weird things can happen during partitioning!
    _stoplvm
    NAME_SCHEME_PARAMETER_RUN=""
    # switch for mbr usage
    set_guid
    : >/tmp/.device-names
    DISCS=$(blockdevices)
    if [[ "$(echo "${DISCS}" | wc -w)" -gt 1 ]]; then
        DIALOG --cr-wrap --msgbox "Available Disks:\n\n$(_getavaildisks)\n" 0 0
        #shellcheck disable=SC2046
        DIALOG --menu "Select the storage drive to use" 14 55 7 $(blockdevices _) 2>"${ANSWER}" || return 1
        DISC=$(cat "${ANSWER}")
    else
        DISC="${DISCS}"
        if [[ "${DISC}" = "" ]]; then
            DIALOG --msgbox "ERROR: Setup cannot find available disk device, please use normal installation routine for partitioning and mounting devices." 0 0
            return 1
        fi
    fi
    BOOT_PART_SIZE=""
    GUID_PART_SIZE=""
    UEFISYS_PART_SIZE=""
    DEFAULTFS=""
    _UEFISYS_BOOTPART=""
    UEFISYS_MOUNTPOINT=""
    UEFISYS_PART_SET=""
    BOOT_PART_SET=""
    SWAP_PART_SET=""
    ROOT_PART_SET=""
    CHOSEN_FS=""
    # get just the disk size in 1000*1000 MB
    DISC_SIZE="$(($(${_LSBLK} SIZE -d -b "${DISC}")/1000000))"
    if [[ "${DISC_SIZE}" = "" ]]; then
        DIALOG --msgbox "ERROR: Setup cannot detect size of your device, please use normal installation routine for partitioning and mounting devices." 0 0
        return 1
    fi

    if [[  "${GUIDPARAMETER}" = "yes" ]]; then
        DIALOG --inputbox "Enter the mountpoint of your UEFI SYSTEM PARTITION (Default is /boot) : " 0 0 "/boot" 2>"${ANSWER}" || return 1
        UEFISYS_MOUNTPOINT="$(cat "${ANSWER}")"
    fi

    if [[ "${UEFISYS_MOUNTPOINT}" == "/boot" ]]; then
        DIALOG --msgbox "You have chosen to use /boot as the UEFISYS Mountpoint. The minimum partition size is 260 MiB and only FAT32 FS is supported" 0 0
        _UEFISYS_BOOTPART="1"
    fi

    while [[ "${DEFAULTFS}" = "" ]]; do
        FSOPTS=""
        [[ "$(which mkfs.btrfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} btrfs Btrfs"
        [[ "$(which mkfs.ext4 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext4 Ext4"
        [[ "$(which mkfs.ext3 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext3 Ext3"
        [[ "$(which mkfs.ext2 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext2 Ext2"
        [[ "$(which mkfs.xfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} xfs XFS"
        [[ "$(which mkfs.f2fs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} f2fs F2FS"
        [[ "$(which mkfs.nilfs2 2>/dev/null)" ]] && FSOPTS="${FSOPTS} nilfs2 Nilfs2"
        [[ "$(which mkfs.jfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} jfs JFS"

        # create 1 MB bios_grub partition for grub BIOS GPT support
        if [[ "${GUIDPARAMETER}" = "yes" ]]; then
            GUID_PART_SIZE="2"
            GPT_BIOS_GRUB_PART_SIZE="${GUID_PART_SIZE}"
            _PART_NUM="1"
            _GPT_BIOS_GRUB_PART_NUM="${_PART_NUM}"
            DISC_SIZE="$((DISC_SIZE-GUID_PART_SIZE))"
        fi

        if [[ "${GUIDPARAMETER}" = "yes" ]]; then
            if [[ "${_UEFISYS_BOOTPART}" == "1" ]]; then
                while [[ "${UEFISYS_PART_SET}" = "" ]]; do
                    DIALOG --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 260.\n\nDisk space left: ${DISC_SIZE} MB" 10 65 "512" 2>"${ANSWER}" || return 1
                    UEFISYS_PART_SIZE="$(cat "${ANSWER}")"
                    if [[ "${UEFISYS_PART_SIZE}" = "" ]]; then
                        DIALOG --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                    else
                        if [[ "${UEFISYS_PART_SIZE}" -ge "${DISC_SIZE}" || "${UEFISYS_PART_SIZE}" -lt "260" || "${UEFISYS_PART_SIZE}" = "${DISC_SIZE}" ]]; then
                            DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                        else
                            BOOT_PART_SET=1
                            UEFISYS_PART_SET=1
                            _PART_NUM="$((_PART_NUM+1))"
                            _UEFISYS_PART_NUM="${_PART_NUM}"
                        fi
                    fi
                done
            else
                while [[ "${UEFISYS_PART_SET}" = "" ]]; do
                    DIALOG --inputbox "Enter the size (MB) of your UEFI SYSTEM PARTITION,\nMinimum value is 260.\n\nDisk space left: ${DISC_SIZE} MB" 10 65 "1024" 2>"${ANSWER}" || return 1
                    UEFISYS_PART_SIZE="$(cat "${ANSWER}")"
                    if [[ "${UEFISYS_PART_SIZE}" = "" ]]; then
                        DIALOG --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                    else
                        if [[ "${UEFISYS_PART_SIZE}" -ge "${DISC_SIZE}" || "${UEFISYS_PART_SIZE}" -lt "260" || "${UEFISYS_PART_SIZE}" = "${DISC_SIZE}" ]]; then
                            DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                        else
                            UEFISYS_PART_SET=1
                            _PART_NUM="$((_PART_NUM+1))"
                            _UEFISYS_PART_NUM="${_PART_NUM}"
                        fi
                    fi
                done
            fi
            DISC_SIZE="$((DISC_SIZE-UEFISYS_PART_SIZE))"

            while [[ "${BOOT_PART_SET}" = "" ]]; do
                DIALOG --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 16.\n\nDisk space left: ${DISC_SIZE} MB" 10 65 "512" 2>"${ANSWER}" || return 1
                BOOT_PART_SIZE="$(cat "${ANSWER}")"
                if [[ "${BOOT_PART_SIZE}" = "" ]]; then
                    DIALOG --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${BOOT_PART_SIZE}" -ge "${DISC_SIZE}" || "${BOOT_PART_SIZE}" -lt "16" || "${BOOT_PART_SIZE}" = "${DISC_SIZE}" ]]; then
                        DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                    else
                        BOOT_PART_SET=1
                        _PART_NUM="$((_UEFISYS_PART_NUM+1))"
                        _BOOT_PART_NUM="${_PART_NUM}"
                        DISC_SIZE="$((DISC_SIZE-BOOT_PART_SIZE))"
                    fi
                fi
            done

        else
            while [[ "${BOOT_PART_SET}" = "" ]]; do
                DIALOG --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 16.\n\nDisk space left: ${DISC_SIZE} MB" 10 65 "512" 2>"${ANSWER}" || return 1
                BOOT_PART_SIZE="$(cat "${ANSWER}")"
                if [[ "${BOOT_PART_SIZE}" = "" ]]; then
                    DIALOG --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${BOOT_PART_SIZE}" -ge "${DISC_SIZE}" || "${BOOT_PART_SIZE}" -lt "16" || "${BOOT_PART_SIZE}" = "${DISC_SIZE}" ]]; then
                        DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                    else
                         BOOT_PART_SET=1
                        _PART_NUM="1"
                        _BOOT_PART_NUM="${_PART_NUM}"
                        DISC_SIZE="$((DISC_SIZE-BOOT_PART_SIZE))"
                    fi
                fi
            done
        fi

        SWAP_SIZE="256"
        [[ "${DISC_SIZE}" -lt "256" ]] && SWAP_SIZE="${DISC_SIZE}"
        while [[ "${SWAP_PART_SET}" = "" ]]; do
            DIALOG --inputbox "Enter the size (MB) of your swap partition,\nMinimum value is > 0.\n\nDisk space left: ${DISC_SIZE} MB" 10 65 "${SWAP_SIZE}" 2>"${ANSWER}" || return 1
            SWAP_PART_SIZE=$(cat "${ANSWER}")
            if [[ "${SWAP_PART_SIZE}" = "" || "${SWAP_PART_SIZE}" = "0" ]]; then
                DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
            else
                if [[ "${SWAP_PART_SIZE}" -ge "${DISC_SIZE}" ]]; then
                    DIALOG --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                else
                    SWAP_PART_SET=1
                    _PART_NUM="$((_PART_NUM+1))"
                    _SWAP_PART_NUM="${_PART_NUM}"
                fi
            fi
        done

        while [[ "${CHOSEN_FS}" = "" ]]; do
            #shellcheck disable=SC2086
            DIALOG --menu "Select a filesystem for / and /home:" 16 45 9 ${FSOPTS} 2>"${ANSWER}" || return 1
            FSTYPE=$(cat "${ANSWER}")
            DIALOG --yesno "${FSTYPE} will be used for / and /home. Is this OK?" 0 0 && CHOSEN_FS=1
        done
        # / and /home are subvolumes on btrfs
        if ! [[ "${FSTYPE}" = "btrfs" ]]; then
            DISC_SIZE="$((DISC_SIZE-SWAP_PART_SIZE))"
            ROOT_SIZE="7500"
            [[ "${DISC_SIZE}" -lt "7500" ]] && ROOT_SIZE="${DISC_SIZE}"
            while [[ "${ROOT_PART_SET}" = "" ]]; do
            DIALOG --inputbox "Enter the size (MB) of your / partition\nMinimum value is 2000,\nthe /home partition will use the remaining space.\n\nDisk space left:  ${DISC_SIZE} MB" 10 65 "${ROOT_SIZE}" 2>"${ANSWER}" || return 1
            ROOT_PART_SIZE=$(cat "${ANSWER}")
                if [[ "${ROOT_PART_SIZE}" = "" || "${ROOT_PART_SIZE}" = "0" || "${ROOT_PART_SIZE}" -lt "2000" ]]; then
                    DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                else
                    if [[ "${ROOT_PART_SIZE}" -ge "${DISC_SIZE}" ]]; then
                        DIALOG --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                    else
                        DIALOG --yesno "$((DISC_SIZE-ROOT_PART_SIZE)) MB will be used for your /home partition. Is this OK?" 0 0 && ROOT_PART_SET=1
                    fi
                fi
            done
        fi
        _PART_NUM="$((_PART_NUM+1))"
        _ROOT_PART_NUM="${_PART_NUM}"
        if ! [[ "${FSTYPE}" = "btrfs" ]]; then
            _PART_NUM="$((_PART_NUM+1))"
        fi
        _HOME_PART_NUM="${_PART_NUM}"
        DEFAULTFS=1
    done

    DIALOG --defaultno --yesno "${DISC} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 \
    || return 1
    DEVICE=${DISC}

    # validate DEVICE
    if [[ ! -b "${DEVICE}" ]]; then
      DIALOG --msgbox "Device '${DEVICE}' is not valid" 0 0
      return 1
    fi

    # validate DEST
    if [[ ! -d "${DESTDIR}" ]]; then
        DIALOG --msgbox "Destination directory '${DESTDIR}' is not valid" 0 0
        return 1
    fi

    [[ -e /tmp/.fstab ]] && rm -f /tmp/.fstab
    # disable swap and all mounted partitions, umount / last!
    _umountall

    # we assume a /dev/sdX,/dev/vdX or /dev/nvmeXnY format
    if [[ "${GUIDPARAMETER}" == "yes" ]]; then
        # GPT (GUID) is supported only by 'parted' or 'sgdisk'
        printk off
        DIALOG --infobox "Partitioning ${DEVICE}" 0 0
        # clean partition table to avoid issues!
        sgdisk --zap "${DEVICE}" &>/dev/null
        # clear all magic strings/signatures - mdadm, lvm, partition tables etc.
        dd if=/dev/zero of="${DEVICE}" bs=512 count=2048 &>/dev/null
        wipefs -a "${DEVICE}" &>/dev/null
        # create fresh GPT
        sgdisk --clear "${DEVICE}" &>/dev/null
        # create actual partitions
        sgdisk --set-alignment="2048" --new=${_GPT_BIOS_GRUB_PART_NUM}:0:+${GPT_BIOS_GRUB_PART_SIZE}M --typecode=${_GPT_BIOS_GRUB_PART_NUM}:EF02 --change-name=${_GPT_BIOS_GRUB_PART_NUM}:BIOS_GRUB "${DEVICE}" > "${LOG}"
        sgdisk --set-alignment="2048" --new=${_UEFISYS_PART_NUM}:0:+"${UEFISYS_PART_SIZE}"M --typecode=${_UEFISYS_PART_NUM}:EF00 --change-name=${_UEFISYS_PART_NUM}:UEFI_SYSTEM "${DEVICE}" > "${LOG}"

        if [[ "${_UEFISYS_BOOTPART}" == "1" ]]; then
            sgdisk --attributes=${_UEFISYS_PART_NUM}:set:2 "${DEVICE}" > "${LOG}"
        else
            sgdisk --set-alignment="2048" --new=${_BOOT_PART_NUM}:0:+"${BOOT_PART_SIZE}"M --typecode=${_BOOT_PART_NUM}:8300 --attributes=${_BOOT_PART_NUM}:set:2 --change-name=${_BOOT_PART_NUM}:ARCHLINUX_BOOT "${DEVICE}" > "${LOG}"
        fi

        sgdisk --set-alignment="2048" --new=${_SWAP_PART_NUM}:0:+"${SWAP_PART_SIZE}"M --typecode=${_SWAP_PART_NUM}:8200 --change-name=${_SWAP_PART_NUM}:ARCHLINUX_SWAP "${DEVICE}" > "${LOG}"
        if [[ "${FSTYPE}" = "btrfs" ]]; then
            sgdisk --set-alignment="2048" --new=${_ROOT_PART_NUM}:0:0 --typecode=${_ROOT_PART_NUM}:8300 --change-name=${_ROOT_PART_NUM}:ARCHLINUX_ROOT "${DEVICE}" > "${LOG}"
        else
            sgdisk --set-alignment="2048" --new=${_ROOT_PART_NUM}:0:+"${ROOT_PART_SIZE}"M --typecode=${_ROOT_PART_NUM}:8300 --change-name=${_ROOT_PART_NUM}:ARCHLINUX_ROOT "${DEVICE}" > "${LOG}"
            sgdisk --set-alignment="2048" --new=${_HOME_PART_NUM}:0:0 --typecode=${_HOME_PART_NUM}:8302 --change-name=${_HOME_PART_NUM}:ARCHLINUX_HOME "${DEVICE}" > "${LOG}"
        fi
        sgdisk --print "${DEVICE}" > "${LOG}"
    else
        # start at sector 1 for 4k drive compatibility and correct alignment
        printk off
        DIALOG --infobox "Partitioning ${DEVICE}" 0 0
        # clean partitiontable to avoid issues!
        dd if=/dev/zero of="${DEVICE}" bs=512 count=2048 >/dev/null 2>&1
        wipefs -a "${DEVICE}" &>/dev/null
        # create DOS MBR with parted
        parted -a optimal -s "${DEVICE}" unit MiB mktable msdos >/dev/null 2>&1
        parted -a optimal -s "${DEVICE}" unit MiB mkpart primary 1 $((GUID_PART_SIZE+BOOT_PART_SIZE)) >"${LOG}"
        parted -a optimal -s "${DEVICE}" unit MiB set 1 boot on >"${LOG}"
        parted -a optimal -s "${DEVICE}" unit MiB mkpart primary $((GUID_PART_SIZE+BOOT_PART_SIZE)) $((GUID_PART_SIZE+BOOT_PART_SIZE+SWAP_PART_SIZE)) >"${LOG}"
        # $(sgdisk -E ${DEVICE}) | grep ^[0-9] as end of last partition to keep the possibilty to convert to GPT later, instead of 100%
        if [[ "${FSTYPE}" = "btrfs" ]]; then
            parted -a optimal -s "${DEVICE}" unit MiB mkpart primary $((GUID_PART_SIZE+BOOT_PART_SIZE+SWAP_PART_SIZE)) "$(sgdisk -E "${DEVICE}" | grep "^[0-9]")S" >"${LOG}"
        else
            parted -a optimal -s "${DEVICE}" unit MiB mkpart primary $((GUID_PART_SIZE+BOOT_PART_SIZE+SWAP_PART_SIZE)) $((GUID_PART_SIZE+BOOT_PART_SIZE+SWAP_PART_SIZE+ROOT_PART_SIZE)) >"${LOG}"
            parted -a optimal -s "${DEVICE}" unit MiB mkpart primary $((GUID_PART_SIZE+BOOT_PART_SIZE+SWAP_PART_SIZE+ROOT_PART_SIZE)) "$(sgdisk -E "${DEVICE}" | grep "^[0-9]")S" >"${LOG}"
        fi
    fi
    #shellcheck disable=SC2181
    if [[ $? -gt 0 ]]; then
        DIALOG --msgbox "Error partitioning ${DEVICE} (see ${LOG} for details)" 0 0
        printk on
        return 1
    fi
    # reread partitiontable for kernel
    partprobe "${DEVICE}"
    printk on
    ## wait until /dev initialized correct devices
    udevadm settle

    if [[ "${NAME_SCHEME_PARAMETER_RUN}" == "" ]]; then
        set_device_name_scheme || return 1
    fi
    ## FSSPECS - default filesystem specs (the + is bootable flag)
    ## <partnum>:<mountpoint>:<partsize>:<fstype>[:<fsoptions>][:+]:labelname
    ## The partitions in FSSPECS list should be listed in the "mountpoint" order.
    ## Make sure the "root" partition is defined first in the FSSPECS list

    _FSSPEC_ROOT_PART="${_ROOT_PART_NUM}:/:${FSTYPE}::ROOT_ARCH"
    _FSSPEC_HOME_PART="${_HOME_PART_NUM}:/home:${FSTYPE}::HOME_ARCH"
    _FSSPEC_SWAP_PART="${_SWAP_PART_NUM}:swap:swap::SWAP_ARCH"

    _FSSPEC_BOOT_PART="${_BOOT_PART_NUM}:/boot:ext2::BOOT_ARCH"
    _FSSPEC_UEFISYS_PART="${_UEFISYS_PART_NUM}:${UEFISYS_MOUNTPOINT}:vfat:-F32:EFISYS"

    if [[ "${GUIDPARAMETER}" == "yes" ]]; then
        if [[ "${_UEFISYS_BOOTPART}" == "1" ]]; then
            FSSPECS="${_FSSPEC_ROOT_PART} ${_FSSPEC_UEFISYS_PART} ${_FSSPEC_HOME_PART} ${_FSSPEC_SWAP_PART}"
        else
            FSSPECS="${_FSSPEC_ROOT_PART} ${_FSSPEC_BOOT_PART} ${_FSSPEC_UEFISYS_PART} ${_FSSPEC_HOME_PART} ${_FSSPEC_SWAP_PART}"
        fi
    else
        FSSPECS="${_FSSPEC_ROOT_PART} ${_FSSPEC_BOOT_PART} ${_FSSPEC_HOME_PART} ${_FSSPEC_SWAP_PART}"
    fi

    ## make and mount filesystems
    for fsspec in ${FSSPECS}; do
        DOMKFS="yes"
        PART="${DEVICE}$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d:)"
        # Add check on nvme controller: Uses /dev/nvme0n1pX name scheme
        echo "${DEVICE}" | grep -q "nvme" && PART="${DEVICE}p$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d:)"
        MP="$(echo "${fsspec}" | tr -d ' ' | cut -f2 -d:)"
        FSTYPE="$(echo "${fsspec}" | tr -d ' ' | cut -f3 -d:)"
        FS_OPTIONS="$(echo "${fsspec}" | tr -d ' ' | cut -f4 -d:)"
        [[ "${FS_OPTIONS}" == "" ]] && FS_OPTIONS="NONE"
        LABEL_NAME="$(echo "${fsspec}" | tr -d ' ' | cut -f5 -d:)"
        BTRFS_DEVICES="${PART}"
        if [[ "${FSTYPE}" = "btrfs" ]]; then
            BTRFS_COMPRESS="compress=zstd"
            [[ "${MP}" = "/" ]] && BTRFS_SUBVOLUME="root"
            [[ "${MP}" = "/home" ]] && BTRFS_SUBVOLUME="home" && DOMKFS="no"
            DOSUBVOLUME="yes"
        else
            BTRFS_COMPRESS="NONE"
            BTRFS_SUBVOLUME="NONE"
            DOSUBVOLUME="no"
        fi
        BTRFS_LEVEL="NONE"
        if ! [[ "${FSTYPE}" = "swap" ]]; then
            DIALOG --infobox "Creating ${FSTYPE} on ${PART}\nwith FSLABEL ${LABEL_NAME} ,\nmounting to ${DESTDIR}${MP}" 0 0
        else
            DIALOG --infobox "Creating and activating swapspace on ${PART}" 0 0
        fi
        _mkfs "${DOMKFS}" "${PART}" "${FSTYPE}" "${DESTDIR}" "${MP}" "${LABEL_NAME}" "${FS_OPTIONS}" "${BTRFS_DEVICES}" ${BTRFS_LEVEL} ${BTRFS_SUBVOLUME} ${DOSUBVOLUME} ${BTRFS_COMPRESS} || return 1
        sleep 3
    done

    DIALOG --infobox "Auto-prepare was successful.\nContinuing in 3 seconds..." 0 0
    sleep 3
    S_MKFSAUTO=1
}
