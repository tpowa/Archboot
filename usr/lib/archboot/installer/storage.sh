#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# menu for raid, lvm and encrypt
create_special() {
    NEXTITEM=""
    SPECIALDONE=0
    while [[ "${SPECIALDONE}" = "0" ]]; do
        if [[ -n "${NEXTITEM}" ]]; then
            DEFAULT="--default-item ${NEXTITEM}"
        else
            DEFAULT=""
        fi
        CANCEL=""
        #shellcheck disable=SC2086
        dialog ${DEFAULT} --backtitle "${TITLE}" --menu "Manage Software Raid, LVM2 and Luks encryption" 11 60 5 \
            "1" "Manage Software Raid" \
            "2" "Manage LVM2" \
            "3" "Manage Luks encryption" \
            "4" "Return to Previous Menu" 2>"${ANSWER}" || CANCEL="1"
        NEXTITEM="$(cat "${ANSWER}")"
        case $(cat "${ANSWER}") in
            "1")
                _createmd ;;
            "2")
                _createlvm ;;
            "3")
                _createluks ;;
            *)
                SPECIALDONE=1 ;;
        esac
    done
    if [[ "${CANCEL}" = "1" ]]; then
        NEXTITEM="3"
    else
        NEXTITEM="4"
    fi
}

# menu for md creation
_createmd() {
    NEXTITEM=""
    MDDONE=0
    while [[ "${MDDONE}" = "0" ]]; do
        if [[ -n "${NEXTITEM}" ]]; then
            DEFAULT="--default-item ${NEXTITEM}"
        else
            DEFAULT=""
        fi
        CANCEL=""
        #shellcheck disable=SC2086
        dialog ${DEFAULT} --backtitle "${TITLE}" --menu "Manage Software Raid" 12 60 5 \
            "1" "Create Software Raid" \
            "2" "Create Partitionable Software Raid" \
            "3" "Reset Software Raid" \
            "4" "Raid Help" \
            "5" "Return to Previous Menu" 2>"${ANSWER}" || CANCEL="1"
        NEXTITEM="$(cat "${ANSWER}")"
        case $(cat "${ANSWER}") in
            "1")
                RAID_PARTITION=""
                _raid ;;
            "2")
                RAID_PARTITION="1"
                _raid ;;
            "3")
                _stopmd ;;
            "4")
                _helpraid ;;
              *)
                MDDONE=1 ;;
        esac
    done
    NEXTITEM="1"
}

# menu for lvm creation
_createlvm() {
    NEXTITEM=""
    LVMDONE=0
    while [[ "${LVMDONE}" = "0" ]]; do
        if [[ -n "${NEXTITEM}" ]]; then
            DEFAULT="--default-item ${NEXTITEM}"
        else
            DEFAULT=""
        fi
        CANCEL=""
        #shellcheck disable=SC2086
        dialog ${DEFAULT} --backtitle "${TITLE}" --menu "Manage physical volume, volume group or logical volume" 13 60 7 \
            "1" "Create Physical Volume" \
            "2" "Create Volume Group" \
            "3" "Create Logical Volume" \
            "4" "Reset Logical Volume" \
            "5" "LVM Help" \
            "6" "Return to Previous Menu" 2>"${ANSWER}" || CANCEL="1"
        NEXTITEM="$(cat "${ANSWER}")"
        case $(cat "${ANSWER}") in
            "1")
                _createpv ;;
            "2")
                _createvg ;;
            "3")
                _createlv ;;
            "4")
                _stoplvm ;;
            "5")
                _helplvm ;;
              *)
                LVMDONE=1 ;;
        esac
    done
    NEXTITEM="2"
}

# menu for luks creation
_createluks() {
    NEXTITEM=""
    LUKSDONE=0
    while [[ "${LUKSDONE}" = "0" ]]; do
        if [[ -n "${NEXTITEM}" ]]; then
            DEFAULT="--default-item ${NEXTITEM}"
        else
            DEFAULT=""
        fi
        CANCEL=""
        #shellcheck disable=SC2086
        dialog ${DEFAULT} --backtitle "${TITLE}" --menu "Manage Luks Encryption" 11 60 5 \
            "1" "Create Luks" \
            "2" "Reset Luks Encryption completely" \
            "3" "Luks Help" \
            "4" "Return to Previous Menu" 2>"${ANSWER}" || CANCEL="1"
        NEXTITEM="$(cat "${ANSWER}")"
        case $(cat "${ANSWER}") in
            "1")
                _luks ;;
            "2")
                _stopluks ;;
            "3")
                _helpluks ;;
              *)
                LUKSDONE=1 ;;
        esac
    done
    NEXTITEM="3"
}
