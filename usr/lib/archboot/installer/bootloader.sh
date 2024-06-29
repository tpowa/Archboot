#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
if [[ "${_RUNNING_ARCH}" == "x86_64" ]] && rg -q 'Intel' /proc/cpuinfo; then
    _UCODE="intel-ucode.img"
    _UCODE_PKG="intel-ucode"
fi

if [[ "${_RUNNING_ARCH}" == "aarch64" || "${_RUNNING_ARCH}" == "x86_64" ]]; then
    if rg -q 'AMD' /proc/cpuinfo; then
        _UCODE="amd-ucode.img"
        _UCODE_PKG="amd-ucode"
    fi
fi

# name of the initramfs filesystem
_INITRAMFS="initramfs-${_KERNELPKG}.img"

_getrootfstype() {
    _ROOTFS="$(_getfstype "${_ROOTDEV}")"
}

_getrootflags() {
    _ROOTFLAGS="$(findmnt -m -n -o options -T "${_DESTDIR}")"
    [[ -n "${_ROOTFLAGS}" ]] && _ROOTFLAGS="rootflags=${_ROOTFLAGS}"
}

_getraidarrays() {
    _RAIDARRAYS=""
    # fallback to md assembly on boot commandline
    if [[ -f "${_DESTDIR}/etc/mdadm.conf" ]] && ! rg -q '^ARRAY' "${_DESTDIR}"/etc/mdadm.conf 2>"${_NO_LOG}"; then
        _RAIDARRAYS="$(echo -n "$(rg '^md' /proc/mdstat 2>"${_NO_LOG}" |\
                       sd '\[[0-9]\]| :.* raid[0-9]+' '' |\
                       sd 'md' 'md=' | sd ' ' ',/dev/' | sd '_' '')")"
    fi
}

_getcryptsetup() {
    _LUKSSETUP=""
    if ! cryptsetup status "$(basename "${_ROOTDEV}")" | rg -q 'inactive'; then
        if cryptsetup status "$(basename "${_ROOTDEV}")" 2>"${_NO_LOG}"; then
            if [[ "${_NAME_SCHEME_PARAMETER}" == "FSUUID" ]]; then
                _LUKSDEV="UUID=$(${_LSBLK} UUID "$(cryptsetup status "$(basename "${_ROOTDEV}")" 2>"${_NO_LOG}" | rg -o 'device: (.*)' -r '$1')" 2>"${_NO_LOG}")"
            elif [[ "${_NAME_SCHEME_PARAMETER}" == "FSLABEL" ]]; then
                _LUKSDEV="LABEL=$(${_LSBLK} LABEL "$(cryptsetup status "$(basename "${_ROOTDEV}")" 2>"${_NO_LOG}" | rg -o 'device: (.*)' -r '$1')" 2>"${_NO_LOG}")"
            else
                _LUKSDEV="$(cryptsetup status "$(basename "${_ROOTDEV}")" 2>"${_NO_LOG}" | rg -o 'device: (.*)' -r '$1')"
            fi
            _LUKSNAME="$(basename "${_ROOTDEV}")"
            _LUKSSETUP="cryptdevice=${_LUKSDEV}:${_LUKSNAME}"
        fi
    fi
}

_getrootpartuuid() {
    _PARTUUID="$(_getpartuuid "${_ROOTDEV}")"
    if [[ -n "${_PARTUUID}" ]]; then
        _ROOTDEV="PARTUUID=${_PARTUUID}"
    fi
}

_getrootpartlabel() {
    _PARTLABEL="$(_getpartlabel "${_ROOTDEV}")"
    if [[ -n "${_PARTLABEL}" ]]; then
        _ROOTDEV="PARTLABEL=${_PARTLABEL}"
    fi
}

_getrootfsuuid() {
    _FSUUID="$(_getfsuuid "${_ROOTDEV}")"
    if [[ -n "${_FSUUID}" ]]; then
        _ROOTDEV="UUID=${_FSUUID}"
    fi
}

_getrootfslabel() {
    _FSLABEL="$(_getfslabel "${_ROOTDEV}")"
    if [[ -n "${_FSLABEL}" ]]; then
        _ROOTDEV="LABEL=${_FSLABEL}"
    fi
}

## Setup kernel cmdline parameters to be added to bootloader configs
_bootloader_kernel_parameters() {
    [[ "${_NAME_SCHEME_PARAMETER}" == "PARTUUID" ]] && _getrootpartuuid
    [[ "${_NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]] && _getrootpartlabel
    [[ "${_NAME_SCHEME_PARAMETER}" == "FSUUID" ]] && _getrootfsuuid
    [[ "${_NAME_SCHEME_PARAMETER}" == "FSLABEL" ]] && _getrootfslabel
    if [[ "${_NAME_SCHEME_PARAMETER}" == "SD_GPT_AUTO_GENERATOR" ]]; then
        _KERNEL_PARAMS_COMMON_UNMOD="${_RAIDARRAYS} ${_LUKSSETUP}"
        _KERNEL_PARAMS_MOD="$(echo "${_KERNEL_PARAMS_COMMON_UNMOD}" | sd ' +' ' ')"
    else
        _KERNEL_PARAMS_COMMON_UNMOD="root=${_ROOTDEV} rootfstype=${_ROOTFS} rw ${_ROOTFLAGS} ${_RAIDARRAYS} ${_LUKSSETUP}"
        _KERNEL_PARAMS_MOD="$(echo "${_KERNEL_PARAMS_COMMON_UNMOD}" | sd ' +' ' ')"
    fi
}

_common_bootloader_checks() {
    _activate_special_devices
    _getrootfstype
    _getraidarrays
    _getcryptsetup
    _getrootflags
    _bootloader_kernel_parameters
}

_check_bootpart() {
    _SUBDIR=""
    _BOOTDEV="$(mount | rg -o "(${_DESTDIR}/boot) .*" -r '$1')"
    if [[ -z "${_BOOTDEV}" ]]; then
        _SUBDIR="/boot"
        _BOOTDEV="${_ROOTDEV}"
    fi
}

# only allow ext2/3/4 and vfat on uboot bootloader
_abort_uboot(){
        _FSTYPE="$(${_LSBLK} FSTYPE "${_BOOTDEV}" 2>"${_NO_LOG}")"
        if ! [[ "${_FSTYPE}" == "ext2" || "${_FSTYPE}" == "ext3" || "${_FSTYPE}" == "ext4" || "${_FSTYPE}" == "vfat" ]]; then
            _dialog --title " ERROR " --no-mouse --infobox "Your selected bootloader cannot boot from none ext2/3/4 or vfat /boot on it." 0 0
            return 1
        fi
}

_abort_bcachefs_bootpart() {
        if  ${_LSBLK} FSTYPE "${_BOOTDEV}" 2>"${_NO_LOG}" | rg -q 'bcachefs'; then
            _dialog --title " ERROR " --no-mouse --infobox "Your selected bootloader cannot boot from bcachefs partition with /boot on it." 0 0
            return 1
        fi
}

_uefi_common() {
    _PACKAGES=""
    _DEV=""
    _BOOTDEV=""
    [[ -f "${_DESTDIR}/usr/bin/mkfs.vfat" ]] || _PACKAGES="${_PACKAGES} dosfstools"
    [[ -f "${_DESTDIR}/usr/bin/efivar" ]] || _PACKAGES="${_PACKAGES} efivar"
    [[ -f "${_DESTDIR}/usr/bin/efibootmgr" ]] || _PACKAGES="${_PACKAGES} efibootmgr"
    if [[ -n "${_UEFI_SECURE_BOOT}" ]]; then
        [[ -f "${_DESTDIR}/usr/bin/mokutil" ]] || _PACKAGES="${_PACKAGES} mokutil"
        [[ -f "${_DESTDIR}/usr/bin/sbsign" ]] || _PACKAGES="${_PACKAGES} sbsigntools"
    fi
    if [[ -n "${_PACKAGES}" ]]; then
        _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
        _pacman_error
    fi
    # automounted /boot and ESP needs to be mounted first, trigger mount with ls
    ls "${_DESTDIR}/boot" &>"${_NO_LOG}"
    ls "${_DESTDIR}/efi" &>"${_NO_LOG}"
    _BOOTDEV="$(${_FINDMNT} "${_DESTDIR}/boot" | rg -vw 'systemd-1')"
    if mountpoint -q "${_DESTDIR}/efi" ; then
        _UEFISYS_MP=efi
    else
        _UEFISYS_MP=boot
    fi
    _UEFISYSDEV="$(${_FINDMNT} "${_DESTDIR}/${_UEFISYS_MP}" | rg -vw 'systemd-1')"
    _UEFISYSDEV_FS_UUID="$(_getfsuuid "${_UEFISYSDEV}")"
}

_uefi_efibootmgr() {
    # delete existing entry
    for _bootnum in $(efibootmgr | rg -F -i "${_BOOTMGR_LABEL}" | rg -o '^Boot(\d+)' -r '$1'); do
        efibootmgr --quiet -b "${_bootnum}" -B >> "${_LOG}"
    done
    _BOOTMGRDEV=$(${_LSBLK} PKNAME "${_UEFISYSDEV}" 2>"${_NO_LOG}")
    _BOOTMGRNUM=$(echo "${_UEFISYSDEV}" | sd "${_BOOTMGRDEV}" '' | sd 'p' '')
    efibootmgr --quiet --create --disk "${_BOOTMGRDEV}" --part "${_BOOTMGRNUM}" --loader "${_BOOTMGR_LOADER_PATH}" --label "${_BOOTMGR_LABEL}" >> "${_LOG}"
}

_apple_efi_hfs_bless() {
    ## Grub upstream bzr mactel branch => http://bzr.savannah.gnu.org/lh/grub/branches/mactel/changes
    ## Fedora's mactel-boot => https://bugzilla.redhat.com/show_bug.cgi?id=755093
    _dialog --msgbox "TODO: Apple Mac EFI Bootloader Setup" 0 0
}

_uefi_bootmgr_setup() {
    if [[ "$(cat "/sys/class/dmi/id/sys_vendor")" == 'Apple Inc.' ]] || [[ "$(cat "/sys/class/dmi/id/sys_vendor")" == 'Apple Computer, Inc.' ]]; then
        _apple_efi_hfs_bless
    else
        _uefi_efibootmgr
    fi
}

_efistub_parameters() {
    _FAIL_COMPLEX=""
    _RAID_ON_LVM=""
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _VMLINUZ="${_VMLINUZ_EFISTUB}"
}

_efistub_uefi() {
    _uefi_common || return 1
    _efistub_parameters
    _common_bootloader_checks
    if [[ "${_RUNNING_ARCH}" == "x86_64" && -z "${_EFI_MIXED}" \
          && ! "${_NAME_SCHEME_PARAMETER}" == "SD_GPT_AUTO_GENERATOR" ]]; then
        _dialog --title " EFISTUB " --menu "" 10 60 3 \
            "FIRMWARE" "Unified Kernel Image for ${_UEFI_ARCH} UEFI" \
            "LIMINE" "LIMINE for ${_UEFI_ARCH} UEFI" \
            "rEFInd" "rEFInd for ${_UEFI_ARCH} UEFI" \
            "SYSTEMD-BOOT" "SYSTEMD-BOOT for ${_UEFI_ARCH} UEFI" 2>"${_ANSWER}"
    elif [[ "${_RUNNING_ARCH}" == "x86_64" && -n "${_EFI_MIXED}" \
            && ! "${_NAME_SCHEME_PARAMETER}" == "SD_GPT_AUTO_GENERATOR" ]]; then
        _dialog --title " EFISTUB " --menu "" 9 60 3 \
            "FIRMWARE" "Unified Kernel Image for ${_UEFI_ARCH} UEFI" \
            "LIMINE" "LIMINE for ${_UEFI_ARCH} UEFI" \
            "SYSTEMD-BOOT" "SYSTEMD-BOOT for ${_UEFI_ARCH} UEFI" 2>"${_ANSWER}"
    else
        _dialog --title " EFISTUB " --menu "" 8 60 3 \
            "FIRMWARE" "Unified Kernel Image for ${_UEFI_ARCH} UEFI" \
            "SYSTEMD-BOOT" "SYSTEMD-BOOT for ${_UEFI_ARCH} UEFI" 2>"${_ANSWER}"
    fi
    case $(cat "${_ANSWER}") in
        "FIRMWARE") _uki_uefi ;;
        "LIMINE") _limine_uefi ;;
        "SYSTEMD-BOOT") _systemd_boot_uefi ;;
        "rEFInd") _refind_uefi ;;
    esac
}

_install_bootloader_uefi() {
    if [[ -n "${_UEFI_SECURE_BOOT}" ]]; then
        _grub_uefi
    else
        _dialog --title " ${_UEFI_ARCH} UEFI Bootloader " --menu "" 8 40 2 \
            "EFISTUB" "EFISTUB for ${_UEFI_ARCH} UEFI" \
            "GRUB_UEFI" "GRUB(2) for ${_UEFI_ARCH} UEFI" 2>"${_ANSWER}"
        case $(cat "${_ANSWER}") in
            "EFISTUB")
                        _efistub_uefi ;;
            "GRUB_UEFI")
                        _grub_uefi ;;
        esac
    fi
}

_install_bootloader() {
    _S_BOOTLOADER=""
    _NEXTITEM=4
    _destdir_mounts || return 1
    # switch for mbr usage
    if [[ -z "${_NAME_SCHEME_PARAMETER_RUN}" ]]; then
        _set_guid
        _set_device_name_scheme || return 1
    fi
    if [[ -n "${_UCODE}" ]]; then
        if ! [[ -f "${_DESTDIR}/boot/${_UCODE}" ]]; then
            _PACKAGES="${_UCODE_PKG}"
            _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
            _pacman_error
        fi
    fi
    if [[ -n "${_UEFI_BOOT}" ]]; then
        _install_bootloader_uefi
    else
        if [[ "${_RUNNING_ARCH}" == "aarch64" || "${_RUNNING_ARCH}" == "riscv64" ]]; then
            _uboot
        else
            _dialog --title " BOOTLOADER " --menu "" 8 40 3 \
            "GRUB" "GRUB BIOS" \
            "LIMINE" "LIMINE BIOS" 2>"${_ANSWER}"
            case $(cat "${_ANSWER}") in
                "GRUB") _grub_bios ;;
                "LIMINE") _limine_bios ;;
            esac
        fi
    fi
    if [[ -z "${_S_BOOTLOADER}" ]]; then
        _NEXTITEM=4
    else
        _NEXTITEM="<"
    fi
}
# vim: set ft=sh ts=4 sw=4 et:
