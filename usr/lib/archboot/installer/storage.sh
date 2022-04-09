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
            "1" "Raid Help" \
            "2" "Reset Software Raid completely" \
            "3" "Create Software Raid" \
            "4" "Create Partitionable Software Raid" \
            "5" "Return to Previous Menu" 2>"${ANSWER}" || CANCEL="1"
        NEXTITEM="$(cat "${ANSWER}")"
        case $(cat "${ANSWER}") in
            "1")
                _helpraid ;;
            "2")
                _stopmd ;;
            "3")
                RAID_PARTITION=""
                _raid ;;
            "4")
                RAID_PARTITION="1"
                _raid ;;
              *)
                MDDONE=1 ;;
        esac
    done
    if [[ "${CANCEL}" = "1" ]]; then
        NEXTITEM="1"
    else
        NEXTITEM="4"
    fi
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
            "1" "LVM Help" \
            "2" "Reset Logical Volume completely" \
            "3" "Create Physical Volume" \
            "4" "Create Volume Group" \
            "5" "Create Logical Volume" \
            "6" "Return to Previous Menu" 2>"${ANSWER}" || CANCEL="1"
        NEXTITEM="$(cat "${ANSWER}")"
        case $(cat "${ANSWER}") in
            "1")
                _helplvm ;;
            "2")
                _stoplvm ;;
            "3")
                _createpv ;;
            "4")
                _createvg ;;
            "5")
                _createlv ;;
              *)
                LVMDONE=1 ;;
        esac
    done
    if [[ "${CANCEL}" = "1" ]]; then
        NEXTITEM="2"
    else
        NEXTITEM="4"
    fi
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
        dialog ${DEFAULT} --backtitle "${TITLE}" --menu "Manage Luks Encryption" 12 60 5 \
            "1" "Luks Help" \
            "2" "Reset Luks Encryption completely" \
            "3" "Create Luks" \
            "4" "Return to Previous Menu" 2>"${ANSWER}" || CANCEL="1"
        NEXTITEM="$(cat "${ANSWER}")"
        case $(cat "${ANSWER}") in
            "1")
                _helpluks ;;
            "2")
                _stopluks ;;
            "3")
                _luks ;;
              *)
                LUKSDONE=1 ;;
        esac
    done
    if [[ "${CANCEL}" = "1" ]]; then
        NEXTITEM="3"
    else
        NEXTITEM="4"
    fi
}
