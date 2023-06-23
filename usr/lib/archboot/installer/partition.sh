#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_check_gpt() {
    _GUID_DETECTED=""
    [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${_DISK}")" == "gpt" ]] && _GUID_DETECTED=1
    if [[ -z "${_GUID_DETECTED}" ]]; then
        _dialog --yesno "Setup detected no GUID (gpt) partition table on ${_DISK}.\n\nDo you want to convert the existing MBR table in ${_DISK} to a GUID (gpt) partition table?" 0 0 || return 1
        sgdisk --mbrtogpt "${_DISK}" >"${_LOG}" && _GUID_DETECTED=1
        # reread partitiontable for kernel
        partprobe "${_DISK}" >"${_LOG}"
        if [[ -z "${_GUID_DETECTED}" ]]; then
            _dialog --defaultno --yesno "Conversion failed on ${_DISK}.\nSetup detected no GUID (gpt) partition table on ${_DISK}.\n\nDo you want to create a new GUID (gpt) table now on ${_DISK}?\n\n${_DISK} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 || return 1
            _clean_disk "${_DISK}"
            # create fresh GPT
            sgdisk --clear "${_DISK}" &>"${_NO_LOG}"
            _GUID_DETECTED=1
        fi
    fi
    if [[ -n "${_GUID_DETECTED}" ]]; then
        ### This check is not enabled in any function yet!
        if [[ -n "${_CHECK_UEFISYSDEV}" ]]; then
            _check_efisys_part
        fi
        if [[ -n "${_CHECK_BIOS_BOOT_GRUB}" ]]; then
            if ! sgdisk -p "${_DISK}" | grep -q 'EF02'; then
                _dialog --msgbox "Setup detected no BIOS BOOT PARTITION in ${_DISK}. Please create a >=1M BIOS BOOT PARTITION for grub BIOS GPT support." 0 0
                _RUN_CFDISK=1
            fi
        fi
    fi
    if [[ -n "${_RUN_CFDISK}" ]]; then
        _dialog --msgbox "$(cat /usr/lib/archboot/installer/help/guid-partition.txt)" 0 0
        clear
        cfdisk "${_DISK}"
        # reread partitiontable for kernel
        partprobe "${_DISK}"
    fi
}

## check EFISYS partition
_check_efisys_part() {
    # automounted /boot and ESP needs to be mounted first, trigger mount with ls
    ls "${_DESTDIR}/boot" &>"${_NO_LOG}"
    ls "${_DESTDIR}/efi" &>"${_NO_LOG}"
    if mountpoint -q "${_DESTDIR}/efi" ; then
        _UEFISYS_MP=efi
    else
        _UEFISYS_MP=boot
    fi
    if ${_FINDMNT} "${_DESTDIR}/${_UEFISYS_MP}" &>"${_NO_LOG}"; then
        if ${_FINDMNT} "${_DESTDIR}/${_UEFISYS_MP}" | grep -qw systemd-1; then
            _DISK="$(${_LSBLK} PKNAME "$(${_FINDMNT} "${_DESTDIR}/${_UEFISYS_MP}" | grep -vw systemd-1)")"
        else
            _DISK="$(${_LSBLK} PKNAME "$(${_FINDMNT} "${_DESTDIR}/${_UEFISYS_MP}")")"
        fi
    else
        _DISK="$(${_LSBLK} PKNAME "$(${_FINDMNT} "${_DESTDIR}/")")"
    fi
    if [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${_DISK}")" != "gpt" ]]; then
        _GUID_DETECTED=""
        _dialog --defaultno --yesno "Setup detected no GUID (gpt) partition table on ${_DISK}.\nUEFI boot requires ${_DISK} to be partitioned as GPT.\n\nDo you want to convert the existing MBR table in ${_DISK} to a GUID (gpt) partition table?" 0 0 || return 1
        _dialog --msgbox "Setup will now try to non-destructively convert ${_DISK} to GPT using sgdisk." 0 0
        sgdisk --mbrtogpt "${_DISK}" >"${_LOG}" && _GUID_DETECTED=1
        partprobe "${_DISK}" >"${_LOG}"
        if [[ -z "${_GUID_DETECTED}" ]]; then
            _dialog --msgbox "Conversion failed on ${_DISK}.\nSetup detected no GUID (gpt) partition table on ${_DISK}.\n\n You need to fix your partition table first, before setup can proceed." 0 0
            return 1
        fi
    fi
    if ! sgdisk -p "${_DISK}" | grep -q 'EF00'; then
        # Windows 10 recommends a minimum of 260M Efi Systen Partition
        _dialog --msgbox "Setup detected no EFI SYSTEM PARTITION (ESP) in ${_DISK}. You will now be put into cfdisk. Please create a >= 260M partition with cfdisk type EFI System .\nWhen prompted (later) to format as FAT32, say YES.\nIf you already have a >=260M FAT32 EFI SYSTEM PARTITIOM (ESP), check whether that partition has EFI System cfdisk type code." 0 0
        clear && cfdisk "${_DISK}"
        _RUN_CFDISK=""
    fi
    if sgdisk -p "${_DISK}" | grep -q 'EF00'; then
        # check on unique PARTTYPE c12a7328-f81f-11d2-ba4b-00a0c93ec93b for EFI System Partition type UUID
        _UEFISYSDEV="$(${_LSBLK} NAME,PARTTYPE "${_DISK}" | grep 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b' | cut -d " " -f1)"
        if [[ "$(${_LSBLK} FSTYPE "${_UEFISYSDEV}")" == "vfat" && "$(${_BLKID} -p -i -o value -s VERSION "${_UEFISYSDEV}")" != "FAT32" ]] || [[ "$(${_LSBLK} FSTYPE "${_UEFISYSDEV}")" != "vfat" ]]; then
            ## Check whether EFISYS is FAT32 (specifically), otherwise warn the user about compatibility issues with UEFI Spec.
            _dialog --defaultno --yesno "Detected EFI SYSTEM PARTITION (ESP) ${_UEFISYSDEV} does not appear to be FAT32 formatted. Do you want to format ${_UEFISYSDEV} as FAT32?\nNote: Setup will proceed even if you select NO. Most systems will boot fine even with FAT16 or FAT12 EFI System partition, however some firmwares may refuse to boot with a non-FAT32 EFI SYSTEM PARTITION (ESP). It is recommended to use FAT32 for maximum compatibility with UEFI Spec." 0 0 && _FORMAT_UEFISYS_FAT32=1
        fi
        # autodetect efisys mountpoint
        _UEFISYS_MP="/$(basename "$(mount | grep "${_UEFISYSDEV}" | cut -d " " -f 3)")"
        while [[ "${_UEFISYS_MP}" == "/" ]]; do
            _UEFISYS_MP="/$(basename "$(mount | grep "${_UEFISYSDEV}" | cut -d " " -f 3)")"
            if [[ "${_UEFISYS_MP}" == "/" ]]; then
                 _dialog --yesno "Setup did not find an mounted EFI SYSTEM PARTITION (ESP) in ${_UEFISYS_MP}. Please mount the partition in other VC and confirm dialog. Retry?" 0 0 || return 1
            fi
        done
        if [[ -n "${_FORMAT_UEFISYS_FAT32}" ]]; then
            umount "${_DESTDIR}/${_UEFISYS_MP}" &>"${_NO_LOG}"
            umount "${_UEFISYSDEV}" &>"${_NO_LOG}"
            mkfs.vfat -F32 -n "EFISYS" "${_UEFISYSDEV}"
            mount -o rw,flush -t vfat "${_UEFISYSDEV}" "${_DESTDIR}/${_UEFISYS_MP}"
        fi
        mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI"
    else
        _dialog --msgbox "Setup did not find any EFI SYSTEM PARTITION (ESP) on ${_DISK}. Please create >= 260M FAT32 partition with cfdisk type EFI System code and try again." 0 0
        return 1
    fi
}

_partition() {
    # stop special devices, else weird things can happen during partitioning
    _stopluks
    _stoplvm
    _stopmd
    _set_guid
    # Select disk to partition
    _DISKS=$(_finddisks)
    _DISKS="${_DISKS} OTHER _ DONE +"
    _DISK=""
    while true; do
        # Prompt the user with a list of known disks
        #shellcheck disable=SC2086
        _dialog --menu "Select the device you want to partition:" 14 45 7 ${_DISKS} 2>"${_ANSWER}" || return 1
        _DISK=$(cat "${_ANSWER}")
        if [[ "${_DISK}" == "OTHER" ]]; then
            _dialog --inputbox "Enter the full path to the device you wish to partition" 8 65 "/dev/sda" 2>"${_ANSWER}" || _DISK=""
            _DISK=$(cat "${_ANSWER}")
        fi
        # Leave our loop if the user is done partitioning
        [[ "${_DISK}" == "DONE" ]] && break
        _MSDOS_DETECTED=""
        if [[ -n "${_DISK}" ]]; then
            if [[ -n "${_GUIDPARAMETER}" ]]; then
                _CHECK_BIOS_BOOT_GRUB=""
                _CHECK_UEFISYSDEV=""
                _RUN_CFDISK=1
                _check_gpt
            else
                [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${_DISK}")" == "dos" ]] && _MSDOS_DETECTED=1

                if [[ -z "${_MSDOS_DETECTED}" ]]; then
                    _dialog --defaultno --yesno "Setup detected no MBR/BIOS partition table on ${_DISK}.\nDo you want to create a MBR/BIOS partition table now on ${_DISK}?\n\n${_DISK} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 || return 1
                   _clean_disk "${_DISK}"
                    parted -a optimal -s "${_DISK}" mktable msdos >"${_LOG}"
                fi
                # Partition disc
                _dialog --msgbox "$(cat /usr/lib/archboot/installer/help/mbr-partition.txt)" 0 0
                clear
                cfdisk "${_DISK}"
                # reread partitiontable for kernel
                partprobe "${_DISK}"
            fi
        fi
    done
    _NEXTITEM="3"
}
# vim: set ft=sh ts=4 sw=4 et:
