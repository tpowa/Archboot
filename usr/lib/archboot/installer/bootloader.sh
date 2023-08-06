#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
if [[ "${_RUNNING_ARCH}" == "x86_64" ]] && grep -q 'Intel' /proc/cpuinfo; then
    _UCODE="intel-ucode.img"
    _UCODE_PKG="intel-ucode"
fi
if [[ "${_RUNNING_ARCH}" == "aarch64" || "${_RUNNING_ARCH}" == "x86_64" ]]; then
    if grep -q 'AMD' /proc/cpuinfo; then
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
    if [[ -f "${_DESTDIR}/etc/mdadm.conf" ]] && ! grep -q '^ARRAY' "${_DESTDIR}"/etc/mdadm.conf 2>"${_NO_LOG}"; then
        _RAIDARRAYS="$(echo -n "$(grep ^md /proc/mdstat 2>"${_NO_LOG}" | sed -e 's#\[[0-9]\]##g' -e 's# :.* raid[0-9]##g' -e 's#md#md=#g' -e 's# #,/dev/#g' -e 's#_##g')")"
    fi
}

_getcryptsetup() {
    _LUKSSETUP=""
    if ! cryptsetup status "$(basename "${_ROOTDEV}")" | grep -q inactive; then
        if cryptsetup status "$(basename "${_ROOTDEV}")" 2>"${_NO_LOG}"; then
            if [[ "${_NAME_SCHEME_PARAMETER}" == "FSUUID" ]]; then
                _LUKSDEV="UUID=$(${_LSBLK} UUID "$(cryptsetup status "$(basename "${_ROOTDEV}")" 2>"${_NO_LOG}" | grep device: | sed -e 's#device:##g')" 2>"${_NO_LOG}")"
            elif [[ "${_NAME_SCHEME_PARAMETER}" == "FSLABEL" ]]; then
                _LUKSDEV="LABEL=$(${_LSBLK} LABEL "$(cryptsetup status "$(basename "${_ROOTDEV}")" 2>"${_NO_LOG}" | grep device: | sed -e 's#device:##g')" 2>"${_NO_LOG}")"
            else
                _LUKSDEV="$(cryptsetup status "$(basename "${_ROOTDEV}")" 2>"${_NO_LOG}" | grep device: | sed -e 's#device:##g'))"
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

# freeze and unfreeze xfs, as hack for grub(2) installing
_freeze_xfs() {
    sync
    if [[ -x /usr/bin/xfs_freeze ]]; then
        if grep "${_DESTDIR}/boot " /proc/mounts | grep -q " xfs "; then
            xfs_freeze -f "${_DESTDIR}"/boot &>"${_NO_LOG}"
            xfs_freeze -u "${_DESTDIR}"/boot &>"${_NO_LOG}"
        fi
        if grep "${_DESTDIR} " /proc/mounts | grep -q " xfs "; then
            xfs_freeze -f "${_DESTDIR}" &>"${_NO_LOG}"
            xfs_freeze -u "${_DESTDIR}" &>"${_NO_LOG}"
        fi
    fi
}

## Setup kernel cmdline parameters to be added to bootloader configs
_bootloader_kernel_parameters() {
    if [[ -n "${_UEFI_BOOT}" ]]; then
        [[ "${_NAME_SCHEME_PARAMETER}" == "PARTUUID" ]] && _getrootpartuuid
        [[ "${_NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]] && _getrootpartlabel
    fi
    [[ "${_NAME_SCHEME_PARAMETER}" == "FSUUID" ]] && _getrootfsuuid
    [[ "${_NAME_SCHEME_PARAMETER}" == "FSLABEL" ]] && _getrootfslabel
    _KERNEL_PARAMS_COMMON_UNMOD="root=${_ROOTDEV} rootfstype=${_ROOTFS} rw ${_ROOTFLAGS} ${_RAIDARRAYS} ${_LUKSSETUP}"
    _KERNEL_PARAMS_MOD="$(echo "${_KERNEL_PARAMS_COMMON_UNMOD}" | sed -e 's#   # #g' | sed -e 's#  # #g')"
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
    _BOOTDEV="$(mount | grep "${_DESTDIR}/boot " | cut -d' ' -f 1)"
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

_abort_nilfs_bootpart() {
        if ${_LSBLK} FSTYPE "${_BOOTDEV}" 2>"${_NO_LOG}" | grep -q "nilfs2"; then
            _dialog --title " ERROR " --no-mouse --infobox "Error:\nYour selected bootloader cannot boot from nilfs2 partition with /boot on it." 0 0
            return 1
        fi
}

_abort_f2fs_bootpart() {
        if  ${_LSBLK} FSTYPE "${_BOOTDEV}" 2>"${_NO_LOG}" | grep -q "f2fs"; then
            _dialog --title " ERROR " --no-mouse --infobox "Your selected bootloader cannot boot from f2fs partition with /boot on it." 0 0
            return 1
        fi
}

_do_uefi_common() {
    _PACKAGES=""
    _DEV=""
    _BOOTDEV=""
    [[ -f "${_DESTDIR}/usr/bin/mkfs.vfat" ]] || _PACKAGES="${_PACKAGES} dosfstools"
    [[ -f "${_DESTDIR}/usr/bin/efivar" ]] || _PACKAGES="${_PACKAGES} efivar"
    [[ -f "${_DESTDIR}/usr/bin/efibootmgr" ]] || _PACKAGES="${_PACKAGES} efibootmgr"
    if [[ -n "${_UEFI_SECURE_BOOT}" ]]; then
        [[ -f "${_DESTDIR}/usr/bin/mokutil" ]] || _PACKAGES="${_PACKAGES} mokutil"
        [[ -f "${_DESTDIR}/usr/bin/efi-readvar" ]] || _PACKAGES="${_PACKAGES} efitools"
        [[ -f "${_DESTDIR}/usr/bin/sbsign" ]] || _PACKAGES="${_PACKAGES} sbsigntools"
    fi
    if [[ -n "${_PACKAGES}" ]]; then
        _run_pacman | _dialog --title " Logging to ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 8 75 0
        _pacman_error
    fi
    # automounted /boot and ESP needs to be mounted first, trigger mount with ls
    ls "${_DESTDIR}/boot" &>"${_NO_LOG}"
    ls "${_DESTDIR}/efi" &>"${_NO_LOG}"
    _BOOTDEV="$(${_FINDMNT} "${_DESTDIR}/boot" | grep -vw 'systemd-1')"
    if mountpoint -q "${_DESTDIR}/efi" ; then
        _UEFISYS_MP=efi
    else
        _UEFISYS_MP=boot
    fi
    _UEFISYSDEV="$(${_FINDMNT} "${_DESTDIR}/${_UEFISYS_MP}" | grep -vw 'systemd-1')"
    _UEFISYSDEV_FS_UUID="$(_getfsuuid "${_UEFISYSDEV}")"
}

_do_uefi_efibootmgr() {
    for _bootnum in $(efibootmgr | grep '^Boot[0-9]' | grep -F -i "${_BOOTMGR_LABEL}" | cut -b5-8) ; do
        efibootmgr --quiet -b "${_bootnum}" -B >> "${_LOG}"
    done
    _BOOTMGRDEV=$(${_LSBLK} PKNAME "${_UEFISYSDEV}" 2>"${_NO_LOG}")
    _BOOTMGRNUM=$(echo "${_UEFISYSDEV}" | sed -e "s#${_BOOTMGRDEV}##g" | sed -e 's#p##g')
    efibootmgr --quiet --create --disk "${_BOOTMGRDEV}" --part "${_BOOTMGRNUM}" --loader "${_BOOTMGR_LOADER_PATH}" --label "${_BOOTMGR_LABEL}" >> "${_LOG}"
}

_do_apple_efi_hfs_bless() {
    ## Grub upstream bzr mactel branch => http://bzr.savannah.gnu.org/lh/grub/branches/mactel/changes
    ## Fedora's mactel-boot => https://bugzilla.redhat.com/show_bug.cgi?id=755093
    _dialog --msgbox "TODO: Apple Mac EFI Bootloader Setup" 0 0
}

_do_uefi_bootmgr_setup() {
    if [[ "$(cat "/sys/class/dmi/id/sys_vendor")" == 'Apple Inc.' ]] || [[ "$(cat "/sys/class/dmi/id/sys_vendor")" == 'Apple Computer, Inc.' ]]; then
        _do_apple_efi_hfs_bless
    else
        _do_uefi_efibootmgr
    fi
}

_do_uefi_secure_boot_efitools() {
    _do_uefi_common || return 1
    # install helper tools and create entries in UEFI boot manager, if not present
    if [[ -n "${_UEFI_SECURE_BOOT}" ]]; then
        [[ -d "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT" ]] || mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT"
        if [[ ! -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/HashTool.efi" ]]; then
            cp "${_DESTDIR}/usr/share/efitools/efi/HashTool.efi" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/HashTool.efi"
            _BOOTMGR_LABEL="HashTool (Secure Boot)"
            _BOOTMGR_LOADER_PATH="/EFI/BOOT/HashTool.efi"
            _do_uefi_bootmgr_setup
        fi
        if [[ ! -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/KeyTool.efi" ]]; then
            cp "${_DESTDIR}/usr/share/efitools/efi/KeyTool.efi" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/KeyTool.efi"
            _BOOTMGR_LABEL="KeyTool (Secure Boot)"
            _BOOTMGR_LOADER_PATH="/EFI/BOOT/KeyTool.efi"
            _do_uefi_bootmgr_setup
        fi
    fi
}

_do_secureboot_keys() {
    _CN=""
    _MOK_PW=""
    _KEYDIR=""
    while [[ -z "${_KEYDIR}" ]]; do
        _dialog --title " Setup Keys " --no-cancel --inputbox "Enter the directory to store the keys on ${_DESTDIR}." 8 65 "/etc/secureboot/keys" 2>"${_ANSWER}" || return 1
        _KEYDIR=$(cat "${_ANSWER}")
        #shellcheck disable=SC2086,SC2001
        _KEYDIR="$(echo ${_KEYDIR} | sed -e 's#^/##g')"
    done
    if [[ ! -d "${_DESTDIR}/${_KEYDIR}" ]]; then
        while [[ -z "${_CN}" ]]; do
            _dialog --title " Setup Keys " --no-cancel --inputbox "Enter a common name(CN) for your keys, eg. Your Name" 8 65 "" 2>"${_ANSWER}" || return 1
            _CN=$(cat "${_ANSWER}")
        done
        secureboot-keys.sh -name="${_CN}" "${_DESTDIR}/${_KEYDIR}" &>"${_LOG}" || return 1
         _dialog --title " Setup Keys " --no-mouse --infobox "Common name(CN) ${_CN}\nused for your keys in ${_DESTDIR}/${_KEYDIR}" 4 60
         sleep 3
    else
         _dialog --title " Setup Keys " --no-mouse --infobox "-Directory ${_DESTDIR}/${_KEYDIR} exists\n-assuming keys are already created\n-trying to use existing keys now" 5 50
         sleep 3
    fi
}

_do_mok_sign () {
    _UEFI_BOOTLOADER_DIR="${_UEFISYS_MP}/EFI/BOOT"
    _INSTALL_MOK=""
    _MOK_PW=""
    while [[ -z "${_MOK_PW}" ]]; do
        _dialog --title " Machine Owner Key Password " --insecure --passwordbox "On reboot you will be asked for this password by mokmanager:" 8 65 2>"${_ANSWER}" || return 1
        _PASS=$(cat "${_ANSWER}")
        _dialog --title " Retype Machine Owner Key Password " --insecure --passwordbox "On reboot you will be asked for this password by mokmanager:" 8 65 2>"${_ANSWER}" || return 1
        _PASS2=$(cat "${_ANSWER}")
        if [[ "${_PASS}" == "${_PASS2}" && -n "${_PASS}" ]]; then
            _MOK_PW=${_PASS}
            echo "${_MOK_PW}" > /tmp/.password
            echo "${_MOK_PW}" >> /tmp/.password
            _MOK_PW=/tmp/.password
        else
            _dialog --title " ERROR " --no-mouse --infobox "Password didn't match or was empty, please enter again." 6 65
            sleep 3
        fi
    done
    mokutil -i "${_DESTDIR}"/"${_KEYDIR}"/MOK/MOK.cer < ${_MOK_PW} >"${_LOG}"
    rm /tmp/.password
    _dialog --title " Machine Owner Key " --no-mouse --infobox "Machine Owner Key has been installed successfully." 3 50
    sleep 3
    ${_NSPAWN} sbsign --key /"${_KEYDIR}"/MOK/MOK.key --cert /"${_KEYDIR}"/MOK/MOK.crt --output /boot/"${_VMLINUZ}" /boot/"${_VMLINUZ}" &>"${_LOG}"
    ${_NSPAWN} sbsign --key /"${_KEYDIR}"/MOK/MOK.key --cert /"${_KEYDIR}"/MOK/MOK.crt --output "${_UEFI_BOOTLOADER_DIR}"/grub"${_SPEC_UEFI_ARCH}".efi "${_UEFI_BOOTLOADER_DIR}"/grub"${_SPEC_UEFI_ARCH}".efi &>"${_LOG}"
    _dialog --title " Kernel And Bootloader Signing " --no-mouse --infobox "/boot/${_VMLINUZ} and ${_UEFI_BOOTLOADER_DIR}/grub${_SPEC_UEFI_ARCH}.efi\n\nhave been signed successfully." 5 60
    sleep 3
}

_do_pacman_sign() {
    [[ -d "${_DESTDIR}/etc/pacman.d/hooks" ]] || mkdir -p  "${_DESTDIR}"/etc/pacman.d/hooks
    _HOOKNAME="${_DESTDIR}/etc/pacman.d/hooks/999-sign_kernel_for_secureboot.hook"
    cat << EOF > "${_HOOKNAME}"
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux

[Action]
Description = Signing kernel with Machine Owner Key for Secure Boot
When = PostTransaction
Exec = /usr/bin/find /boot/ -maxdepth 1 -name 'vmlinuz-*' -exec /usr/bin/sh -c 'if ! /usr/bin/sbverify --list {} 2>"${_NO_LOG}" | /usr/bin/grep -q "signature certificates"; then /usr/bin/sbsign --key /${_KEYDIR}/MOK/MOK.key --cert /${_KEYDIR}/MOK/MOK.crt --output {} {}; fi' ;
Depends = sbsigntools
Depends = findutils
Depends = grep
EOF
    _dialog --title " Automatic Signing " --no-mouse --infobox "Pacman hook for automatic signing has been installed successfully:\n\n${_HOOKNAME}" 5 70
    sleep 3
}

_do_efistub_parameters() {
    _FAIL_COMPLEX=""
    _RAID_ON_LVM=""
    _UEFISYS_PATH="EFI/archlinux"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _VMLINUZ="${_VMLINUZ_EFISTUB}"
    if [[ "${_UEFISYS_MP}" == "boot" ]]; then
        _KERNEL="${_VMLINUZ}"
        if [[ -n "${_UCODE}" ]]; then
            _INITRD_UCODE="${_UCODE}"
        fi
        _INITRD="${_INITRAMFS}"
    else
        _KERNEL="${_UEFISYS_PATH}/${_VMLINUZ}"
        if [[ -n "${_UCODE}" ]]; then
            _INITRD_UCODE="${_UEFISYS_PATH}/${_UCODE}"
        fi
        _INITRD="${_UEFISYS_PATH}/${_INITRAMFS}"
    fi
}

_do_efistub_copy_to_efisys() {
    if ! [[ "${_UEFISYS_MP}" == "boot" ]]; then
        # clean and copy to efisys
        _dialog --no-mouse --infobox "Copying kernel, ucode and initramfs\nto EFI SYSTEM PARTITION (ESP) now..." 4 65
        [[ -d "${_DESTDIR}/${_UEFISYS_MP}/${_UEFISYS_PATH}" ]] || mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/${_UEFISYS_PATH}"
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/${_KERNEL}"
        cp -f "${_DESTDIR}/boot/${_VMLINUZ}" "${_DESTDIR}/${_UEFISYS_MP}/${_KERNEL}"
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/${_INITRD}"
        cp -f "${_DESTDIR}/boot/${_INITRAMFS}" "${_DESTDIR}/${_UEFISYS_MP}/${_INITRD}"
        if [[ -n "${_INITRD_UCODE}" ]]; then
            rm -f "${_DESTDIR}/${_UEFISYS_MP}/${_INITRD_UCODE}"
            cp -f "${_DESTDIR}/boot/${_UCODE}" "${_DESTDIR}/${_UEFISYS_MP}/${_INITRD_UCODE}"
        fi
        sleep 5
        _dialog --no-mouse --infobox "Enable automatic copying of system files\nto EFI SYSTEM PARTITION (ESP) on installed system..." 4 65
        cat << CONFEOF > "${_DESTDIR}/etc/systemd/system/efistub_copy.path"
[Unit]
Description=Copy EFISTUB Kernel and Initramfs files to EFI SYSTEM PARTITION
[Path]
PathChanged=/boot/${_VMLINUZ}
PathChanged=/boot/${_INITRAMFS}
CONFEOF
        if [[ -n "${_UCODE}" ]]; then
            echo "PathChanged=/boot/${_UCODE}" >> "${_DESTDIR}/etc/systemd/system/efistub_copy.path"
        fi
        cat << CONFEOF >> "${_DESTDIR}/etc/systemd/system/efistub_copy.path"
Unit=efistub_copy.service
[Install]
WantedBy=multi-user.target
CONFEOF
        cat << CONFEOF > "${_DESTDIR}/etc/systemd/system/efistub_copy.service"
[Unit]
Description=Copy EFISTUB Kernel and Initramfs files to EFI SYSTEM PARTITION
[Service]
Type=oneshot
ExecStart=/usr/bin/cp -f /boot/${_VMLINUZ} /${_UEFISYS_MP}/${_KERNEL}
ExecStart=/usr/bin/cp -f /boot/${_INITRAMFS} /${_UEFISYS_MP}/${_INITRD}
CONFEOF
        if [[ -n "${_INITRD_UCODE}" ]]; then
            echo "ExecStart=/usr/bin/cp -f /boot/${_UCODE} /${_UEFISYS_MP}/${_INITRD_UCODE}" \
            >> "${_DESTDIR}/etc/systemd/system/efistub_copy.service"
        fi
        ${_NSPAWN} systemctl enable efistub_copy.path &>"${_NO_LOG}"
        sleep 2
    fi
    # reset _VMLINUZ on aarch64
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        _VMLINUZ="Image.gz"
    fi
}

_do_efistub_uefi() {
    _do_uefi_common || return 1
    _do_efistub_parameters
    _common_bootloader_checks
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        _ADDITIONAL_BOOTLOADER="rEFInd"
        _ADDITIONAL_BOOTLOADER_DESC="rEFInd for ${_UEFI_ARCH} UEFI"
    fi
    _dialog --title " EFISTUB Menu " --menu "" 9 60 3 \
        "FIRMWARE" "Unified Kernel Image for ${_UEFI_ARCH} UEFI" \
        "SYSTEMD-BOOT" "SYSTEMD-BOOT for ${_UEFI_ARCH} UEFI" \
        "${_ADDITIONAL_BOOTLOADER}" "${_ADDITIONAL_BOOTLOADER_DESC}" 2>"${_ANSWER}"
    case $(cat "${_ANSWER}") in
        "FIRMWARE") _do_uki_uefi;;
        "SYSTEMD-BOOT") _do_systemd_boot_uefi ;;
        "rEFInd") _do_refind_uefi ;;
    esac
}

_do_systemd_boot_uefi() {
    _dialog --no-mouse --infobox "Setting up SYSTEMD-BOOT now..." 3 40
    # create directory structure, if it doesn't exist
    [[ -d "${_DESTDIR}/${_UEFISYS_MP}/loader/entries" ]] || mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/loader/entries"
    echo "title    Arch Linux" > "${_DESTDIR}/${_UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
    echo "linux    /${_KERNEL}" >> "${_DESTDIR}/${_UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
    if [[ -n "${_INITRD_UCODE}" ]]; then
        echo "initrd   /${_INITRD_UCODE}" >> "${_DESTDIR}/${_UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
    fi
    cat << GUMEOF >> "${_DESTDIR}/${_UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
initrd   /${_INITRD}
options  ${_KERNEL_PARAMS_MOD}
GUMEOF
    cat << GUMEOF > "${_DESTDIR}/${_UEFISYS_MP}/loader/loader.conf"
timeout 5
default archlinux-core-main
GUMEOF
    _chroot_mount
    chroot "${_DESTDIR}" bootctl --path="/${_UEFISYS_MP}" install &>"${_LOG}"
    chroot "${_DESTDIR}" bootctl --path="/${_UEFISYS_MP}" update &>"${_LOG}"
    _chroot_umount
    if [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi" ]]; then
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        cp -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi"  \
              "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        _BOOTMGR_LABEL="SYSTEMD-BOOT"
        _BOOTMGR_LOADER_PATH="/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi"
        _do_uefi_bootmgr_setup
        _dialog --msgbox "You will now be put into the editor to edit:\nloader.conf and menu entry files\n\nAfter you save your changes, exit the editor." 8 50
        _geteditor || return 1
        "${_EDITOR}" "${_DESTDIR}/${_UEFISYS_MP}/loader/entries/archlinux-core-main.conf"
        "${_EDITOR}" "${_DESTDIR}/${_UEFISYS_MP}/loader/loader.conf"
        _do_efistub_copy_to_efisys
        _dialog --no-mouse --infobox "SYSTEMD-BOOT has been setup successfully." 3 50
        sleep 3
        _S_BOOTLOADER=1
    else
        _dialog --msgbox "Error installing SYSTEMD-BOOT." 0 0
    fi
}

_do_refind_uefi() {
    if [[ ! -f "${_DESTDIR}/usr/bin/refind-install" ]]; then
        _PACKAGES="refind"
        _run_pacman | _dialog --title " Logging to ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 8 75 0
        _pacman_error
    fi
    _dialog --no-mouse --infobox "Setting up rEFInd now. This needs some time..." 3 60
    [[ -d "${_DESTDIR}/${_UEFISYS_MP}/EFI/refind" ]] || mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/refind/"
    cp -f "${_DESTDIR}/usr/share/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${_DESTDIR}/${_UEFISYS_MP}/EFI/refind/"
    cp -r "${_DESTDIR}/usr/share/refind/icons" "${_DESTDIR}/${_UEFISYS_MP}/EFI/refind/"
    cp -r "${_DESTDIR}/usr/share/refind/fonts" "${_DESTDIR}/${_UEFISYS_MP}/EFI/refind/"
    cp -r "${_DESTDIR}/usr/share/refind/drivers_${_SPEC_UEFI_ARCH}" "${_DESTDIR}/${_UEFISYS_MP}/EFI/refind/"
    _REFIND_CONFIG="${_DESTDIR}/${_UEFISYS_MP}/EFI/refind/refind.conf"
    cat << CONFEOF > "${_REFIND_CONFIG}"
timeout 20
use_nvram false
resolution 1024 768
scanfor manual,internal,external,optical,firmware
menuentry "Arch Linux" {
    icon     /EFI/refind/icons/os_arch.png
    loader   /${_KERNEL}
CONFEOF
    if [[ -n "${_INITRD_UCODE}" ]]; then
        echo "    initrd   /${_INITRD_UCODE}" >> "${_REFIND_CONFIG}"
    fi
    cat << CONFEOF >> "${_REFIND_CONFIG}"
    initrd   /${_INITRD}
    options  "${_KERNEL_PARAMS_MOD}"
}
CONFEOF
    if [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" ]]; then
        _BOOTMGR_LABEL="rEFInd"
        _BOOTMGR_LOADER_PATH="/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi"
        _do_uefi_bootmgr_setup
        mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT"
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        cp -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        _dialog --msgbox "You will now be put into the editor to edit:\nrefind.conf\n\nAfter you save your changes, exit the editor." 8 50
        _geteditor || return 1
        "${_EDITOR}" "${_REFIND_CONFIG}"
        cp -f "${_REFIND_CONFIG}" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/"
        _do_efistub_copy_to_efisys
        _dialog --no-mouse --infobox "rEFInd has been setup successfully." 3 50
        sleep 3
        _S_BOOTLOADER=1
    else
        _dialog --msgbox "Error setting up rEFInd." 3 40
    fi
}

_do_uki_uefi() {
    if [[ ! -f "${_DESTDIR}/usr/lib/systemd/ukify" ]]; then
        _PACKAGES="systemd-ukify"
        _run_pacman | _dialog --title " Logging to ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 8 75 0
        _pacman_error
    fi
    _UKIFY_CONFIG="${_DESTDIR}/etc/ukify.conf"
    _CMDLINE="${_DESTDIR}/etc/kernel/cmdline"
    echo "${_KERNEL_PARAMS_MOD}" > "${_CMDLINE}"
    echo "KERNEL=/boot/${_VMLINUZ}" > "${_UKIFY_CONFIG}"
    if [[ -n ${_UCODE} ]]; then
        echo "UCODE=/boot/${_UCODE}" >> "${_UKIFY_CONFIG}"
    fi
    cat << CONFEOF >> "${_UKIFY_CONFIG}"
INITRD=/boot/${_INITRAMFS}
CMDLINE=/etc/kernel/cmdline
SPLASH=/usr/share/systemd/bootctl/splash-arch.bmp
EFI=/${_UEFISYS_MP}/EFI/Linux/archlinux-linux.efi
CONFEOF
    echo "/usr/lib/systemd/ukify \${KERNEL} \${UCODE} \${INITRD} --cmdline @\${CMDLINE} --splash \${SPLASH} --output \${EFI}" >> "${_UKIFY_CONFIG}"
    mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/Linux"
    _geteditor || return 1
    "${_EDITOR}" "${_CMDLINE}"
    "${_EDITOR}" "${_UKIFY_CONFIG}"

    _dialog --no-mouse --infobox "Setting up Unified Kernel Image ..." 3 60
    ${_NSPAWN} /usr/bin/bash -c "source /etc/ukify.conf" >>"${_LOG}"
    sleep 2
    if [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/Linux/archlinux-linux.efi" ]]; then
        _dialog --no-mouse --infobox "Enable automatic UKI creation\non EFI SYSTEM PARTITION (ESP) on installed system..." 4 60
        cat << CONFEOF > "${_DESTDIR}/etc/systemd/system/run_ukify.path"
[Unit]
Description=Run systemd ukify
[Path]
PathChanged=/boot/${_INITRAMFS}
PathChanged=/boot/${_UCODE}
Unit=run_ukify.service
[Install]
WantedBy=multi-user.target
CONFEOF
        cat << CONFEOF > "${_DESTDIR}/etc/systemd/system/run_ukify.service"
[Unit]
Description=Run systemd ukify
[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c "source /etc/ukify.conf"
CONFEOF
        ${_NSPAWN} systemctl enable run_ukify.path &>"${_NO_LOG}"
        sleep 3
        _BOOTMGR_LABEL="Arch Linux - Unified Kernel Image"
        _BOOTMGR_LOADER_PATH="/EFI/Linux/archlinux-linux.efi"
        _do_uefi_bootmgr_setup
        mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT"
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        cp -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/Linux/archlinux-linux.efi" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        _dialog --no-mouse --infobox "Unified Kernel Image has been setup successfully." 3 60
        sleep 3
        _S_BOOTLOADER=1
    else
        _dialog --title " ERROR " --no-mouse --infobox "Setting up Unified Kernel Image failed!" 3 60
        sleep 5
    fi
}

_do_grub_common_before() {
    ##### Check whether the below limitations still continue with ver 2.00~beta4
    ### Grub(2) restrictions:
    ## - Encryption is not recommended for grub(2) /boot!
    _BOOTDEV=""
    _FAIL_COMPLEX=""
    _RAID_ON_LVM=""
    _common_bootloader_checks
    _abort_f2fs_bootpart || return 1
    if [[ ! -d "${_DESTDIR}/usr/lib/grub" ]]; then
        _PACKAGES="grub"
        _run_pacman | _dialog --title " Logging to ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 8 75 0
        _pacman_error
    fi
    if [[ ! -f "${_DESTDIR}/usr/share/grub/ter-u16n.pf2" ]]; then
        _PACKAGES=terminus-font
        _run_pacman | _dialog --title " Logging to ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 8 75 0
        _pacman_error
    fi
}

_do_grub_config() {
    _chroot_mount
    _GRUB_PROBE="chroot ${_DESTDIR} grub-probe"
    _BOOTDEV_FS_UUID="$(${_GRUB_PROBE} --target="fs_uuid" "/boot" 2>"${_NO_LOG}")"
    _BOOTDEV_FS_LABEL="$(${_GRUB_PROBE} --target="fs_label" "/boot" 2>"${_NO_LOG}")"
    _BOOTDEV_HINTS_STRING="$(${_GRUB_PROBE} --target="hints_string" "/boot" 2>"${_NO_LOG}")"
    _BOOTDEV_FS="$(${_GRUB_PROBE} --target="fs" "/boot" 2>"${_NO_LOG}")"
    _BOOTDEV_DRIVE="$(${_GRUB_PROBE} --target="drive" "/boot" 2>"${_NO_LOG}")"
    _ROOTDEV_FS_UUID="$(${_GRUB_PROBE} --target="fs_uuid" "/" 2>"${_NO_LOG}")"
    _ROOTDEV_HINTS_STRING="$(${_GRUB_PROBE} --target="hints_string" "/" 2>"${_NO_LOG}")"
    _ROOTDEV_FS="$(${_GRUB_PROBE} --target="fs" "/" 2>"${_NO_LOG}")"
    _USRDEV_FS_UUID="$(${_GRUB_PROBE} --target="fs_uuid" "/usr" 2>"${_NO_LOG}")"
    _USRDEV_HINTS_STRING="$(${_GRUB_PROBE} --target="hints_string" "/usr" 2>"${_NO_LOG}")"
    _USRDEV_FS="$(${_GRUB_PROBE} --target="fs" "/usr" 2>"${_NO_LOG}")"
    if [[ -n "${_GRUB_UEFI}" ]]; then
        _UEFISYSDEV_FS_UUID="$(${_GRUB_PROBE} --target="fs_uuid" "/${_UEFISYS_MP}" 2>"${_NO_LOG}")"
        _UEFISYSDEV_HINTS_STRING="$(${_GRUB_PROBE} --target="hints_string" "/${_UEFISYS_MP}" 2>"${_NO_LOG}")"
    fi
    _chroot_umount
    if [[ "${_ROOTDEV_FS_UUID}" == "${_BOOTDEV_FS_UUID}" ]]; then
        _SUBDIR="/boot"
        # on btrfs we need to check on subvol
        if mount | grep "${_DESTDIR} " | grep btrfs | grep -q subvol; then
            _SUBDIR="/$(btrfs subvolume show "${_DESTDIR}/" | grep Name | cut -c 11-60)"/boot
        fi
        if mount | grep "${_DESTDIR}/boot " | grep btrfs | grep -q subvol; then
            _SUBDIR="/$(btrfs subvolume show "${_DESTDIR}/boot" | grep Name | cut -c 11-60)"
        fi
    else
        _SUBDIR=""
        # on btrfs we need to check on subvol
        if mount | grep "${_DESTDIR}/boot " | grep btrfs | grep -q subvol; then
            _SUBDIR="/$(btrfs subvolume show "${_DESTDIR}/boot" | grep Name | cut -c 11-60)"
        fi
    fi
    if [[ -n "${_UCODE}" ]]; then
        _INITRD_UCODE="${_SUBDIR}/${_UCODE}"
    fi
    ## Move old config file, if any
    if [[ -n "${_UEFI_SECURE_BOOT}" ]]; then
        _GRUB_CFG="grub${_SPEC_UEFI_ARCH}.cfg"
    else
        _GRUB_CFG="grub.cfg"
    fi
    [[ -f "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}" ]] && (mv "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}" "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}.bak" || true)
    ## Ignore if the insmod entries are repeated - there are possibilities of having /boot in one disk and root-fs in altogether different disk
    ## with totally different configuration.
    cat << EOF > "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
# Include modules - required for boot
insmod part_gpt
insmod part_msdos
insmod fat
insmod ${_BOOTDEV_FS}
insmod ${_ROOTDEV_FS}
insmod ${_USRDEV_FS}
insmod search_fs_file
insmod search_fs_uuid
insmod search_label
insmod linux
insmod chain
set pager=1
# set debug="all"
set locale_dir="\${prefix}/locale"
EOF
    [[ -n "${_USE_RAID}" ]] && echo "insmod raid" >> "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
    [[ -n "${_RAID_ON_LVM}" ]] && echo "insmod lvm" >> "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
    #shellcheck disable=SC2129
    cat << EOF >> "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
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
search --fs-uuid --no-floppy --set=usr_part ${_USRDEV_HINTS_STRING} ${_USRDEV_FS_UUID}
search --fs-uuid --no-floppy --set=root_part ${_ROOTDEV_HINTS_STRING} ${_ROOTDEV_FS_UUID}
if [ -e "\${prefix}/fonts/ter-u16n.pf2" ]; then
    set _fontfile="\${prefix}/fonts/ter-u16n.pf2"
else
    if [ -e "(\${root_part})/usr/share/grub/ter-u16n.pf2" ]; then
        set _fontfile="(\${root_part})/usr/share/grub/ter-u16n.pf2"
    else
        if [ -e "(\${usr_part})/share/grub/ter-u16n.pf2" ]; then
            set _fontfile="(\${usr_part})/share/grub/ter-u16n.pf2"
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
    [[ -e "/tmp/.device-names" ]] && sort "/tmp/.device-names" >> "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
    if [[ "${_NAME_SCHEME_PARAMETER}" == "PARTUUID" ]] || [[ "${_NAME_SCHEME_PARAMETER}" == "FSUUID" ]] ; then
        _GRUB_ROOT_DRIVE="search --fs-uuid --no-floppy --set=root ${_BOOTDEV_HINTS_STRING} ${_BOOTDEV_FS_UUID}"
    else
        if [[ "${_NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]] || [[ "${_NAME_SCHEME_PARAMETER}" == "FSLABEL" ]] ; then
            _GRUB_ROOT_DRIVE="search --label --no-floppy --set=root ${_BOOTDEV_HINTS_STRING} ${_BOOTDEV_FS_LABEL}"
        else
            _GRUB_ROOT_DRIVE="set root=${_BOOTDEV_DRIVE}"
        fi
    fi
    if [[ -n "${_GRUB_UEFI}" ]]; then
        _LINUX_UNMOD_COMMAND="linux ${_SUBDIR}/${_VMLINUZ} ${_KERNEL_PARAMS_MOD}"
    else
        _LINUX_UNMOD_COMMAND="linux ${_SUBDIR}/${_VMLINUZ} ${_KERNEL_PARAMS_MOD}"
    fi
    _LINUX_MOD_COMMAND=$(echo "${_LINUX_UNMOD_COMMAND}" | sed -e 's#   # #g' | sed -e 's#  # #g')
    ## create default kernel entry
    _NUMBER=0
    cat << EOF >> "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
# (${_NUMBER}) Arch Linux
menuentry "Arch Linux" {
    set gfxpayload="keep"
    ${_GRUB_ROOT_DRIVE}
    ${_LINUX_MOD_COMMAND}
    initrd ${_INITRD_UCODE} ${_SUBDIR}/${_INITRAMFS}
}
EOF
    _NUMBER=$((_NUMBER+1))
if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
    if [[ -n "${_UEFI_BOOT}" ]]; then
        _NUMBER=$((_NUMBER+1))
        cat << EOF >> "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
if [ "\${grub_platform}" == "efi" ]; then
    if [ "\${grub_cpu}" == "x86_64" ]; then
        ## (${_NUMBER}) Microsoft Windows 10/11 via x86_64 UEFI
        #menuentry Microsoft Windows 10/11 x86_64 UEFI-GPT {
        #    insmod part_gpt
        #    insmod fat
        #    insmod search_fs_uuid
        #    insmod chain
        #    search --fs-uuid --no-floppy --set=root ${_UEFISYSDEV_HINTS_STRING} ${_UEFISYSDEV_FS_UUID}
        #    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        #}
    fi
fi
EOF
    else
        _NUMBER=$((_NUMBER+1))
        ## TODO: Detect actual Windows installation if any
        ## create example file for windows
        cat << EOF >> "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
if [ "\${grub_platform}" == "pc" ]; then
    ## (${_NUMBER}) Microsoft Windows 10/11 BIOS
    #menuentry Microsoft Windows 10/11 BIOS-MBR {
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
fi
    ## copy ter-u16n.pf2 font file
    [[ -d ${_DESTDIR}/${_GRUB_PREFIX_DIR}/fonts ]] || mkdir -p "${_DESTDIR}/${_GRUB_PREFIX_DIR}/fonts"
    cp -f "${_DESTDIR}/usr/share/grub/ter-u16n.pf2" "${_DESTDIR}/${_GRUB_PREFIX_DIR}/fonts/ter-u16n.pf2"
    ## Edit grub.cfg config file
    _dialog --msgbox "You must now review the GRUB(2) configuration file.\n\nYou will now be put into the editor.\nAfter you save your changes, exit the editor." 8 55
    _geteditor || return 1
    "${_EDITOR}" "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
}

_do_uboot() {
    _common_bootloader_checks
    _check_bootpart
    _abort_uboot
    [[ -d "${_DESTDIR}/boot/extlinux" ]] || mkdir -p "${_DESTDIR}/boot/extlinux"
    _KERNEL_PARAMS_COMMON_UNMOD="root=${_ROOTDEV} rootfstype=${_ROOTFS} rw ${_ROOTFLAGS} ${_RAIDARRAYS} ${_LUKSSETUP}"
    _KERNEL_PARAMS_COMMON_MOD="$(echo "${_KERNEL_PARAMS_COMMON_UNMOD}" | sed -e 's#   # #g' | sed -e 's#  # #g')"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _TITLE="ARM 64"
    [[ "${_RUNNING_ARCH}" == "riscv64" ]] && _TITLE="RISC-V 64"
    # write extlinux.conf
    _dialog --no-mouse --infobox "Installing UBOOT..." 0 0
    cat << EOF >> "${_DESTDIR}/boot/extlinux/extlinux.conf"
menu title Welcome Arch Linux ${_TITLE}
timeout 100
default linux
label linux
    menu label Boot System (automatic boot in 10 seconds...)
    kernel ${_SUBDIR}/${_VMLINUZ}
    initrd ${_SUBDIR}/${_INITRAMFS}
    append ${_KERNEL_PARAMS_COMMON_MOD}
EOF
    _dialog --no-mouse --infobox "UBOOT has been installed successfully." 3 55
    sleep 3
}

_grub_install_bios() {
    # freeze and unfreeze xfs filesystems to enable grub(2) installation on xfs filesystems
    _freeze_xfs
    _chroot_mount
    chroot "${_DESTDIR}" grub-install \
        --directory="/usr/lib/grub/i386-pc" \
        --target="i386-pc" \
        --boot-directory="/boot" \
        --recheck \
        --debug \
        "${_BOOTDEV}" &>"/tmp/grub_bios_install.log"
    cat "/tmp/grub_bios_install.log" >>"${_LOG}"
    _chroot_umount
    rm /.archboot
}

_grub_bios() {
    touch /.archboot
    _grub_install_bios &
    _progress_wait "11" "99" "Setting up GRUB(2) BIOS..." "0.15"
    _progress "100" "Setting up GRUB(2) BIOS completed."
    sleep 2
}

_do_grub_bios() {
    _do_grub_common_before
    # try to auto-configure GRUB(2)...
    _check_bootpart
    # check if raid, raid partition, or device devicemapper is used
    if echo "${_BOOTDEV}" | grep -q /dev/md || echo "${_BOOTDEV}" | grep -q /dev/mapper; then
        # boot from lvm, raid, partitioned and raid devices is supported
        _FAIL_COMPLEX=""
        if cryptsetup status "${_BOOTDEV}"; then
            # encryption devices are not supported
            _FAIL_COMPLEX=1
        fi
    fi
    if [[ -z "${_FAIL_COMPLEX}" ]]; then
        # check if mapper is used
        if  echo "${_BOOTDEV}" | grep -q /dev/mapper; then
            _RAID_ON_LVM=""
            #check if mapper contains a md device!
            for devpath in $(pvs -o pv_name --noheading); do
                if echo "${devpath}" | grep -v "/dev/md.p" | grep -q /dev/md; then
                    _DETECTEDVOLUMEGROUP="$(pvs -o vg_name --noheading "${devpath}")"
                    if echo /dev/mapper/"${_DETECTEDVOLUMEGROUP}"-* | grep -q "${_BOOTDEV}"; then
                        # change _BOOTDEV to md device!
                        _BOOTDEV=$(pvs -o pv_name --noheading "${devpath}")
                        _RAID_ON_LVM=1
                        break
                    fi
                fi
            done
        fi
        #check if raid is used
        _USE_RAID=""
        if echo "${_BOOTDEV}" | grep -q /dev/md; then
            _USE_RAID=1
        fi
    fi
    # A switch is needed if complex ${_BOOTDEV} is used!
    # - LVM and RAID ${_BOOTDEV} needs the MBR of a device and cannot be used itself as ${_BOOTDEV}
    # -  grub BIOS install to partition is not supported
    _DEVS="$(_findbootloaderdisks _)"
    if [[ -z "${_DEVS}" ]]; then
        _dialog --msgbox "No storage drives were found" 0 0
        return 1
    fi
    #shellcheck disable=SC2086
    _dialog --title " Grub Boot Device " --no-cancel --menu "" 14 55 7 ${_DEVS} 2>"${_ANSWER}" || return 1
    _BOOTDEV=$(cat "${_ANSWER}")
    if [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${_BOOTDEV}")" == "gpt" ]]; then
        _CHECK_BIOS_BOOT_GRUB=1
        _RUN_CFDISK=""
        _DISK="${_BOOTDEV}"
        _check_gpt
    else
        if [[ -z "${_FAIL_COMPLEX}" ]]; then
            _dialog --defaultno --yesno "Warning:\nSetup detected no GUID (gpt) partition table.\n\nGrub(2) has only space for approx. 30k core.img file. Depending on your setup, it might not fit into this gap and fail.\n\nDo you really want to install GRUB(2) to a msdos partition table?" 0 0 || return 1
        fi
    fi
    if [[ -n "${_FAIL_COMPLEX}" ]]; then
        _dialog --msgbox "Error:\nGRUB(2) cannot boot from ${_BOOTDEV}, which contains /boot!\n\nPossible error sources:\n- encrypted devices are not supported" 0 0
        return 1
    fi
    _grub_bios | _dialog --title " Logging to ${_LOG} " --gauge "Setting up GRUB(2) BIOS..." 6 75 0
    mkdir -p "${_DESTDIR}/boot/grub/locale"
    cp -f "${_DESTDIR}/usr/share/locale/en@quot/LC_MESSAGES/grub.mo" "${_DESTDIR}/boot/grub/locale/en.mo"
    if [[ -e "${_DESTDIR}/boot/grub/i386-pc/core.img" ]]; then
        _GRUB_PREFIX_DIR="/boot/grub/"
        _do_grub_config || return 1
        _dialog --title " Success " --no-mouse --infobox "GRUB(2) BIOS has been installed successfully." 3 55
        sleep 3
        _S_BOOTLOADER=1
    else
        _dialog --msgbox "Error installing GRUB(2) BIOS.\nCheck /tmp/grub_bios_install.log for more info.\n\nYou probably need to install it manually by chrooting into ${_DESTDIR}.\nDon't forget to bind mount /dev and /proc into ${_DESTDIR} before chrooting." 0 0
        return 1
    fi
}

_grub_install_uefi() {
    chroot "${_DESTDIR}" grub-install \
        --directory="/usr/lib/grub/${_GRUB_ARCH}-efi" \
        --target="${_GRUB_ARCH}-efi" \
        --efi-directory="/${_UEFISYS_MP}" \
        --bootloader-id="grub" \
        --boot-directory="/boot" \
        --no-nvram \
        --recheck \
        --debug &> "/tmp/grub_uefi_${_UEFI_ARCH}_install.log"
    cat "/tmp/grub_uefi_${_UEFI_ARCH}_install.log" >>"${_LOG}"
    rm /.archboot
}

_grub_install_uefi_sb() {
    ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
    # add -v for verbose
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        ${_NSPAWN} grub-mkstandalone -d /usr/lib/grub/"${_GRUB_ARCH}"-efi -O "${_GRUB_ARCH}"-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd chain tpm" --fonts="ter-u16n" --locales="en@quot" --themes="" -o "${_GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg=/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
    elif [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        ### In case grub will be broken!
        #_dialog --no-mouse --infobox "Pacman is running...\n\nInstalling grub-2:2.06.r533.g78bc9a9b2-1 to ${_DESTDIR}...\n\nCheck ${_VC} console (ALT-F${_VC_NUM}) for progress..." 8 70
        # fix broken grub with last working version:
        # https://lists.gnu.org/archive/html/grub-devel/2023-06/msg00121.html
        #if [[ -e "${_LOCAL_DB}" ]]; then
        #    cp "/var/cache/pacman/pkg/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst" "${_DESTDIR}"
        #    cp "/var/cache/pacman/pkg/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst.sig" "${_DESTDIR}"
        #else
        #    ${_DLPROG} "https://archboot.com/src/grub/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst" -P "${_DESTDIR}"
        #    ${_DLPROG} "https://archboot.com/src/grub/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst.sig" -P "${_DESTDIR}"
        #fi
        #${_NSPAWN} pacman -U --noconfirm /grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst >>"${_LOG}"
        #rm "${_DESTDIR}/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst"
        #rm "${_DESTDIR}/grub-2:2.06.r533.g78bc9a9b2-1-x86_64.pkg.tar.zst.sig"
        #_dialog --no-mouse --infobox "grub-2:2.06.r533.g78bc9a9b2-1 has been installed successfully.\nContinuing in 5 seconds..." 4 70
        #sleep 5
        ${_NSPAWN} grub-mkstandalone -d /usr/lib/grub/"${_GRUB_ARCH}"-efi -O "${_GRUB_ARCH}"-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efi_uga efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd backtrace chain tpm usb usbserial_common usbserial_pl2303 usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard" --fonts="ter-u16n" --locales="en@quot" --themes="" -o "${_GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg=/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
    fi
    rm /.archboot
}

_setup_grub_uefi() {
    if [[ -n "${_UEFI_SECURE_BOOT}" ]]; then
        _progress "50" "Installing fedora's shim and mokmanager..."
        sleep 2
        # install fedora shim
        [[ -d  ${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT ]] || mkdir -p "${_DESTDIR}"/"${_UEFISYS_MP}"/EFI/BOOT
        cp -f /usr/share/archboot/bootloader/shim"${_SPEC_UEFI_ARCH}".efi "${_DESTDIR}"/"${_UEFISYS_MP}"/EFI/BOOT/BOOT"${_UEFI_ARCH}".EFI
        cp -f /usr/share/archboot/bootloader/mm"${_SPEC_UEFI_ARCH}".efi "${_DESTDIR}"/"${_UEFISYS_MP}"/EFI/BOOT/
        _progress "100" "Installing fedora's shim and mokmanager completed."
        sleep 2
    else
        ## Install GRUB
        _GRUB_PREFIX_DIR="/boot/grub/"
        _progress "10" "Setting up GRUB(2) UEFI..."
        _chroot_mount
        touch /.archboot
        _grub_install_uefi &
        _progress_wait "11" "99" "Setting up GRUB(2) UEFI..." "0.1"
        _chroot_umount
        _progress "100" "Setting up GRUB(2) UEFI completed."
        sleep 2
    fi
    _GRUB_UEFI=1
}

_setup_grub_uefi_sb() {
    if [[ -n "${_UEFI_SECURE_BOOT}" ]]; then
        _GRUB_PREFIX_DIR="${_UEFISYS_MP}/EFI/BOOT/"
        _progress "10" "Setting up GRUB(2) UEFI Secure Boot..."
        # generate GRUB with config embeded
        #remove existing, else weird things are happening
        [[ -f "${_DESTDIR}/${_GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" ]] && rm "${_DESTDIR}"/"${_GRUB_PREFIX_DIR}"/grub"${_SPEC_UEFI_ARCH}".efi
        touch /.archboot
        _grub_install_uefi_sb &
        _progress_wait "11" "99" "Setting up GRUB(2) UEFI Secure Boot..." "0.1"
        _progress "100" "Setting up GRUB(2) UEFI Secure Boot completed."
        sleep 2
    fi
}

_do_grub_uefi() {
    _GRUB_UEFI=""
    _do_uefi_common || return 1
    [[ "${_UEFI_ARCH}" == "X64" ]] && _GRUB_ARCH="x86_64"
    [[ "${_UEFI_ARCH}" == "IA32" ]] && _GRUB_ARCH="i386"
    [[ "${_UEFI_ARCH}" == "AA64" ]] && _GRUB_ARCH="arm64"
    _do_grub_common_before
    _setup_grub_uefi | _dialog --title " Logging to ${_LOG} " --gauge "Setting up GRUB(2) UEFI..." 6 75 0
    _do_grub_config || return 1
    _setup_grub_uefi_sb | _dialog --title " Logging to ${_LOG} " --gauge "Setting up GRUB(2) UEFI Secure Boot..." 6 75 0
    if [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi" && -z "${_UEFI_SECURE_BOOT}" && -e "${_DESTDIR}/boot/grub/${_GRUB_ARCH}-efi/core.efi" ]]; then
        _BOOTMGR_LABEL="GRUB"
        _BOOTMGR_LOADER_PATH="/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi"
        _do_uefi_bootmgr_setup
        mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT"
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        cp -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        _dialog --title " Success " --no-mouse --infobox "GRUB(2) for ${_UEFI_ARCH} UEFI has been installed successfully." 3 60
        sleep 3
        _S_BOOTLOADER=1
    elif [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/grub${_SPEC_UEFI_ARCH}.efi" && -n "${_UEFI_SECURE_BOOT}" ]]; then
        _do_secureboot_keys || return 1
        _do_mok_sign
        _do_pacman_sign
        _do_uefi_secure_boot_efitools
        _BOOTMGR_LABEL="SHIM with GRUB Secure Boot"
        _BOOTMGR_LOADER_PATH="/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        _do_uefi_bootmgr_setup
        _dialog --title " Success " --no-mouse --infobox "SHIM and GRUB(2) Secure Boot for ${_UEFI_ARCH} has been installed successfully." 3 75
        sleep 3
        _S_BOOTLOADER=1
    else
        _dialog --msgbox "Error installing GRUB(2) for ${_UEFI_ARCH} UEFI.\nCheck /tmp/grub_uefi_${_UEFI_ARCH}_install.log for more info.\n\nYou probably need to install it manually by chrooting into ${_DESTDIR}.\nDon't forget to bind mount /dev, /sys and /proc into ${_DESTDIR} before chrooting." 0 0
        return 1
    fi
}

_install_bootloader_uefi() {
    if [[ -n "${_EFI_MIXED}" ]]; then
        _EFISTUB_MENU_LABEL=""
        _EFISTUB_MENU_TEXT=""
    else
        _EFISTUB_MENU_LABEL="EFISTUB"
        _EFISTUB_MENU_TEXT="EFISTUB for ${_UEFI_ARCH} UEFI"
    fi
    # aarch64 is broken for UKI and systemd-boot
    # https://github.com/systemd/systemd/issues/27837
    # https://sourceforge.net/p/gnu-efi/bugs/37/
    if [[ -n "${_UEFI_SECURE_BOOT}" ]]; then
        _do_grub_uefi
    else
        _dialog --title " ${_UEFI_ARCH} UEFI Bootloader " --menu "" 8 40 2 \
            "${_EFISTUB_MENU_LABEL}" "${_EFISTUB_MENU_TEXT}" \
            "GRUB_UEFI" "GRUB(2) for ${_UEFI_ARCH} UEFI" 2>"${_ANSWER}"
        case $(cat "${_ANSWER}") in
            "EFISTUB")
                        _do_efistub_uefi ;;
            "GRUB_UEFI")
                        _do_grub_uefi ;;
        esac
    fi
}

_install_bootloader() {
    _S_BOOTLOADER=""
    _destdir_mounts || return 1
    # switch for mbr usage
    if [[ -z "${_NAME_SCHEME_PARAMETER_RUN}" ]]; then
        _set_guid
        _set_device_name_scheme || return 1
    fi
    if [[ -n "${_UCODE}" ]]; then
        if ! [[ -f "${_DESTDIR}/boot/${_UCODE}" ]]; then
            _PACKAGES="${_UCODE_PKG}"
            _run_pacman | _dialog --title " Logging to ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 8 75 0
            _pacman_error
        fi
    fi
    if [[ -n "${_UEFI_BOOT}" ]]; then
        _install_bootloader_uefi
    else
        if [[ "${_RUNNING_ARCH}" == "aarch64" || "${_RUNNING_ARCH}" == "riscv64" ]]; then
            _do_uboot
        else
            _do_grub_bios
        fi
    fi
    if [[ -z "${_S_BOOTLOADER}" ]]; then
        _NEXTITEM="4"
    else
        _NEXTITEM="5"
    fi
}
# vim: set ft=sh ts=4 sw=4 et:
