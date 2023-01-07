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
if pgrep -x Xorg > /dev/null 2>&1; then
    _LOG="/dev/tty8"
else
    _LOG="/dev/tty7"
fi
_VC_NUM="$(basename ${_LOG} | sed -e 's#tty##g')"
_VC="VC${_VC_NUM}"
# install stages
_S_SRC=0         # choose mirror
_S_MKFS=0        # formatting
_S_MKFSAUTO=0    # auto fs part/formatting
# menu item tracker- autoselect the next item
_NEXTITEM=""
# To allow choice in script set EDITOR=""
_EDITOR=""

set_title() {
    if [[ -e "${LOCAL_DB}" ]]; then
        _TITLE="Archboot Arch Linux Installation (Local mode) --> https://bit.ly/archboot"
    else
        _TITLE="Archboot Arch Linux Installation (Online mode) --> https://bit.ly/archboot"
    fi
}

# DIALOG()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
DIALOG() {
    dialog --backtitle "${_TITLE}" --aspect 15 "$@"
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
    if ! [[ "${_EDITOR}" ]]; then
        DIALOG --menu "Select a Text Editor to Use" 9 35 3 \
        "1" "nano (easier)" \
        "2" "neovim" 2>${_ANSWER} || return 1
        case $(cat ${_ANSWER}) in
            "1") EDITOR="nano" ;;
            "2") EDITOR="nvim" ;;
        esac
    fi
}

set_uefi_parameters() {
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

# set GUID (gpt) usage
set_guid() {
    # all uefi systems should use GUID layout
    if [[ "${_UEFI_BOOT}" == "0" ]]; then
        ## Lenovo BIOS-GPT issues - Arch Forum - https://bbs.archlinux.org/viewtopic.php?id=131149 , https://bbs.archlinux.org/viewtopic.php?id=133330 , https://bbs.archlinux.org/viewtopic.php?id=138958
        ## Lenovo BIOS-GPT issues - in Fedora - https://bugzilla.redhat.com/show_bug.cgi?id=735733, https://bugzilla.redhat.com/show_bug.cgi?id=749325 , http://git.fedorahosted.org/git/?p=anaconda.git;a=commit;h=ae74cebff312327ce2d9b5ac3be5dbe22e791f09
        #shellcheck disable=SC2034
        DIALOG --yesno "You are running in BIOS/MBR mode.\n\nDo you want to use GUID Partition Table (GPT)?\n\nIt is a standard for the layout of the partition table on a physical storage disk. Although it forms a part of the Unified Extensible Firmware Interface (UEFI) standard, it is also used on some BIOS systems because of the limitations of MBR aka msdos partition tables, which restrict maximum disk size to 2 TiB.\n\nWindows 10 and later versions include the capability to use GPT for non-boot aka data disks (only UEFI systems can boot Windows 10 and later from GPT disks).\n\nAttention:\n- Please check if your other operating systems have GPT support!\n- Use this option for a GRUB(2) setup, which should support LVM, RAID\n  etc., which doesn't fit into the usual 30k MS-DOS post-MBR gap.\n- BIOS-GPT boot may not work in some Lenovo systems (irrespective of the\n   bootloader used). " 0 0 && _GUIDPARAMETER="1"
    fi
}
