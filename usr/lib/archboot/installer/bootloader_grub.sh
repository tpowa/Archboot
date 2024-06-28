#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
# freeze and unfreeze xfs, as hack for grub(2) installing
_freeze_xfs() {
    sync
    if [[ -x /usr/bin/xfs_freeze ]]; then
        if mount | rg -q "${_DESTDIR}/boot type xfs"; then
            xfs_freeze -f "${_DESTDIR}"/boot &>"${_NO_LOG}"
            xfs_freeze -u "${_DESTDIR}"/boot &>"${_NO_LOG}"
        fi
        if mount | rg -q "${_DESTDIR} type xfs"; then
            xfs_freeze -f "${_DESTDIR}" &>"${_NO_LOG}"
            xfs_freeze -u "${_DESTDIR}" &>"${_NO_LOG}"
        fi
    fi
}

_grub_common_before() {
    ##### Check whether the below limitations still continue with ver 2.00~beta4
    ### Grub(2) restrictions:
    ## - Encryption is not recommended for grub(2) /boot!
    _BOOTDEV=""
    _FAIL_COMPLEX=""
    _RAID_ON_LVM=""
    _common_bootloader_checks
    _abort_bcachefs_bootpart || return 1
    if [[ ! -d "${_DESTDIR}/usr/lib/grub" ]]; then
        _PACKAGES="grub"
        _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
        _pacman_error
    fi
    if [[ ! -f "${_DESTDIR}/usr/share/grub/ter-u16n.pf2" ]]; then
        _PACKAGES=terminus-font
        _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
        _pacman_error
    fi
}

_grub_config() {
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
        if mount | rg -q "${_DESTDIR} type btrfs .*subvol"; then
            _SUBDIR="/$(btrfs subvolume show "${_DESTDIR}/" | rg -o 'Name: +\t+(.*)' -r '$1')"/boot
        fi
        if mount | rg -q "${_DESTDIR}/boot type btrfs .*subvol"; then
            _SUBDIR="/$(btrfs subvolume show "${_DESTDIR}/boot" | rg -o 'Name: +\t+(.*)' -r '$1')"
        fi
    else
        _SUBDIR=""
        # on btrfs we need to check on subvol
        if mount | rg -q "${_DESTDIR}/boot type btrfs .*subvol"; then
            _SUBDIR="/$(btrfs subvolume show "${_DESTDIR}/boot" | rg -o 'Name: +\t+(.*)' -r '$1')"
        fi
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
if [ "\${grub_platform}" == "efi" ]; then
    insmod all_video
    insmod efi_gop
    if [ "\${grub_cpu}" == "x86_64" ]; then
        insmod bli
        insmod efi_uga
    elif [ "\${grub_cpu}" == "i386" ]; then
        insmod bli
        insmod efi_uga
    fi
elif [ "\${grub_platform}" == "pc" ]; then
    insmod vbe
    insmod vga
    insmod png
fi
insmod video_bochs
insmod video_cirrus
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
    if [[ "${_NAME_SCHEME_PARAMETER}" == "PARTUUID" ||\
        "${_NAME_SCHEME_PARAMETER}" == "FSUUID" ||\
        "${_NAME_SCHEME_PARAMETER}" == "SD_GPT_AUTO_GENERATOR" ]] ; then
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
    initrd ${_SUBDIR}/${_INITRAMFS}

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
    cat << EOF >> "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
if [ "\${grub_platform}" == "efi" ]; then
    menuentry "UEFI Firmware Setup" {
        fwsetup
        }
fi
EOF
cat << EOF >> "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
menuentry "Reboot System" {
    reboot
}
menuentry "Poweroff System" {
    halt
}
EOF
    ## copy ter-u16n.pf2 font file
    [[ -d ${_DESTDIR}/${_GRUB_PREFIX_DIR}/fonts ]] || mkdir -p "${_DESTDIR}/${_GRUB_PREFIX_DIR}/fonts"
    cp -f "${_DESTDIR}/usr/share/grub/ter-u16n.pf2" "${_DESTDIR}/${_GRUB_PREFIX_DIR}/fonts/ter-u16n.pf2"
    ## Edit grub.cfg config file
    _dialog --msgbox "You must now review the GRUB(2) configuration file.\n\nYou will now be put into the editor.\nAfter you save your changes, exit the editor." 8 55
    _geteditor || return 1
    "${_EDITOR}" "${_DESTDIR}/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
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
        "${_BOOTDEV}" &>"/tmp/grub_bios_install.log"
    cat "/tmp/grub_bios_install.log" >>"${_LOG}"
    _chroot_umount
    rm /.archboot
}

_setup_grub_bios() {
    : > /.archboot
    _grub_install_bios &
    _progress_wait "11" "99" "Setting up GRUB(2) BIOS..." "0.15"
    _progress "100" "Setting up GRUB(2) BIOS completed."
    sleep 2
}

_grub_bios() {
    _grub_common_before
    # try to auto-configure GRUB(2)...
    _check_bootpart
    # check if raid, raid partition, or device devicemapper is used
    if echo "${_BOOTDEV}" | rg -q '/dev/md|/dev/mapper'; then
        # boot from lvm, raid, partitioned and raid devices is supported
        _FAIL_COMPLEX=""
        if cryptsetup status "${_BOOTDEV}"; then
            # encryption devices are not supported
            _FAIL_COMPLEX=1
        fi
    fi
    if [[ -z "${_FAIL_COMPLEX}" ]]; then
        # check if mapper is used
        if  echo "${_BOOTDEV}" | rg -q '/dev/mapper'; then
            _RAID_ON_LVM=""
            #check if mapper contains a md device!
            for devpath in $(pvs -o pv_name --noheading); do
                if echo "${devpath}" | rg -v "/dev/md.p" | rg -q '/dev/md'; then
                    _DETECTEDVOLUMEGROUP="$(pvs -o vg_name --noheading "${devpath}")"
                    if echo /dev/mapper/"${_DETECTEDVOLUMEGROUP}"-* | rg -q "${_BOOTDEV}"; then
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
        if echo "${_BOOTDEV}" | rg -q '/dev/md'; then
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
    if [[ "$(${_LSBLK} PTTYPE -d "${_BOOTDEV}")" == "gpt" ]]; then
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
    _setup_grub_bios | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Setting up GRUB(2) BIOS..." 6 75 0
    mkdir -p "${_DESTDIR}/boot/grub/locale"
    cp -f "${_DESTDIR}/usr/share/locale/en@quot/LC_MESSAGES/grub.mo" "${_DESTDIR}/boot/grub/locale/en.mo"
    if [[ -e "${_DESTDIR}/boot/grub/i386-pc/core.img" ]]; then
        _GRUB_PREFIX_DIR="/boot/grub"
        _grub_config || return 1
        _pacman_hook_grub_bios
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
        --bootloader-id="GRUB" \
        --recheck \
        --debug &> "/tmp/grub_uefi_${_UEFI_ARCH}_install.log"
    cat "/tmp/grub_uefi_${_UEFI_ARCH}_install.log" >>"${_LOG}"
    rm /.archboot
}

_grub_install_uefi_sb() {
    ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
    if [[ "${_RUNNING_ARCH}" == "aarch64" || "${_RUNNING_ARCH}" == "x86_64" ]]; then
        ${_NSPAWN} grub-mkstandalone -d /usr/lib/grub/"${_GRUB_ARCH}"-efi -O "${_GRUB_ARCH}"-efi --sbat=/usr/share/grub/sbat.csv --fonts="ter-u16n" --locales="en@quot" --themes="" -o "/${_GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg=/${_GRUB_PREFIX_DIR}/${_GRUB_CFG}"
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
        _progress "10" "Setting up GRUB(2) UEFI..."
        _chroot_mount
        : > /.archboot
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
        _progress "10" "Setting up GRUB(2) UEFI Secure Boot..."
        # generate GRUB with config embeded
        #remove existing, else weird things are happening
        [[ -f "${_DESTDIR}/${_GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" ]] && rm "${_DESTDIR}"/"${_GRUB_PREFIX_DIR}"/grub"${_SPEC_UEFI_ARCH}".efi
        : > /.archboot
        _grub_install_uefi_sb &
        _progress_wait "11" "99" "Setting up GRUB(2) UEFI Secure Boot..." "0.1"
        _progress "100" "Setting up GRUB(2) UEFI Secure Boot completed."
        sleep 2
    fi
}

_grub_uefi() {
    _GRUB_UEFI=""
    _uefi_common || return 1
    [[ "${_UEFI_ARCH}" == "X64" ]] && _GRUB_ARCH="x86_64"
    [[ "${_UEFI_ARCH}" == "IA32" ]] && _GRUB_ARCH="i386"
    [[ "${_UEFI_ARCH}" == "AA64" ]] && _GRUB_ARCH="arm64"
    if [[ -n "${_UEFI_SECURE_BOOT}" ]]; then
        _GRUB_PREFIX_DIR="${_UEFISYS_MP}/EFI/BOOT"
    else
        _GRUB_PREFIX_DIR="boot/grub"
    fi
    _grub_common_before
    _setup_grub_uefi | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Setting up GRUB(2) UEFI..." 6 75 0
    _grub_config || return 1
    _setup_grub_uefi_sb | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Setting up GRUB(2) UEFI Secure Boot..." 6 75 0
    if [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi" && -z "${_UEFI_SECURE_BOOT}" && -e "${_DESTDIR}/boot/grub/${_GRUB_ARCH}-efi/core.efi" ]]; then
        _pacman_hook_grub_uefi
        mkdir -p "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT"
        rm -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        cp -f "${_DESTDIR}/${_UEFISYS_MP}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi" "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        _dialog --title " Success " --no-mouse --infobox "GRUB(2) for ${_UEFI_ARCH} UEFI has been installed successfully." 3 60
        sleep 3
        _S_BOOTLOADER=1
    elif [[ -e "${_DESTDIR}/${_UEFISYS_MP}/EFI/BOOT/grub${_SPEC_UEFI_ARCH}.efi" && -n "${_UEFI_SECURE_BOOT}" ]]; then
        _secureboot_keys || return 1
        _mok_sign
        _pacman_sign
        _pacman_hook_grub_sb
        _BOOTMGR_LABEL="SHIM with GRUB Secure Boot"
        _BOOTMGR_LOADER_PATH="/EFI/BOOT/BOOT${_UEFI_ARCH}.EFI"
        _uefi_bootmgr_setup
        _dialog --title " Success " --no-mouse --infobox "SHIM and GRUB(2) Secure Boot for ${_UEFI_ARCH} has been installed successfully." 3 75
        sleep 3
        _S_BOOTLOADER=1
    else
        _dialog --msgbox "Error installing GRUB(2) for ${_UEFI_ARCH} UEFI.\nCheck /tmp/grub_uefi_${_UEFI_ARCH}_install.log for more info.\n\nYou probably need to install it manually by chrooting into ${_DESTDIR}.\nDon't forget to bind mount /dev, /sys and /proc into ${_DESTDIR} before chrooting." 0 0
        return 1
    fi
}
