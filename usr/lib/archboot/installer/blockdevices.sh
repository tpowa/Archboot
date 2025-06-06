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
     for dev in $(${_LSBLK} NAME,TYPE | rg '(.*) disk$' -r '$1'); do
        # exclude checks:
        #- iso9660 devices
        #  (${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | rg 'iso9660'
        #- fakeraid isw devices
        #  ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | rg 'isw_raid_member'
        #- fakeraid ddf devices
        #  ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | rg 'ddf_raid_member'
        # - zram devices
        #   rg -q 'zram' <<< "${dev}"
        if ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'iso9660' &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'isw_raid_member' &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'ddf_raid_member' &&\
            ! rg -q 'zram' <<< "${dev}"; then
                ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
     done
}

# lists linux blockdevice partitions
_blockdevices_partitions() {
    # all available block devices partitions
    for dev in $(${_LSBLK} NAME,TYPE | rg -v '^/dev/md' | rg '(.*) part$' -r '$1'); do
        # exclude checks:
        #- part of raid device
        #  ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | rg 'linux_raid_member'
        #- part of lvm2 device
        #  ${_LSBLK} FSTYPE /dev/${dev} 2>"${_NO_LOG}" | rg 'LVM2_member'
        #- part of luks device
        #  ${_LSBLK} FSTYPE /dev/${dev} 2>"${_NO_LOG}" | rg 'crypto_LUKS'
        #- extended partition
        #  sfdisk -l 2>"${_NO_LOG}" | rg "${dev}" | rg 'Extended$'
        # - extended partition (LBA)
        #   sfdisk -l 2>"${_NO_LOG}" | rg "${dev}" | rg '\(LBA\)$'
        #- bios_grub partitions
        #  sfdisk -l 2>"${_NO_LOG}" | rg "${dev}" | rg -q 'BIOS boot$'
        #- iso9660 devices
        #  "${_LSBLK} FSTYPE -s ${dev} | rg 'iso9660'
        if ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'linux_raid_member' &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'LVM2_member' &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'crypto_LUKS' &&\
            ! ${_LSBLK} FSTYPE -s "${dev}" 2>"${_NO_LOG}" | rg -q 'iso9660' &&\
            ! sfdisk -l 2>"${_NO_LOG}" | rg "${dev}" | rg -q 'Extended$' &&\
            ! sfdisk -l 2>"${_NO_LOG}" | rg "${dev}" | rg -q '\(LBA\)$' &&\
            ! sfdisk -l 2>"${_NO_LOG}" | rg "${dev}" | rg -q 'BIOS boot$'; then
                ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
}

# list none partitionable raid md devices
_raid_devices() {
    for dev in $(${_LSBLK} NAME,TYPE | rg '(.*) raid.*$|(.*) linear$' -r '$1' | sort -u); do
        # exclude checks:
        # - part of lvm2 device_found
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | rg 'LVM2_member'
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | rg 'crypto_LUKS'
        # - part of isw fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s 2>"${_NO_LOG}" | rg 'isw_raid_member'
        # - part of ddf fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s 2>"${_NO_LOG}" | rg 'ddf_raid_member'
        if ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'LVM2_member' &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'crypto_LUKS' &&\
            ! ${_LSBLK} FSTYPE "${dev}" -s 2>"${_NO_LOG}" | rg -q 'isw_raid_member' &&\
            ! ${_LSBLK} FSTYPE "${dev}" -s 2>"${_NO_LOG}" | rg -q 'ddf_raid_member' &&\
            ! fd "${dev}p.*" /dev 2>"${_NO_LOG}"; then
                ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
}

# lists linux partitionable raid devices partitions
_partitionable_raid_devices_partitions() {
    for dev in $(${_LSBLK} NAME,TYPE | rg 'part$' | rg -o '(^/dev/md.*p.*) ' -r '$1' 2>"${_NO_LOG}" | sort -u) ; do
        # exclude checks:
        # - part of lvm2 device_found
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | rg 'LVM2_member'
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | rg 'crypto_LUKS'
        # - extended partition
        #   sfdisk -l 2>"${_NO_LOG}" 2>"${_NO_LOG}" | rg "${dev}" | rg 'Extended$'
        # - extended partition (LBA)
        #   sfdisk -l 2>"${_NO_LOG}" 2>"${_NO_LOG}" | rg "${dev}" | rg '\(LBA\)$'
        # - part of isw fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s 2>"${_NO_LOG}" | rg 'isw_raid_member'
        # - part of ddf fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s 2>"${_NO_LOG}" | rg 'ddf_raid_member'
        if ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'LVM2_member' &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'crypto_LUKS' &&\
            ! sfdisk -l 2>"${_NO_LOG}" | rg "${dev}" | rg -q 'Extended$' &&\
            ! sfdisk -l 2>"${_NO_LOG}" | rg "${dev}" | rg -q '\(LBA\)$' &&\
            ! ${_LSBLK} FSTYPE "${dev}" -s 2>"${_NO_LOG}" | rg -q 'isw_raid_member' &&\
            ! ${_LSBLK} FSTYPE "${dev}" -s 2>"${_NO_LOG}" | rg -q 'ddf_raid_member'; then
                ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
}

_dmraid_devices() {
    # ddf_raid_member or isw_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE | rg '(.*) raid.*$' -r '$1' | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" 2>"${_NO_LOG}" | rg -q 'ddf_raid_member$|isw_raid_member$'; then
            ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
}

_dmraid_partitions() {
    # ddf_raid_member or isw_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE | rg '(.*) md$' -r '$1' | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" 2>"${_NO_LOG}" | rg 'ddf_raid_member$|isw_raid_member$'; then
            ${_LSBLK} NAME,SIZE -d "${dev}"
        fi
    done
}

# dm_devices
# - show device mapper devices:
#   lvm2 and cryptdevices
_dm_devices() {
    for dev in $(${_LSBLK} NAME,TYPE | rg 'lvm$|crypt$' | rg '(.*) .*' -r '$1' | sort -u); do
        # exclude checks:
        # - part of lvm2 device
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | rg 'LVM2_member'
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | rg 'crypto_LUKS'
        # - part of raid device
        #   ${_LSBLK} FSTYPE ${dev} 2>"${_NO_LOG}" | rg 'linux_raid_member$'
        # - part of running raid on encrypted device
        #   ${_LSBLK} TYPE ${dev} 2>"${_NO_LOG}" | rg 'raid.*$'
        if ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'crypto_LUKS$' &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'LVM2_member$' &&\
            ! ${_LSBLK} FSTYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'linux_raid_member$' &&\
            ! ${_LSBLK} TYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'raid.*$'; then
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
        # write to template
        { echo " lvm vgscan --ignorelockingfailure &>\"\${_NO_LOG}\""
        echo "lvm vgchange --ignorelockingfailure --ignoremonitoring -ay &>\"\${_NO_LOG}\""
        } >> "${_TEMPLATE}"
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
        # write to template
        echo "mdadm --assemble --scan &>\"\${_NO_LOG}\"" >> "${_TEMPLATE}"
    fi
}

_activate_luks()
{
    _LUKS_READY=""
    if [[ -e /usr/bin/cryptsetup ]]; then
        _dialog --no-mouse --infobox "Scanning for luks encrypted devices..." 0 0
        if ${_LSBLK} FSTYPE | rg -q 'crypto_LUKS'; then
            for part in $(${_LSBLK} NAME,FSTYPE | rg '(.*) crypto_LUKS$' -r '$1'); do
                # skip already encrypted devices, device mapper!
                if ! ${_LSBLK} TYPE "${part}" 2>"${_NO_LOG}" | rg -q 'crypt$'; then
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
    _NAME_SCHEME_LEVELS=()
    ## util-linux root=PARTUUID=/root=PARTLABEL= support - https://git.kernel.org/?p=utils/util-linux/util-linux.git;a=commitdiff;h=fc387ee14c6b8672761ae5e67ff639b5cae8f27c;hp=21d1fa53f16560dacba33fffb14ffc05d275c926
    ## mkinitcpio's init root=PARTUUID= support - https://projects.archlinux.org/mkinitcpio.git/tree/init_functions#n185
    if [[ -n "${_UEFI_BOOT}" || -n "${_GUIDPARAMETER}" ]]; then
        _NAME_SCHEME_LEVELS+=('PARTUUID' 'PARTUUID=<partuuid>' 'PARTLABEL' 'PARTLABEL=<partlabel>' 'SD_GPT_AUTO_GENERATOR' 'none')
    fi
    _NAME_SCHEME_LEVELS+=('FSUUID' 'UUID=<uuid>' 'FSLABEL' 'LABEL=<label>' 'KERNEL' '/dev/<kernelname>')
    _dialog --no-cancel --title " Device Name Scheme " --menu "Use PARTUUID on GPT disks. Use FSUUID on MBR/MSDOS disks." 13 65 7 "${_NAME_SCHEME_LEVELS[@]}" 2>"${_ANSWER}" || return 1
    _NAME_SCHEME_PARAMETER=$(cat "${_ANSWER}")
    _NAME_SCHEME_PARAMETER_RUN=1
}

# Disable swap and all mounted partitions for the destination system. Unmount
# the destination root partition last!
_umountall()
{
    if [[ "${_DESTDIR}" == "/mnt/install" ]]; then
        if rg 'partition' /proc/swaps || rg 'file' /proc/swaps; then
            swapoff -a &>"${_NO_LOG}"
            _dialog --no-mouse --infobox "Disabled swapspace..." 3 70
            # write to template
            echo "swapoff -a &>\"\${_NO_LOG}\"" >> "${_TEMPLATE}"
            sleep 2
        fi
        if mountpoint -q "/mnt/install"; then
            umount -R "${_DESTDIR}" &>"${_NO_LOG}"
            _dialog --no-mouse --infobox "Unmounted already mounted disk devices in ${_DESTDIR}..." 3 70
            # write to template
            echo "umount -R \"\${_DESTDIR}\" &>\"\${_NO_LOG}\"" >> "${_TEMPLATE}"
            sleep 2
        fi
    fi
}

_clean_disk() {
    _umountall
    # clear all magic strings/signatures - mdadm, lvm, partition tables etc
    wipefs -a -f "${1}" &>"${_NO_LOG}"
    # really clear everything MBR/GPT at the beginning of the device!
    dd if=/dev/zero of="${1}" bs=1M count=10 &>"${_NO_LOG}"
    sync
    # write to template
    { echo "wipefs -a -f \"${1}\" &>\"\${_NO_LOG}\""
    echo "dd if=/dev/zero of=\"${1}\" bs=1M count=10 &>\"\${_NO_LOG}\""
    echo "sync"
    } >> "${_TEMPLATE}"
}

_stopmd()
{
    _DISABLEMD=""
    if rg -q '^md' /proc/mdstat 2>"${_NO_LOG}"; then
        _dialog --defaultno --yesno "Setup detected already running software raid device(s)...\n\nDo you want to delete ALL of them completely?\nWARNING: ALL DATA ON THEM WILL BE LOST!" 0 0 && _DISABLEMD=1
        if [[ -n "${_DISABLEMD}" ]]; then
            _umountall
            # write to template
            echo "### remove all md devices" >> "${_TEMPLATE}"
            for dev in $(rg -o '(^md.*) :' -r '$1' /proc/mdstat); do
                wipefs -a -f "/dev/${dev}" &>"${_NO_LOG}"
                mdadm --manage --stop "/dev/${dev}" &>"${_LOG}"
                # write to template
                { echo "wipefs -a -f \"/dev/${dev}\" &>\"\${_NO_LOG}\""
                echo "mdadm --manage --stop \"/dev/${dev}\" &>\"\${_LOG}\""
                } >> "${_TEMPLATE}"
            done
            _dialog --no-mouse --infobox "Removing software raid device(s) done." 3 50
            sleep 3
        fi
    fi
    _DISABLEMDSB=""
    if ${_LSBLK} FSTYPE | rg -q 'linux_raid_member'; then
        _dialog --defaultno --yesno "Setup detected superblock(s) of software raid devices...\n\nDo you want to delete the superblock on ALL of them?\nWARNING: ALL DATA ON THEM WILL BE LOST!" 0 0 && _DISABLEMDSB=1
        if [[ -n "${_DISABLEMDSB}" ]]; then
            _umountall
        fi
    fi
    if [[ -n "${_DISABLEMD}" || -n "${_DISABLEMDSB}" ]]; then
        for dev in $(${_LSBLK} NAME,FSTYPE | rg '(.*) linux_raid_member$' -r '$1'); do
            _clean_disk "${dev}"
        done
        # write to template
        echo "" >> "${_TEMPLATE}"
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
        # write to template
        echo "### remove all lvm devices" >> "${_TEMPLATE}"
        for dev in ${_LV_VOLUMES}; do
            lvremove -f "/dev/mapper/${dev}" 2>"${_NO_LOG}">"${_LOG}"
            # write to template
            echo "lvremove -f \"/dev/mapper/${dev}\" 2>\"\${_NO_LOG}\">\"\${_LOG}\"" >> "${_TEMPLATE}"
        done
        for dev in ${_LV_GROUPS}; do
            vgremove -f "${dev}" 2>"${_NO_LOG}" >"${_LOG}"
            # write to template
            echo "vgremove -f \"${dev}\" 2>\"\${_NO_LOG}\" >\"\${_LOG}\"" >> "${_TEMPLATE}"
        done
        for dev in ${_LV_PHYSICAL}; do
            pvremove -f "${dev}" 2>"${_NO_LOG}" >"${_LOG}"
            # write to template
            echo "pvremove -f \"${dev}\" 2>\"\${_NO_LOG}\" >\"\${_LOG}\"" >> "${_TEMPLATE}"
        done
        # write to template
        echo "" >> "${_TEMPLATE}"
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
    _LUKSDEV="$(${_LSBLK} NAME,TYPE | rg '(.*) crypt$' -r '$1')"
    [[ -z "${_LUKSDEV}" ]] || _DETECTED_LUKS=1
    if [[ -n "${_DETECTED_LUKS}" ]]; then
        _dialog --defaultno --yesno "Setup detected running luks encrypted device(s)...\n\nDo you want to delete ALL of them completely?\nWARNING: ALL DATA ON THEM WILL BE LOST!" 0 0 && _DISABLELUKS=1
    fi
    if [[ -n "${_DISABLELUKS}" ]]; then
        # write to template
        echo "### remove all luks devices" >> "${_TEMPLATE}"
        _umountall
        for dev in ${_LUKSDEV}; do
            _LUKS_REAL_DEV="$(${_LSBLK} NAME,FSTYPE -s "${_LUKSDEV}" 2>"${_NO_LOG}" | rg '(.*) crypto_LUKS$' -r '$1')"
            cryptsetup remove "${dev}" >"${_LOG}"
            # delete header from device
            wipefs -a "${_LUKS_REAL_DEV}" &>"${_NO_LOG}"
            # write to template
            { echo "cryptsetup remove \"${dev}\" >\"\${_LOG}\""
            echo "wipefs -a \"${_LUKS_REAL_DEV}\" &>\"\${_NO_LOG}\""
            echo ""
            } >> "${_TEMPLATE}"
        done
        _dialog --no-mouse --infobox "Removing luks encrypted device(s) done." 3 50
        sleep 3
    fi
    _DISABLELUKS=""
    _DETECTED_LUKS=""
    # detect not running luks devices
    ${_LSBLK} FSTYPE | rg -q "crypto_LUKS" && _DETECTED_LUKS=1
    if [[ -n "${_DETECTED_LUKS}" ]]; then
        _dialog --defaultno --yesno "Setup detected not running luks encrypted device(s)...\n\nDo you want to delete ALL of them completely?\nWARNING: ALL DATA ON THEM WILL BE LOST!" 0 0 && _DISABLELUKS=1
    fi
    if [[ -n "${_DISABLELUKS}" ]]; then
        for dev in $(${_LSBLK} NAME,FSTYPE | rg '(.*) crypto_LUKS$' -r '$1'); do
           # delete header from device
           wipefs -a "${dev}" &>"${_NO_LOG}"
           # write to template
           echo "wipefs -a \"${dev}\" &>\"\${_NO_LOG}\"" >> "${_TEMPLATE}"
        done
        _dialog --no-mouse --infobox "Removing not running luks encrypted device(s) done." 3 60
        # write to template
        { echo ": > /tmp/.crypttab"
        echo ""
        } >> "${_TEMPLATE}"
        : > /tmp/.crypttab
        sleep 3
    fi
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
        _RAID_BLACKLIST=()
        for i in $(_raid_devices) $(_partitionable_raid_devices_partitions); do
            _RAID_BLACKLIST+=("${i}")
        done
        _DEVS=()
        for i in $(_finddevices); do
            _DEVS+=("${i}")
        done
        if [[ -n "${_RAID_BLACKLIST[*]}" ]]; then
            for i in "${_RAID_BLACKLIST[@]}"; do
                _remove_from_devs "${i}"
            done
        fi
        # break if all devices are in use
        if [[ -z "${_DEVS[*]}" ]]; then
            _dialog --msgbox "All devices in use. No more devices left for new creation." 0 0
            return 1
        fi
        # enter raid device name
        _RAIDDEV=""
        while [[ -z "${_RAIDDEV}" ]]; do
            _dialog --inputbox "Enter the node name for the raiddevice:\n/dev/md[number]\n/dev/md0\n/dev/md1\n\n" 12 50 "/dev/md0" 2>"${_ANSWER}" || return 1
            _RAIDDEV=$(cat "${_ANSWER}")
            if rg -q "^${_RAIDDEV//\/dev\//}" /proc/mdstat 2>"${_NO_LOG}"; then
                _dialog --msgbox "ERROR: You have defined 2 identical node names! Please enter another name." 8 65
                _RAIDDEV=""
            fi
        done
        _RAIDLEVELS=(linear - raid0 - raid1 - raid4 - raid5 - raid6 - raid10 -)
        _dialog --no-cancel --menu "Select the raid level you want to use:" 14 50 7 "${_RAIDLEVELS[@]}" 2>"${_ANSWER}" || return 1
        _LEVEL=$(cat "${_ANSWER}")
        # raid5 and raid10 support parity parameter
        _PARITY=""
        if [[ "${_LEVEL}" == "raid5" || "${_LEVEL}" == "raid6" || "${_LEVEL}" == "raid10" ]]; then
            _PARITYLEVELS=(left-asymmetric - left-symmetric - right-asymmetric - right-symmetric -)
            _dialog --no-cancel --menu "Select the parity layout you want to use (default is left-symmetric):" 21 50 13 "${_PARITYLEVELS[@]}" 2>"${_ANSWER}" || return 1
            _PARITY=$(cat "${_ANSWER}")
        fi
        # select the first device to use, no missing option available!
        _RAIDNUMBER=1
        _DEGRADED=""
        _dialog --no-cancel --menu "Select device ${_RAIDNUMBER}:" 21 50 13 "${_DEVS[@]}" 2>"${_ANSWER}" || return 1
        _DEV=$(cat "${_ANSWER}")
        echo "${_DEV}" >>/tmp/.raid
        while true; do
            _RAIDNUMBER=$((_RAIDNUMBER + 1))
            if [[ -n "${_DEV}" ]]; then
                # clean loop from used partition and options
                _remove_from_devs "${_DEV}"
            fi
            # add more devices
            # raid0 doesn't support missing devices
            if [[ "${_LEVEL}" == "raid0" || "${_LEVEL}" == "linear" || -n "${_DEGRADED}" ]]; then
                _dialog --no-cancel --menu "Select additional device ${_RAIDNUMBER}:" \
                21 50 13 "${_DEVS[@]}" "> DONE" "Proceed To Summary" 2>"${_ANSWER}" || return 1
            else
                _dialog --no-cancel --menu "Select additional device ${_RAIDNUMBER}:" \
                21 50 13 "${_DEVS[@]}" "> MISSING" "Degraded Raid Device" "> DONE" "Proceed To Summary" 2>"${_ANSWER}" || return 1
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
                else
                    echo "${_DEV}" >>/tmp/.raid
                fi
            fi
        done
    mapfile -t _DEVS < <(cat /tmp/.raid)
    mapfile -t _SPARES < <(cat /tmp/.raid-spare)
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to create ${_RAIDDEV} like this?\n\nLEVEL:\n${_LEVEL}\n\nDEVICES:\n${_DEVS[*]}\nSPARES:\n${_SPARES[*]}" 0 0 && break
    done
    _umountall
    # get number of devices
    _RAID_DEVS="${#_DEVS[@]}"
    _SPARE_DEVS="${#_SPARES[@]}"
    # combine both if spares are available, spares at the end!
    [[ -n ${_SPARES[*]} ]] && _DEVS=("${_DEVS[@]}" "${_SPARES[@]}")
    # generate options for mdadm
    _RAIDOPTIONS=(--force --run --level="${_LEVEL}")
    ! [[ "${_RAID_DEVS}" == 0 ]] && _RAIDOPTIONS+=(--raid-devices="${_RAID_DEVS}")
    ! [[ "${_SPARE_DEVS}" == 0 ]] && _RAIDOPTIONS+=(--spare-devices="${_SPARE_DEVS}")
    [[ -n "${_PARITY}" ]] && _RAIDOPTIONS+=(--layout="${_PARITY}")
    if mdadm --create "${_RAIDDEV}" "${_RAIDOPTIONS[@]}" "${_DEVS[@]}" &>"${_LOG}"; then
        _dialog --no-mouse --infobox "${_RAIDDEV} created successfully." 3 50
        sleep 3
        { echo "### mdadm device"
        echo "mdadm --create ${_RAIDDEV} ${_RAIDOPTIONS[*]} ${_DEVS[*]} &>\"\${_LOG}\""
        echo ""
        } >> "${_TEMPLATE}"
    else
        _dialog --title " ERROR " --no-mouse --infobox "Creating ${_RAIDDEV} failed." 3 60
        sleep 5
        return 1
    fi
    if [[ -n "${_RAID_PARTITION}" ]]; then
        # switch for mbr usage
        _set_guid
        _DISK="${_RAIDDEV}"
        if [[ -z "${_GUIDPARAMETER}" ]]; then
            _dialog --msgbox "Now you'll be put into the cfdisk program where you can partition your raiddevice to your needs." 6 70
            _cfdisk
        else
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
        _LVM_BLACKLIST=()
        # Remove all lvm devices with children
        for i in $(${_LSBLK} NAME,TYPE | rg '(.*) lvm$' -r '$1' | sort -u); do
            _LVM_BLACKLIST+=("${i}")
        done
        _DEVS=()
        for i in $(_finddevices); do
            _DEVS+=("${i}")
        done
        if [[ -n "${_LVM_BLACKLIST[*]}" ]]; then
            for i in "${_LVM_BLACKLIST[@]}"; do
                _remove_from_devs "${i}"
            done
        fi
        # break if all devices are in use
        if [[ -z "${_DEVS[*]}" ]]; then
            _dialog --msgbox "No devices left for physical volume creation." 0 0
            return 1
        fi
        # select the first device to use
        _DEVNUMBER=1
        _dialog --menu "Select device number ${_DEVNUMBER} for physical volume:" 15 50 12 "${_DEVS[@]}" 2>"${_ANSWER}" || return 1
        _DEV=$(cat "${_ANSWER}")
        echo "${_DEV}" >>/tmp/.pvs-create
        while [[ "${_DEV}" != "> DONE" ]]; do
            _DEVNUMBER="$((_DEVNUMBER + 1))"
            # clean loop from used partition and options
            _remove_from_devs "${_DEV}"
            # add more devices
            _dialog --no-cancel --menu "Select additional device number ${_DEVNUMBER} for physical volume:" 15 60 12 \
                "${_DEVS[@]}" "> DONE" "Proceed To Summary" 2>"${_ANSWER}" || return 1
            _DEV=$(cat "${_ANSWER}")
            [[ "${_DEV}" == "> DONE" ]] && break
            echo "${_DEV}" >>/tmp/.pvs-create
        done
        # final step ask if everything is ok?
        mapfile -t _PV_CREATE < <(cat /tmp/.pvs-create)
        _dialog --yesno "Would you like to create physical volume on devices below?\n${_PV_CREATE[*]}" 0 0 && break
    done
    _umountall
    if pvcreate -y "${_PV_CREATE[@]}" &>"${_LOG}"; then
        _dialog --no-mouse --infobox "Creating physical volume on ${_PV_CREATE[*]} was successful." 5 75
        # write to template
        { echo "### pv device"
        echo "pvcreate -y ${_PV_CREATE[*]} &>\"\${_LOG}\""
        } >> "${_TEMPLATE}"
        sleep 3
    else
        _dialog --title " ERROR " --no-mouse --infobox "Creating physical volume on ${_PV_CREATE[*]} failed." 5 60
        sleep 5
        return 1
    fi
    # run udevadm to get values exported
    udevadm trigger
    udevadm settle
    { echo "udevadm trigger"
    echo "udevadm settle"
    echo ""
    } >> "${_TEMPLATE}"
}

#find physical volumes that are not in use
_findpv()
{
    for dev in $(${_LSBLK} NAME,FSTYPE | rg '(.*) LVM2_member$' -r '$1' | sort -u); do
        # exclude checks:
        #-  not part of running lvm2
        # ! "$(${_LSBLK} TYPE ${dev} 2>"${_NO_LOG}" | rg -q 'lvm')"
        #- not part of volume group
        # $(pvs -o vg_name --noheading ${dev} | rg ' $')
        if ! ${_LSBLK} TYPE "${dev}" 2>"${_NO_LOG}" | rg -q 'lvm' && pvs -o vg_name --noheading "${dev}" | rg -q ' $'; then
            ${_LSBLK} NAME,SIZE "${dev}"
        fi
    done
}

#find volume groups that are not already full in use
_findvg()
{
    for dev in $(vgs -o vg_name --noheading); do
        if ! vgs -o vg_free --noheading --units m "${dev}" | rg -q ' 0m$'; then
            echo "${dev} $(vgs -o vg_free --noheading --units m "${dev}")"
        fi
    done
}

_createvg()
{
    while true; do
        : >/tmp/.pvs
        _PVS=()
        for i in $(_findpv); do
            _PVS+=("${i}")
        done
        # break if all devices are in use
        if [[ -z "${_PVS[*]}" ]]; then
            _dialog --msgbox "No devices left for Volume Group creation." 0 0
            return 1
        fi
        # enter volume group name
        _VGDEV=""
        while [[ -z "${_VGDEV}" ]]; do
            _dialog --inputbox "Enter the Volume Group name:\nfoogroup\n<yourvolumegroupname>\n\n" 11 40 "foogroup" 2>"${_ANSWER}" || return 1
            _VGDEV=$(cat "${_ANSWER}")
            if vgs -o vg_name --noheading | rg -q "^  ${_VGDEV}"; then
                _dialog --msgbox "ERROR: You have defined 2 identical Volume Group names! Please enter another name." 8 65
                _VGDEV=""
            fi
        done
        # show all devices with sizes, which are not in use
        # select the first device to use, no missing option available!
        _PVNUMBER=1
        _dialog --no-cancel --menu "Select Physical Volume ${_PVNUMBER} for ${_VGDEV}:" 13 50 10 "${_PVS[@]}" 2>"${_ANSWER}" || return 1
        _PV=$(cat "${_ANSWER}")
        echo "${_PV}" >>/tmp/.pvs
        while [[ "${_PV}" != "> DONE" ]]; do
            _PVNUMBER=$((_PVNUMBER + 1))
            # clean loop from used partition and options
            IFS=" " read -r -a _PVS <<< "$(sd "$(${_LSBLK} NAME,SIZE -d "${_PV}")" "" <<< "${_PVS[@]}")"
            # add more devices
            _dialog --no-cancel --menu "Select additional Physical Volume ${_PVNUMBER} for ${_VGDEV}:" 13 50 10 \
                "${_PVS[@]}" "> DONE" "Proceed To Summary" 2>"${_ANSWER}" || return 1
            _PV=$(cat "${_ANSWER}")
            [[ "${_PV}" == "> DONE" ]] && break
            echo "${_PV}" >>/tmp/.pvs
        done
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to create Volume Group like this?\n\n${_VGDEV}\n\nPhysical Volumes:\n$(rg '(.*$)' -r '$1\n' /tmp/.pvs)" 0 0 && break
    done
    mapfile -t _PV < <(cat /tmp/.pvs)
    _umountall
    if vgcreate "${_VGDEV}" "${_PV[@]}" &>"${_LOG}"; then
        _dialog --no-mouse --infobox "Creating Volume Group ${_VGDEV} was successful." 3 60
        # write to template
        { echo "### vg device"
        echo "vgcreate ${_VGDEV} ${_PV[*]} &>\"\${_LOG}\""
        echo ""
        } >> "${_TEMPLATE}"
        sleep 3
    else
        _dialog --msgbox "Error while creating Volume Group ${_VGDEV} (see ${_LOG} for details)." 0 0
        return 1
    fi
}

_createlv()
{
    while true; do
        _LVS=()
        for i in $(_findvg); do
            _LVS+=("${i}")
        done
        # break if all devices are in use
        if [[ -z "${_LVS[*]}" ]]; then
            _dialog --msgbox "No Volume Groups with free space available for Logical Volume creation." 0 0
            return 1
        fi
        # show all devices with sizes, which are not 100% in use!
        _dialog --menu "Select Volume Group:" 11 50 5 "${_LVS[@]}" 2>"${_ANSWER}" || return 1
        _LV=$(cat "${_ANSWER}")
        # enter logical volume name
        _LVDEV=""
        while [[ -z "${_LVDEV}" ]]; do
            _dialog --no-cancel --inputbox "Enter the Logical Volume name:\nfooname\n<yourvolumename>\n\n" 10 65 "fooname" 2>"${_ANSWER}" || return 1
            _LVDEV=$(cat "${_ANSWER}")
            if lvs -o lv_name,vg_name --noheading | rg -q " ${_LVDEV} ${_LV}$"; then
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
                    if [[ "${_LV_SIZE}" -ge "$(vgs -o vg_free --noheading --units M | sd 'm' '')" ]]; then
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
            _LV_EXTRA=(-W y -C y -y)
        else
            _CONTIGUOUS=no
            _LV_EXTRA=(-W y -y)
        fi
        [[ -z "${_LV_SIZE}" ]] && _LV_SIZE="All free space left"
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to create Logical Volume ${_LVDEV} like this?\nVolume Group: ${_LV}\nVolume Size: ${_LV_SIZE}\nContiguous Volume: ${_CONTIGUOUS}" 0 0 && break
    done
    _umountall
    if [[ -n "${_LV_ALL}" ]]; then
        if lvcreate "${_LV_EXTRA[@]}" -l +100%FREE "${_LV}" -n "${_LVDEV}" &>"${_LOG}"; then
            _dialog --no-mouse --infobox "Creating Logical Volume ${_LVDEV} was successful." 3 60
            # write to template
            { echo "### lv device"
            echo "lvcreate ${_LV_EXTRA[*]} -l +100%FREE ${_LV} -n ${_LVDEV} &>\"\${_LOG}\""
            echo ""
            } >> "${_TEMPLATE}"
            sleep 3
        else
            _dialog --msgbox "Error while creating Logical Volume ${_LVDEV} (see ${_LOG} for details)." 0 0
            return 1
        fi
    else
        if lvcreate "${_LV_EXTRA[@]}" -L "${_LV_SIZE}" "${_LV}" -n "${_LVDEV}" &>"${_LOG}"; then
            _dialog --no-mouse --infobox "Creating Logical Volume ${_LVDEV} was successful." 3 60
            # write to template
            { echo "### lv device"
            echo "lvcreate ${_LV_EXTRA[*]} -L ${_LV_SIZE} ${_LV} -n ${_LVDEV} &>\"\${_LOG}\""
            echo ""
            } >> "${_TEMPLATE}"
            sleep 3
        else
            _dialog --msgbox "Error while creating Logical Volume ${_LVDEV} (see ${_LOG} for details)." 0 0
            return 1
        fi
    fi
}

_enter_luks_name() {
    _LUKSDEV=""
    while [[ -z "${_LUKSNAME}" ]]; do
        _dialog --no-cancel --inputbox "Enter the name for luks encrypted device ${_LUKSDEVICE}:\nfooname\n<yourname>\n\n" 10 65 "fooname" 2>"${_ANSWER}" || return 1
        _LUKSNAME=$(cat "${_ANSWER}")
        if ! cryptsetup status "${_LUKSNAME}" | rg -q 'inactive'; then
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
            _dialog --no-cancel --insecure --passwordbox "Enter passphrase for luks encrypted device ${_LUKSNAME}:" 8 70 2>"${_ANSWER}" || return 1
            _LUKSPASS=$(cat "${_ANSWER}")
        done
        while [[ -z "${_LUKSPASS2}" ]]; do
            _dialog --no-cancel --insecure --passwordbox "Retype passphrase for luks encrypted device ${_LUKSNAME}:" 8 70 2>"${_ANSWER}" || return 1
            _LUKSPASS2=$(cat "${_ANSWER}")
        done
        if [[ "${_LUKSPASS}" == "${_LUKSPASS2}" ]]; then
            _LUKSPASSPHRASE=${_LUKSPASS}
            echo "${_LUKSPASSPHRASE}" > "/tmp/passphrase-${_LUKSNAME}"
            # write to template
            { echo "### luks device"
            echo "echo \"${_LUKSPASSPHRASE}\" > \"/tmp/passphrase-${_LUKSNAME}\""
            } >> "${_TEMPLATE}"
            _LUKSPASSPHRASE="/tmp/passphrase-${_LUKSNAME}"
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
    _dialog --no-mouse --infobox "Opening encrypted ${_LUKSDEVICE}..." 0 0
    while true; do
        if cryptsetup luksOpen "${_LUKSDEVICE}" "${_LUKSNAME}" <"${_LUKSPASSPHRASE}" >"${_LOG}"; then
            # write to template
            echo "cryptsetup luksOpen \"${_LUKSDEVICE}\" \"${_LUKSNAME}\" <\"${_LUKSPASSPHRASE}\" >\"\${_LOG}\"" >> "${_TEMPLATE}"
            break
        fi
        _dialog --no-mouse --infobox "Error: Passphrase didn't match, please enter again" 0 0
        sleep 5
        _enter_luks_passphrase || return 1
    done
    if _dialog --yesno "Would you like to save the passphrase of luks device in /etc/$(basename "${_LUKSPASSPHRASE}")?\nName:${_LUKSNAME}" 0 0; then
        echo "${_LUKSNAME}" "${_LUKSDEVICE}" "/etc/$(basename "${_LUKSPASSPHRASE}")" >> /tmp/.crypttab
        # write to template
        { echo "echo \"${_LUKSNAME}\" \"${_LUKSDEVICE}\" \"/etc/\$(basename \"${_LUKSPASSPHRASE}\")\" >> /tmp/.crypttab"
        echo ""
        } >> "${_TEMPLATE}"
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
        _LUKS_BLACKLIST=()
        for i in $(${_LSBLK} NAME,TYPE | rg '(.*) crypt$' -r '$1' | sort -u); do
            _LUKS_BLACKLIST+=("${i}")
        done
        _DEVS=()
        for i in $(_finddevices); do
            _DEVS+=("${i}")
        done
        if [[ -n "${_LUKS_BLACKLIST[*]}" ]]; then
            for i in "${_LUKS_BLACKLIST[@]}"; do
                _remove_from_devs "${i}"
            done
        fi
        # break if all devices are in use
        if [[ -z "${_DEVS[*]}" ]]; then
            _dialog --msgbox "No devices left for luks encryption." 0 0
            return 1
        fi
        # show all devices with sizes
        _dialog --menu "Select device for luks encryption:" 15 50 12 "${_DEVS[@]}" 2>"${_ANSWER}" || return 1
        _LUKSDEVICE=$(cat "${_ANSWER}")
        # enter luks name
        _enter_luks_name || return 1
        ### TODO: offer more options for encrypt!
        ###       defaults are used only
        # final step ask if everything is ok?
        _dialog --yesno "Would you like to encrypt luks device below?\nName:${_LUKSNAME}\nDevice:${_LUKSDEVICE}\n" 0 0 && break
    done
    _enter_luks_passphrase || return 1
    _umountall
    _dialog --no-mouse --infobox "Encrypting ${_LUKSDEVICE}..." 0 0
    cryptsetup -q luksFormat "${_LUKSDEVICE}" <"${_LUKSPASSPHRASE}" >"${_LOG}"
    # write to template
    echo "cryptsetup -q luksFormat \"${_LUKSDEVICE}\" <\"${_LUKSPASSPHRASE}\" >\"\${_LOG}\"" >> "${_TEMPLATE}"
    _opening_luks
}
