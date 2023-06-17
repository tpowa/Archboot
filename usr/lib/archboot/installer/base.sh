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
_S_NET=""         # network setting
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
_DLPROG="wget -q"
if [[ ${_DESTDIR} == "/" ]]; then
    _S_NET=1
    _S_SRC=1
fi

_set_title() {
    if [[ "${_DESTDIR}" == "/" ]]; then
        _TITLE="Archboot Arch Linux (System Setup mode) --> https://archboot.com"
    else
        if [[ -e "${_LOCAL_DB}" ]]; then
            _TITLE="Archboot Arch Linux Installation (Local mode) --> https://archboot.com"
        else
            _TITLE="Archboot Arch Linux Installation (Online mode) --> https://archboot.com"
        fi
    fi
}

# _dialog()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dialog() {
    dialog --backtitle "${_TITLE}" --aspect 15 "$@"
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
    _dialog --msgbox "This function is not available on System Setup mode." 5 60
}

_geteditor() {
    if ! [[ "${_EDITOR}" ]]; then
        _dialog --menu "Select a Text Editor to Use" 9 35 3 \
        "1" "nano (easier)" \
        "2" "neovim" 2>${_ANSWER} || return 1
        case $(cat ${_ANSWER}) in
            "1") _EDITOR="nano"
                if ! [[ -f "${_DESTDIR}/usr/bin/nano" ]]; then
                    _PACKAGES="nano"
                    _run_pacman
                    _dialog --infobox "Enable nano's syntax highlighting on installed system..." 3 70
                    grep -q '^include' "${_DESTDIR}/etc/nanorc" || \
                        echo "include \"/usr/share/nano/*.nanorc\"" >> "${_DESTDIR}/etc/nanorc"
                    sleep 2
                fi
                ;;
            "2") _EDITOR="nvim"
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

_set_vconsole() {
    if [[ -e /usr/bin/km ]]; then
        km && _NEXTITEM=1
    elif [[ -e /usr/bin/archboot-km.sh ]]; then
        archboot-km.sh && _NEXTITEM=1
    else
        _dialog --msgbox "Error:\nkm script not found, aborting console and keyboard setting." 0 0
    fi
}

_select_source() {
    _NEXTITEM="2"
    _set_title
    _S_SRC=""
    if [[ -e "${_LOCAL_DB}" ]]; then
        _getsource || return 1
    else
        if [[ -z ${_S_NET} ]]; then
            _check_network || return 1
        fi
        if [[ -z ${_S_SRC} ]]; then
            [[ "${_RUNNING_ARCH}" == "x86_64" ]] && _enable_testing
            _getsource || return 1
        fi
    fi
    _NEXTITEM="3"
}

_set_clock() {
    if [[ -e /usr/bin/tz ]]; then
        tz && _NEXTITEM="4"
    elif [[ -e /usr/bin/archboot-tz.sh ]]; then
        archboot-tz.sh && _NEXTITEM="4"
    else
        _dialog --msgbox "Error:\ntz script not found, aborting clock setting" 0 0
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
        dialog ${_DEFAULT} --backtitle "${_TITLE}" --menu "Prepare Storage Device" 12 60 5 \
            "1" "Auto-Prepare (erases the ENTIRE storage device)" \
            "2" "Partition Storage Device" \
            "3" "Manage Software Raid, LVM2 and LUKS Encryption" \
            "4" "Set Filesystem Mountpoints" \
            "5" "Return to Main Menu" 2>${_ANSWER} || _CANCEL=1
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
        _NEXTITEM="4"
    else
        _NEXTITEM="5"
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
        _dialog ${_DEFAULT} --menu "Configuration" 20 60 16 \
            "/etc/hostname"                 "System Hostname" \
            "/etc/vconsole.conf"            "Virtual Console" \
            "/etc/locale.conf"              "Locale Setting" \
            "/etc/fstab"                    "Filesystem Mountpoints" \
            "/etc/mkinitcpio.conf"          "Initramfs Config" \
            "/etc/modprobe.d/modprobe.conf" "Kernel Modules" \
            "/etc/resolv.conf"              "DNS Servers" \
            "/etc/hosts"                    "Network Hosts" \
            "/etc/locale.gen"               "Glibc Locales" \
            "/etc/pacman.d/mirrorlist"      "Pacman Mirror List" \
            "/etc/pacman.conf"              "Pacman Config File" \
            "Root-Password"                 "Set the root password" \
            "Return"                        "Return to Main Menu" 2>${_ANSWER} || break
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
        _NEXTITEM="7"
    fi
}

_mainmenu() {
    if [[ -n "${_NEXTITEM}" ]]; then
        _DEFAULT="--default-item ${_NEXTITEM}"
    else
        _DEFAULT=""
    fi
    #shellcheck disable=SC2086
    dialog ${_DEFAULT} --backtitle "${_TITLE}" --title " MAIN MENU " \
    --menu "Use the UP and DOWN arrows to navigate menus.\nUse TAB to switch between buttons and ENTER to select." 17 58 14 \
    "0" "Set Console Font And Keymap" \
    "1" "Configure Network" \
    "2" "Select Source" \
    "3" "Set Time And Date" \
    "4" "Prepare Storage Device" \
    "5" "Install Packages" \
    "6" "Configure System" \
    "7" "Install Bootloader" \
    "8" "Exit Program" 2>${_ANSWER}
    _NEXTITEM="$(cat ${_ANSWER})"
    case $(cat ${_ANSWER}) in
        "0")
            _set_vconsole ;;
        "1")
            _donetwork ;;
        "2")
            if [[ "${_DESTDIR}" == "/" ]]; then
                _abort_running_system
            else
                _select_source || return 1
                _update_environment
            fi ;;
        "3")
            _set_clock ;;
        "4")
            if [[ "${_DESTDIR}" == "/" ]]; then
                _abort_running_system
            else
                _prepare_storagedrive
            fi ;;
        "5")
            if [[ "${_DESTDIR}" == "/" ]]; then
                _abort_running_system
            else
                _install_packages
            fi ;;
        "6")
            _configure_system ;;
        "7")
            _install_bootloader ;;
        "8")
            dialog ${_DEFAULT} --backtitle "${_TITLE}" --title " EXIT MENU " 10 40 6 \
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
                _dialog --msgbox "Reboot:\nHit 'Enter' for rebooting the system.\nDon't forget to remove the boot medium!" 7 50
                reboot
            elif [[ "${_EXIT}" == "3" ]]; then
                _dialog --msgbox "Poweroff:\nHit 'Enter' for powering off the system." 6 50
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
