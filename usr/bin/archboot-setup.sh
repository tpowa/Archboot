#!/usr/bin/env bash
# source base and common first, contains basic parameters
. /usr/lib/archboot/installer/base.sh
. /usr/lib/archboot/installer/common.sh
# source all other functions
. /usr/lib/archboot/installer/autoconfiguration.sh
. /usr/lib/archboot/installer/autoprepare.sh
. /usr/lib/archboot/installer/blockdevices.sh
. /usr/lib/archboot/installer/bootloader.sh
. /usr/lib/archboot/installer/btrfs.sh
. /usr/lib/archboot/installer/configuration.sh
. /usr/lib/archboot/installer/mountpoints.sh
. /usr/lib/archboot/installer/network.sh
. /usr/lib/archboot/installer/pacman.sh
. /usr/lib/archboot/installer/partition.sh
. /usr/lib/archboot/installer/storage.sh

set_vconsole() {
    if [[ -e /usr/bin/km ]]; then
        km --setup && _NEXTITEM="1"
    elif [[ -e /usr/bin/archboot-km.sh ]]; then
        archboot-km.sh --setup && _NEXTITEM="1"
    else
        DIALOG --msgbox "Error:\nkm script not found, aborting console and keyboard setting." 0 0
    fi
}

select_source() {
    NEXTITEM="2"
    set_title
    if [[ -e "${_LOCAL_DB}" ]]; then
        getsource || return 1
    else
        if [[ ${_S_NET} -eq 0 ]]; then
            check_nework || return 1
        fi
        [[ "${_RUNNING_ARCH}" == "x86_64" ]] && dotesting
        getsource || return 1
    fi
    NEXTITEM="3"
}

set_clock() {
    if [[ -e /usr/bin/tz ]]; then
        tz --setup && _NEXTITEM="4"
    elif [[ -e /usr/bin/archboot-tz.sh ]]; then
        archboot-tz.sh --setup && _NEXTITEM="4"
    else
        DIALOG --msgbox "Error:\ntz script not found, aborting clock setting" 0 0
    fi
}

prepare_storagedrive() {
    _S_MKFSAUTO=0
    _S_MKFS=0
    _DONE=0
    _NEXTITEM=""
    while [[ "${_DONE}" = "0" ]]; do
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
            "5" "Return to Main Menu" 2>${_ANSWER} || _CANCEL="1"
        _NEXTITEM="$(cat ${_ANSWER})"
        [[ "${_S_MKFSAUTO}" = "1" ]] && _DONE=1
        case $(cat ${_ANSWER}) in
            "1")
                autoprepare
                [[ "${_S_MKFSAUTO}" = "1" ]] && _DONE=1
                ;;
            "2")
                partition ;;
            "3")
                create_special ;;
            "4")
                _PARTFINISH=""
                _ASK_MOUNTPOINTS="1"
                mountpoints ;;
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

configure_system() {
    destdir_mounts || return 1
    check_root_password || return 1
    geteditor || return 1
    ## PREPROCESSING ##
    set_locale || return 1
    auto_mkinitcpio
    ## END PREPROCESS ##
    _FILE=""
    _S_CONFIG=""
    # main menu loop
    while true; do
        if [[ -n "${_FILE}" ]]; then
            DEFAULT="--default-item ${_FILE}"
        else
            DEFAULT=""
        fi
        #shellcheck disable=SC2086
        DIALOG ${_DEFAULT} --menu "Configuration" 20 60 16 \
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
        if [[ "${_FILE}" = "Return" || -z "${_FILE}" ]]; then       # exit
            _S_CONFIG=1
            break           
        elif [[ "${_FILE}" = "/etc/mkinitcpio.conf" ]]; then       # non-file
            set_mkinitcpio
        elif [[ "${_FILE}" = "/etc/locale.gen" ]]; then            # non-file
            _auto_set_locale
            ${_EDITOR} "${_DESTDIR}""${_FILE}"
            run_locale_gen
        elif [[ "${_FILE}" = "Root-Password" ]]; then              # non-file
            set_password
        else                                                      #regular file
            ${_EDITOR} "${_DESTDIR}""${_FILE}"
        fi
    done
    if [[ ${_S_CONFIG} -eq 1 ]]; then
        _NEXTITEM="7"
    fi
}

mainmenu() {
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
            set_vconsole ;;
        "1")
            donetwork ;;
        "2")
            select_source || return 1
            update_environment ;;
        "3")
            set_clock ;;
        "4")
            prepare_storagedrive ;;
        "5")
            install_packages ;;
        "6")
            configure_system ;;
        "7")
            install_bootloader ;;
        "8")
            [[ -e /tmp/.setup-running ]] && rm /tmp/.setup-running
            clear
            echo ""
            echo "If the install finished successfully, you can now type 'reboot'"
            echo "to restart the system."
            echo ""
            exit 0 ;;
        *)
            DIALOG --yesno "Abort Installation?" 6 40 && [[ -e /tmp/.setup-running ]] && rm /tmp/.setup-running && clear && exit 0
            ;;
    esac
}

#####################
## begin execution ##
if [[ -e /tmp/.setup-running ]]; then
    DIALOG --msgbox "Attention:\n\nSetup already runs on a different console!\nPlease remove /tmp/.setup-running first to launch setup!" 8 60
    exit 1
fi
: >/tmp/.setup-running
: >/tmp/.setup

set_title
set_uefi_parameters

DIALOG --msgbox "Welcome to the Archboot Arch Linux Installation program.\n\nThe install process is fairly straightforward, and you should run through the options in the order they are presented.\n\nIf you are unfamiliar with partitioning/making filesystems, you may want to consult some documentation before continuing.\n\nYou can view all output from commands by viewing your ${_VC} console (ALT-F${_VC_NUM}). ALT-F1 will bring you back here." 14 65

while true; do
    mainmenu
done

clear
exit 0

# vim: set ts=4 sw=4 et:
