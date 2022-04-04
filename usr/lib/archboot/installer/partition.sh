#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
detect_DISC() {

    if [[ "${DISC}" == "" ]] || ! echo "${DISC}" | grep -q '/dev/'; then
        DISC="$(${_LSBLK} PKNAME "$(findmnt -vno SOURCE "${DESTDIR}/boot")")"
    fi

    if [[ "${DISC}" == "" ]]; then
        DISC="$(${_LSBLK} PKNAME "$(findmnt -vno SOURCE "${DESTDIR}/")")"
    fi

}

check_gpt() {

    GUID_DETECTED=""
    [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${DISC}")" == "gpt" ]] && GUID_DETECTED="1"

    if [[ "${GUID_DETECTED}" == "" ]]; then
        DIALOG --yesno "Setup detected no GUID (gpt) partition table on ${DISC}.\n\nDo you want to convert the existing MBR table in ${DISC} to a GUID (gpt) partition table?" 0 0 || return 1
        sgdisk --mbrtogpt "${DISC}" > "${LOG}" && GUID_DETECTED="1"
        # reread partitiontable for kernel
        partprobe "${DISC}" > "${LOG}"
        if [[ "${GUID_DETECTED}" == "" ]]; then
            DIALOG --defaultno --yesno "Conversion failed on ${DISC}.\nSetup detected no GUID (gpt) partition table on ${DISC}.\n\nDo you want to create a new GUID (gpt) table now on ${DISC}?\n\n${DISC} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 || return 1
            # clean partition table to avoid issues!
            sgdisk --zap "${DISC}" &>/dev/null
            # clear all magic strings/signatures - mdadm, lvm, partition tables etc.
            dd if=/dev/zero of="${DISC}" bs=512 count=2048 &>/dev/null
            wipefs -a "${DISC}" &>/dev/null
            # create fresh GPT
            sgdisk --clear "${DISC}" &>/dev/null
            GUID_DETECTED="1"
        fi
    fi

    if [[ "${GUID_DETECTED}" == "1" ]]; then
        ### This check is not enabled in any function yet!
        if [[ "${CHECK_UEFISYS_PART}" == "1" ]]; then
            check_efisys_part
        fi

        if [[ "${CHECK_BIOS_BOOT_GRUB}" == "1" ]]; then
            if ! sgdisk -p "${DISC}" | grep -q 'EF02'; then
                DIALOG --msgbox "Setup detected no BIOS BOOT PARTITION in ${DISC}. Please create a >=1 MB BIOS Boot partition for grub BIOS GPT support." 0 0
                RUN_CFDISK="1"
            fi
        fi
    fi

    if [[ "${RUN_CFDISK}" == "1" ]]; then
        DIALOG --msgbox "Now you'll be put into cfdisk where you can partition your storage drive. You should make a swap partition and as many data partitions as you will need." 7 60
        clear && cfdisk "${DISC}"
        # reread partitiontable for kernel
        partprobe "${DEVICE}"
    fi
}

## check and mount EFISYS partition at ${UEFISYS_MOUNTPOINT}
check_efisys_part() {

    detect_DISC

    if [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${DISC}")" != "gpt" ]]; then
        GUID_DETECTED=""
        DIALOG --defaultno --yesno "Setup detected no GUID (gpt) partition table on ${DISC}.\nUEFI boot requires ${DISC} to be partitioned as GPT.\n\nDo you want to convert the existing MBR table in ${DISC} to a GUID (gpt) partition table?" 0 0 || return 1
        DIALOG --msgbox "Setup will now try to non-destructively convert ${DISC} to GPT using sgdisk." 0 0
        sgdisk --mbrtogpt "${DISC}" > "${LOG}" && GUID_DETECTED="1"
        partprobe "${DISC}" > "${LOG}"
        if [[ "${GUID_DETECTED}" == "" ]]; then
            DIALOG --msgbox "Conversion failed on ${DISC}.\nSetup detected no GUID (gpt) partition table on ${DISC}.\n\n You need to fix your partition table first, before setup can proceed." 0 0
            return 1
        fi
    fi

    if ! sgdisk -p "${DISC}" | grep -q 'EF00'; then
        # Windows 10 recommends a minimum of 260MB Efi Systen Partition
        DIALOG --msgbox "Setup detected no EFI System partition in ${DISC}. You will now be put into cfdisk. Please create a >= 260 MB partition with cfdisk type EFI System .\nWhen prompted (later) to format as FAT32, say YES.\nIf you already have a >=260 MB FAT32 EFI System partition, check whether that partition has EFI System cfdisk type code." 0 0
        clear && cfdisk "${DISC}"
        RUN_CFDISK=""
    fi

    if sgdisk -p "${DISC}" | grep -q 'EF00'; then
        # check on unique PARTTYPE c12a7328-f81f-11d2-ba4b-00a0c93ec93b for EFI System Partition type UUID
        UEFISYS_PART="$(${_LSBLK} NAME,PARTTYPE "${DISC}" | grep 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b' | cut -d " " -f1)"

        if [[ "$(${_LSBLK} FSTYPE "${UEFISYS_PART}")" != "vfat" ]]; then
            ## Check whether EFISYS is FAT, otherwise inform the user and offer to format the partition as FAT32.
            DIALOG --defaultno --yesno "Detected EFI System partition ${UEFISYS_PART} does not appear to be FAT formatted. UEFI Specification requires EFI System partition to be FAT32 formatted. Do you want to format ${UEFISYS_PART} as FAT32?\nNote: Setup will proceed even if you select NO. Some systems like Apple Macs may work with Non-FAT EFI System partition. However the installed system is not in conformance with UEFI Spec., and MAY NOT boot properly." 0 0 && _FORMAT_UEFISYS_FAT32="1"
        fi

        if [[ "$(${_LSBLK} FSTYPE "${UEFISYS_PART}")" == "vfat" ]] && [[ "$(${_BLKID} -p -i -o value -s VERSION "${UEFISYS_PART}")" != "FAT32" ]]; then
            ## Check whether EFISYS is FAT32 (specifically), otherwise warn the user about compatibility issues with UEFI Spec.
            DIALOG --defaultno --yesno "Detected EFI System partition ${UEFISYS_PART} does not appear to be FAT32 formatted. Do you want to format ${UEFISYS_PART} as FAT32?\nNote: Setup will proceed even if you select NO. Most systems will boot fine even with FAT16 or FAT12 EFI System partition, however some firmwares may refuse to boot with a non-FAT32 EFI System partition. It is recommended to use FAT32 for maximum compatibility with UEFI Spec." 0 0 && _FORMAT_UEFISYS_FAT32="1"
        fi

        #autodetect efisys mountpoint, on fail ask for mountpoint
        UEFISYS_MOUNTPOINT="/$(basename "$(mount | grep "${UEFISYS_PART}" | cut -d " " -f 3)")"
        if [[ "${UEFISYS_MOUNTPOINT}" == "/" ]]; then
            DIALOG --inputbox "Enter the mountpoint of your EFI System partition (Default is /boot): " 0 0 "/boot" 2>"${ANSWER}" || return 1
            UEFISYS_MOUNTPOINT="$(cat "${ANSWER}")"
        fi

        umount "${DESTDIR}/${UEFISYS_MOUNTPOINT}" &> /dev/null
        umount "${UEFISYS_PART}" &> /dev/null

        if [[ "${_FORMAT_UEFISYS_FAT32}" == "1" ]]; then
            mkfs.vfat -F32 -n "EFISYS" "${UEFISYS_PART}"
        fi

        mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}"

        if [[ "$(${_LSBLK} FSTYPE "${UEFISYS_PART}")" == "vfat" ]]; then
            mount -o rw,flush -t vfat "${UEFISYS_PART}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}"
        else
            DIALOG --msgbox "${UEFISYS_PART} is not formatted using FAT filesystem. Setup will go ahead but there might be issues using non-FAT FS for EFI System partition." 0 0

            mount -o rw "${UEFISYS_PART}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}"
        fi

        mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI" || true
    else
        DIALOG --msgbox "Setup did not find any EFI System partition in ${DISC}. Please create >= 260 MB FAT32 partition with cfdisk type EFI System code and try again." 0 0
        return 1
    fi

}

partition() {
    # disable swap and all mounted partitions, umount / last!
    _umountall
    # activate dmraid
    activate_dmraid
    # check on encrypted devices, else weird things can happen!
    _stopluks
    # check on raid devices, else weird things can happen during partitioning!
    _stopmd
    # check on lvm devices, else weird things can happen during partitioning!
    _stoplvm
    # update dmraid
    ! [[ "$(dmraid_devices)" = "" ]] && _dmraid_update
    # switch for mbr usage
    set_guid
    # Select disk to partition
    DISCS=$(finddisks _)
    DISCS="${DISCS} OTHER _ DONE +"
    DIALOG --cr-wrap --msgbox "Available Disks:\n\n$(_getavaildisks)\n" 0 0
    DISC=""
    while true; do
        # Prompt the user with a list of known disks
        #shellcheck disable=SC2086
        DIALOG --menu "Select the disk you want to partition\n(select DONE when finished)" 14 55 7 ${DISCS} 2>"${ANSWER}" || return 1
        DISC=$(cat "${ANSWER}")
        if [[ "${DISC}" == "OTHER" ]]; then
            DIALOG --inputbox "Enter the full path to the device you wish to partition" 8 65 "/dev/sda" 2>"${ANSWER}" || DISC=""
            DISC=$(cat "${ANSWER}")
        fi
        # Leave our loop if the user is done partitioning
        [[ "${DISC}" == "DONE" ]] && break
        MSDOS_DETECTED=""
        if ! [[ "${DISC}" == "" ]]; then
            if [[ "${GUIDPARAMETER}" == "yes" ]]; then
                CHECK_BIOS_BOOT_GRUB=""
                CHECK_UEFISYS_PART=""
                RUN_CFDISK="1"
                check_gpt
            else
                [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${DISC}")" == "dos" ]] && MSDOS_DETECTED="1"

                if [[ "${MSDOS_DETECTED}" == "" ]]; then
                    DIALOG --defaultno --yesno "Setup detected no MS-DOS partition table on ${DISC}.\nDo you want to create a MS-DOS partition table now on ${DISC}?\n\n${DISC} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 || return 1
                    # clean partitiontable to avoid issues!
                    dd if=/dev/zero of="${DEVICE}" bs=512 count=2048 >/dev/null 2>&1
                    wipefs -a "${DEVICE}" /dev/null 2>&1
                    parted -a optimal -s "${DISC}" mktable msdos >"${LOG}"
                fi
                # Partition disc
                DIALOG --msgbox "Now you'll be put into cfdisk where you can partition your storage drive. You should make a swap partition and as many data partitions as you will need." 18 70
                clear
                cfdisk "${DISC}"
                # reread partitiontable for kernel
                partprobe "${DISC}"
            fi
        fi
    done
    # update dmraid
    _dmraid_update
    NEXTITEM="4"
}
