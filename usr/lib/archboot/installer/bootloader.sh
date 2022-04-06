#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# name of intel ucode initramfs image
INTEL_UCODE="intel-ucode.img"
# name of amd ucode initramfs image
AMD_UCODE="amd-ucode.img"
PART_ROOT=""
ROOTFS=""
# name of the initramfs filesystem
INITRAMFS="initramfs-${KERNELPKG}"

getrootfstype() {
    ROOTFS="$(getfstype "${PART_ROOT}")"
}

getrootflags() {
    ROOTFLAGS=""
    ROOTFLAGS="$(findmnt -m -n -o options -T "${DESTDIR}")"
    # add subvolume for btrfs
    if [[ "${ROOTFS}" == "btrfs" ]]; then
        findmnt -m -n -o SOURCE -T "${DESTDIR}" | grep -q "\[" && ROOTFLAGS="${ROOTFLAGS},subvol=$(basename "$(findmnt -m -n -o SOURCE -T "${DESTDIR}" | cut -d "]" -f1)")"
    fi
    [[ -n "${ROOTFLAGS}" ]] && ROOTFLAGS="rootflags=${ROOTFLAGS}"
}

getraidarrays() {
    RAIDARRAYS=""
    if ! grep -q ^ARRAY "${DESTDIR}"/etc/mdadm.conf; then
        RAIDARRAYS="$(echo -n "$(grep ^md /proc/mdstat 2>/dev/null | sed -e 's#\[[0-9]\]##g' -e 's# :.* raid[0-9]##g' -e 's#md#md=#g' -e 's# #,/dev/#g' -e 's#_##g')")"
    fi
}

getcryptsetup() {
    CRYPTSETUP=""
    if ! cryptsetup status "$(basename "${PART_ROOT}")" | grep -q inactive; then
        #avoid clash with dmraid here
        if cryptsetup status "$(basename "${PART_ROOT}")"; then
            if [[ "${NAME_SCHEME_PARAMETER}" == "FSUUID" ]]; then
                CRYPTDEVICE="UUID=$(${_LSBLK} UUID "$(cryptsetup status "$(basename "${PART_ROOT}")" | grep device: | sed -e 's#device:##g')")"
            elif [[ "${NAME_SCHEME_PARAMETER}" == "FSLABEL" ]]; then
                CRYPTDEVICE="LABEL=$(${_LSBLK} LABEL "$(cryptsetup status "$(basename "${PART_ROOT}")" | grep device: | sed -e 's#device:##g')")"
            else
                CRYPTDEVICE="$(cryptsetup status "$(basename "${PART_ROOT}")" | grep device: | sed -e 's#device:##g'))"
            fi
            CRYPTNAME="$(basename "${PART_ROOT}")"
            CRYPTSETUP="cryptdevice=${CRYPTDEVICE}:${CRYPTNAME}"
        fi
    fi
}

getrootpartuuid() {
    _rootpart="${PART_ROOT}"
    _partuuid="$(getpartuuid "${PART_ROOT}")"
    if [[ -n "${_partuuid}" ]]; then
        _rootpart="PARTUUID=${_partuuid}"
    fi
}

getrootpartlabel() {
    _rootpart="${PART_ROOT}"
    _partlabel="$(getpartlabel "${PART_ROOT}")"
    if [[ -n "${_partlabel}" ]]; then
        _rootpart="PARTLABEL=${_partlabel}"
    fi
}

getrootfsuuid() {
    _rootpart="${PART_ROOT}"
    _fsuuid="$(getfsuuid "${PART_ROOT}")"
    if [[ -n "${_fsuuid}" ]]; then
        _rootpart="UUID=${_fsuuid}"
    fi
}

getrootfslabel() {
    _rootpart="${PART_ROOT}"
    _fslabel="$(getfslabel "${PART_ROOT}")"
    if [[ -n "${_fslabel}" ]]; then
        _rootpart="LABEL=${_fslabel}"
    fi
}

# freeze and unfreeze xfs, as hack for grub(2) installing
freeze_xfs() {
    sync
    if [[ -x /usr/bin/xfs_freeze ]]; then
        if grep -q "${DESTDIR}/boot " /proc/mounts | grep -q " xfs "; then
            xfs_freeze -f "${DESTDIR}"/boot >/dev/null 2>&1
            xfs_freeze -u "${DESTDIR}"/boot >/dev/null 2>&1
        fi
        if grep -q "${DESTDIR} " /proc/mounts | grep -q " xfs "; then
            xfs_freeze -f "${DESTDIR}" >/dev/null 2>&1
            xfs_freeze -u "${DESTDIR}" >/dev/null 2>&1
        fi
    fi
}

## Setup kernel cmdline parameters to be added to bootloader configs
bootloader_kernel_parameters() {

    if [[ "${GUID_DETECTED}" == "1" ]]; then
        [[ "${NAME_SCHEME_PARAMETER}" == "PARTUUID" ]] && getrootpartuuid
        [[ "${NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]] && getrootpartlabel
    fi

    [[ "${NAME_SCHEME_PARAMETER}" == "FSUUID" ]] && getrootfsuuid
    [[ "${NAME_SCHEME_PARAMETER}" == "FSLABEL" ]] && getrootfslabel

    [[ "${_rootpart}" == "" ]] && _rootpart="${PART_ROOT}"

    _KERNEL_PARAMS_COMMON_UNMOD="root=${_rootpart} rootfstype=${ROOTFS} rw ${ROOTFLAGS} ${RAIDARRAYS} ${CRYPTSETUP}"
    # add uncommonn options here
    _KERNEL_PARAMS_BIOS_UNMOD="${_KERNEL_PARAMS_COMMON_UNMOD}"
    _KERNEL_PARAMS_UEFI_UNMOD="${_KERNEL_PARAMS_COMMON_UNMOD}"
    _KERNEL_PARAMS_BIOS_MOD="$(echo "${_KERNEL_PARAMS_BIOS_UNMOD}" | sed -e 's#   # #g' | sed -e 's#  # #g')"
    _KERNEL_PARAMS_UEFI_MOD="$(echo "${_KERNEL_PARAMS_UEFI_UNMOD}" | sed -e 's#   # #g' | sed -e 's#  # #g')"

}

# basic checks needed for all bootloaders
common_bootloader_checks() {
    activate_special_devices
    getrootfstype
    getraidarrays
    getcryptsetup
    getrootflags
    bootloader_kernel_parameters
}

# look for a separately-mounted /boot partition
check_bootpart() {
    subdir=""
    bootdev="$(mount | grep "${DESTDIR}/boot " | cut -d' ' -f 1)"
    if [[ "${bootdev}" == "" ]]; then
        subdir="/boot"
        bootdev="${PART_ROOT}"
    fi
}

# check for nilfs2 bootpart and abort if detected
abort_nilfs_bootpart() {
        FSTYPE="$(${_LSBLK} FSTYPE "${bootdev}")"
        if [[ "${FSTYPE}" = "nilfs2" ]]; then
            DIALOG --msgbox "Error:\nYour selected bootloader cannot boot from nilfs2 partition with /boot on it." 0 0
            return 1
        fi
}

# check for f2fs bootpart and abort if detected
abort_f2fs_bootpart() {
        FSTYPE="$(${_LSBLK} FSTYPE "${bootdev}")"
        if [[ "${FSTYPE}" = "f2fs" ]]; then
            DIALOG --msgbox "Error:\nYour selected bootloader cannot boot from f2fs partition with /boot on it." 0 0
            return 1
        fi
}

uefi_mount_efivarfs() {

    ## Mount efivarfs if it is not already mounted
    if ! mount | grep -q /sys/firmware/efi/efivars; then
        modprobe -q efivarfs
        mount -t efivarfs efivarfs /sys/firmware/efi/efivars
    fi

}

detect_uefi_secure_boot() {

    export _DETECTED_UEFI_SECURE_BOOT="0"

    if [[ "${_DETECTED_UEFI_BOOT}" == "1" ]]; then
        uefi_mount_efivarfs
        _SECUREBOOT_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SecureBoot 2>/dev/null | tail -n -1 | awk '{print $2}')"
        _SETUPMODE_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode  2>/dev/null | tail -n -1 | awk '{print $2}')"

        if [[ "${_SECUREBOOT_VAR_VALUE}" == "01" ]] && [[ "${_SETUPMODE_VAR_VALUE}" == "00" ]]; then
            export _DETECTED_UEFI_SECURE_BOOT="1"
        fi
    fi

}

detect_uefi_boot() {

    export _DETECTED_UEFI_BOOT="0"

    [[ -e "/sys/firmware/efi" ]] && _DETECTED_UEFI_BOOT="1"

    detect_uefi_secure_boot

}

do_uefi_setup_env_vars() {

    if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
        if grep -q '_IA32_UEFI=1' /proc/cmdline 1>/dev/null; then
            export _EFI_MIXED="1"
            export _UEFI_ARCH="IA32"
            export _SPEC_UEFI_ARCH="ia32"
        else
            export _EFI_MIXED="0"
            export _UEFI_ARCH="X64"
            export _SPEC_UEFI_ARCH="x64"
        fi
    fi
    if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
        export _EFI_MIXED="0"
        export _UEFI_ARCH="AA64"
        export _SPEC_UEFI_ARCH="aa64"
    fi

}

do_uefi_common() {

    do_uefi_setup_env_vars

    PACKAGES=""
    [[ ! -f "${DESTDIR}/usr/bin/mkfs.vfat" ]] && PACKAGES="${PACKAGES} dosfstools"
    [[ ! -f "${DESTDIR}/usr/bin/efivar" ]] && PACKAGES="${PACKAGES} efivar"
    [[ ! -f "${DESTDIR}/usr/bin/efibootmgr" ]] && PACKAGES="${PACKAGES} efibootmgr"
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        [[ ! -f "${DESTDIR}/usr/bin/mokutil" ]] && PACKAGES="${PACKAGES} mokutil"
        [[ ! -f "${DESTDIR}/usr/bin/efi-readvar" ]] && PACKAGES="${PACKAGES} efitools"
        [[ ! -f "${DESTDIR}/usr/bin/sbsign" ]] && PACKAGES="${PACKAGES} sbsigntools"
    fi
    ! [[ "${PACKAGES}" == "" ]] && run_pacman

    check_efisys_part

}

do_uefi_efibootmgr() {

    uefi_mount_efivarfs

    if [[ "$(/usr/bin/efivar -l)" ]]; then
        cat << EFIBEOF > "/tmp/efibootmgr_run.sh"
#!/usr/bin/env bash

_EFIBOOTMGR_LOADER_PARAMETERS="${_EFIBOOTMGR_LOADER_PARAMETERS}"

for _bootnum in \$(efibootmgr | grep '^Boot[0-9]' | fgrep -i "${_EFIBOOTMGR_LABEL}" | cut -b5-8) ; do
    efibootmgr --quiet --bootnum "\${_bootnum}" --delete-bootnum
done

if [[ "\${_EFIBOOTMGR_LOADER_PARAMETERS}" != "" ]]; then
    efibootmgr --quiet --create --disk "${_EFIBOOTMGR_DISC}" --part "${_EFIBOOTMGR_PART_NUM}" --loader "${_EFIBOOTMGR_LOADER_PATH}" --label "${_EFIBOOTMGR_LABEL}" --unicode "\${_EFIBOOTMGR_LOADER_PARAMETERS}" -e "3"
else
    efibootmgr --quiet --create --disk "${_EFIBOOTMGR_DISC}" --part "${_EFIBOOTMGR_PART_NUM}" --loader "${_EFIBOOTMGR_LOADER_PATH}" --label "${_EFIBOOTMGR_LABEL}" -e "3"
fi

EFIBEOF

        chmod a+x "/tmp/efibootmgr_run.sh"
        /tmp/efibootmgr_run.sh &>"/tmp/efibootmgr_run.log"
    else
        DIALOG --msgbox "Boot entry could not be created. Check whether you have booted in UEFI boot mode and create a boot entry for ${UEFISYS_MOUNTPOINT}/${_EFIBOOTMGR_LOADER_PATH} using efibootmgr." 0 0
    fi

    unset _EFIBOOTMGR_LABEL
    unset _EFIBOOTMGR_DISC
    unset _EFIBOOTMGR_PART_NUM
    unset _EFIBOOTMGR_LOADER_PATH
    unset _EFIBOOTMGR_LOADER_PARAMETERS

}

do_apple_efi_hfs_bless() {

    ## Grub upstream bzr mactel branch => http://bzr.savannah.gnu.org/lh/grub/branches/mactel/changes
    ## Fedora's mactel-boot => https://bugzilla.redhat.com/show_bug.cgi?id=755093
    DIALOG --msgbox "TODO: Apple Mac EFI Bootloader Setup" 0 0

}

do_uefi_bootmgr_setup() {

    _uefisysdev="$(findmnt -vno SOURCE "${DESTDIR}/${UEFISYS_MOUNTPOINT}")"
    _DISC="$(${_LSBLK} KNAME "${_uefisysdev}")"
    UEFISYS_PART_NUM="$(${_BLKID} -p -i -s PART_ENTRY_NUMBER -o value "${_uefisysdev}")"

    _BOOTMGR_DISC="${_DISC}"
    _BOOTMGR_PART_NUM="${UEFISYS_PART_NUM}"

    if [[ "$(cat "/sys/class/dmi/id/sys_vendor")" == 'Apple Inc.' ]] || [[ "$(cat "/sys/class/dmi/id/sys_vendor")" == 'Apple Computer, Inc.' ]]; then
        do_apple_efi_hfs_bless
    else
        ## For all the non-Mac UEFI systems
        _EFIBOOTMGR_LABEL="${_BOOTMGR_LABEL}"
        _EFIBOOTMGR_DISC="${_BOOTMGR_DISC}"
        _EFIBOOTMGR_PART_NUM="${_BOOTMGR_PART_NUM}"
        _EFIBOOTMGR_LOADER_PATH="${_BOOTMGR_LOADER_PATH}"
        _EFIBOOTMGR_LOADER_PARAMETERS="${_BOOTMGR_LOADER_PARAMETERS}"
        do_uefi_efibootmgr
    fi

    unset _BOOTMGR_LABEL
    unset _BOOTMGR_DISC
    unset _BOOTMGR_PART_NUM
    unset _BOOTMGR_LOADER_PATH
    unset _BOOTMGR_LOADER_PARAMETERS

}

do_uefi_secure_boot_efitools() {

    do_uefi_common
    # install helper tools and create entries in UEFI boot manager, if not present
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        if [[ ! -f "${UEFISYS_MOUNTPOINT}/EFI/BOOT/HashTool.efi" ]]; then
            systemd-nspawn -q -D "${DESTDIR}" cp "/usr/share/efitools/efi/HashTool.efi" "${UEFISYS_MOUNTPOINT}/EFI/BOOT/HashTool.efi"
            _BOOTMGR_LABEL="HashTool (Secure Boot)"
            _BOOTMGR_LOADER_DIR="/EFI/BOOT/HashTool.efi"
            do_uefi_bootmgr_setup
        fi
        if [[ ! -f "${UEFISYS_MOUNTPOINT}/EFI/BOOT/KeyTool.efi" ]]; then
            systemd-nspawn -q -D "${DESTDIR}" cp "/usr/share/efitools/efi/KeyTool.efi" "${UEFISYS_MOUNTPOINT}/EFI/BOOT/KeyTool.efi"
            _BOOTMGR_LABEL="KeyTool (Secure Boot)"
            _BOOTMGR_LOADER_DIR="/EFI/BOOT/KeyTool.efi"
            do_uefi_bootmgr_setup
        fi
    fi

}

do_secureboot_keys() {
    CN=""
    MOK_PW=""
    KEYDIR=""
    while [[ "${KEYDIR}" = "" ]]; do
        DIALOG --inputbox "Setup keys:\nEnter the directory to store the keys on ${DESTDIR}.\nPlease leave the leading slash \"/\"." 8 65 "etc/secureboot/keys" 2>"${ANSWER}" || KEYDIR=""
        KEYDIR=$(cat "${ANSWER}")
    done
    if [[ ! -d "${DESTDIR}/${KEYDIR}" ]]; then
        while [[ "${CN}" = "" ]]; do
            DIALOG --inputbox "Setup keys:\nEnter a common name(CN) for your keys, eg. Your Name" 8 65 "" 2>"${ANSWER}" || CN=""
            CN=$(cat "${ANSWER}")
        done
        secureboot-keys.sh -name="${CN}" "${DESTDIR}/${KEYDIR}" > "${LOG}" 2>&1 || return 1
         DIALOG --msgbox "Setup keys created:\nCommon name(CN) ${CN} used for your keys in ${DESTDIR}/${KEYDIR} " 8 65
    else
         DIALOG --msgbox "Setup keys:\n-Directory ${DESTDIR}/${KEYDIR} exists\n-assuming keys are already created\n-trying to use existing keys now" 8 65 ""
    fi
}

do_mok_sign () {
    UEFI_BOOTLOADER_DIR="${UEFISYS_MOUNTPOINT}/EFI/BOOT"
    INSTALL_MOK=""
    MOK_PW=""
    DIALOG --yesno "Do you want to install the MOK certificate to the UEFI keys?" 0 0 && INSTALL_MOK="1"
    if [[ "${INSTALL_MOK}" == "1" ]]; then
        while [[ "${MOK_PW}" = "" ]]; do
            DIALOG --insecure --passwordbox "Enter a one time MOK password for SHIM on reboot:" 8 65 2>"${ANSWER}" || return 1
            PASS=$(cat "${ANSWER}")
            DIALOG --insecure --passwordbox "Retype one time MOK password:" 8 65 2>"${ANSWER}" || return 1
            PASS2=$(cat "${ANSWER}")
            if [[ "${PASS}" = "${PASS2}" ]]; then
                MOK_PW=${PASS}
                echo "${MOK_PW}" > /tmp/.password
                echo "${MOK_PW}" >> /tmp/.password
                MOK_PW=/tmp/.password
            else
                DIALOG --msgbox "Password didn't match, please enter again." 8 65
            fi
        done
        mokutil -i "${DESTDIR}"/"${KEYDIR}"/MOK/MOK.cer < ${MOK_PW} > "${LOG}"
        rm /tmp/.password
        DIALOG --infobox "MOK keys have been installed successfully.\n\nContinuing in 3 seconds..." 6 65
        sleep 3
    fi
    SIGN_MOK=""
    DIALOG --yesno "Do you want to sign /boot/${VMLINUZ} and ${UEFI_BOOTLOADER_DIR}/grub${_SPEC_UEFI_ARCH}.efi with the MOK certificate?" 0 0 && SIGN_MOK="1"
    if [[ "${SIGN_MOK}" == "1" ]]; then
        systemd-nspawn -q -D "${DESTDIR}" sbsign --key /"${KEYDIR}"/MOK/MOK.key --cert /"${KEYDIR}"/MOK/MOK.crt --output /boot/${VMLINUZ} /boot/"${VMLINUZ}" > "${LOG}"
        systemd-nspawn -q -D "${DESTDIR}" sbsign --key /"${KEYDIR}"/MOK/MOK.key --cert /"${KEYDIR}"/MOK/MOK.crt --output "${UEFI_BOOTLOADER_DIR}"/grub${_SPEC_UEFI_ARCH}.efi "${UEFI_BOOTLOADER_DIR}"/grub${_SPEC_UEFI_ARCH}.efi > "${LOG}"
        DIALOG --infobox "/boot/${VMLINUZ} and ${UEFI_BOOTLOADER_DIR}/grub${_SPEC_UEFI_ARCH}.efi\nbeen signed successfully.\n\nContinuing in 3 seconds..." 9 65
        sleep 3
    fi
}

do_pacman_sign() {
    SIGN_KERNEL=""
    DIALOG --yesno "Do you want to install a pacman hook for automatic signing /boot/${VMLINUZ} on updates?" 0 0 && SIGN_KERNEL="1"
    if [[ "${SIGN_KERNEL}" == "1" ]]; then
        [[ ! -d "${DESTDIR}/etc/pacman.d/hooks" ]] &&  mkdir -p  "${DESTDIR}"/etc/pacman.d/hooks/
        HOOKNAME="${DESTDIR}/etc/pacman.d/hooks/999-sign_kernel_for_secureboot.hook"
        cat << EOF > "${HOOKNAME}"
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux

[Action]
Description = Signing kernel with Machine Owner Key for Secure Boot
When = PostTransaction
Exec = /usr/bin/find /boot/ -maxdepth 1 -name 'vmlinuz-*' -exec /usr/bin/sh -c 'if ! /usr/bin/sbverify --list {} 2>/dev/null | /usr/bin/grep -q "signature certificates"; then /usr/bin/sbsign --key /${KEYDIR}/MOK/MOK.key --cert /${KEYDIR}/MOK/MOK.crt --output {} {}; fi' ;
Depends = sbsigntools
Depends = findutils
Depends = grep
EOF
        DIALOG --infobox "Pacman hook for automatic signing\nhas been installed successfully:\n${HOOKNAME}\n\nContinuing in 3 seconds..." 7 60
        sleep 3
    fi
}

do_efistub_copy_to_efisys() {

    if [[ "${UEFISYS_MOUNTPOINT}" != "/boot" ]]; then
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            _EFISTUB_KERNEL="linux/arch/${VMLINUZ_EFISTUB}.efi"
        else
            _EFISTUB_KERNEL="linux/arch/${VMLINUZ}.efi"
        fi
        _EFISTUB_INITRAMFS="linux/arch/${INITRAMFS}"

        ! [[ -d "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch" ]] && mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/"

        rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_KERNEL}"
        rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}.img"
        rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}-fallback.img"

        cp -f "${DESTDIR}/boot/${VMLINUZ}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_KERNEL}"
        cp -f "${DESTDIR}/boot/${INITRAMFS}.img" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}.img"
        cp -f "${DESTDIR}/boot/${INITRAMFS}-fallback.img" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}-fallback.img"

        #######################

        cat << CONFEOF > "${DESTDIR}/etc/systemd/system/efistub_copy.path"
[Unit]
Description=Copy EFISTUB Kernel and Initramfs files to EFI SYSTEM PARTITION

[Path]
PathChanged=/boot/${VMLINUZ}
PathChanged=/boot/${INTEL_UCODE}
PathChanged=/boot/${AMD_UCODE}
PathChanged=/boot/${INITRAMFS}.img
PathChanged=/boot/${INITRAMFS}-fallback.img
Unit=efistub_copy.service

[Install]
WantedBy=multi-user.target
CONFEOF

        cat << CONFEOF > "${DESTDIR}/etc/systemd/system/efistub_copy.service"
[Unit]
Description=Copy EFISTUB Kernel and Initramfs files to EFI SYSTEM PARTITION

[Service]
Type=oneshot
ExecStart=/usr/bin/cp -f /boot/${VMLINUZ} ${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_KERNEL}
ExecStart=/usr/bin/cp -f /boot/${INTEL_UCODE} ${UEFISYS_MOUNTPOINT}/EFI/arch/${INTEL_UCODE}
ExecStart=/usr/bin/cp -f /boot/${AMD_UCODE} ${UEFISYS_MOUNTPOINT}/EFI/arch/${AMD_UCODE}
ExecStart=/usr/bin/cp -f /boot/${INITRAMFS}.img ${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}.img
ExecStart=/usr/bin/cp -f /boot/${INITRAMFS}-fallback.img ${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}-fallback.img
CONFEOF

        systemd-nspawn -q -D "${DESTDIR}" /usr/bin/systemctl enable efistub_copy.path
    fi

    ###########################

    _bootdev="$(findmnt -vno SOURCE "${DESTDIR}/boot")"
    _uefisysdev="$(findmnt -vno SOURCE "${DESTDIR}/${UEFISYS_MOUNTPOINT}")"

    UEFISYS_PART_FS_UUID="$(getfsuuid "${_uefisysdev}")"

    if [[ "${UEFISYS_MOUNTPOINT}" == "/boot" ]]; then
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
             _KERNEL_NORMAL="/${VMLINUZ_EFISTUB}"
        else
            _KERNEL_NORMAL="/${VMLINUZ}"
            _INITRD_INTEL_UCODE="/${INTEL_UCODE}"
        fi

        _INITRD_AMD_UCODE="/${AMD_UCODE}"

        _INITRD_NORMAL="/${INITRAMFS}.img"

        _INITRD_FALLBACK_NORMAL="/${INITRAMFS}-fallback.img"
    else
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            _KERNEL_NORMAL="/EFI/arch/${VMLINUZ_EFISTUB}"
        else
            _KERNEL_NORMAL="/EFI/arch/${_EFISTUB_KERNEL}"
            _INITRD_INTEL_UCODE="/EFI/arch/${INTEL_UCODE}"
        fi
        _INITRD_AMD_UCODE="/EFI/arch/${AMD_UCODE}"

        _INITRD_NORMAL="/EFI/arch/${_EFISTUB_INITRAMFS}.img"

        _INITRD_FALLBACK_NORMAL="/EFI/arch/${_EFISTUB_INITRAMFS}-fallback.img"
    fi

}

do_efistub_uefi() {

    do_uefi_common

    bootdev=""
    FAIL_COMPLEX=""
    USE_DMRAID=""
    RAID_ON_LVM=""
    common_bootloader_checks

    do_efistub_copy_to_efisys

    ###################################

    if [[ "${UEFISYS_MOUNTPOINT}" == "/boot" ]]; then
        _CONTINUE="1"
    else
        if [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_KERNEL}" ]] && [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}.img" ]]; then
            DIALOG --msgbox "The EFISTUB Kernel and initramfs have been copied to ${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_KERNEL} and ${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}.img respectively." 0 0
            _CONTINUE="1"
        else
            DIALOG --msgbox "Error setting up EFISTUB kernel and initramfs in ${UEFISYS_MOUNTPOINT}." 0 0
            _CONTINUE="0"
        fi
    fi

    if [[ "${_CONTINUE}" == "1" ]]; then
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            do_systemd_boot_uefi
        else
            DIALOG --menu "Select which UEFI Boot Manager to install, to provide a menu for the EFISTUB kernels?" 11 55 3 \
                "systemd-boot" "systemd-boot for ${_UEFI_ARCH} UEFI" \
                "refind" "refind for ${_UEFI_ARCH} UEFI" \
                "NONE" "No Boot Manager" 2>"${ANSWER}" || CANCEL=1
            case $(cat "${ANSWER}") in
                "systemd-boot") do_systemd_boot_uefi ;;
                "refind") do_refind_uefi;;
                "NONE") return 0 ;;
            esac
        fi
    fi

}

do_systemd_boot_uefi() {

    DIALOG --infobox "Setting up systemd-boot now..." 3 40

    # create directory structure, if it doesn't exist
    ! [[ -d "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries" ]] && mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries"
    cat << GUMEOF > "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-main.conf"
title    Arch Linux
linux    ${_KERNEL_NORMAL}
GUMEOF

    if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
    cat << GUMEOF >> "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-main.conf"
initrd   ${_INITRD_INTEL_UCODE}
GUMEOF
    fi

    cat << GUMEOF >> "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-main.conf"
initrd   ${_INITRD_AMD_UCODE}
initrd   ${_INITRD_NORMAL}
options  ${_KERNEL_PARAMS_UEFI_MOD}
GUMEOF

    cat << GUMEOF > "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-fallback.conf"
title    Arch Linux Fallback
linux    ${_KERNEL_NORMAL}
GUMEOF

    if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
    cat << GUMEOF >> "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-fallback.conf"
initrd   ${_INITRD_INTEL_UCODE}
GUMEOF
    fi

    cat << GUMEOF >> "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-fallback.conf"
initrd   ${_INITRD_AMD_UCODE}
initrd   ${_INITRD_FALLBACK_NORMAL}
options  ${_KERNEL_PARAMS_UEFI_MOD}
GUMEOF

    cat << GUMEOF > "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/loader.conf"
timeout 5
default archlinux-core-main
GUMEOF

    uefi_mount_efivarfs

    chroot_mount
    chroot "${DESTDIR}" "/usr/bin/bootctl" --path="${UEFISYS_MOUNTPOINT}" install >"${LOG}" 2>&1
    chroot "${DESTDIR}" "/usr/bin/bootctl" --path="${UEFISYS_MOUNTPOINT}" update >"${LOG}" 2>&1
    chroot_umount

    if [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi" ]]; then
        DIALOG --msgbox "You will now be put into the editor to edit:\nloader.conf and systemd-boot menu entry files\n\nAfter you save your changes, exit the editor." 8 50
        geteditor || return 1

        "${EDITOR}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-main.conf"
        "${EDITOR}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-fallback.conf"

        "${EDITOR}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/loader.conf"

        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            _UEFISYS_EFI_BOOT_DIR="1"
        else
            DIALOG --defaultno --yesno "Do you want to copy?\n\n${UEFISYS_MOUNTPOINT}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi --> ${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi\n\nThis might be needed in some systems,\nwhere efibootmgr may not work due to firmware issues." 10 75 && _UEFISYS_EFI_BOOT_DIR="1"
        fi

        if [[ "${_UEFISYS_EFI_BOOT_DIR}" == "1" ]]; then
            mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT"
            rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi" || true
            cp -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi"
        fi
    else
        DIALOG --msgbox "Error installing systemd-boot..." 0 0
    fi
}

do_refind_uefi() {
    if [[ ! -f "${DESTDIR}/usr/bin/refind-install" ]]; then
        DIALOG --infobox "Installing refind..." 0 0
        PACKAGES="refind"
        run_pacman
    fi

    DIALOG --infobox "Setting up refind now. This needs some time..." 3 50

    ! [[ -d "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind" ]] && mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/"
    cp -f "${DESTDIR}/usr/share/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi"
    cp -r "${DESTDIR}/usr/share/refind/icons" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/"
    cp -r "${DESTDIR}/usr/share/refind/fonts" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/"

     ! [[ -d "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/tools" ]] &&  mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/tools/"
    cp -rf "${DESTDIR}/usr/share/refind/drivers_${_SPEC_UEFI_ARCH}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/tools/"

    _REFIND_CONFIG="${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/refind.conf"
    cp -f "${DESTDIR}/usr/share/refind/refind.conf-sample" "${_REFIND_CONFIG}"

    sed 's|^#resolution 1024 768|resolution 1024 768|g' -i "${_REFIND_CONFIG}"
    sed 's|^#scan_driver_dirs EFI/tools/drivers,drivers|scan_driver_dirs EFI/tools/drivers_${_SPEC_UEFI_ARCH}|g' -i "${_REFIND_CONFIG}"
    sed 's|^#scanfor internal,external,optical,manual|scanfor manual,internal,external,optical|g' -i "${_REFIND_CONFIG}"
    sed 's|^#also_scan_dirs boot,ESP2:EFI/linux/kernels|also_scan_dirs boot|g' -i "${_REFIND_CONFIG}"
    sed 's|^#scan_all_linux_kernels|scan_all_linux_kernels|g' -i "${_REFIND_CONFIG}"

    if [[ "${UEFISYS_MOUNTPOINT}" == "/boot" ]]; then
        _REFIND_LINUX_CONF="${DESTDIR}/${UEFISYS_MOUNTPOINT}/refind_linux.conf"
    else
        _REFIND_LINUX_CONF="${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/refind_linux.conf"
    fi

    cat << REFINDEOF > "${_REFIND_LINUX_CONF}"
"Boot with Defaults"              "${_KERNEL_PARAMS_UEFI_MOD} initrd=${_INITRD_INTEL_UCODE} initrd=${_INITRD_AMD_UCODE} initrd=${_INITRD_NORMAL}"
"Boot with fallback initramfs"    "${_KERNEL_PARAMS_UEFI_MOD} initrd=${_INITRD_INTEL_UCODE} initrd=${_INITRD_AMD_UCODE} initrd=${_INITRD_FALLBACK_NORMAL}"
REFINDEOF

    if [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" ]]; then
        _BOOTMGR_LABEL="rEFInd"
        _BOOTMGR_LOADER_DIR="/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi"
        do_uefi_bootmgr_setup

        DIALOG --infobox "refind has been setup successfully.\n\nContinuing in 3 seconds..." 6 40
        sleep 3

        DIALOG --msgbox "You will now be put into the editor to edit:\nrefind.conf and refind_linux.conf\n\nAfter you save your changes, exit the editor." 8 50
        geteditor || return 1
        "${EDITOR}" "${_REFIND_CONFIG}"
        "${EDITOR}" "${_REFIND_LINUX_CONF}"
        DIALOG --defaultno --yesno "Do you want to copy?\n\n${UEFISYS_MOUNTPOINT}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi --> ${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi\n\nThis might be needed in some systems,\nwhere efibootmgr may not work due to firmware issues." 10 70 && _UEFISYS_EFI_BOOT_DIR="1"

        if [[ "${_UEFISYS_EFI_BOOT_DIR}" == "1" ]]; then
            mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT"

            rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi" || true
            rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/refind.conf" || true
            rm -rf "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/icons" || true

            cp -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi"
            cp -f "${_REFIND_CONFIG}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/refind.conf"
            cp -rf "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/icons" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/"
        fi
    else
        DIALOG --msgbox "Error setting up refind." 3 40
    fi

}

do_grub_common_before() {
    ##### Check whether the below limitations still continue with ver 2.00~beta4
    ### Grub(2) restrictions:
    ## - Encryption is not recommended for grub(2) /boot!

    bootdev=""
    FAIL_COMPLEX=""
    USE_DMRAID=""
    RAID_ON_LVM=""
    common_bootloader_checks
    abort_f2fs_bootpart || return 1

    if ! dmraid -r | grep -q ^no; then
        DIALOG --yesno "Setup detected dmraid device.\nDo you want to install grub on this device?" 6 50 && USE_DMRAID="1"
    fi
    if [[ ! -d "${DESTDIR}/usr/lib/grub" ]]; then
        DIALOG --infobox "Installing grub..." 0 0
        PACKAGES="grub"
        run_pacman
    fi
}

do_grub_config() {

    chroot_mount

    ########

    BOOT_PART_FS_UUID="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs_uuid" "/boot" 2>/dev/null)"
    BOOT_PART_FS_LABEL="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs_label" "/boot" 2>/dev/null)"
    BOOT_PART_HINTS_STRING="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="hints_string" "/boot" 2>/dev/null)"
    BOOT_PART_FS="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs" "/boot" 2>/dev/null)"

    BOOT_PART_DRIVE="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="drive" "/boot" 2>/dev/null)"

    ########

    ROOT_PART_FS_UUID="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs_uuid" "/" 2>/dev/null)"
    ROOT_PART_HINTS_STRING="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="hints_string" "/" 2>/dev/null)"
    ROOT_PART_FS="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs" "/" 2>/dev/null)"

    ########

    USR_PART_FS_UUID="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs_uuid" "/usr" 2>/dev/null)"
    USR_PART_HINTS_STRING="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="hints_string" "/usr" 2>/dev/null)"
    USR_PART_FS="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs" "/usr" 2>/dev/null)"

    ########

    if [[ "${GRUB_UEFI}" == "1" ]]; then
        UEFISYS_PART_FS_UUID="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs_uuid" "/${UEFISYS_MOUNTPOINT}" 2>/dev/null)"
        UEFISYS_PART_HINTS_STRING="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="hints_string" "/${UEFISYS_MOUNTPOINT}" 2>/dev/null)"
    fi

    ########

    if [[ "${ROOT_PART_FS_UUID}" == "${BOOT_PART_FS_UUID}" ]]; then
        subdir="/boot"
        # on btrfs we need to check on subvol
        if mount | grep "${DESTDIR} " | grep btrfs | grep subvol; then
            subdir="/$(btrfs subvolume show "${DESTDIR}/" | grep Name | cut -d ":" -f2)"/boot
        fi
    else
        subdir=""
        # on btrfs we need to check on subvol
        if mount | grep "${DESTDIR}/boot " | grep btrfs | grep subvol; then
            subdir="/$(btrfs subvolume show "${DESTDIR}/boot" | grep Name | cut -d ":" -f2)"
        fi
    fi

    ########

    ## Move old config file, if any
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        GRUB_CFG="grub${_SPEC_UEFI_ARCH}.cfg"
    else
        GRUB_CFG="grub.cfg"
    fi
    [[ -f "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}" ]] && (mv "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}" "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}.bak" || true)
    ## Ignore if the insmod entries are repeated - there are possibilities of having /boot in one disk and root-fs in altogether different disk
    ## with totally different configuration.

    cat << EOF > "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

if [ "\${grub_platform}" == "efi" ]; then
    set _UEFI_ARCH="\${grub_cpu}"

    if [ "\${grub_cpu}" == "x86_64" ]; then
        set _SPEC_UEFI_ARCH="x64"
    fi

    if [ "\${grub_cpu}" == "i386" ]; then
        set _SPEC_UEFI_ARCH="ia32"
    fi
    if [ "\${grub_cpu}" == "aarch64" ]; then
        set _SPEC_UEFI_ARCH="aa64"
    fi
fi

EOF

    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

insmod part_gpt
insmod part_msdos

# Include fat fs module - required for uefi systems.
insmod fat

insmod ${BOOT_PART_FS}
insmod ${ROOT_PART_FS}
insmod ${USR_PART_FS}

insmod search_fs_file
insmod search_fs_uuid
insmod search_label

insmod linux
insmod chain

set pager="1"
# set debug="all"

set locale_dir="\${prefix}/locale"

EOF

    [[ "${USE_RAID}" == "1" ]] && echo "insmod raid" >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    ! [[ "${RAID_ON_LVM}" == "" ]] && echo "insmod lvm" >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    #shellcheck disable=SC2129
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

if [ -e "\${prefix}/\${grub_cpu}-\${grub_platform}/all_video.mod" ]; then
    insmod all_video
else
    if [ "\${grub_platform}" == "efi" ]; then
        insmod efi_gop
        insmod efi_uga
    fi

    if [ "\${grub_platform}" == "pc" ]; then
        insmod vbe
        insmod vga
    fi

    insmod video_bochs
    insmod video_cirrus
fi

insmod font

search --fs-uuid --no-floppy --set=usr_part ${USR_PART_HINTS_STRING} ${USR_PART_FS_UUID}
search --fs-uuid --no-floppy --set=root_part ${ROOT_PART_HINTS_STRING} ${ROOT_PART_FS_UUID}

if [ -e "\${prefix}/fonts/unicode.pf2" ]; then
    set _fontfile="\${prefix}/fonts/unicode.pf2"
else
    if [ -e "(\${root_part})/usr/share/grub/unicode.pf2" ]; then
        set _fontfile="(\${root_part})/usr/share/grub/unicode.pf2"
    else
        if [ -e "(\${usr_part})/share/grub/unicode.pf2" ]; then
            set _fontfile="(\${usr_part})/share/grub/unicode.pf2"
        fi
    fi
fi

if loadfont "\${_fontfile}" ; then
    insmod gfxterm
    set gfxmode="auto"

    terminal_input console
    terminal_output gfxterm
fi

EOF

    echo "" >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    sort "/tmp/.device-names" >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    echo "" >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

    if [[ "${NAME_SCHEME_PARAMETER}" == "PARTUUID" ]] || [[ "${NAME_SCHEME_PARAMETER}" == "FSUUID" ]] ; then
        GRUB_ROOT_DRIVE="search --fs-uuid --no-floppy --set=root ${BOOT_PART_HINTS_STRING} ${BOOT_PART_FS_UUID}"
    else
        if [[ "${NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]] || [[ "${NAME_SCHEME_PARAMETER}" == "FSLABEL" ]] ; then
            GRUB_ROOT_DRIVE="search --label --no-floppy --set=root ${BOOT_PART_HINTS_STRING} ${BOOT_PART_FS_LABEL}"
        else
            GRUB_ROOT_DRIVE="set root=${BOOT_PART_DRIVE}"
        fi
    fi

    if [[ "${GRUB_UEFI}" == "1" ]]; then
        LINUX_UNMOD_COMMAND="linux ${subdir}/${VMLINUZ} ${_KERNEL_PARAMS_UEFI_MOD}"
    else
        LINUX_UNMOD_COMMAND="linux ${subdir}/${VMLINUZ} ${_KERNEL_PARAMS_BIOS_MOD}"
    fi

    LINUX_MOD_COMMAND=$(echo "${LINUX_UNMOD_COMMAND}" | sed -e 's#   # #g' | sed -e 's#  # #g')

    ## create default kernel entry

    NUMBER="0"

if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

# (${NUMBER}) Arch Linux
menuentry "Arch Linux" {
    set gfxpayload="keep"
    ${GRUB_ROOT_DRIVE}
    ${LINUX_MOD_COMMAND}
    initrd ${subdir}/${AMD_UCODE} ${subdir}/${INITRAMFS}.img
}

EOF

    NUMBER=$((NUMBER+1))

    ## create kernel fallback entry
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

# (${NUMBER}) Arch Linux Fallback
menuentry "Arch Linux Fallback" {
    set gfxpayload="keep"
    ${GRUB_ROOT_DRIVE}
    ${LINUX_MOD_COMMAND}
    initrd ${subdir}/${AMD_UCODE} ${subdir}/${INITRAMFS}-fallback.img
}

EOF

else
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

# (${NUMBER}) Arch Linux
menuentry "Arch Linux" {
    set gfxpayload="keep"
    ${GRUB_ROOT_DRIVE}
    ${LINUX_MOD_COMMAND}
    initrd ${subdir}/${INTEL_UCODE} ${subdir}/${AMD_UCODE} ${subdir}/${INITRAMFS}.img
}

EOF

    NUMBER=$((NUMBER+1))

    ## create kernel fallback entry
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

# (${NUMBER}) Arch Linux Fallback
menuentry "Arch Linux Fallback" {
    set gfxpayload="keep"
    ${GRUB_ROOT_DRIVE}
    ${LINUX_MOD_COMMAND}
    initrd ${subdir}/${INTEL_UCODE} ${subdir}/${AMD_UCODE} ${subdir}/${INITRAMFS}-fallback.img
}

EOF

    NUMBER=$((NUMBER+1))

    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

if [ "\${grub_platform}" == "efi" ]; then

    ## UEFI Shell 2.0
    #menuentry "UEFI Shell \${_UEFI_ARCH} v2" {
    #    search --fs-uuid --no-floppy --set=root ${UEFISYS_PART_HINTS_STRING} ${UEFISYS_PART_FS_UUID}
    #    chainloader /EFI/tools/shell\${_SPEC_UEFI_ARCH}_v2.efi
    #}

    ## UEFI Shell 1.0
    #menuentry "UEFI Shell \${_UEFI_ARCH} v1" {
    #    search --fs-uuid --no-floppy --set=root ${UEFISYS_PART_HINTS_STRING} ${UEFISYS_PART_FS_UUID}
    #    chainloader /EFI/tools/shell\${_SPEC_UEFI_ARCH}_v1.efi
    #}

fi

EOF

    NUMBER=$((NUMBER+1))

    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

if [ "\${grub_platform}" == "efi" ]; then
    if [ "\${grub_cpu}" == "x86_64" ]; then
        ## Microsoft Windows 10/11 via x86_64 UEFI
        #menuentry \"Microsoft Windows 10/11 x86_64 UEFI-GPT\" {
        #    insmod part_gpt
        #    insmod fat
        #    insmod search_fs_uuid
        #    insmod chain
        #    search --fs-uuid --no-floppy --set=root ${UEFISYS_PART_HINTS_STRING} ${UEFISYS_PART_FS_UUID}
        #    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        #}
    fi
fi

EOF

    NUMBER=$((NUMBER+1))

    ## TODO: Detect actual Windows installation if any
    ## create example file for windows
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

if [ "\${grub_platform}" == "pc" ]; then

    ## Microsoft Windows 10/11 BIOS
    #menuentry \"Microsoft Windows 10/11 BIOS-MBR\" {
    #    insmod part_msdos
    #    insmod ntfs
    #    insmod search_fs_uuid
    #    insmod ntldr
    #    search --fs-uuid --no-floppy --set=root <FS_UUID of Windows SYSTEM Partition>
    #    ntldr /bootmgr
    #}

fi

EOF

fi
    ## copy unicode.pf2 font file
    cp -f "${DESTDIR}/usr/share/grub/unicode.pf2" "${DESTDIR}/${GRUB_PREFIX_DIR}/fonts/unicode.pf2"

    chroot_umount

    ## Edit grub.cfg config file
    DIALOG --msgbox "You must now review the grub(2) configuration file.\n\nYou will now be put into the editor.\nAfter you save your changes, exit the editor." 8 50
    geteditor || return 1
    "${EDITOR}" "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

    unset BOOT_PART_FS_UUID
    unset BOOT_PART_FS
    unset BOOT_PART_FS_LABEL
    unset BOOT_PART_DRIVE

    unset ROOT_PART_FS_UUID
    unset ROOT_PART_FS

    unset GRUB_ROOT_DRIVE
    unset LINUX_UNMOD_COMMAND
    unset LINUX_MOD_COMMAND

}

do_grub_bios() {

    do_grub_common_before

    # try to auto-configure GRUB(2)...
    if [[ "${PART_ROOT}" != "" ]]; then
        check_bootpart

        # check if raid, raid partition, dmraid or device devicemapper is used
        if echo "${bootdev}" | grep -q /dev/md || echo "${bootdev}" | grep /dev/mapper; then
            # boot from lvm, raid, partitioned raid and dmraid devices is supported
            FAIL_COMPLEX="0"

            if cryptsetup status "${bootdev}"; then
                # encryption devices are not supported
                FAIL_COMPLEX="1"
            fi
        fi

        if [[ "${FAIL_COMPLEX}" == "0" ]]; then
            # check if mapper is used
            if  echo "${bootdev}" | grep -q /dev/mapper; then
                RAID_ON_LVM="0"

                #check if mapper contains a md device!
                for devpath in $(pvs -o pv_name --noheading); do
                    if echo "${devpath}" | grep -v "/dev/md.p" | grep /dev/md; then
                        detectedvolumegroup="$(pvs -o vg_name --noheading "${devpath}")"

                        if echo /dev/mapper/"${detectedvolumegroup}"-* | grep "${bootdev}"; then
                            # change bootdev to md device!
                            bootdev=$(pvs -o pv_name --noheading "${devpath}")
                            RAID_ON_LVM="1"
                            break
                        fi
                    fi
                done
            fi

            #check if raid is used
            USE_RAID=""
            if echo "${bootdev}" | grep -q /dev/md; then
                USE_RAID="1"
            fi
        fi
    fi


    # A switch is needed if complex ${bootdev} is used!
    # - LVM and RAID ${bootdev} needs the MBR of a device and cannot be used itself as ${bootdev}
    if [[ "${FAIL_COMPLEX}" == "0" ]]; then
        DEVS="$(findbootloaderdisks _)"

        if [[ "${DEVS}" == "" ]]; then
            DIALOG --msgbox "No storage drives were found" 0 0
            return 1
        fi
        #shellcheck disable=SC2086
        DIALOG --menu "Select the boot device where the GRUB(2) bootloader will be installed." 14 55 7 ${DEVS} 2>"${ANSWER}" || return 1
        bootdev=$(cat "${ANSWER}")
    else
        DEVS="$(findbootloaderdisks _)"

        ## grub BIOS install to partition is not supported
        # DEVS="${DEVS} $(findbootloaderpartitions _)"

        if [[ "${DEVS}" == "" ]]; then
            DIALOG --msgbox "No storage drives were found" 0 0
            return 1
        fi
        #shellcheck disable=SC2086
        DIALOG --menu "Select the boot device where the GRUB(2) bootloader will be installed." 14 55 7 ${DEVS} 2>"${ANSWER}" || return 1
        bootdev=$(cat "${ANSWER}")
    fi

    if [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${bootdev}")" == "gpt" ]]; then
        CHECK_BIOS_BOOT_GRUB="1"
        CHECK_UEFISYS_PART=""
        RUN_CFDISK=""
        DISC="${bootdev}"
        check_gpt
    else
        if [[ "${FAIL_COMPLEX}" == "0" ]]; then
            DIALOG --defaultno --yesno "Warning:\nSetup detected no GUID (gpt) partition table.\n\nGrub(2) has only space for approx. 30k core.img file. Depending on your setup, it might not fit into this gap and fail.\n\nDo you really want to install grub(2) to a msdos partition table?" 0 0 || return 1
        fi
    fi

    if [[ "${FAIL_COMPLEX}" == "1" ]]; then
        DIALOG --msgbox "Error:\ngrub(2) cannot boot from ${bootdev}, which contains /boot!\n\nPossible error sources:\n- encrypted devices are not supported" 0 0
        return 1
    fi

    DIALOG --infobox "Installing grub(2) BIOS. This needs some time..." 3 55
    # freeze and unfreeze xfs filesystems to enable grub(2) installation on xfs filesystems
    freeze_xfs
    chroot_mount

    chroot "${DESTDIR}" "/usr/bin/grub-install" \
        --directory="/usr/lib/grub/i386-pc" \
        --target="i386-pc" \
        --boot-directory="/boot" \
        --recheck \
        --debug \
        "${bootdev}" &>"/tmp/grub_bios_install.log"

    chroot_umount

    mkdir -p "${DESTDIR}/boot/grub/locale"
    cp -f "${DESTDIR}/usr/share/locale/en@quot/LC_MESSAGES/grub.mo" "${DESTDIR}/boot/grub/locale/en.mo"

    if [[ -e "${DESTDIR}/boot/grub/i386-pc/core.img" ]]; then
        DIALOG --infobox "grub(2) BIOS has been successfully installed.\n\nContinuing in 3 seconds..." 6 40
        sleep 3

        GRUB_PREFIX_DIR="/boot/grub/"
        do_grub_config
    else
        DIALOG --msgbox "Error installing grub(2) bios.\nCheck /tmp/grub_bios_install.log for more info.\n\nYou probably need to install it manually by chrooting into ${DESTDIR}.\nDon't forget to bind mount /dev and /proc into ${DESTDIR} before chrooting." 0 0
        return 1
    fi

}

do_grub_uefi() {

    do_uefi_common

    [[ "${_UEFI_ARCH}" == "X64" ]] && _GRUB_ARCH="x86_64"
    [[ "${_UEFI_ARCH}" == "IA32" ]] && _GRUB_ARCH="i386"
    [[ "${_UEFI_ARCH}" == "AA64" ]] && _GRUB_ARCH="arm64"

    do_grub_common_before
    DIALOG --infobox "Setting up grub UEFI. This needs some time..." 3 55
    chroot_mount
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        # install fedora shim
        [[ ! -d  ${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT ]] && mkdir -p "${DESTDIR}"/"${UEFISYS_MOUNTPOINT}"/EFI/BOOT/
        cp -f /usr/share/archboot/bootloader/shim${_SPEC_UEFI_ARCH}.efi "${DESTDIR}"/"${UEFISYS_MOUNTPOINT}"/EFI/BOOT/BOOT${_UEFI_ARCH}.efi
        cp -f /usr/share/archboot/bootloader/mm${_SPEC_UEFI_ARCH}.efi "${DESTDIR}"/"${UEFISYS_MOUNTPOINT}"/EFI/BOOT/
        GRUB_PREFIX_DIR="${UEFISYS_MOUNTPOINT}/EFI/BOOT/"
    else
        ## Install GRUB
        chroot "${DESTDIR}" "/usr/bin/grub-install" \
            --directory="/usr/lib/grub/${_GRUB_ARCH}-efi" \
            --target="${_GRUB_ARCH}-efi" \
            --efi-directory="${UEFISYS_MOUNTPOINT}" \
            --bootloader-id="grub" \
            --boot-directory="/boot" \
            --no-nvram \
            --recheck \
            --debug &> "/tmp/grub_uefi_${_UEFI_ARCH}_install.log"
        cat "/tmp/grub_uefi_${_UEFI_ARCH}_install.log" >> "${LOG}"
        GRUB_PREFIX_DIR="/boot/grub/"
    fi
    chroot_umount
    GRUB_UEFI="1"
    do_grub_config
    GRUB_UEFI=""
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        # generate GRUB with config embeded
        #remove existing, else weird things are happening
        [[ -f "${DESTDIR}/${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" ]] && rm "${DESTDIR}"/${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi
        ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
        # add -v for verbose
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
                systemd-nspawn -q -D "${DESTDIR}" grub-mkstandalone -d /usr/lib/grub/${_GRUB_ARCH}-efi -O ${_GRUB_ARCH}-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd chain tpm" --fonts="unicode" --locales="en@quot" --themes="" -o "${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg=/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
            else
                systemd-nspawn -q -D "${DESTDIR}" grub-mkstandalone -d /usr/lib/grub/${_GRUB_ARCH}-efi -O ${_GRUB_ARCH}-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efi_uga efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd backtrace chain tpm usb usbserial_common usbserial_pl2303 usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard" --fonts="unicode" --locales="en@quot" --themes="" -o "${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg=/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
            fi
        cp /${GRUB_PREFIX_DIR}/${GRUB_CFG} "${UEFISYS_MOUNTPOINT}"/EFI/BOOT/grub${_SPEC_UEFI_ARCH}.cfg
    fi
    if [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi" ]] && [[ -e "${DESTDIR}/boot/grub/${_GRUB_ARCH}-efi/core.efi" ]]; then
        _BOOTMGR_LABEL="GRUB"
        _BOOTMGR_LOADER_DIR="/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi"
        do_uefi_bootmgr_setup

        DIALOG --infobox "GRUB(2) for ${_UEFI_ARCH} UEFI has been installed successfully.\n\nContinuing in 3 seconds..." 6 40
        sleep 3

        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            _UEFISYS_EFI_BOOT_DIR="1"
        else
            DIALOG --defaultno --yesno "Do you want to copy?\n\n${UEFISYS_MOUNTPOINT}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi --> ${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi\n\nThis might be needed in some systems,\nwhere efibootmgr may not work due to firmware issues." 10 70 && _UEFISYS_EFI_BOOT_DIR="1"
        fi

        if [[ "${_UEFISYS_EFI_BOOT_DIR}" == "1" ]]; then
            mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT"
            rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi" || true
            cp -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi"
        fi
    elif [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/grub${_SPEC_UEFI_ARCH}.efi" ]]; then
        do_secureboot_keys
        do_mok_sign
        do_pacman_sign
        do_uefi_secure_boot_efitools
        _BOOTMGR_LABEL="SHIM with GRUB Secure Boot"
        _BOOTMGR_LOADER_DIR="/EFI/BOOT/BOOT${_UEFI_ARCH}.efi"
        do_uefi_bootmgr_setup
        DIALOG --infobox "SHIM and GRUB Secure Boot for ${_UEFI_ARCH} UEFI\nhas been installed successfully.\n\nContinuing in 3 seconds..." 6 60
        sleep 3
    else
        DIALOG --msgbox "Error installing grub(2) for ${_UEFI_ARCH} UEFI.\nCheck /tmp/grub_uefi_${_UEFI_ARCH}_install.log for more info.\n\nYou probably need to install it manually by chrooting into ${DESTDIR}.\nDon't forget to bind mount /dev, /sys and /proc into ${DESTDIR} before chrooting." 0 0
        return 1

    fi
}

install_bootloader_uefi() {

    do_uefi_setup_env_vars

    if [[ "${_EFI_MIXED}" == "1" ]]; then
        _EFISTUB_MENU_LABEL=""
        _EFISTUB_MENU_TEXT=""
    else
        _EFISTUB_MENU_LABEL="EFISTUB"
        _EFISTUB_MENU_TEXT="EFISTUB for ${_UEFI_ARCH} UEFI"
    fi
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        do_grub_uefi
    else
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
        DIALOG --menu "Which ${_UEFI_ARCH} UEFI bootloader would you like to use?" 12 55 5 \
            "${_EFISTUB_MENU_LABEL}" "${_EFISTUB_MENU_TEXT}" \
            "GRUB_UEFI" "GRUB(2) for ${_UEFI_ARCH} UEFI" 2>"${ANSWER}" || CANCEL=1
        else
            DIALOG --menu "Which ${_UEFI_ARCH} UEFI bootloader would you like to use?" 12 55 5 \
                "${_EFISTUB_MENU_LABEL}" "${_EFISTUB_MENU_TEXT}" \
                "GRUB_UEFI" "GRUB(2) for ${_UEFI_ARCH} UEFI" 2>"${ANSWER}" || CANCEL=1
        fi
        case $(cat "${ANSWER}") in
            "EFISTUB") do_efistub_uefi ;;
            "GRUB_UEFI") do_grub_uefi ;;
        esac
    fi

}

install_bootloader_bios() {

    DIALOG --menu "Which BIOS bootloader would you like to use?" 11 50 4 \
        "GRUB_BIOS" "GRUB(2) BIOS" 2>"${ANSWER}" || CANCEL=1
    case $(cat "${ANSWER}") in
        "GRUB_BIOS") do_grub_bios ;;
    esac

}

install_bootloader() {
    destdir_mounts || return 1
    if [[ "${NAME_SCHEME_PARAMETER_RUN}" == "" ]]; then
        set_device_name_scheme || return 1
    fi
    if [[ "${S_SRC}" = "0" ]]; then
        select_source || return 1
    fi
    prepare_pacman
    CANCEL=""
    detect_uefi_boot
    _ANOTHER="1"
    NEXTITEM="7"
    if [[ "${_DETECTED_UEFI_BOOT}" == "1" ]]; then
        do_uefi_setup_env_vars
         _ANOTHER="0"
        if [[ "${_DETECTED_UEFI_SECURE_BOOT}" ==  "1" ]]; then
            DIALOG --yesno "Setup has detected that you are using Secure Boot.\nDo you like to install SHIM and GRUB ${_UEFI_ARCH} UEFI bootloader?" 0 0 || CANCEL="1"
            if [[ "${CANCEL}" == "" ]]; then
                install_bootloader_uefi
                NEXTITEM="8"
            else
                NEXTITEM="7"
            fi
        else
            DIALOG --yesno "Setup has detected that you are using ${_UEFI_ARCH} UEFI.\nDo you like to install a ${_UEFI_ARCH} UEFI bootloader?" 0 0 && install_bootloader_uefi
            DIALOG --defaultno --yesno "Do you want to install another bootloader?" 5 50 && _ANOTHER="1"
            NEXTITEM="8"
        fi
    fi
    while [[ "${_ANOTHER}" == "1" ]]; do
        install_bootloader_menu
        _ANOTHER="0"
        DIALOG --defaultno --yesno "Do you want to install another bootloader?" 5 50 && _ANOTHER="1"
    done
}
