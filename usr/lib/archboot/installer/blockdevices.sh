#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
_getfstype()
{
    ${_LSBLK} FSTYPE "${1}" 2>"${_NO_LOG}"
}

_getfsuuid()
{
    ${_LSBLK} UUID "${1}" 2>"${_NO_LOG}"
}

_getfslabel()
{
    ${_LSBLK} LABEL "${1}" 2>"${_NO_LOG}"
}

_getpartuuid()
{
    ${_LSBLK} PARTUUID "${1}" 2>"${_NO_LOG}"
}

_getpartlabel()
{
    ${_LSBLK} PARTLABEL "${1}" 2>"${_NO_LOG}"
}

# lists linux blockdevices
_blockdevices() {
     # all available block disk devices
     for dev in $(${_LSBLK} NAME,TYPE | grep "disk$" | cut -d ' ' -f1); do
        # exclude checks:
        #- iso9660 devices
        #  (${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | grep "iso9660"
        #- fakeraid isw devices
        #  ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | grep "isw_raid_member"
        #- fakeraid ddf devices
        #  ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | grep "ddf_raid_member"
        # - zram devices
        #  echo "${dev}" | grep -q 'zram'
        if ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "iso9660" &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "isw_raid_member" &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "ddf_raid_member" &&\
            ! echo "${dev}" | grep -q 'zram'; then
                ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
     done
}

# lists linux blockdevice partitions
_blockdevices_partitions() {
    # all available block devices partitions
    for dev in $(${_LSBLK} NAME,TYPE | grep -v '^/dev/md' | grep "part$"| cut -d ' ' -f1); do
        # exclude checks:
        #- part of raid device
        #  ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | grep "linux_raid_member"
        #- part of lvm2 device
        #  ${_LSBLK} FSTYPE /dev/${dev} 2>"${_NO_LOG}" | grep "LVM2_member"
        #- part of luks device
        #  ${_LSBLK} FSTYPE /dev/${dev} 2>"${_NO_LOG}" | grep "crypto_LUKS"
        #- extended partition
        #  sfdisk -l 2>"${_NO_LOG}" | grep "${dev}" | grep "Extended$"
        # - extended partition (LBA)
        #   sfdisk -l 2>"${_NO_LOG}" | grep "${dev}" | grep "(LBA)$"
        #- bios_grub partitions
        #  sfdisk -l 2>"${_NO_LOG}" | grep "${dev}" | grep -q "BIOS boot$"
        #- iso9660 devices
        #  "${_LSBLK} FSTYPE -s ${dev} | grep "iso9660"
        if ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "linux_raid_member" &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "LVM2_member" &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "crypto_LUKS" &&\
            ! ${_LSBLK} FSTYPE -s "${dev}" 2>"${_NO_LOG}" | grep -q "iso9660" &&\
            ! sfdisk -l 2>"${_NO_LOG}" | grep "${dev}" | grep -q "Extended$" &&\
            ! sfdisk -l 2>"${_NO_LOG}" | grep "${dev}" | grep -q "(LBA)$" &&\
            ! sfdisk -l 2>"${_NO_LOG}" | grep "${dev}" | grep -q "BIOS boot$"; then
                ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
}

# list none partitionable raid md devices
_raid_devices() {
    for dev in $(${_LSBLK} NAME,TYPE | grep " raid.*$\| linear$" | cut -d ' ' -f 1 | sort -u); do
        # exclude checks:
        # - part of lvm2 device_found
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | grep "LVM2_member"
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | grep "crypto_LUKS"
        # - part of isw fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s 2>"${_NO_LOG}" | grep "isw_raid_member"
        # - part of ddf fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s 2>"${_NO_LOG}" | grep "ddf_raid_member"
        if ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "LVM2_member" &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "crypto_LUKS" &&\
            ! ${_LSBLK} FSTYPE "${dev}" -s 2>"${_NO_LOG}" | grep -q "isw_raid_member" &&\
            ! ${_LSBLK} FSTYPE "${dev}" -s 2>"${_NO_LOG}" | grep -q "ddf_raid_member" &&\
            ! find "$dev"*p* -type f -exec echo {} \; 2>"${_NO_LOG}"; then
                ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
}

# lists linux partitionable raid devices partitions
_partitionable_raid_devices_partitions() {
    for dev in $(${_LSBLK} NAME,TYPE | grep "part$" | grep "^/dev/md.*p" 2>"${_NO_LOG}" | cut -d ' ' -f 1 | sort -u) ; do
        # exclude checks:
        # - part of lvm2 device_found
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | grep "LVM2_member"
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | grep "crypto_LUKS"
        # - extended partition
        #   sfdisk -l 2>"${_NO_LOG}" 2>"${_NO_LOG}" | grep "${dev}" | grep "Extended$"
        # - extended partition (LBA)
        #   sfdisk -l 2>"${_NO_LOG}" 2>"${_NO_LOG}" | grep "${dev}" | grep "(LBA)$"
        # - part of isw fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s 2>"${_NO_LOG}" | grep "isw_raid_member"
        # - part of ddf fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s 2>"${_NO_LOG}" | grep "ddf_raid_member"
        if ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "LVM2_member" &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "crypto_LUKS" &&\
            ! sfdisk -l 2>"${_NO_LOG}" | grep "${dev}" | grep -q "Extended$" &&\
            ! sfdisk -l 2>"${_NO_LOG}" | grep "${dev}" | grep -q "(LBA)$" &&\
            ! ${_LSBLK} FSTYPE "${dev}" -s 2>"${_NO_LOG}" | grep -q "isw_raid_member" &&\
            ! ${_LSBLK} FSTYPE "${dev}" -s 2>"${_NO_LOG}" | grep -q "ddf_raid_member"; then
                ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
}

_dmraid_devices() {
    # isw_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE | grep " raid.*$" | cut -d ' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" 2>"${_NO_LOG}" | grep -q "isw_raid_member$"; then
            ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
    # ddf_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE | grep " raid.*$" | cut -d ' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" 2>"${_NO_LOG}" | grep -q "ddf_raid_member$"; then
            ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
}

_dmraid_partitions() {
    # isw_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE | grep " md$" | cut -d ' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" 2>"${_NO_LOG}" | grep "isw_raid_member$" | cut -d ' ' -f 1; then
            ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
    # ddf_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE | grep " md$" | cut -d ' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" 2>"${_NO_LOG}" | grep "ddf_raid_member$" | cut -d ' ' -f 1; then
            ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
}

# dm_devices
# - show device mapper devices:
#   lvm2 and cryptdevices
_dm_devices() {
    for dev in $(${_LSBLK} NAME,TYPE | grep -e "lvm$" -e "crypt$" | cut -d ' ' -f1 | sort -u); do
        # exclude checks:
        # - part of lvm2 device
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | grep "LVM2_member"
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | grep "crypto_LUKS"
        # - part of raid device
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | grep "linux_raid_member$"
        # - part of running raid on encrypted device
        #   ${_LSBLK} TYPE ${dev} 2>"${_NO_LOG}" | grep "raid.*$
        if ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "crypto_LUKS$" &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "LVM2_member$" &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | grep -q "linux_raid_member$" &&\
            ! ${_LSBLK} TYPE "${dev}" 2>"${_NO_LOG}" | grep -q "raid.*$"; then
                ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
}

_finddisks() {
    _blockdevices
    _dmraid_devices
}

_finddevices() {
    _blockdevices_partitions
    _dm_devices
    _dmraid_partitions
    _raid_devices
    _partitionable_raid_devices_partitions
}

# don't check on raid devices!
_findbootloaderdisks() {
    if [[ -z "${_USE_DMRAID}" ]]; then
        _blockdevices
    else
        _dmraid_devices
    fi
}

_activate_lvm2()
{
    _LVM2_READY=""
    if [[ -e /usr/bin/lvm ]]; then
        _OLD_LVM2_GROUPS=${_LVM2_GROUPS}
        _OLD_LVM2_VOLUMES=${_LVM2_VOLUMES}
        _dialog --no-mouse --infobox "Scanning logical volumes..." 0 0
        lvm vgscan --ignorelockingfailure &>"${_NO_LOG}"
        _dialog --no-mouse --infobox "Activating logical volumes..." 0 0
        lvm vgchange --ignorelockingfailure --ignoremonitoring -ay &>"${_NO_LOG}"
        _LVM2_GROUPS="$(vgs -o vg_name --noheading 2>"${_NO_LOG}")"
        _LVM2_VOLUMES="$(lvs -o vg_name,lv_name --noheading --separator - 2>"${_NO_LOG}")"
        [[ "${_OLD_LVM2_GROUPS}" == "${_LVM2_GROUPS}" && "${_OLD_LVM2_VOLUMES}" == "${_LVM2_VOLUMES}" ]] && _LVM2_READY=1
    fi
}

_activate_md()
{
    _RAID_READY=""
    if [[ -e /usr/bin/mdadm ]]; then
        _dialog --no-mouse --infobox "Activating RAID arrays..." 0 0
        mdadm --assemble --scan &>"${_NO_LOG}" || _RAID_READY=1
    fi
}

_activate_luks()
{
    _LUKS_READY=""
    if [[ -e /usr/bin/cryptsetup ]]; then
        _dialog --no-mouse --infobox "Scanning for luks encrypted devices..." 0 0
        if ${_LSBLK} FSTYPE | grep -q "crypto_LUKS"; then
            for part in $(${_LSBLK} NAME,FSTYPE | grep " crypto_LUKS$" | cut -d ' ' -f 1); do
                # skip already encrypted devices, device mapper!
                if ! ${_LSBLK} TYPE "${part}" 2>"${_NO_LOG}" | grep -q "crypt$"; then
                    _RUN_LUKS=""
                    _dialog --yesno "Setup detected luks encrypted device, do you want to activate ${part} ?" 0 0 && _RUN_LUKS=1
                    [[ -n "${_RUN_LUKS}" ]] && _enter_luks_name && _enter_luks_passphrase && _opening_luks
                    [[ -z "${_RUN_LUKS}" ]] && _LUKS_READY=1
                else
                    _LUKS_READY=1
                fi
            done
        else
            _LUKS_READY=1
        fi
    fi
}

# activate special devices:
# activate lvm2 and raid devices, if not already activated during bootup!
# run it more times if needed, it can be hidden by each other!
_activate_special_devices()
{
    _RAID_READY=""
    _LUKS_READY=""
    _LVM2_READY=""
    while [[ -n "${_LVM2_READY}" && -n "${_RAID_READY}" && -n "${_LUKS_READY}" ]]; do
        _activate_md
        _activate_lvm2
        _activate_luks
    done
}

_set_device_name_scheme() {
    _NAME_SCHEME_PARAMETER=""
    _NAME_SCHEME_LEVELS=""
    ## util-linux root=PARTUUID=/root=PARTLABEL= support - https://git.kernel.org/?p=utils/util-linux/util-linux.git;a=commitdiff;h=fc387ee14c6b8672761ae5e67ff639b5cae8f27c;hp=21d1fa53f16560dacba33fffb14ffc05d275c926
    ## mkinitcpio's init root=PARTUUID= support - https://projects.archlinux.org/mkinitcpio.git/tree/init_functions#n185
    if [[ -n "${_UEFI_BOOT}" || -n "${_GUIDPARAMETER}" ]]; then
        _NAME_SCHEME_LEVELS="${_NAME_SCHEME_LEVELS} PARTUUID PARTUUID=<partuuid> PARTLABEL PARTLABEL=<partlabel> SD_GPT_AUTO_GENERATOR none"
    fi
    _NAME_SCHEME_LEVELS="${_NAME_SCHEME_LEVELS} FSUUID UUID=<uuid> FSLABEL LABEL=<label> KERNEL /dev/<kernelname>"
    #shellcheck disable=SC2086
    _dialog --no-cancel --title " Device Name Scheme " --menu "Use PARTUUID on GPT disks. Use FSUUID on MBR/MSDOS disks." 13 65 7 ${_NAME_SCHEME_LEVELS} 2>"${_ANSWER}" || return 1
    _NAME_SCHEME_PARAMETER=$(cat "${_ANSWER}")
    _NAME_SCHEME_PARAMETER_RUN=1
}

_clean_disk() {
    # clear all magic strings/signatures - mdadm, lvm, partition tables etc
    wipefs -a -f "${1}" &>"${_NO_LOG}"
    # really clear everything MBR/GPT at the beginning of the device!
    dd if=/dev/zero of="${1}" bs=1M count=10 &>"${_NO_LOG}"
}

# Disable swap and all mounted partitions for the destination system. Unmount
# the destination root partition last!
_umountall()
{
    if [[ "${_DESTDIR}" == "/mnt/install" ]] && mountpoint -q "${_DESTDIR}"; then
        swapoff -a &>"${_NO_LOG}"
        umount -R "${_DESTDIR}"
        _dialog --no-mouse --infobox "Disabled swapspace,\nunmounted already mounted disk devices in ${_DESTDIR}..." 4 70
        sleep 3
    fi
}

_stopmd()
{
    _DISABLEMD=""
    if grep -q ^md /proc/mdstat 2>"${_NO_LOG}"; then
        _dialog --defaultno --yesno "Setup detected already running software raid device(s)...\n\nDo you want to delete ALL of them completely?\nWARNING: ALL DATA ON THEM WILL BE LOST!" 0 0 && _DISABLEMD=1
        if [[ -n "${_DISABLEMD}" ]]; then
            _umountall
            # shellcheck disable=SC2013
            for dev in $(grep ^md /proc/mdstat | sed -e 's# :.*##g'); do
                wipefs -a -f "/dev/${dev}" &>"${_NO_LOG}"
                mdadm --manage --stop "/dev/${dev}" &>"${_LOG}"
            done
            _dialog --no-mouse --infobox "Removing software raid device(s) done." 3 50
            sleep 3
        fi
    fi
    _DISABLEMDSB=""
    if ${_LSBLK} FSTYPE | grep -q "linux_raid_member"; then
        _dialog --defaultno --yesno "Setup detected superblock(s) of software raid devices...\n\nDo you want to delete the superblock on ALL of them?\nWARNING: ALL DATA ON THEM WILL BE LOST!" 0 0 && _DISABLEMDSB=1
        if [[ -n "${_DISABLEMDSB}" ]]; then
            _umountall
        fi
    fi
    if [[ -n "${_DISABLEMD}" || -n "${_DISABLEMDSB}" ]]; then
        for dev in $(${_LSBLK} NAME,FSTYPE | grep "linux_raid_member$" | cut -d ' ' -f 1); do
            _clean_disk "${dev}"
        done
        _dialog --no-mouse --infobox "Removing superblock(s) on software raid devices done." 3 60
        sleep 3
    fi
}

_stoplvm()
{
    _DISABLELVM=""
    _DETECTED_LVM=""
    _LV_VOLUMES="$(lvs -o vg_name,lv_name --noheading --separator - 2>"${_NO_LOG}")"
    _LV_GROUPS="$(vgs -o vg_name --noheading 2>"${_NO_LOG}")"
    _LV_PHYSICAL="$(pvs -o pv_name --noheading 2>"${_NO_LOG}")"
    [[ -n "${_LV_VOLUMES}" ]] && _DETECTED_LVM=1
    [[ -n "${_LV_GROUPS}" ]] && _DETECTED_LVM=1
    [[ -n "${_LV_PHYSICAL}" ]] && _DETECTED_LVM=1
    if [[ -n "${_DETECTED_LVM}" ]]; then
        _dialog --defaultno --yesno "Setup detected lvm volume(s), volume group(s) or physical device(s)...\n\nDo you want to delete ALL of them completely?\nWARNING: ALL DATA ON THEM WILL BE LOST!" 0 0 && _DISABLELVM=1
    fi
    if [[ -n "${_DISABLELVM}" ]]; then
        _umountall
        for dev in ${_LV_VOLUMES}; do
            lvremove -f "/dev/mapper/${dev}" 2>"${_NO_LOG}">"${_LOG}"
        done
        for dev in ${_LV_GROUPS}; do
            vgremove -f "${dev}" 2>"${_NO_LOG}" >"${_LOG}"
        done
        for dev in ${_LV_PHYSICAL}; do
            pvremove -f "${dev}" 2>"${_NO_LOG}" >"${_LOG}"
        done
        _dialog --no-mouse --infobox "Removing logical volume(s), logical group(s)\nand physical volume(s) done." 3 60
        sleep 3
    fi
}

_stopluks()
{
    _DISABLELUKS=""
    _DETECTED_LUKS=""
    _LUKSDEV=""
    # detect already running luks devices
    _LUKSDEV="$(${_LSBLK} NAME,TYPE | grep " crypt$" | cut -d ' ' -f1)"
    [[ -z "${_LUKSDEV}" ]] || _DETECTED_LUKS=1
    if [[ -n "${_DETECTED_LUKS}" ]]; then
        _dialog --defaultno --yesno "Setup detected running luks encrypted device(s)...\n\nDo you want to delete ALL of them completely?\nWARNING: ALL DATA ON THEM WILL BE LOST!" 0 0 && _DISABLELUKS=1
    fi
    if [[ -n "${_DISABLELUKS}" ]]; then
        _umountall
        for dev in ${_LUKSDEV}; do
            _LUKS_REAL_DEV="$(${_LSBLK} NAME,FSTYPE -s "${_LUKSDEV}" 2>"${_NO_LOG}" | grep " crypto_LUKS$" | cut -d ' ' -f1)"
            cryptsetup remove "${dev}" >"${_LOG}"
            # delete header from device
            wipefs -a "${_LUKS_REAL_DEV}" &>"${_NO_LOG}"
        done
        _dialog --no-mouse --infobox "Removing luks encrypted device(s) done." 3 50
        sleep 3
    fi
    _DISABLELUKS=""
    _DETECTED_LUKS=""
    # detect not running luks devices
    ${_LSBLK} FSTYPE | grep -q "crypto_LUKS" && _DETECTED_LUKS=1
    if [[ -n "${_DETECTED_LUKS}" ]]; then
        _dialog --defaultno --yesno "Setup detected not running luks encrypted device(s)...\n\nDo you want to delete ALL of them completely?\nWARNING: ALL DATA ON THEM WILL BE LOST!" 0 0 && _DISABLELUKS=1
    fi
    if [[ -n "${_DISABLELUKS}" ]]; then
        for dev in $(${_LSBLK} NAME,FSTYPE | grep "crypto_LUKS$" | cut -d ' ' -f1); do
           # delete header from device
           wipefs -a "${dev}" &>"${_NO_LOG}"
        done
        _dialog --no-mouse --infobox "Removing not running luks encrypted device(s) done." 3 60
        sleep 3
    fi
    [[ -e /tmp/.crypttab ]] && rm /tmp/.crypttab
}

_helpmd()
{
_dialog --msgbox "$(cat /usr/lib/archboot/installer/help/md.txt)" 0 0
}

_createmd()
{
    while true; do
        _activate_special_devices
        : >/tmp/.raid
        : >/tmp/.raid-spare
        # check for devices
        # Remove all raid devices with children
        _dialog --no-mouse --infobox "Scanning blockdevices... This may need some time." 3 60
        _RAID_BLACKLIST="$(_raid_devices;_partitionable_raid_devices_partitions)"
        #shellcheck disable=SC2119
        _DEVS="$(_finddevices)"
        if [[ -n "${_RAID_BLACKLIST}" ]]; then
            for dev in ${_RAID_BLACKLIST}; do
                _DEVS="${_DEVS//$(${_LSBLK} NAME,SIZE -d "${dev}" 2>"${_NO_LOG}")/}"
            done
        fi
        # break if all devices are in use
        if [[ -z "${_DEVS}" ]]; then
            _dialog --msgbox "All devices in use. No more devices left for new creation." 0 0
            return 1
        fi
        # enter raid device name
        _RAIDDEV=""
        while [[ -z "${_RAIDDEV}" ]]; do
            _dialog --inputbox "Enter the node name for the raiddevice:\n/dev/md[number]\n/dev/md0\n/dev/md1\n\n" 12 50 "/dev/md0" 2>"${_ANSWER}" || return 1
            _RAIDDEV=$(cat "${_ANSWER}")
            if grep -q "^${_RAIDDEV//\/dev\//}" /proc/mdstat; then
                _dialog --msgbox "ERROR: You have defined 2 identical node names! Please enter another name." 8 65
                _RAIDDEV=""
            fi
        done
        _RAIDLEVELS="linear - raid0 - raid1 - raid4 - raid5 - raid6 - raid10 -"
        #shellcheck disable=SC2086
        _dialog --no-cancel --menu "Select the raid level you want to use:" 14 50 7 ${_RAIDLEVELS} 2>"${_ANSWER}" || return 1
        _LEVEL=$(cat "${_ANSWER}")
        # raid5 and raid10 support parity parameter
        _PARITY=""
        if [[ "${_LEVEL}" == "raid5" || "${_LEVEL}" == "raid6" || "${_LEVEL}" == "raid10" ]]; then
            _PARITYLEVELS="left-asymmetric - left-symmetric - right-asymmetric - right-symmetric -"
            #shellcheck disable=SC2086
            _dialog --no-cancel --menu "Select the parity layout you want to use (default is left-symmetric):" 21 50 13 ${_PARITYLEVELS} 2>"${_ANSWER}" || return 1
            _PARITY=$(cat "${_ANSWER}")
        fi
        # select the first device to use, no missing option available!
        _RAIDNUMBER=1
        _DEGRADED=""
        #shellcheck disable=SC2086
        _dialog --no-cancel --menu "Select device ${_RAIDNUMBER}:" 21 50 13 ${_DEVS} 2>"${_ANSWER}" || return 1
        _DEV=$(cat "${_ANSWER}")
        echo "${_DEV}" >>/tmp/.raid
        while true; do
            _RAIDNUMBER=$((_RAIDNUMBER + 1))
            if [[ -n "${_DEV}" ]]; then
                # clean loop from used partition and options
                _DEVS="${_DEVS//$(${_LSBLK} NAME,SIZE -d "${_DEV}" 2>"${_NO_LOG}")/}"
            fi
            # add more devices
            # raid0 doesn't support missing devices
            if [[ "${_LEVEL}" == "raid0" || "${_LEVEL}" == "linear" || -n "${_DEGRADED}" ]]; then
                #shellcheck disable=SC2086
                _dialog --no-cancel --menu "Select additional device ${_RAIDNUMBER}:" \
                21 50 13 ${_DEVS} "> DONE" "Proceed To Summary" 2>"${_ANSWER}" || return 1
            else
                #shellcheck disable=SC2086
                _dialog --no-cancel --menu "Select additional device ${_RAIDNUMBER}:" \
                21 50 13 ${_DEVS} "> MISSING" "Degraded Raid Device" "> DONE" "Proceed To Summary" 2>"${_ANSWER}" || return 1
            fi
            _DEV=$(cat "${_ANSWER}")
            [[ "${_DEV}" == "> DONE" ]] && break
            if [[ "${_DEV}" == "> MISSING" && -z "${_DEGRADED}" ]]; then
                _DEGRADED="missing"
                echo "${_DEGRADED}" >>/tmp/.raid
                _DEV=""
            else
                if ! [[ "${_LEVEL}" == "raid0" || "${_LEVEL}" == "linear" ]]; then
                    if _dialog --defaultno --yesno "Would you like to use ${_DEV} as spare device?" 0 0; then
                        echo "${_DEV}" >>/tmp/.raid-spare
                    else
                        echo "${_DEV}" >>/tmp/.raid
                    fi
                fi
            fi
        done
        # final step ask if everything is ok?
        # shellcheck disable=SC2028
        _dialog --yesno "Would you like to create ${_RAIDDEV} like this?\n\nLEVEL:\n${_LEVEL}\n\nDEVICES:\n$(while read -r dev;do echo "${dev}\n"; done < /tmp/.raid)\nSPARES:\n$(while read -r dev;do echo "${dev}\n"; done < tmp/.raid-spare)" 0 0 && break
    done
    _umountall
    _DEVS="$(echo -n "$(cat /tmp/.raid)")"
    _SPARES="$(echo -n "$(cat /tmp/.raid-spare)")"
    # combine both if spares are available, spares at the end!
    [[ -n ${_SPARES} ]] && _DEVS="${_DEVS} ${_SPARES}"
    # get number of devices
    _RAID_DEVS="$(wc -l < /tmp/.raid)"
    _SPARE_DEVS="$(wc -l < /tmp/.raid-spare)"
    # generate options for mdadm
    _RAIDOPTIONS="--force --run --level=${_LEVEL}"
    ! [[ "${_RAID_DEVS}" == 0 ]] && _RAIDOPTIONS="${_RAIDOPTIONS} --raid-devices=${_RAID_DEVS}"
    ! [[ "${_SPARE_DEVS}" == 0 ]] && _RAIDOPTIONS="${_RAIDOPTIONS} --spare-devices=${_SPARE_DEVS}"
    [[ -n "${_PARITY}" ]] && _RAIDOPTIONS="${_RAIDOPTIONS} --layout=${_PARITY}"
    #shellcheck disable=SC2086
    if mdadm --create ${_RAIDDEV} ${_RAIDOPTIONS} ${_DEVS} &>"${_LOG}"; then
        _dialog --no-mouse --infobox "${_RAIDDEV} created successfully." 3 50
        sleep 3
    else
        _dialog --title " ERROR " --no-mouse --infobox "Creating ${_RAIDDEV} failed." 3 60
        sleep 5
        return 1
    fi
    if [[ -n "${_RAID_PARTITION}" ]]; then
        # switch for mbr usage
        _set_guid
        if [[ -z "${_GUIDPARAMETER}" ]]; then
            _dialog --msgbox "Now you'll be put into the cfdisk program where you can partition your raiddevice to your needs." 6 70
            cfdisk "${_RAIDDEV}"
        else
            _DISK="${_RAIDDEV}"
            _RUN_CFDISK=1
            _CHECK_BIOS_BOOT_GRUB=""
            _check_gpt
        fi
    fi
}

_helplvm()
{
_dialog --msgbox "$(cat /usr/lib/archboot/installer/help/lvm2.txt)" 0 0
}

_createpv()
{
    while true; do
        _activate_special_devices
        : >/tmp/.pvs-create
        _dialog --no-mouse --infobox "Scanning blockdevices... This may need some time." 3 60
        # Remove all lvm devices with children
        _LVM_BLACKLIST="$(for dev in $(${_LSBLK} NAME,TYPE | grep " lvm$" | cut -d ' ' -f1 | sort -u); do
                    echo "${dev}"
                    done)"
        #shellcheck disable=SC2119
        _DEVS="$(_finddevices)"
        if [[ -n "${_LVM_BLACKLIST}" ]]; then
            for dev in ${_LVM_BLACKLIST}; do
                _DEVS="${_DEVS//$(${_LSBLK} NAME,SIZE -d "${dev}" 2>"${_NO_LOG}")/}"
            done
        fi
        # break if all devices are in use
        if [[ -z "${_DEVS}" ]]; then
            _dialog --msgbox "No devices left for physical volume creation." 0 0
            return 1
        fi
        # select the first device to use
        _DEVNUMBER=1
        #shellcheck disable=SC2086
        _dialog --menu "Select device number ${_DEVNUMBER} for physical volume:" 15 50 12 ${_DEVS} 2>"${_ANSWER}" || return 1
        _DEV=$(cat "${_ANSWER}")
        echo "${_DEV}" >>/tmp/.pvs-create
        while [[ "${_DEV}" != "> DONE" ]]; do
            _DEVNUMBER="$((_DEVNUMBER + 1))"
            # clean loop from used partition and options
            _DEVS="${_DEVS//$(${_LSBLK} NAME,SIZE -d "${_DEV}" 2>"${_NO_LOG}")/}"
            # add more devices
            #shellcheck disable=SC2086
            _dialog --no-cancel --menu "Select additional device number ${_DEVNUMBER} for physical volume:" 15 60 12 \
                ${_DEVS} "> DONE" "Proceed To Summary" 2>"${_ANSWER}" || return 1
            _DEV=$(cat "${_ANSWER}")
            [[ "${_DEV}" == "> DONE" ]] && break
            echo "${_DEV}" >>/tmp/.pvs-create
        done
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to create physical volume on devices below?\n$(sed -e 's#$#\\n#g' /tmp/.pvs-create)" 0 0 && break
    done
    _DEV="$(echo -n "$(cat /tmp/.pvs-create)")"
    #shellcheck disable=SC2028,SC2086
    _umountall
    #shellcheck disable=SC2086
    if pvcreate -y ${_DEV} &>"${_LOG}"; then
        _dialog --no-mouse --infobox "Creating physical volume on ${_DEV} was successful." 3 75
        sleep 3
    else
        _dialog --title " ERROR " --no-mouse --infobox "Creating physical volume on ${_DEV} failed." 3 60
        sleep 5
        return 1
    fi
    # run udevadm to get values exported
    udevadm trigger
    udevadm settle
}

#find physical volumes that are not in use
_findpv()
{
    for dev in $(${_LSBLK} NAME,FSTYPE | grep " LVM2_member$" | cut -d ' ' -f1 | sort -u); do
        # exclude checks:
        #-  not part of running lvm2
        # ! "$(${_LSBLK} TYPE ${dev} 2>"${_NO_LOG}" | grep "lvm")"
        #- not part of volume group
        # $(pvs -o vg_name --noheading ${dev} | grep " $")
        if ! ${_LSBLK} TYPE "${dev}" 2>"${_NO_LOG}" | grep -q "lvm" && pvs -o vg_name --noheading "${dev}" | grep -q " $"; then
            ${_LSBLK} NAME,SIZE "${dev}"
        fi
    done
}

#find volume groups that are not already full in use
_findvg()
{
    for dev in $(vgs -o vg_name --noheading); do
        if ! vgs -o vg_free --noheading --units m "${dev}" | grep -q " 0m$"; then
            #shellcheck disable=SC2028
            echo "${dev} $(vgs -o vg_free --noheading --units m "${dev}")"
        fi
    done
}

_createvg()
{
    while true; do
        : >/tmp/.pvs
        _PVS=$(_findpv)
        # break if all devices are in use
        if [[ -z "${_PVS}" ]]; then
            _dialog --msgbox "No devices left for Volume Group creation." 0 0
            return 1
        fi
        # enter volume group name
        _VGDEV=""
        while [[ -z "${_VGDEV}" ]]; do
            _dialog --inputbox "Enter the Volume Group name:\nfoogroup\n<yourvolumegroupname>\n\n" 11 40 "foogroup" 2>"${_ANSWER}" || return 1
            _VGDEV=$(cat "${_ANSWER}")
            if vgs -o vg_name --noheading | grep -q "^  ${_VGDEV}"; then
                _dialog --msgbox "ERROR: You have defined 2 identical Volume Group names! Please enter another name." 8 65
                _VGDEV=""
            fi
        done
        # show all devices with sizes, which are not in use
        # select the first device to use, no missing option available!
        _PVNUMBER=1
        #shellcheck disable=SC2086
        _dialog --no-cancel --menu "Select Physical Volume ${_PVNUMBER} for ${_VGDEV}:" 13 50 10 ${_PVS} 2>"${_ANSWER}" || return 1
        _PV=$(cat "${_ANSWER}")
        echo "${_PV}" >>/tmp/.pvs
        while [[ "${_PVS}" != "> DONE" ]]; do
            _PVNUMBER=$((_PVNUMBER + 1))
            # clean loop from used partition and options
            _PVS="${_PVS//$(${_LSBLK} NAME,SIZE -d "${_PV}" 2>"${_NO_LOG}")/}"
            # add more devices
            #shellcheck disable=SC2086
            _dialog --no-cancel --menu "Select additional Physical Volume ${_PVNUMBER} for ${_VGDEV}:" 13 50 10 \
                ${_PVS} "> DONE" "Proceed To Summary" 2>"${_ANSWER}" || return 1
            _PV=$(cat "${_ANSWER}")
            [[ "${_PV}" == "> DONE" ]] && break
            echo "${_PV}" >>/tmp/.pvs
        done
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to create Volume Group like this?\n\n${_VGDEV}\n\nPhysical Volumes:\n$(sed -e 's#$#\\n#g' /tmp/.pvs)" 0 0 && break
    done
    _PV="$(echo -n "$(cat /tmp/.pvs)")"
    _umountall
    #shellcheck disable=SC2086
    if vgcreate ${_VGDEV} ${_PV} &>"${_LOG}"; then
        _dialog --no-mouse --infobox "Creating Volume Group ${_VGDEV} was successful." 3 60
        sleep 3
    else
        _dialog --msgbox "Error while creating Volume Group ${_VGDEV} (see ${_LOG} for details)." 0 0
        return 1
    fi
}

_createlv()
{
    while true; do
        _LVS=$(_findvg)
        # break if all devices are in use
        if [[ -z "${_LVS}" ]]; then
            _dialog --msgbox "No Volume Groups with free space available for Logical Volume creation." 0 0
            return 1
        fi
        # show all devices with sizes, which are not 100% in use!
        #shellcheck disable=SC2086
        _dialog --menu "Select Volume Group:" 11 50 5 ${_LVS} 2>"${_ANSWER}" || return 1
        _LV=$(cat "${_ANSWER}")
        # enter logical volume name
        _LVDEV=""
        while [[ -z "${_LVDEV}" ]]; do
            _dialog --no-cancel --inputbox "Enter the Logical Volume name:\nfooname\n<yourvolumename>\n\n" 10 65 "fooname" 2>"${_ANSWER}" || return 1
            _LVDEV=$(cat "${_ANSWER}")
            if lvs -o lv_name,vg_name --noheading | grep -q " ${_LVDEV} ${_LV}$"; then
                _dialog --msgbox "ERROR: You have defined 2 identical Logical Volume names! Please enter another name." 8 65
                _LVDEV=""
            fi
        done
        while true; do
            _LV_ALL=""
            _dialog --no-cancel --inputbox "Enter the size (M/MiB) of your Logical Volume,\nMinimum value is > 0.\n\nVolume space left: $(vgs -o vg_free --noheading --units M "${_LV}")\n\nIf you enter no value, all free space left will be used." 12 65 "" 2>"${_ANSWER}" || return 1
                _LV_SIZE=$(cat "${_ANSWER}")
                if [[ -z "${_LV_SIZE}" ]]; then
                    _LV_ALL=1
                    break
                elif [[ "${_LV_SIZE}" == 0 ]]; then
                    _dialog --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${_LV_SIZE}" -ge "$(vgs -o vg_free --noheading --units M | sed -e 's#m##g')" ]]; then
                        _dialog --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                    else
                        break
                    fi
                fi
        done
        #Contiguous doesn't work with +100%FREE
        _LV_CONTIGUOUS=""
        if [[ -z "${_LV_ALL}" ]]; then
            _dialog --defaultno --yesno "Would you like to create Logical Volume as a contiguous partition, that means that your space doesn't get partitioned over one or more disks nor over non-contiguous physical extents.\n(usefull for swap space etc.)?" 0 0 && _LV_CONTIGUOUS=1
        fi
        if [[ -n "${_LV_CONTIGUOUS}" ]]; then
            _CONTIGUOUS=yes
            _LV_EXTRA="-W y -C y -y"
        else
            _CONTIGUOUS=no
            _LV_EXTRA="-W y -y"
        fi
        [[ -z "${_LV_SIZE}" ]] && _LV_SIZE="All free space left"
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to create Logical Volume ${_LVDEV} like this?\nVolume Group: ${_LV}\nVolume Size: ${_LV_SIZE}\nContiguous Volume: ${_CONTIGUOUS}" 0 0 && break
    done
    _umountall
    if [[ -n "${_LV_ALL}" ]]; then
        #shellcheck disable=SC2086
        if lvcreate ${_LV_EXTRA} -l +100%FREE ${_LV} -n ${_LVDEV} &>"${_LOG}"; then
            _dialog --no-mouse --infobox "Creating Logical Volume ${_LVDEV} was successful." 3 60
            sleep 3
        else
            _dialog --msgbox "Error while creating Logical Volume ${_LVDEV} (see ${_LOG} for details)." 0 0
            return 1
        fi
    else
        #shellcheck disable=SC2086
        if lvcreate ${_LV_EXTRA} -L ${_LV_SIZE} ${_LV} -n ${_LVDEV} &>"${_LOG}"; then
            _dialog --no-mouse --infobox "Creating Logical Volume ${_LVDEV} was successful." 3 60
            sleep 3
        else
            _dialog --msgbox "Error while creating Logical Volume ${_LVDEV} (see ${_LOG} for details)." 0 0
            return 1
        fi
    fi
}

_enter_luks_name() {
    _LUKSDEV=""
    while [[ -z "${_LUKSDEV}" ]]; do
        _dialog --no-cancel --inputbox "Enter the name for luks encrypted device ${_DEV}:\nfooname\n<yourname>\n\n" 10 65 "fooname" 2>"${_ANSWER}" || return 1
        _LUKSDEV=$(cat "${_ANSWER}")
        if ! cryptsetup status "${_LUKSDEV}" | grep -q inactive; then
            _dialog --msgbox "ERROR: You have defined 2 identical luks encryption device names! Please enter another name." 8 65
            _LUKSDEV=""
        fi
    done
}

_enter_luks_passphrase () {
    _LUKSPASS=""
    _LUKSPASS2=""
    while true; do
        while [[ -z "${_LUKSPASS}" ]]; do
            _dialog --no-cancel --insecure --passwordbox "Enter passphrase for luks encrypted device ${_LUKSDEV}:" 8 70 2>"${_ANSWER}" || return 1
            _LUKSPASS=$(cat "${_ANSWER}")
        done
        while [[ -z "${_LUKSPASS2}" ]]; do
            _dialog --no-cancel --insecure --passwordbox "Retype passphrase for luks encrypted device ${_LUKSDEV}:" 8 70 2>"${_ANSWER}" || return 1
            _LUKSPASS2=$(cat "${_ANSWER}")
        done
        if [[ "${_LUKSPASS}" == "${_LUKSPASS2}" ]]; then
            _LUKSPASSPHRASE=${_LUKSPASS}
            echo "${_LUKSPASSPHRASE}" > "/tmp/passphrase-${_LUKSDEV}"
            _LUKSPASSPHRASE="/tmp/passphrase-${_LUKSDEV}"
            break
        else
             _dialog --no-mouse --infobox "Passphrases didn't match, please enter again." 0 0
             sleep 3
            _LUKSPASS=""
            _LUKSPASS2=""
        fi
    done
}

_opening_luks() {
    _dialog --no-mouse --infobox "Opening encrypted ${_DEV}..." 0 0
    while true; do
        cryptsetup luksOpen "${_DEV}" "${_LUKSDEV}" <"${_LUKSPASSPHRASE}" >"${_LOG}" && break
        _dialog --no-mouse --infobox "Error: Passphrase didn't match, please enter again" 0 0
        sleep 5
        _enter_luks_passphrase || return 1
    done
    if _dialog --yesno "Would you like to save the passphrase of luks device in /etc/$(basename "${_LUKSPASSPHRASE}")?\nName:${_LUKSDEV}" 0 0; then
        echo "${_LUKSDEV}" "${_DEV}" "/etc/$(basename "${_LUKSPASSPHRASE}")" >> /tmp/.crypttab
    fi
}

_helpluks()
{
_dialog --msgbox "$(cat /usr/lib/archboot/installer/help/luks.txt)" 0 0
}

_createluks()
{
    while true; do
        _activate_special_devices
        _dialog --no-mouse --infobox "Scanning blockdevices... This may need some time." 3 60
        # Remove all crypt devices with children
        _LUKS_BLACKLIST="$(for dev in $(${_LSBLK} NAME,TYPE | grep " crypt$" | cut -d ' ' -f1 | sort -u); do
                    echo "${dev}"
                    done)"
        #shellcheck disable=SC2119
         _DEVS="$(_finddevices)"
        if [[ -n "${_LUKS_BLACKLIST}" ]]; then
            for dev in ${_LUKS_BLACKLIST}; do
                _DEVS="${_DEVS//$(${_LSBLK} NAME,SIZE -d "${dev}" 2>"${_NO_LOG}")/}"
            done
        fi
        # break if all devices are in use
        if [[ -z "${_DEVS}" ]]; then
            _dialog --msgbox "No devices left for luks encryption." 0 0
            return 1
        fi
        # show all devices with sizes
        #shellcheck disable=SC2086
        _dialog --menu "Select device for luks encryption:" 15 50 12 ${_DEVS} 2>"${_ANSWER}" || return 1
        _DEV=$(cat "${_ANSWER}")
        # enter luks name
        _enter_luks_name || return 1
        ### TODO: offer more options for encrypt!
        ###       defaults are used only
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to encrypt luks device below?\nName:${_LUKSDEV}\nDevice:${_DEV}\n" 0 0 && break
    done
    _enter_luks_passphrase || return 1
    _umountall
    _dialog --no-mouse --infobox "Encrypting ${_DEV}..." 0 0
    cryptsetup -q luksFormat "${_DEV}" <"${_LUKSPASSPHRASE}" >"${_LOG}"
    _opening_luks
}
# vim: set ft=sh ts=4 sw=4 et:
