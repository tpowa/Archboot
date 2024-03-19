#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_auto_partition() {
    sleep 2
    _progress "10" "Cleaning ${_DISK}..."
    _clean_disk "${_DISK}"
    # we assume a /dev/sdX,/dev/vdX or /dev/nvmeXnY format
    if [[ -n "${_GUIDPARAMETER}" ]]; then
        # GPT (GUID) is best supported by 'sgdisk'
        # create fresh GPT
        sgdisk --clear "${_DISK}" &>"${_LOG}"
        # create actual partitions
        _progress "20" "Creating BIOS_GRUB partition..."
        sgdisk --new="${_GPT_BIOS_GRUB_DEV_NUM}":0:+"${_GPT_BIOS_GRUB_DEV_SIZE}"M --typecode="${_GPT_BIOS_GRUB_DEV_NUM}":EF02 --change-name="${_GPT_BIOS_GRUB_DEV_NUM}":BIOS_GRUB "${_DISK}" >"${_LOG}"
        if [[ -n "${_UEFI_BOOT}" ]]; then
            _progress "25" "Creating EFI SYSTEM partition..."
            sgdisk --new="${_UEFISYSDEV_NUM}":0:+"${_UEFISYSDEV_SIZE}"M --typecode="${_UEFISYSDEV_NUM}":EF00 --change-name="${_UEFISYSDEV_NUM}":EFI_SYSTEM "${_DISK}" >"${_LOG}"
        fi
        if [[ -z "${_UEFISYS_BOOTDEV}" ]]; then
            _progress "40" "Creating XBOOTLDR partition..."
            sgdisk --new="${_BOOTDEV_NUM}":0:+"${_BOOTDEV_SIZE}"M --typecode="${_BOOTDEV_NUM}":EA00 --change-name="${_BOOTDEV_NUM}":ARCH_LINUX_XBOOT "${_DISK}" >"${_LOG}"
        fi
        if [[ -z "${_SKIP_SWAP}" ]]; then
            _progress "55" "Creating SWAP partition..."
            sgdisk --new="${_SWAPDEV_NUM}":0:+"${_SWAPDEV_SIZE}"M --typecode="${_SWAPDEV_NUM}":8200 --change-name="${_SWAPDEV_NUM}":ARCH_LINUX_SWAP "${_DISK}" >"${_LOG}"
        fi
        _progress "70" "Creating ROOT partition..."
        [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _GUID_TYPE=8305
        [[ "${_RUNNING_ARCH}" == "riscv64" ]] && _GUID_TYPE=FFFF
        [[ "${_RUNNING_ARCH}" == "x86_64" ]] && _GUID_TYPE=8304
        if [[ -z "${_SKIP_HOME}" ]]; then
            sgdisk --new="${_ROOTDEV_NUM}":0:+"${_ROOTDEV_SIZE}"M --typecode="${_ROOTDEV_NUM}":"${_GUID_TYPE}" --change-name="${_ROOTDEV_NUM}":ARCH_LINUX_ROOT "${_DISK}" >"${_LOG}"
            _progress "85" "Creating HOME partition..."
            sgdisk --new="${_HOMEDEV_NUM}":0:0 --typecode="${_HOMEDEV_NUM}":8302 --change-name="${_HOMEDEV_NUM}":ARCH_LINUX_HOME "${_DISK}" >"${_LOG}"
        else
            sgdisk --new="${_ROOTDEV_NUM}":0:0 --typecode="${_ROOTDEV_NUM}":"${_GUID_TYPE}" --change-name="${_ROOTDEV_NUM}":ARCH_LINUX_ROOT "${_DISK}" >"${_LOG}"
        fi
        sgdisk --print "${_DISK}" >"${_LOG}"
    else
        # create DOS MBR with sfdisk
        _progress "20" "Creating BIOS MBR..."
        echo "label: dos" | sfdisk --wipe always "${_DISK}" &>"${_LOG}"
        _progress "50" "Creating BOOT partition with bootable flag..."
        echo ",+${_BOOTDEV_SIZE}M,L,*" | sfdisk -a "${_DISK}" &>"${_LOG}"
        if [[ -z "${_SKIP_SWAP}" ]]; then
            _progress "60" "Creating SWAP partition..."
            echo ",+${_SWAPDEV_SIZE}M,S,-" | sfdisk -a "${_DISK}" &>"${_LOG}"
        fi
        _progress "70" "Creating ROOT partition..."
        if [[ -z "${_SKIP_HOME}" ]]; then
            echo ",+${_ROOTDEV_SIZE}M,L,-" | sfdisk -a "${_DISK}" &>"${_LOG}"
            _progress "85" "Creating HOME partition..."
            echo ",+,L,-" | sfdisk -a "${_DISK}" &>"${_LOG}"
        else
            echo ",+,L,-" | sfdisk -a "${_DISK}" &>"${_LOG}"
        fi
    fi
    _progress "100" "Partitions created successfully."
    sleep 2
}

_auto_create_filesystems() {
    _COUNT=0
    #shellcheck disable=SC2086
    _MAX_COUNT=$(echo ${_FSSPECS} | wc -w)
    _PROGRESS_COUNT=$((100/_MAX_COUNT))
    ## make and mount filesystems
    for fsspec in ${_FSSPECS}; do
        _DEV="${_DISK}$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d '|')"
        # Add check on nvme or mmc controller:
        # NVME uses /dev/nvme0n1pX name scheme
        # MMC uses /dev/mmcblk0pX
        if echo "${_DISK}" | grep -q "nvme" || echo "${_DISK}" | grep -q "mmc"; then
            _DEV="${_DISK}p$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d '|')"
        fi
        _FSTYPE="$(echo "${fsspec}" | tr -d ' ' | cut -f2 -d '|')"
        _DOMKFS=1
        _MP="$(echo "${fsspec}" | tr -d ' ' | cut -f3 -d '|')"
        _LABEL_NAME="$(echo "${fsspec}" | tr -d ' ' | cut -f4 -d '|')"
        _FS_OPTIONS=""
        _BTRFS_DEVS=""
        _BTRFS_LEVEL=""
        _BTRFS_SUBVOLUME=""
        _BTRFS_COMPRESS=""
        # bcachefs, btrfs and other parameters
        if [[ "${_FSTYPE}" == "bcachefs" ]]; then
             _BCACHEFS_COMPRESS="--compression=zstd"
            _mkfs "${_DEV}" "${_FSTYPE}" "${_DESTDIR}" "${_DOMKFS}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" \
                  "${_BCACHEFS_COMPRESS}" || return 1
        elif [[ "${_FSTYPE}" == "btrfs" ]]; then
            _BTRFS_DEVS="${_DEV}"
            [[ "${_MP}" == "/" ]] && _BTRFS_SUBVOLUME="root"
            [[ "${_MP}" == "/home" ]] && _BTRFS_SUBVOLUME="home"
            _BTRFS_COMPRESS="compress=zstd"
            _mkfs "${_DEV}" "${_FSTYPE}" "${_DESTDIR}" "${_DOMKFS}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" \
                  "${_BTRFS_DEVS}" "${_BTRFS_LEVEL}" "${_BTRFS_SUBVOLUME}" "${_BTRFS_COMPRESS}" || return 1
        else
            _mkfs "${_DEV}" "${_FSTYPE}" "${_DESTDIR}" "${_DOMKFS}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" || return 1
        fi
        sleep 1
        # set default subvolume for systemd-gpt-autogenerator
        if [[ "${_FSTYPE}" == "btrfs" ]]; then
            btrfs subvolume set-default "${_DESTDIR}"/"${_MP}" || return 1
        fi
        _COUNT=$((_COUNT+_PROGRESS_COUNT))
    done
    _progress "100" "Filesystems created successfully."
    sleep 2
}
_autoprepare() {
    # check on special devices and stop them, else weird things can happen during partitioning!
    _stopluks
    _stoplvm
    _stopmd
    _NAME_SCHEME_PARAMETER_RUN=""
    # switch for mbr usage
    _set_guid
    : >/tmp/.device-names
    _DISKS=$(_blockdevices)
    if [[ "$(echo "${_DISKS}" | wc -w)" -gt 1 ]]; then
        #shellcheck disable=SC2046
        _dialog --title " Storage Device " --menu "" 11 40 5 $(_finddisks) 2>"${_ANSWER}" || return 1
        _DISK=$(cat "${_ANSWER}")
    else
        _DISK="${_DISKS}"
        if [[ -z "${_DISK}" ]]; then
            _dialog --msgbox "ERROR: Setup cannot find available disk device, please use normal installation routine for partitioning and mounting devices." 0 0
            return 1
        fi
    fi
    _DEV=""
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
    _SKIP_SWAP=""
    _SKIP_HOME=""
    # get just the disk size in M/MiB 1024*1024
    _DISK_SIZE="$(($(${_LSBLK} SIZE -d -b "${_DISK}" 2>"${_NO_LOG}")/1048576))"
    if [[ -z "${_DISK_SIZE}" ]]; then
        _dialog --msgbox "ERROR: Setup cannot detect size of your device, please use normal installation routine for partitioning and mounting devices." 0 0
        return 1
    fi
    if [[ -z "${_NAME_SCHEME_PARAMETER_RUN}" ]]; then
        _set_device_name_scheme || return 1
    fi
    while [[ -z "${_DEFAULTFS}" ]]; do
        _FSOPTS=""
        command -v mkfs.btrfs &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} btrfs Btrfs"
        command -v mkfs.ext4 &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} ext4 Ext4"
        command -v mkfs.xfs &>"${_NO_LOG}" && _FSOPTS="${_FSOPTS} xfs XFS"
        command -v mkfs.bcachefs &>"${_NO_LOG}" && modinfo bcachefs >"${_NO_LOG}" && _FSOPTS="${_FSOPTS} bcachefs Bcachefs"
        _DEV_NUM=0
        # create 2M bios_grub partition for grub BIOS GPT support
        if [[ -n "${_GUIDPARAMETER}" ]]; then
            _GPT_BIOS_GRUB_DEV_SIZE="2"
            _GPT_BIOS_GRUB_DEV_NUM="$((_DEV_NUM+1))"
            _DISK_SIZE="$((_DISK_SIZE-_GPT_BIOS_GRUB_DEV_SIZE))"
            _DEV_NUM="${_GPT_BIOS_GRUB_DEV_NUM}"
        fi
        # only create ESP on UEFI systems
        if [[ -n "${_GUIDPARAMETER}" && -n "${_UEFI_BOOT}" ]]; then
            _dialog --title " EFI SYSTEM PARTITION (ESP) " --no-cancel --menu "" 8 40 2 "/efi" "MULTIBOOT" "/boot" "SINGLEBOOT" 2>"${_ANSWER}" || return 1
            _UEFISYS_MP=$(cat "${_ANSWER}")
            if [[ "${_UEFISYS_MP}" == "/boot" ]]; then
                _UEFISYS_BOOTDEV=1
            fi
            if [[ -n "${_UEFISYS_BOOTDEV}" ]]; then
                while [[ -z "${_UEFISYSDEV_SET}" ]]; do
                    _dialog --title " /boot In MiB" --no-cancel --inputbox "Disk space left: ${_DISK_SIZE}M | Minimum value is 260" 8 55 "512" 2>"${_ANSWER}" || return 1
                    _UEFISYSDEV_SIZE="$(cat "${_ANSWER}")"
                    if [[ -z "${_UEFISYSDEV_SIZE}" ]]; then
                        _dialog --title " ERROR " --no-mouse --infobox "You have entered a invalid size, please enter again." 3 60
                        sleep 5
                    else
                        if [[ "${_UEFISYSDEV_SIZE}" -ge "${_DISK_SIZE}" || "${_UEFISYSDEV_SIZE}" -lt "260" || "${_UEFISYSDEV_SIZE}" == "${_DISK_SIZE}" ]]; then
                            _dialog --title " ERROR " --no-mouse --infobox "You have entered an invalid size, please enter again." 3 60
                            sleep 5
                        else
                            _BOOTDEV_SET=1
                            _UEFISYSDEV_SET=1
                            _UEFISYSDEV_NUM="$((_DEV_NUM+1))"
                            _DEV_NUM="${_UEFISYSDEV_NUM}"
                        fi
                    fi
                done
            else
                while [[ -z "${_UEFISYSDEV_SET}" ]]; do
                    _dialog --title " EFI SYSTEM PARTITION (ESP) In MiB " --no-cancel --inputbox "Disk space left: ${_DISK_SIZE}M | Minimum value is 260" 8 55 "1024" 2>"${_ANSWER}" || return 1
                    _UEFISYSDEV_SIZE="$(cat "${_ANSWER}")"
                    if [[ -z "${_UEFISYSDEV_SIZE}" ]]; then
                        _dialog --title " ERROR " --no-mouse --infobox "You have entered a invalid size, please enter again." 3 60
                        sleep 5
                    else
                        if [[ "${_UEFISYSDEV_SIZE}" -ge "${_DISK_SIZE}" || "${_UEFISYSDEV_SIZE}" -lt "260" || "${_UEFISYSDEV_SIZE}" == "${_DISK_SIZE}" ]]; then
                            _dialog --title " ERROR " --no-mouse --infobox "You have entered an invalid size, please enter again." 3 60
                            sleep 5
                        else
                            _UEFISYSDEV_SET=1
                            _UEFISYSDEV_NUM="$((_DEV_NUM+1))"
                            _DEV_NUM=${_UEFISYSDEV_NUM}
                        fi
                    fi
                done
            fi
            _DISK_SIZE="$((_DISK_SIZE-_UEFISYSDEV_SIZE))"
            while [[ -z "${_BOOTDEV_SET}" ]]; do
                _dialog --title " /boot In MiB " --no-cancel --inputbox "Disk space left: ${_DISK_SIZE}M | Minimum value is 100" 8 55 "512" 2>"${_ANSWER}" || return 1
                _BOOTDEV_SIZE="$(cat "${_ANSWER}")"
                if [[ -z "${_BOOTDEV_SIZE}" ]]; then
                    _dialog --title " ERROR " --no-mouse --infobox "You have entered a invalid size, please enter again." 3 60
                    sleep 5
                else
                    if [[ "${_BOOTDEV_SIZE}" -ge "${_DISK_SIZE}" || "${_BOOTDEV_SIZE}" -lt "100" || "${_BOOTDEV_SIZE}" == "${_DISK_SIZE}" ]]; then
                        _dialog --title " ERROR " --no-mouse --infobox "You have entered an invalid size, please enter again." 3 60
                    else
                        _BOOTDEV_SET=1
                        _BOOTDEV_NUM="$((_DEV_NUM+1))"
                        _DEV_NUM="${_BOOTDEV_NUM}"
                        _DISK_SIZE="$((_DISK_SIZE-_BOOTDEV_SIZE))"
                    fi
                fi
            done
        else
            while [[ -z "${_BOOTDEV_SET}" ]]; do
                _dialog --title " /boot In MiB "--no-cancel --inputbox "Disk space left: ${_DISK_SIZE}M | Minimum value is 100" 8 55 "512" 2>"${_ANSWER}" || return 1
                _BOOTDEV_SIZE="$(cat "${_ANSWER}")"
                if [[ -z "${_BOOTDEV_SIZE}" ]]; then
                    _dialog --title " ERROR " --no-mouse --infobox "You have entered a invalid size, please enter again." 3 60
                    sleep 5
                else
                    if [[ "${_BOOTDEV_SIZE}" -ge "${_DISK_SIZE}" || "${_BOOTDEV_SIZE}" -lt "100" || "${_BOOTDEV_SIZE}" == "${_DISK_SIZE}" ]]; then
                        _dialog --title " ERROR " --no-mouse --infobox "You have entered an invalid size, please enter again." 3 60
                        sleep 5
                    else
                        _BOOTDEV_SET=1
                        _BOOTDEV_NUM=$((_DEV_NUM+1))
                        _DEV_NUM="${_BOOTDEV_NUM}"
                        _DISK_SIZE="$((_DISK_SIZE-_BOOTDEV_SIZE))"
                    fi
                fi
            done
        fi
        _SWAP_SIZE="256"
        [[ "${_DISK_SIZE}" -lt "256" ]] && _SWAP_SIZE="${_DISK_SIZE}"
        while [[ -z "${_SWAPDEV_SET}" ]]; do
            _dialog --title " Swap In MiB " --no-cancel --inputbox "Disk space left: ${_DISK_SIZE}M | Value 0 skips Swap" 8 55 "${_SWAP_SIZE}" 2>"${_ANSWER}" || return 1
            _SWAPDEV_SIZE=$(cat "${_ANSWER}")
            if [[ -z "${_SWAPDEV_SIZE}" ]]; then
                _dialog --title " ERROR " --no-mouse --infobox "You have entered an invalid size, please enter again." 3 60
                sleep 5
            else
                if [[ "${_SWAPDEV_SIZE}" -ge "${_DISK_SIZE}" ]]; then
                    _dialog --title " ERROR " --no-mouse --infobox "You have entered a too large size, please enter again." 3 60
                    sleep 5
                elif [[ "${_SWAPDEV_SIZE}" == "0" ]]; then
                    _SWAPDEV_SET=1
                    _SKIP_SWAP=1
                else
                    _SWAPDEV_SET=1
                    _SWAPDEV_NUM="$((_DEV_NUM+1))"
                    _DEV_NUM="${_SWAPDEV_NUM}"
                fi
            fi
        done
        while [[ -z "${_CHOSENFS}" ]]; do
            #shellcheck disable=SC2086
            _dialog --title " Filesystem / and /home " --no-cancel --menu "" 10 45 8 ${_FSOPTS} 2>"${_ANSWER}" || return 1
            _FSTYPE=$(cat "${_ANSWER}")
            _dialog --title " Confirmation " --yesno " Filesystem ${_FSTYPE} will be used for / and /home?" 5 55 && _CHOSENFS=1
        done
        _DISK_SIZE="$((_DISK_SIZE-_SWAPDEV_SIZE))"
        _ROOT_SIZE="7500"
        # xfs minimum size is around 300M
        # btrfs minimum size is around 120M
        [[ "${_DISK_SIZE}" -lt "7500" ]] && _ROOT_SIZE="$((_DISK_SIZE-350))"
        [[ "$((_DISK_SIZE-350))" -lt "2000" ]] && _ROOT_SIZE=0
        _ROOTDEV_NUM="$((_DEV_NUM+1))"
        _DEV_NUM="${_ROOTDEV_NUM}"
        while [[ -z "${_ROOTDEV_SET}" ]]; do
        _dialog --title " / in MiB " --inputbox "Disk space left: $((_DISK_SIZE-350))M | Minimum value is 2000\nValue 0 skips /home and uses the left ${_DISK_SIZE}M for /" 9 60 "${_ROOT_SIZE}" 2>"${_ANSWER}" || return 1
        _ROOTDEV_SIZE=$(cat "${_ANSWER}")
        if [[ "${_ROOTDEV_SIZE}" == 0 ]]; then
            if _dialog --title " Confirmation " --yesno "${_DISK_SIZE}M will be used for your / completely?" 5 55; then
                _ROOTDEV_SET=1
                _SKIP_HOME=1
            fi
        else
            if [[ -z "${_ROOTDEV_SIZE}" || "${_ROOTDEV_SIZE}" == 0 || "${_ROOTDEV_SIZE}" -lt "2000" ]]; then
                _dialog --title " ERROR " --no-mouse --infobox "You have entered an invalid size, please enter again." 3 60
                sleep 5
            else
                if [[ "${_ROOTDEV_SIZE}" -ge "${_DISK_SIZE}" || "$((_DISK_SIZE-_ROOTDEV_SIZE))" -lt "350" ]]; then
                    _dialog --title " ERROR " --no-mouse --infobox "You have entered a too large size, please enter again." 3 60
                    sleep 5
                else
                    if _dialog --title " Confirmation " --yesno "$((_DISK_SIZE-_ROOTDEV_SIZE))M will be used for your /home completely?" 5 55; then
                        _ROOTDEV_SET=1
                        _HOMEDEV_NUM="$((_DEV_NUM+1))"
                        _DEV_NUM="${_HOMEDEV_NUM}"
                    fi
                fi
            fi
        fi
        done
        _DEFAULTFS=1
    done
    _dialog --defaultno --yesno "${_DISK} will be COMPLETELY ERASED!\nALL DATA ON ${_DISK} WILL BE LOST.\n\nAre you absolutely sure?" 0 0 || return 1
    [[ -e /tmp/.fstab ]] && rm -f /tmp/.fstab
    _umountall
    # disable swap and all mounted partitions, umount / last!
    _printk off
    _auto_partition | _dialog --title " Partitioning " --no-mouse --gauge "Partitioning ${_DISK}..." 6 75 0
    _printk on
    ## wait until /dev initialized correct devices
    udevadm settle
    ## FSSPECS - default filesystem specs
    ## <partnum>|<fstype>|<mountpoint>|<labelname>
    ## The partitions in FSSPECS list should be listed in the "mountpoint" order.
    ## Make sure the "root" partition is defined first in the FSSPECS list
    [[ -z "${_SKIP_SWAP}" ]] && _FSSPEC_SWAPDEV="${_SWAPDEV_NUM}|swap|swap|ARCH_SWAP"
    _FSSPEC_ROOTDEV="${_ROOTDEV_NUM}|${_FSTYPE}|/|ARCH_ROOT"
    _FSSPEC_BOOTDEV="${_BOOTDEV_NUM}|ext2|/boot|ARCH_BOOT"
    [[ -z "${_SKIP_HOME}" ]] &&_FSSPEC_HOMEDEV="${_HOMEDEV_NUM}|${_FSTYPE}|/home|ARCH_HOME"
    _FSSPEC_UEFISYSDEV="${_UEFISYSDEV_NUM}|vfat|${_UEFISYS_MP}|ESP"
    if [[ -n "${_GUIDPARAMETER}" && -n "${_UEFI_BOOT}" ]]; then
        if [[ -n "${_UEFISYS_BOOTDEV}" ]]; then
            _FSSPECS="${_FSSPEC_ROOTDEV} ${_FSSPEC_UEFISYSDEV} ${_FSSPEC_HOMEDEV} ${_FSSPEC_SWAPDEV}"
        else
            _FSSPECS="${_FSSPEC_ROOTDEV} ${_FSSPEC_UEFISYSDEV} ${_FSSPEC_BOOTDEV} ${_FSSPEC_HOMEDEV} ${_FSSPEC_SWAPDEV}"
        fi
    else
        _FSSPECS="${_FSSPEC_ROOTDEV} ${_FSSPEC_BOOTDEV} ${_FSSPEC_HOMEDEV} ${_FSSPEC_SWAPDEV}"
    fi
    _auto_create_filesystems | _dialog --title " Filesystems " --no-mouse --gauge "Creating Filesystems on ${_DISK}..." 6 75 0
    _dialog --title " Success " --no-mouse --infobox "Quick Setup was successful." 3 40
    sleep 3
    _S_QUICK_SETUP=1
}
# vim: set ft=sh ts=4 sw=4 et:
