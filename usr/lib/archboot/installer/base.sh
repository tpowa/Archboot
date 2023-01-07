#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
ANSWER="/tmp/.setup"
# use the first VT not dedicated to a running console
# don't use DESTDIR=/mnt because it's intended to mount other things there!
# check first if bootet in archboot
if grep -qw archboot /etc/hostname; then
    DESTDIR="/install"
else
    DESTDIR="/"
fi
if pgrep -x Xorg > /dev/null 2>&1; then
    LOG="/dev/tty8"
else
    LOG="/dev/tty7"
fi
VC_NUM="$(basename ${LOG} | sed -e 's#tty##g')"
VC="VC${VC_NUM}"
# install stages
S_SRC=0         # choose mirror
S_MKFS=0        # formatting
S_MKFSAUTO=0    # auto fs part/formatting
# menu item tracker- autoselect the next item
NEXTITEM=""
# To allow choice in script set EDITOR=""
EDITOR=""

set_title() {
    if [[ -e "${LOCAL_DB}" ]]; then
        TITLE="Archboot Arch Linux Installation (Local mode) --> https://bit.ly/archboot"
    else
        TITLE="Archboot Arch Linux Installation (Online mode) --> https://bit.ly/archboot"
    fi
}

# DIALOG()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
DIALOG() {
    dialog --backtitle "${TITLE}" --aspect 15 "$@"
    return $?
}

printk()
{
    case ${1} in
        "on")  echo 4 >/proc/sys/kernel/printk ;;
        "off") echo 0 >/proc/sys/kernel/printk ;;
    esac
}

# geteditor()
# prompts the user to choose an editor
# sets EDITOR global variable
geteditor() {
    if ! [[ "${EDITOR}" ]]; then
        DIALOG --menu "Select a Text Editor to Use" 9 35 3 \
        "1" "nano (easier)" \
        "2" "neovim" 2>${ANSWER} || return 1
        case $(cat ${ANSWER}) in
            "1") EDITOR="nano" ;;
            "2") EDITOR="nvim" ;;
        esac
    fi
}

detect_uefi_parameters() {
    _UEFI_BOOT="0"
    _UEFI_SECURE_BOOT="0"
    _GUIDPARAMETER="0"
    [[ -e "/sys/firmware/efi" ]] && _UEFI_BOOT="1"
    if [[ "${_UEFI_BOOT}" == "1" ]]; then
        _GUIDPARAMETER="1"
        _SECUREBOOT_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SecureBoot 2>/dev/null | tail -n -1 | awk '{print $2}')"
        _SETUPMODE_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode  2>/dev/null | tail -n -1 | awk '{print $2}')"
        if [[ "${_SECUREBOOT_VAR_VALUE}" == "01" ]] && [[ "${_SETUPMODE_VAR_VALUE}" == "00" ]]; then
            _UEFI_SECURE_BOOT="1"
        fi
        if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
            if grep -q '_IA32_UEFI=1' /proc/cmdline 1>/dev/null; then
                _EFI_MIXED="1"
                _UEFI_ARCH="IA32"
                _SPEC_UEFI_ARCH="ia32"
            else
                _EFI_MIXED="0"
                _UEFI_ARCH="X64"
                _SPEC_UEFI_ARCH="x64"
            fi
        fi
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            _EFI_MIXED="0"
            _UEFI_ARCH="AA64"
            _SPEC_UEFI_ARCH="aa64"
        fi
    fi
}
