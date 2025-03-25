#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_auto_partition() {
    sleep 2
    _progress "10" "Cleaning ${_DISK}..."
    _clean_disk "${_DISK}"
    # we assume a /dev/sdX,/dev/vdX or /dev/nvmeXnY format
    if [[ -n "${_GUIDPARAMETER}" ]]; then
        # create fresh GPT
        # GUID codes: https://en.wikipedia.org/wiki/GUID_Partition_Table
        echo "label: gpt" | sfdisk --wipe always "${_DISK}" &>"${_LOG}"
        # create actual partitions
        _progress "20" "Creating BIOS_GRUB partition..."
        echo "size=+${_GPT_BIOS_GRUB_DEV_SIZE}M, type=21686148-6449-6E6F-744E-656564454649, name=BIOS_GRUB" | sfdisk -a "${_DISK}" &>"${_LOG}"
        if [[ -n "${_UEFI_BOOT}" ]]; then
            _progress "25" "Creating EFI System partition..."
            echo "size=+${_ESP_DEV_SIZE}M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=ESP" | sfdisk -a "${_DISK}" &>"${_LOG}"
        fi
        if [[ -z "${_ESP_BOOTDEV}" ]]; then
            _progress "40" "Creating Extended Boot Loader partition..."
            echo "size=+${_BOOTDEV_SIZE}M, type=BC13C2FF-59E6-4262-A352-B275FD6F7172, name=XBOOTLDR" | sfdisk -a "${_DISK}" &>"${_LOG}"
        fi
        if [[ -z "${_SKIP_SWAP}" ]]; then
            _progress "65" "Creating SWAP partition..."
            echo "size=+${_SWAPDEV_SIZE}M, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F, name=SWAP" | sfdisk -a "${_DISK}" &>"${_LOG}"
        fi
        _progress "70" "Creating ROOT partition..."
        [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _GUID_TYPE=B921B045-1DF0-41C3-AF44-4C6F280D3FAE
        [[ "${_RUNNING_ARCH}" == "riscv64" ]] && _GUID_TYPE=BEAEC34B-8442-439B-A40B-984381ED097D
        [[ "${_RUNNING_ARCH}" == "x86_64" ]] && _GUID_TYPE=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
        if [[ -z "${_SKIP_HOME}" ]]; then
            echo "size=+${_ROOTDEV_SIZE}M, type=${_GUID_TYPE}, name=ARCH_LINUX_ROOT" | sfdisk -a "${_DISK}" &>"${_LOG}"
            _progress "85" "Creating HOME partition..."
            echo "type=933AC7E1-2EB4-4F13-B844-0E14E2AEF915, name=ARCH_LINUX_HOME" | sfdisk -a "${_DISK}" &>"${_LOG}"
        else
            echo "type=${_GUID_TYPE}, name=ARCH_LINUX_ROOT" | sfdisk -a "${_DISK}" &>"${_LOG}"
        fi
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
    _write_partition_template
    sleep 2
}

_auto_create_filesystems() {
    _COUNT=0
    _MAX_COUNT=${#_FSSPECS}
    _PROGRESS_COUNT=$((100/_MAX_COUNT))
    ## make and mount filesystems
    for fsspec in "${_FSSPECS[@]}"; do
        _DEV="${_DISK}$(echo "${fsspec}" | tr -d ' ' | choose -f '\|' 0)"
        # Add check on nvme or mmc controller:
        # NVME uses /dev/nvme0n1pX name scheme
        # MMC uses /dev/mmcblk0pX
        if echo "${_DISK}" | rg -q "nvme|mmc"; then
            _DEV="${_DISK}p$(echo "${fsspec}" | tr -d ' ' | choose -f '\|' 0)"
        fi
        _FSTYPE="$(echo "${fsspec}" | tr -d ' ' | choose -f '\|' 1)"
        _DOMKFS=1
        _MP="$(echo "${fsspec}" | tr -d ' ' | choose -f '\|' 2)"
        _LABEL_NAME="$(echo "${fsspec}" | tr -d ' ' | choose -f '\|' 3)"
        _FS_OPTIONS=""
        _BTRFS_DEVS=""
        _BTRFS_LEVEL=""
        _BTRFS_SUBVOLUME=""
        _BTRFS_COMPRESS=""
        # bcachefs, btrfs and other parameters
        if [[ "${_FSTYPE}" == "bcachefs" ]]; then
            _BCFS_DEVS="${_DEV}"
            _BCFS_COMPRESS=""
            _mkfs "${_DEV}" "${_FSTYPE}" "${_DESTDIR}" "${_DOMKFS}" "${_MP}" "${_LABEL_NAME}" "${_FS_OPTIONS}" \
                   "${_BCFS_DEVS}" "${_BCFS_COMPRESS}" || return 1
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
            # write to template
            echo "btrfs subvolume set-default \"\${_DESTDIR}\"/\"${_MP}\"" >> "${_TEMPLATE}"
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
    { echo "### quicksetup"
    echo ": > /tmp/.device-names"
    } >> "${_TEMPLATE}"
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
    _ESP_BOOTDEV=""
    _ESP_MP=""
    _ESP_DEV_SET=""
    _BOOTDEV_SET=""
    _SWAPDEV_SET=""
    _ROOTDEV_SET=""
    _BOOTDEV_SIZE=""
    _ESP_DEV_SIZE=""
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
        _FSOPTS=()
        command -v mkfs.btrfs &>"${_NO_LOG}" && _FSOPTS+=(btrfs Btrfs)
        command -v mkfs.ext4 &>"${_NO_LOG}" && _FSOPTS+=(ext4 Ext4)
        command -v mkfs.xfs &>"${_NO_LOG}" && _FSOPTS+=(xfs XFS)
        command -v mkfs.bcachefs &>"${_NO_LOG}" && modinfo bcachefs >"${_NO_LOG}" && _FSOPTS+=(bcachefs Bcachefs)
        _DEV_NUM=0
        # create 2M bios_grub partition for grub BIOS GPT support
        if [[ -n "${_GUIDPARAMETER}" ]]; then
            _GPT_BIOS_GRUB_DEV_SIZE=2
            _GPT_BIOS_GRUB_DEV_NUM="$((_DEV_NUM+1))"
            _DISK_SIZE="$((_DISK_SIZE-_GPT_BIOS_GRUB_DEV_SIZE))"
            _DEV_NUM="${_GPT_BIOS_GRUB_DEV_NUM}"
        fi
        # only create ESP on UEFI systems
        if [[ -n "${_GUIDPARAMETER}" && -n "${_UEFI_BOOT}" ]]; then
            _dialog --title " EFI SYSTEM PARTITION (ESP) " --no-cancel --menu "" 8 40 2 "/efi" "MULTIBOOT" "/boot" "SINGLEBOOT" 2>"${_ANSWER}" || return 1
            _ESP_MP=$(cat "${_ANSWER}")
            if [[ "${_ESP_MP}" == "/boot" ]]; then
                _ESP_BOOTDEV=1
            fi
            if [[ -n "${_ESP_BOOTDEV}" ]]; then
                while [[ -z "${_ESP_DEV_SET}" ]]; do
                    _dialog --title " EFI SYSTEM PARTITION (ESP) in MiB " --no-cancel --inputbox "Disk space left: ${_DISK_SIZE}M | Minimum value is 260" 8 65 "512" 2>"${_ANSWER}" || return 1
                    _ESP_DEV_SIZE="$(cat "${_ANSWER}")"
                    if [[ -z "${_ESP_DEV_SIZE}" ]]; then
                        _dialog --title " ERROR " --no-mouse --infobox "You have entered a invalid size, please enter again." 3 60
                        sleep 5
                    else
                        if [[ "${_ESP_DEV_SIZE}" -ge "${_DISK_SIZE}" || "${_ESP_DEV_SIZE}" -lt "260" || "${_ESP_DEV_SIZE}" == "${_DISK_SIZE}" ]]; then
                            _dialog --title " ERROR " --no-mouse --infobox "You have entered an invalid size, please enter again." 3 60
                            sleep 5
                        else
                            _BOOTDEV_SET=1
                            _ESP_DEV_SET=1
                            _ESP_DEV_NUM="$((_DEV_NUM+1))"
                            _DEV_NUM="${_ESP_DEV_NUM}"
                        fi
                    fi
                done
            else
                while [[ -z "${_ESP_DEV_SET}" ]]; do
                    _dialog --title " EFI SYSTEM PARTITION (ESP) in MiB " --no-cancel --inputbox "Disk space left: ${_DISK_SIZE}M | Minimum value is 260" 8 65 "1024" 2>"${_ANSWER}" || return 1
                    _ESP_DEV_SIZE="$(cat "${_ANSWER}")"
                    if [[ -z "${_ESP_DEV_SIZE}" ]]; then
                        _dialog --title " ERROR " --no-mouse --infobox "You have entered a invalid size, please enter again." 3 60
                        sleep 5
                    else
                        if [[ "${_ESP_DEV_SIZE}" -ge "${_DISK_SIZE}" || "${_ESP_DEV_SIZE}" -lt "260" || "${_ESP_DEV_SIZE}" == "${_DISK_SIZE}" ]]; then
                            _dialog --title " ERROR " --no-mouse --infobox "You have entered an invalid size, please enter again." 3 60
                            sleep 5
                        else
                            _ESP_DEV_SET=1
                            _ESP_DEV_NUM="$((_DEV_NUM+1))"
                            _DEV_NUM=${_ESP_DEV_NUM}
                        fi
                    fi
                done
            fi
            _DISK_SIZE="$((_DISK_SIZE-_ESP_DEV_SIZE))"
            while [[ -z "${_BOOTDEV_SET}" ]]; do
                _dialog --title " Extended Boot Loader Partition (XBOOTLDR) in MiB " --no-cancel --inputbox "Disk space left: ${_DISK_SIZE}M | Minimum value is 100" 8 65 "512" 2>"${_ANSWER}" || return 1
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
                _dialog --title " /boot in MiB " --no-cancel --inputbox "Disk space left: ${_DISK_SIZE}M | Minimum value is 100" 8 65 "512" 2>"${_ANSWER}" || return 1
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
        _SWAP_SIZE=256
        [[ "${_DISK_SIZE}" -lt "256" ]] && _SWAP_SIZE="${_DISK_SIZE}"
        while [[ -z "${_SWAPDEV_SET}" ]]; do
            _dialog --title " Swap in MiB " --no-cancel --inputbox "Disk space left: ${_DISK_SIZE}M | Value 0 skips Swap" 8 65 "${_SWAP_SIZE}" 2>"${_ANSWER}" || return 1
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
            _dialog --title " Filesystem / and /home " --no-cancel --menu "" 10 45 8 "${_FSOPTS[@]}" 2>"${_ANSWER}" || return 1
            _FSTYPE=$(cat "${_ANSWER}")
            _dialog --title " Confirmation " --yesno " Filesystem ${_FSTYPE} will be used for / and /home?" 5 65 && _CHOSENFS=1
        done
        _DISK_SIZE="$((_DISK_SIZE-_SWAPDEV_SIZE))"
        _ROOT_SIZE=7500
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
            if _dialog --title " Confirmation " --yesno "${_DISK_SIZE}M will be used for your / completely?" 5 65; then
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
                    if _dialog --title " Confirmation " --yesno "$((_DISK_SIZE-_ROOTDEV_SIZE))M will be used for your /home completely?" 5 65; then
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
    : > /tmp/.fstab
    # write to template
    echo ": > /tmp/.fstab" >> "${_TEMPLATE}"
    # disable swap and all mounted partitions, umount / last!
    _printk off
    _auto_partition | _dialog --title " Partitioning " --no-mouse --gauge "Partitioning ${_DISK}..." 6 75 0
    _printk on
    ## wait until /dev initialized correct devices
    udevadm settle
    # write to template
    { echo "### quicksetup mountpoints"
    echo "udevadm settle"
    } >> "${_TEMPLATE}"
    ## FSSPECS - default filesystem specs
    ## <partnum>|<fstype>|<mountpoint>|<labelname>
    ## The partitions in FSSPECS list should be listed in the "mountpoint" order.
    ## Make sure the "root" partition is defined first in the FSSPECS list
    [[ -z "${_SKIP_SWAP}" ]] && _FSSPEC_SWAPDEV="${_SWAPDEV_NUM}|swap|swap|SWAP"
    _FSSPEC_ROOTDEV="${_ROOTDEV_NUM}|${_FSTYPE}|/|ARCH_ROOT"
    _FSSPEC_BOOTDEV="${_BOOTDEV_NUM}|vfat|/boot|XBOOTLDR"
    [[ -z "${_SKIP_HOME}" ]] &&_FSSPEC_HOMEDEV="${_HOMEDEV_NUM}|${_FSTYPE}|/home|ARCH_HOME"
    _FSSPEC_ESP_DEV="${_ESP_DEV_NUM}|vfat|${_ESP_MP}|ESP"
    if [[ -n "${_GUIDPARAMETER}" && -n "${_UEFI_BOOT}" ]]; then
        if [[ -n "${_ESP_BOOTDEV}" ]]; then
            _FSSPECS=("${_FSSPEC_ROOTDEV}" "${_FSSPEC_ESP_DEV}" "${_FSSPEC_HOMEDEV}" "${_FSSPEC_SWAPDEV}")
        else
            _FSSPECS=("${_FSSPEC_ROOTDEV}" "${_FSSPEC_ESP_DEV}" "${_FSSPEC_BOOTDEV}" "${_FSSPEC_HOMEDEV}" "${_FSSPEC_SWAPDEV}")
        fi
    else
        _FSSPECS=("${_FSSPEC_ROOTDEV}" "${_FSSPEC_BOOTDEV}" "${_FSSPEC_HOMEDEV}" "${_FSSPEC_SWAPDEV}")
    fi
    _auto_create_filesystems | _dialog --title " Filesystems " --no-mouse --gauge "Creating Filesystems on ${_DISK}..." 6 75 0
    echo "" >> "${_TEMPLATE}"
    _dialog --title " Success " --no-mouse --infobox "Quick Setup was successful." 3 40
    sleep 3
}
