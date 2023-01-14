#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_ANSWER="/tmp/.setup"
# use the first VT not dedicated to a running console
# don't use _DESTDIR=/mnt because it's intended to mount other things there!
# check first if bootet in archboot
if grep -qw archboot /etc/hostname; then
    _DESTDIR="/install"
else
    _DESTDIR="/"
fi
_NO_LOG="/dev/null"
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
_BLKID="blkid -c /dev/null"
_DLPROG="wget -q"

_set_title() {
    if [[ -e "${_LOCAL_DB}" ]]; then
        _TITLE="Archboot Arch Linux Installation (Local mode) --> https://bit.ly/archboot"
    else
        _TITLE="Archboot Arch Linux Installation (Online mode) --> https://bit.ly/archboot"
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

# _geteditor()
# prompts the user to choose an editor
# sets EDITOR global variable
_geteditor() {
    if ! [[ "${_EDITOR}" ]]; then
        _dialog --menu "Select a Text Editor to Use" 9 35 3 \
        "1" "nano (easier)" \
        "2" "neovim" 2>${_ANSWER} || return 1
        case $(cat ${_ANSWER}) in
            "1") _EDITOR="nano" ;;
            "2") _EDITOR="nvim" ;;
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
        _SECUREBOOT_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SecureBoot 2>/dev/null | tail -n -1 | awk '{print $2}')"
        _SETUPMODE_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode  2>/dev/null | tail -n -1 | awk '{print $2}')"
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
        ## Lenovo BIOS-GPT issues - Arch Forum - https://bbs.archlinux.org/viewtopic.php?id=131149 , https://bbs.archlinux.org/viewtopic.php?id=133330 , https://bbs.archlinux.org/viewtopic.php?id=138958
        ## Lenovo BIOS-GPT issues - in Fedora - https://bugzilla.redhat.com/show_bug.cgi?id=735733, https://bugzilla.redhat.com/show_bug.cgi?id=749325 , http://git.fedorahosted.org/git/?p=anaconda.git;a=commit;h=ae74cebff312327ce2d9b5ac3be5dbe22e791f09
        #shellcheck disable=SC2034
        _dialog --yesno "You are running in BIOS/MBR mode.\n\nDo you want to use GUID Partition Table (GPT)?\n\nIt is a standard for the layout of the partition table on a physical storage disk. Although it forms a part of the Unified Extensible Firmware Interface (UEFI) standard, it is also used on some BIOS systems because of the limitations of MBR aka msdos partition tables, which restrict maximum disk size to 2 TiB.\n\nWindows 10 and later versions include the capability to use GPT for non-boot aka data disks (only UEFI systems can boot Windows 10 and later from GPT disks).\n\nAttention:\n- Please check if your other operating systems have GPT support!\n- Use this option for a GRUB(2) setup, which should support LVM, RAID\n  etc., which doesn't fit into the usual 30k MS-DOS post-MBR gap.\n- BIOS-GPT boot may not work in some Lenovo systems (irrespective of the\n   bootloader used). " 0 0 && _GUIDPARAMETER=1
    fi
}

_set_vconsole() {
    if [[ -e /usr/bin/km ]]; then
        km --setup && _NEXTITEM=1
    elif [[ -e /usr/bin/archboot-km.sh ]]; then
        archboot-km.sh --setup && _NEXTITEM=1
    else
        _dialog --msgbox "Error:\nkm script not found, aborting console and keyboard setting." 0 0
    fi
}

_select_source() {
    _NEXTITEM="2"
    _set_title
    if [[ -e "${_LOCAL_DB}" ]]; then
        _getsource || return 1
    else
        if [[ -z ${_S_NET} ]]; then
            _check_network || return 1
        fi
        [[ "${_RUNNING_ARCH}" == "x86_64" ]] && _enable_testing
        _getsource || return 1
    fi
    _NEXTITEM="3"
}

_set_clock() {
    if [[ -e /usr/bin/tz ]]; then
        tz --setup && _NEXTITEM="4"
    elif [[ -e /usr/bin/archboot-tz.sh ]]; then
        archboot-tz.sh --setup && _NEXTITEM="4"
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
        dialog ${_DEFAULT} --backtitle "${_TITLE}" --menu "Prepare Storage Drive" 12 60 5 \
            "1" "Auto-Prepare (erases the ENTIRE storage drive)" \
            "2" "Partition Storage Drives" \
            "3" "Manage Software Raid, Lvm2 and Luks encryption" \
            "4" "Set Filesystem Mountpoints" \
            "5" "Return to Main Menu" 2>${_ANSWER} || _CANCEL=1
        _NEXTITEM="$(cat ${_ANSWER})"
        [[ "${_S_MKFSAUTO}" = "1" ]] && _DONE=1
        case $(cat ${_ANSWER}) in
            "1")
                _autoprepare
                [[ "${_S_MKFSAUTO}" = "1" ]] && _DONE=1
                ;;
            "2")
                _partition ;;
            "3")
                _create_special ;;
            "4")
                _DEVFINISH=""
                _ASK_MOUNTPOINTS=1
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
    "1" "Set up Network" \
    "2" "Select Source" \
    "3" "Set Time And Date" \
    "4" "Prepare Storage Drive" \
    "5" "Install Packages" \
    "6" "Configure System" \
    "7" "Install Bootloader" \
    "8" "Exit Install" 2>${_ANSWER}
    _NEXTITEM="$(cat ${_ANSWER})"
    case $(cat ${_ANSWER}) in
        "0")
            _set_vconsole ;;
        "1")
            _donetwork ;;
        "2")
            _select_source || return 1
            _update_environment ;;
        "3")
            _set_clock ;;
        "4")
            _prepare_storagedrive ;;
        "5")
            _install_packages ;;
        "6")
            _configure_system ;;
        "7")
            _install_bootloader ;;
        "8")
            [[ -e /tmp/.setup-running ]] && rm /tmp/.setup-running
            clear
            echo ""
            echo "If the install finished successfully, you can now type 'reboot'"
            echo "to restart the system."
            echo ""
            exit 0 ;;
        *)
            _dialog --yesno "Abort Installation?" 6 40 && [[ -e /tmp/.setup-running ]] && rm /tmp/.setup-running && clear && exit 0
            ;;
    esac
}
