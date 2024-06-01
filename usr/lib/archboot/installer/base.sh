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

_printk()
{
    case ${1} in
        "on")  echo 4 >/proc/sys/kernel/printk ;;
        "off") echo 0 >/proc/sys/kernel/printk ;;
    esac
}

_abort_running_system() {
    _dialog --msgbox "This function is not available on System Setup Mode." 5 60
}

_geteditor() {
    if ! [[ "${_EDITOR}" ]]; then
        _dialog --title " Text Editor " --no-cancel --menu "" 8 45 2 \
        "NANO" "Easier for newbies" \
        "NEOVIM" "VIM variant for experts" 2>"${_ANSWER}" || return 1
        case $(cat "${_ANSWER}") in
            "NANO") _EDITOR="nano"
                if ! [[ -f "${_DESTDIR}/usr/bin/nano" ]]; then
                    _PACKAGES="nano"
                    _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
                    _pacman_error
                    _dialog --no-mouse --infobox "Enable nano's syntax highlighting on installed system..." 3 70
                    grep -q '^include' "${_DESTDIR}/etc/nanorc" || \
                        echo "include \"/usr/share/nano/*.nanorc\"" >> "${_DESTDIR}/etc/nanorc"
                    sleep 2
                fi
                ;;
            "NEOVIM") _EDITOR="nvim"
                if ! [[ -f "${_DESTDIR}/usr/bin/nvim" ]]; then
                    _PACKAGES="neovim"
                    _run_pacman | _dialog --title " Logging to ${_VC} | ${_LOG} " --gauge "Installing package(s):\n${_PACKAGES}..." 7 75 0
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
        _SECUREBOOT_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SecureBoot 2>"${_NO_LOG}" | tail -n -1 | awk '{print $2}')"
        _SETUPMODE_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode  2>"${_NO_LOG}" | tail -n -1 | awk '{print $2}')"
        if [[ "${_SECUREBOOT_VAR_VALUE}" == "01" ]] && [[ "${_SETUPMODE_VAR_VALUE}" == "00" ]]; then
            _UEFI_SECURE_BOOT=1
        fi
        if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
            if grep -q '_IA32_UEFI=1' /proc/cmdline; then
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
        #shellcheck disable=SC2034
        _dialog --yesno "$(cat /usr/lib/archboot/installer/help/guid.txt)" 0 0 && _GUIDPARAMETER=1
    fi
}

_prepare_storagedrive() {
    _S_QUICK_SETUP=""
    _DONE=""
    _NEXTITEM=""
    while [[ -z "${_DONE}" ]]; do
        if [[ -n "${_NEXTITEM}" ]]; then
            _DEFAULT="--default-item ${_NEXTITEM}"
        else
            _DEFAULT=""
        fi
        _CANCEL=""
        #shellcheck disable=SC2086
        _dialog --title " Prepare Storage Device " --no-cancel ${_DEFAULT} --menu "" 11 60 5 \
            "1" "Quick Setup (erases the ENTIRE storage device)" \
            "2" "Partition Storage Device" \
            "3" "Manage Software Raid, LVM2 And LUKS Encryption" \
            "4" "Set Filesystem Mountpoints" \
            "5" "Return To Main Menu" 2>"${_ANSWER}" || _CANCEL=1
        _NEXTITEM="$(cat "${_ANSWER}")"
        [[ "${_S_QUICK_SETUP}" = "1" ]] && _DONE=1
        case $(cat "${_ANSWER}") in
            "1")
                _CREATE_MOUNTPOINTS=1
                _autoprepare
                [[ "${_S_QUICK_SETUP}" = "1" ]] && _DONE=1
                ;;
            "2")
                _partition ;;
            "3")
                _create_special ;;
            "4")
                _DEVFINISH=""
                _CREATE_MOUNTPOINTS=1
                _mountpoints ;;
            *)
                _DONE=1 ;;
        esac
    done
    if [[ "${_CANCEL}" = "1" ]]; then
        _NEXTITEM="1"
    else
        _NEXTITEM="2"
    fi
}

_configure_system() {
    _destdir_mounts || return 1
    _check_root_password || return 1
    _geteditor || return 1
    ## PREPROCESSING ##
    _auto_mkinitcpio
    ## END PREPROCESS ##
    _FILE=""
    _S_CONFIG=""
    # main menu loop
    while true; do
        if [[ -n "${_FILE}" ]]; then
            _DEFAULT="--default-item ${_FILE}"
        else
            _DEFAULT=""
        fi
        #shellcheck disable=SC2086
        _dialog --title " System Configuration " --no-cancel ${_DEFAULT} --menu "" 19 60 13 \
            "Basic User Configuration"      "User Management" \
            "/etc/vconsole.conf"            "Virtual Console" \
            "/etc/locale.conf"              "Locale Setting" \
            "/etc/locale.gen"               "Glibc Locales" \
            "/etc/fstab"                    "Filesystem Mountpoints" \
            "/etc/mkinitcpio.conf"          "Initramfs Config" \
            "/etc/modprobe.d/modprobe.conf" "Kernel Modules" \
            "/etc/hostname"                 "System Hostname" \
            "/etc/resolv.conf"              "DNS Servers" \
            "/etc/hosts"                    "Network Hosts" \
            "/etc/pacman.d/mirrorlist"      "Pacman Mirrors" \
            "/etc/pacman.conf"              "Pacman Config" \
            "Back to Main Menu"             "Return" 2>"${_ANSWER}" || break
        _FILE="$(cat "${_ANSWER}")"
        if [[ "${_FILE}" = "Back to Main Menu" || -z "${_FILE}" ]]; then
            _S_CONFIG=1
            break
        elif [[ "${_FILE}" = "/etc/mkinitcpio.conf" ]]; then
            _set_mkinitcpio
        elif [[ "${_FILE}" = "/etc/locale.gen" ]]; then
            _auto_set_locale
            ${_EDITOR} "${_DESTDIR}""${_FILE}"
            _run_locale_gen
        elif [[ "${_FILE}" = "Basic User Configuration" ]]; then
            _user_management
        else
            ${_EDITOR} "${_DESTDIR}""${_FILE}"
        fi
    done
    if [[ ${_S_CONFIG} -eq 1 ]]; then
        _NEXTITEM="4"
    fi
}

_mainmenu() {
    if [[ -n "${_NEXTITEM}" ]]; then
        _DEFAULT="--default-item ${_NEXTITEM}"
    fi
    #shellcheck disable=SC2086
    _dialog --no-cancel ${_DEFAULT} --title " Setup Menu " \
    --menu "" 11 45 7 \
    "1" "Prepare Storage Device" \
    "2" "Install Packages" \
    "3" "Configure System" \
    "4" "Install Bootloader" \
    "5" "Exit" 2>"${_ANSWER}"
    _NEXTITEM="$(cat "${_ANSWER}")"
    case $(cat "${_ANSWER}") in
        "1")
            if [[ "${_DESTDIR}" == "/" ]]; then
                _abort_running_system
            else
                _prepare_storagedrive
            fi ;;
        "2")
            if [[ "${_DESTDIR}" == "/" ]]; then
                _abort_running_system
            else
                _install_packages
            fi ;;
        "3")
            _configure_system ;;
        "4")
            _install_bootloader ;;
        "5")
            #shellcheck disable=SC2086
            _dialog --title " Exit Menu " --menu "" 9 30 5 \
            "1" "Exit Program" \
            "2" "Reboot System" \
            "3" "Poweroff System" 2>"${_ANSWER}"
            _EXIT="$(cat "${_ANSWER}")"
            if [[ "${_EXIT}" == "1" ]]; then
                [[ -e /tmp/.setup-running ]] && rm /tmp/.setup-running
                clear
                if mountpoint -q /install; then
                    echo ""
                    echo "If the installation finished successfully:"
                    echo "Remove the boot medium and type 'reboot'"
                    echo "to restart the system."
                    echo ""
                fi
                exit 0
            elif [[ "${_EXIT}" == "2" ]]; then
                _COUNT=0
                while true; do
                    sleep 1
                    _COUNT=$((_COUNT+1))
                    # abort after 10 seconds
                    _progress "$((_COUNT*10))" "Rebooting in $((10-_COUNT)) second(s). Don't forget to remove the boot medium!"
                    [[ "${_COUNT}" == 10 ]] && break
                done | _dialog --title " System Reboot " --no-mouse --gauge "Rebooting in 10 seconds. Don't forget to remove the boot medium!" 6 75 0
                reboot
            elif [[ "${_EXIT}" == "3" ]]; then
                _COUNT=0
                while true; do
                    sleep 1
                    _COUNT=$((_COUNT+1))
                    # abort after 10 seconds
                    _progress "$((_COUNT*10))" "Powering off in $((10-_COUNT)) second(s). Don't forget to remove the boot medium!"
                    [[ "${_COUNT}" == 10 ]] && break
                done | _dialog --title " System Shutdown " --no-mouse --gauge "Powering off in 10 seconds. Don't forget to remove the boot medium!" 6 75 0
                poweroff
            fi
            ;;
        *)
            if _dialog --yesno "Abort Program?" 6 40; then
                [[ -e /tmp/.setup-running ]] && rm /tmp/.setup-running
                clear
                exit 1
            fi
            ;;
    esac
}
# vim: set ft=sh ts=4 sw=4 et:
