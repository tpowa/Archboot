#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# created by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.setup"
if pgrep -x Xorg &>"${_NO_LOG}"; then
    _LOG="/dev/tty8"
else
    _LOG="/dev/tty7"
fi
_VC_NUM="$(basename ${_LOG} | sed -e 's#tty##g')"
_VC="VC${_VC_NUM}"
# install stages
_S_SRC=""         # choose mirror
_S_MKFS=""        # formatting
_S_MKFSAUTO=""    # auto fs part/formatting
# menu item tracker- autoselect the next item
_NEXTITEM=""
# To allow choice in script set EDITOR=""
_EDITOR=""
# programs
_LSBLK="lsblk -rpno"
_BLKID="blkid -c ${_NO_LOG}"
_FINDMNT="findmnt -vno SOURCE"
_DLPROG="wget -q"
if [[ ${_DESTDIR} == "/" ]]; then
    _S_SRC=1
fi

_set_title() {
    if [[ "${_DESTDIR}" == "/" ]]; then
        _TITLE="Archboot ${_RUNNING_ARCH} | Arch Linux Setup (System Mode) | https://archboot.com"
    else
        if [[ -e "${_LOCAL_DB}" ]]; then
            _TITLE="Archboot ${_RUNNING_ARCH} | Arch Linux Setup (Offline Mode) | https://archboot.com"
        else
            _TITLE="Archboot ${_RUNNING_ARCH} | Arch Linux Setup (Online Mode) | https://archboot.com"
        fi
    fi
}

# _dialog()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dialog() {
    dialog --cancel-label "Back" --backtitle "${_TITLE}" --aspect 15 "$@"
    return $?
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
        _dialog --title " Text Editor " --no-cancel --menu "" 8 55 2 \
        "NANO" "Easier for newbies" \
        "NEOVIM" "VIM variant for experts" 2>${_ANSWER} || return 1
        case $(cat ${_ANSWER}) in
            "NANO") _EDITOR="nano"
                if ! [[ -f "${_DESTDIR}/usr/bin/nano" ]]; then
                    _PACKAGES="nano"
                    _run_pacman
                    _dialog --infobox "Enable nano's syntax highlighting on installed system..." 3 70
                    grep -q '^include' "${_DESTDIR}/etc/nanorc" || \
                        echo "include \"/usr/share/nano/*.nanorc\"" >> "${_DESTDIR}/etc/nanorc"
                    sleep 2
                fi
                ;;
            "NEOVIM") _EDITOR="nvim"
                if ! [[ -f "${_DESTDIR}/usr/bin/nvim" ]]; then
                    _PACKAGES="nvim"
                    _run_pacman
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
    _S_MKFSAUTO=""
    _S_MKFS=""
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
            "5" "Return To Main Menu" 2>${_ANSWER} || _CANCEL=1
        _NEXTITEM="$(cat ${_ANSWER})"
        [[ "${_S_MKFSAUTO}" = "1" ]] && _DONE=1
        case $(cat ${_ANSWER}) in
            "1")
                _CREATE_MOUNTPOINTS=1
                _autoprepare
                [[ "${_S_MKFSAUTO}" = "1" ]] && _DONE=1
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
    _set_locale || return 1
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
        _dialog --no-cancel ${_DEFAULT} --menu "System Configuration" 20 60 16 \
            "/etc/hostname"                 "System Hostname" \
            "/etc/vconsole.conf"            "Virtual Console" \
            "/etc/locale.conf"              "Locale Setting" \
            "/etc/fstab"                    "Filesystem Mountpoints" \
            "/etc/mkinitcpio.conf"          "Initramfs Config" \
            "/etc/modprobe.d/modprobe.conf" "Kernel Modules" \
            "/etc/resolv.conf"              "DNS Servers" \
            "/etc/hosts"                    "Network Hosts" \
            "/etc/locale.gen"               "Glibc Locales" \
            "/etc/pacman.d/mirrorlist"      "Pacman Mirrors" \
            "/etc/pacman.conf"              "Pacman Config" \
            "Root-Password"                 "Set Root Password" \
            "Return"                        "Return To Main Menu" 2>${_ANSWER} || break
        _FILE="$(cat ${_ANSWER})"
        if [[ "${_FILE}" = "Return" || -z "${_FILE}" ]]; then
            _S_CONFIG=1
            break
        elif [[ "${_FILE}" = "/etc/mkinitcpio.conf" ]]; then
            _set_mkinitcpio
        elif [[ "${_FILE}" = "/etc/locale.gen" ]]; then
            _auto_set_locale
            ${_EDITOR} "${_DESTDIR}""${_FILE}"
            _run_locale_gen
        elif [[ "${_FILE}" = "Root-Password" ]]; then
            _set_password
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
    _dialog --no-cancel ${_DEFAULT} --title " MAIN MENU " \
    --menu "Use the UP and DOWN arrows to navigate menus.\nUse TAB to switch between buttons and ENTER to select." 13 58 7 \
    "1" "Prepare Storage Device" \
    "2" "Install Packages" \
    "3" "Configure System" \
    "4" "Install Bootloader" \
    "5" "Exit" 2>${_ANSWER}
    _NEXTITEM="$(cat ${_ANSWER})"
    case $(cat ${_ANSWER}) in
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
            "3" "Poweroff System" 2>${_ANSWER}
            _EXIT="$(cat ${_ANSWER})"
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
                _dialog --infobox "Rebooting in 10 seconds...\nDon't forget to remove the boot medium!" 4 50
                sleep 10
                clear
                reboot
            elif [[ "${_EXIT}" == "3" ]]; then
                _dialog --infobox "Powering off in 10 seconds...\nDon't forget to remove the boot medium!" 4 50
                sleep 10
                clear
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
