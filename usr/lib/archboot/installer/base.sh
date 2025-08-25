#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_set_title() {
    if [[ "${_DESTDIR}" == "/" ]]; then
        _TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Arch Linux Setup (System Mode)"
    else
        if [[ -e "${_LOCAL_DB}" ]]; then
            _TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Setup (Offline Mode)"
        else
            _TITLE="archboot.com | ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Setup (Online Mode)"
        fi
    fi
}

_abort_running_system() {
    _dialog --msgbox "This function is not available on System Setup Mode." 5 60
}

_geteditor() {
    if [[ -z "${_EDITOR}" ]]; then
        _dialog --title " Text Editor " --no-cancel --menu "" 8 45 2 \
        "NANO" "Easier for newbies" \
        "NEOVIM" "VIM variant for experts" 2>"${_ANSWER}" || return 1
        case $(cat "${_ANSWER}") in
            "NANO") _EDITOR="nano"
                if ! [[ -f "${_DESTDIR}/usr/bin/nano" ]]; then
                    _PACKAGES=(nano)
                    _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES[*]}..." 7 75 0
                    _pacman_error
                    _dialog --no-mouse --title " Autoconfiguration " --infobox "Enable nano's syntax highlighting on installed system..." 3 70
                    rg -q '^include' "${_DESTDIR}/etc/nanorc" || \
                        echo "include \"/usr/share/nano/*.nanorc\"" >> "${_DESTDIR}/etc/nanorc"
                    sleep 2
                fi
                ;;
            "NEOVIM") _EDITOR="nvim"
                if ! [[ -f "${_DESTDIR}/usr/bin/nvim" ]]; then
                    _PACKAGES=(neovim)
                    _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES[*]}..." 7 75 0
                    _pacman_error
                fi
                ;;
        esac
    fi
}

_set_uefi_parameters() {
    _UEFI_BOOT=""
    _UEFI_SECURE_BOOT=""
    _GUIDPARAMETER=""
    [[ -e "/sys/firmware/efi" ]] && _UEFI_BOOT=1
    if [[ -n "${_UEFI_BOOT}" ]]; then
        _GUIDPARAMETER=1
        _SECUREBOOT_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SecureBoot 2>"${_NO_LOG}" | rg -o '  ([0-9]+)' -r '$1')"
        _SETUPMODE_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode 2>"${_NO_LOG}" | rg -o '  ([0-9]+)' -r '$1')"
        if [[ "${_SECUREBOOT_VAR_VALUE}" == "01" ]] && [[ "${_SETUPMODE_VAR_VALUE}" == "00" ]]; then
            _UEFI_SECURE_BOOT=1
        fi
        if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
            if rg -q '_IA32_UEFI=1' /proc/cmdline; then
                _EFI_MIXED=1
                _UEFI_ARCH="IA32"
                _SPEC_UEFI_ARCH="ia32"
            else
                _EFI_MIXED=""
                _UEFI_ARCH="X64"
                _SPEC_UEFI_ARCH="x64"
            fi
        fi
        if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
            _EFI_MIXED=""
            _UEFI_ARCH="AA64"
            _SPEC_UEFI_ARCH="aa64"
        fi
    fi
}

# set GUID (gpt) usage
_set_guid() {
    # all uefi systems should use GUID layout
    if [[ -z "${_UEFI_BOOT}" ]]; then
        _GUIDPARAMETER=""
        ## Lenovo BIOS-GPT issues - Arch Forum - https://bbs.archlinux.org/viewtopic.php?id=131149 ,
        ## https://bbs.archlinux.org/viewtopic.php?id=133330 ,
        ## https://bbs.archlinux.org/viewtopic.php?id=138958
        ## Lenovo BIOS-GPT issues - in Fedora - https://bugzilla.redhat.com/show_bug.cgi?id=735733,
        ## https://bugzilla.redhat.com/show_bug.cgi?id=749325,
        ## http://git.fedorahosted.org/git/?p=anaconda.git;a=commit;h=ae74cebff312327ce2d9b5ac3be5dbe22e791f09
        _dialog --yesno "$(cat /usr/lib/archboot/installer/help/guid.txt)" 0 0 && _GUIDPARAMETER=1
    fi
}

_prepare_storagedrive() {
    _NEXTITEM=1
    while true; do
        [[ -n "${_NEXTITEM}" ]] && _DEFAULT=(--default-item "${_NEXTITEM}")
        if ! _dialog --title " Prepare Storage Device " --no-cancel "${_DEFAULT[@]}" --menu "" 11 60 5 \
            "1" "Quick Setup (erases the ENTIRE storage device)" \
            "2" "Partition Storage Device" \
            "3" "Manage Software Raid, LVM2 And LUKS Encryption" \
            "4" "Set Filesystem Mountpoints" \
            "<" "Return To Main Menu" 2>"${_ANSWER}"; then
                _NEXTITEM=1
                return 1
        fi
        _NEXTITEM="$(cat "${_ANSWER}")"
        case $(cat "${_ANSWER}") in
            "1") _CREATE_MOUNTPOINTS=1
                 if _autoprepare; then
                     _NEXTITEM=2
                     break
                 fi
                 ;;
            "2") _partition ;;
            "3") _create_special ;;
            "4") _DEVFINISH=""
                 _CREATE_MOUNTPOINTS=1
                 if _mountpoints; then
                     _NEXTITEM=2
                     break
                 else
                     _NEXTITEM=4
                 fi ;;
              *) _NEXTITEM=1
                 break ;;
        esac
    done
}

_configure_system() {
    _NEXTITEM=3
    _destdir_mounts || return 1
    _check_root_password || return 1
    _geteditor || return 1
    ## PREPROCESSING ##
    _auto_mkinitcpio || return 1
    ## END PREPROCESS ##
    _FILE=""
    _NEXTITEM=""
    # main menu loop
    while true; do
        [[ -n "${_FILE}" ]] && _DEFAULT=(--default-item "${_FILE}")
        if ! _dialog --title " System Configuration " --no-cancel "${_DEFAULT[@]}" --menu "" 19 60 13 \
                "> User Management"             "User Configuration" \
                "/etc/vconsole.conf"            "Virtual Console" \
                "/etc/locale.conf"              "Locale Setting" \
                "/etc/locale.gen"               "Glibc Locales" \
                "/etc/fstab"                    "Filesystem Mountpoints" \
                "/etc/modprobe.d/modprobe.conf" "Kernel Modules" \
                "/etc/mkinitcpio.conf"          "Initramfs Config" \
                "/etc/hostname"                 "System Hostname" \
                "/etc/resolv.conf"              "DNS Servers" \
                "/etc/hosts"                    "Network Hosts" \
                "/etc/pacman.d/mirrorlist"      "Pacman Mirrors" \
                "/etc/pacman.conf"              "Pacman Config" \
                "< Back"                        "Return to Main Menu" 2>"${_ANSWER}"; then
                    _NEXTITEM=3
                    return 1
        fi
        _FILE="$(cat "${_ANSWER}")"
        if [[ "${_FILE}" = "< Back" || -z "${_FILE}" ]]; then
            _NEXTITEM=4
            break
        elif [[ "${_FILE}" = "/etc/mkinitcpio.conf" ]]; then
            _set_mkinitcpio
        elif [[ "${_FILE}" = "/etc/locale.gen" ]]; then
            _auto_set_locale |\
            _dialog --title " Locales " --no-mouse --gauge "Enable glibc locales based on locale.conf on installed system..."  6 75 0
            _editor "${_DESTDIR}${_FILE}"
            _run_locale_gen |\
            _dialog --title " Locales " --no-mouse --gauge "Rebuilding glibc locales on installed system..." 6 75 0
        elif [[ "${_FILE}" = "> User Management" ]]; then
            _user_management
            _FILE=""
        else
            _editor "${_DESTDIR}${_FILE}"
        fi
    done
}

_mainmenu() {
    if [[ -n "${_NEXTITEM}" ]]; then
        _DEFAULT=(--default-item "${_NEXTITEM}")
    fi
    _dialog --no-cancel "${_DEFAULT[@]}" --title " Setup Menu " \
    --menu "" 11 45 7 \
    "1" "Prepare Storage Device" \
    "2" "Install Packages" \
    "3" "Configure System" \
    "4" "Install Bootloader" \
    "<" "Exit" 2>"${_ANSWER}"
    case $(cat "${_ANSWER}") in
        "1") if [[ "${_DESTDIR}" == "/" ]]; then
                 _abort_running_system
                 _NEXTITEM=1
             else
                 _prepare_storagedrive
             fi ;;
        "2") if [[ "${_DESTDIR}" == "/" ]]; then
                 _abort_running_system
                 _NEXTITEM=2
             else
                 _install_packages
             fi ;;
        "3") _configure_system ;;
        "4") _install_bootloader ;;
        "<") _dialog --title " Exit Menu " --menu "" 9 30 5 \
             "1" "Exit Program" \
             "2" "Reboot System" \
             "3" "Poweroff System" 2>"${_ANSWER}"
            case $(cat "${_ANSWER}") in
                "1") [[ -e /tmp/.setup-running ]] && rm /tmp/.setup-running
                     clear
                     if mountpoint -q /install; then
                         echo ""
                         echo "If the installation finished successfully:"
                         echo "Remove the boot medium and type 'reboot'"
                         echo "to restart the system."
                         echo ""
                     fi
                     exit 0 ;;
                "2") _COUNT=0
                     while true; do
                         sleep 1
                         _COUNT=$((_COUNT+1))
                         # abort after 10 seconds
                         _progress "$((_COUNT*10))" "Rebooting in $((10-_COUNT)) second(s). Don't forget to remove the boot medium!"
                         [[ "${_COUNT}" == 10 ]] && break
                     done | _dialog --title " System Reboot " --no-mouse --gauge \
                            "Rebooting in 10 seconds. Don't forget to remove the boot medium!" 6 75 0
                     reboot ;;
                "3") _COUNT=0
                     while true; do
                         sleep 1
                         _COUNT=$((_COUNT+1))
                         # abort after 10 seconds
                         _progress "$((_COUNT*10))" "Powering off in $((10-_COUNT)) second(s). Don't forget to remove the boot medium!"
                         [[ "${_COUNT}" == 10 ]] && break
                     done | _dialog --title " System Shutdown " --no-mouse --gauge \
                            "Powering off in 10 seconds. Don't forget to remove the boot medium!" 6 75 0
                     poweroff ;;
            esac ;;
        *) if _dialog --yesno "Abort Program?" 5 20; then
              [[ -e /tmp/.setup-running ]] && rm /tmp/.setup-running
              clear
              exit 1
           fi ;;
    esac
}
