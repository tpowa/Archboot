#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
_LSBLK="lsblk -rpno"
_BLKID="blkid -c /dev/null"

getfstype()
{
    ${_LSBLK} FSTYPE "${1}"
}

# getfsuuid()
# converts /dev devices to FSUUIDs
#
# parameters: device file
# outputs:    FSUUID on success
#             nothing on failure
# returns:    nothing
getfsuuid()
{
    ${_LSBLK} UUID "${1}"
}

# parameters: device file
# outputs:    LABEL on success
#             nothing on failure
# returns:    nothing
getfslabel()
{
    ${_LSBLK} LABEL "${1}"
}

getpartuuid()
{
    ${_LSBLK} PARTUUID "${1}"
}

getpartlabel()
{
    ${_LSBLK} PARTLABEL "${1}"
}

# lists linux blockdevices
blockdevices() {
     # all available block disk devices
     for dev in $(${_LSBLK} NAME,TYPE | grep "disk$" | cut -d' ' -f1); do
         # exclude checks:
         #- dmraid_devices
         #  ${_LSBLK} TYPE ${dev} | grep "dmraid"
         #- iso9660 devices
         #  (${_LSBLK} FSTYPE ${dev} | grep "iso9660"
         #- fakeraid isw devices
         #  ${_LSBLK} FSTYPE ${dev} | grep "isw_raid_member"
         #- fakeraid ddf devices
         #  ${_LSBLK} FSTYPE ${dev} | grep "ddf_raid_member"
         if ! ${_LSBLK} TYPE "${dev}" 2>/dev/null | grep -q "dmraid" || ${_LSBLK} FSTYPE "${dev}" 2>/dev/null | grep -q "iso9660" || ${_LSBLK} FSTYPE "${dev}" 2>/dev/null | grep -q "isw_raid_member" || ${_LSBLK} FSTYPE "${dev}" 2>/dev/null | grep -q "ddf_raid_member"; then
             echo "${dev}"
             [[ "${1}" ]] && echo "${1}"
         fi
     done
}

# lists linux blockdevice partitions
blockdevices_partitions() {
    # all available block devices partitions
    # printk off needed cause of parted usage
    printk off
    for part in $(${_LSBLK} NAME,TYPE | grep -v '^/dev/md' | grep "part$"| cut -d' ' -f1); do
        # exclude checks:
        #- part of raid device
        #  ${_LSBLK} FSTYPE ${part} | grep "linux_raid_member"
        #- part of lvm2 device
        #  ${_LSBLK} FSTYPE /dev/${part} | grep "LVM2_member"
        #- part of luks device
        #  ${_LSBLK} FSTYPE /dev/${part} | grep "crypto_LUKS"
        #- extended partition
        #  sfdisk -l 2>/dev/null | grep "${part}" | grep "Extended$"
        # - extended partition (LBA)
        #   sfdisk -l 2>/dev/null | grep "${part}" | grep "(LBA)$"
        #- bios_grub partitions
        #  "echo ${part} | grep "[a-z]$(parted -s $(${_LSBLK} PKNAME ${part}) print 2>/dev/null | grep bios_grub | cut -d " " -f 2)$"
        #- iso9660 devices
        #  "${_LSBLK} FSTYPE -s ${part} | grep "iso9660"
        if ! (${_LSBLK} FSTYPE "${part}" 2>/dev/null | grep -q "linux_raid_member" || ${_LSBLK} FSTYPE "${part}" 2>/dev/null | grep -q "LVM2_member" || ${_LSBLK} FSTYPE "${part}" 2>/dev/null | grep -q "crypto_LUKS" || sfdisk -l 2>/dev/null | grep "${part}" | grep -q "Extended$" || sfdisk -l 2>/dev/null | grep "${part}" | grep -q "(LBA)$" || echo "${part}" | grep -q "[a-z]$(parted -s "$(${_LSBLK} PKNAME "${part}" 2>/dev/null)" print 2>/dev/null | grep bios_grub | cut -d " " -f 2)$" || ${_LSBLK} FSTYPE -s "${part}" 2>/dev/null | grep -q "iso9660"); then
            echo "${part}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
    printk on
}

# list none partitionable raid md devices
raid_devices() {
    for dev in $(${_LSBLK} NAME,TYPE | grep " raid.*$" | cut -d' ' -f 1 | sort -u); do
        # exclude checks:
        # - part of lvm2 device_found
        #   ${_LSBLK} FSTYPE ${dev} | grep "LVM2_member"
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} | grep "crypto_LUKS"
        # - part of isw fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s | grep "isw_raid_member"
        # - part of ddf fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s | grep "ddf_raid_member"
        if ! (${_LSBLK} FSTYPE "${dev}" 2>/dev/null | grep -q "LVM2_member" || ${_LSBLK} FSTYPE "${dev}" 2>/dev/null | grep -q "crypto_LUKS" || ${_LSBLK} FSTYPE "${dev}" -s 2>/dev/null | grep -q "isw_raid_member" || ${_LSBLK} FSTYPE "${dev}" -s 2>/dev/null | grep -q "ddf_raid_member" || find "$dev"*p* -type f -exec echo {} \; 2>/dev/null ); then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

# lists linux partitionable raid devices partitions
partitionable_raid_devices_partitions() {
    for part in $(${_LSBLK} NAME,TYPE | grep "part$" | grep "^/dev/md.*p" 2>/dev/null | cut -d' ' -f 1 | sort -u) ; do
        # exclude checks:
        # - part of lvm2 device_found
        #   ${_LSBLK} FSTYPE ${part} | grep "LVM2_member"
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${part} | grep "crypto_LUKS"
        # - extended partition
        #   sfdisk -l 2>/dev/null | grep "${part}" | grep "Extended$"
        # - extended partition (LBA)
        #   sfdisk -l 2>/dev/null | grep "${part}" | grep "(LBA)$"
        # - part of isw fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s | grep "isw_raid_member"
        # - part of ddf fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s | grep "ddf_raid_member"
        if ! (${_LSBLK} FSTYPE "${part}" 2>/dev/null | grep -q "LVM2_member" || ${_LSBLK} FSTYPE "${part}" 2>/dev/null | grep -q "crypto_LUKS" || sfdisk -l 2>/dev/null | grep "${part}" | grep -q "Extended$" || sfdisk -l 2>/dev/null | grep "${part}" | grep -q "(LBA)$" || ${_LSBLK} FSTYPE "${dev}" -s 2>/dev/null | grep -q "isw_raid_member" || ${_LSBLK} FSTYPE "${dev}" -s 2>/dev/null | grep -q "ddf_raid_member"); then
            echo "${part}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

# lists dmraid devices
dmraid_devices() {
    for dev in $(${_LSBLK} NAME,TYPE  | grep "dmraid$" | cut -d' ' -f 1 | grep -v "_.*p.*$" | sort -u); do
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
    done
    # isw_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE 2>/dev/null | grep " raid.*$" | cut -d' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" | grep "isw_raid_member$"; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
    # ddf_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE 2>/dev/null | grep " raid.*$" | cut -d' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" | grep "ddf_raid_member$"; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

# dmraid_partitions
# - show dmraid partitions
dmraid_partitions() {
    for part in $(${_LSBLK} NAME,TYPE | grep "dmraid$" | cut -d' ' -f 1 | grep "_.*p.*$" | sort -u); do
        # exclude checks:
        # - part of lvm2 device
        #   ${_LSBLK} FSTYPE ${dev} | grep "LVM2_member"
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} | grep "crypto_LUKS"
        # - part of raid device
        #   ${_LSBLK} FSTYPE ${dev} | grep "linux_raid_member$"
        # - extended partition
        #   $(sfdisk -l 2>/dev/null | grep "${part}" | grep "Extended$"
        # - extended partition (LBA)
        #   sfdisk -l 2>/dev/null | grep "${part}" | grep "(LBA)$")
        if ! (${_LSBLK} FSTYPE "${part}" 2>/dev/null | grep -q "crypto_LUKS$" || ${_LSBLK} FSTYPE "${part}" 2>/dev/null | grep -q "LVM2_member$" || ${_LSBLK} FSTYPE "${part}" 2>/dev/null | grep -q "linux_raid_member$" || sfdisk -l 2>/dev/null | grep "${part}" | grep -q "Extended$"|| sfdisk -l 2>/dev/null | grep "${part}" | grep -q "(LBA)$"); then
            echo "${part}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
    # isw_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE | grep " md$" | cut -d' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" 2>/dev/null | grep "isw_raid_member$" | cut -d' ' -f 1; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
    # ddf_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE | grep " md$" | cut -d' ' -f 1 | sort -u); do
        if ${_LSBLK} NAME,FSTYPE -s "${dev}" 2>/dev/null | grep "ddf_raid_member$" | cut -d' ' -f 1; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

# dm_devices
# - show device mapper devices:
#   lvm2 and cryptdevices
dm_devices() {

    for dev in $(${_LSBLK} NAME,TYPE | grep -e "lvm$" -e "crypt$" | cut -d' ' -f1 | sort -u); do
        # exclude checks:
        # - part of lvm2 device
        #   ${_LSBLK} FSTYPE ${dev} | grep "LVM2_member"
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} | grep "crypto_LUKS"
        # - part of raid device
        #   ${_LSBLK} FSTYPE ${dev} | grep "linux_raid_member$"
        # - part of running raid on encrypted device
        #   ${_LSBLK} TYPE ${dev} | grep "raid.*$
        if ! (${_LSBLK} FSTYPE "${dev}" | grep -q "crypto_LUKS$" 2>/dev/null || ${_LSBLK} FSTYPE "${dev}" | grep -q "LVM2_member$" 2>/dev/null || ${_LSBLK} FSTYPE "${dev}" 2>/dev/null | grep -q "linux_raid_member$" || ${_LSBLK} TYPE "${dev}" 2>/dev/null | grep -q "raid.*$"); then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

finddisks() {
    blockdevices "${1}"
    dmraid_devices "${1}"
}

findpartitions() {
    blockdevices_partitions "${1}"
    dm_devices "${1}"
    dmraid_partitions "${1}"
    raid_devices "${1}"
    partitionable_raid_devices_partitions "${1}"
}

# don't check on raid devices!
findbootloaderdisks() {
    if ! [[ "${USE_DMRAID}" = "1" ]]; then
        blockdevices "${1}"
    else
        dmraid_devices "${1}"
    fi
}

# don't list raid devices, lvm2 and devicemapper!
findbootloaderpartitions() {
    if ! [[ "${USE_DMRAID}" = "1" ]]; then
        blockdevices_partitions "${1}"
    else
        dmraid_partitions "${1}"
    fi
}

# find any gpt/guid formatted disks
find_gpt() {
    GUID_DETECTED=""
    #shellcheck disable=SC2119
    for i in $(finddisks); do
        [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${i}")" == "gpt" ]] && GUID_DETECTED="1"
    done
}

# activate_dmraid()
# activate dmraid devices
activate_dmraid()
{
    if [[ -e /usr/bin/dmraid ]]; then
        DIALOG --infobox "Activating dmraid arrays..." 0 0
        dmraid -ay -I -Z >/dev/null 2>&1
    fi
}

# activate_lvm2
# activate lvm2 devices
activate_lvm2()
{
    ACTIVATE_LVM2=""
    if [[ -e /usr/bin/lvm ]]; then
        OLD_LVM2_GROUPS=${LVM2_GROUPS}
        OLD_LVM2_VOLUMES=${LVM2_VOLUMES}
        DIALOG --infobox "Scanning logical volumes..." 0 0
        lvm vgscan --ignorelockingfailure >/dev/null 2>&1
        DIALOG --infobox "Activating logical volumes..." 0 0
        lvm vgchange --ignorelockingfailure --ignoremonitoring -ay >/dev/null 2>&1
        LVM2_GROUPS="$(vgs -o vg_name --noheading 2>/dev/null)"
        LVM2_VOLUMES="$(lvs -o vg_name,lv_name --noheading --separator - 2>/dev/null)"
        [[ "${OLD_LVM2_GROUPS}" = "${LVM2_GROUPS}" && "${OLD_LVM2_VOLUMES}" = "${LVM2_VOLUMES}" ]] && ACTIVATE_LVM2="no"
    fi
}

# activate_raid
# activate md devices
activate_raid()
{
    ACTIVATE_RAID=""
    if [[ -e /usr/bin/mdadm ]]; then
        DIALOG --infobox "Activating RAID arrays..." 0 0
        mdadm --assemble --scan >/dev/null 2>&1 || ACTIVATE_RAID="no"
    fi
}

# activate_luks
# activate luks devices
activate_luks()
{
    ACTIVATE_LUKS=""
    if [[ -e /usr/bin/cryptsetup ]]; then
        DIALOG --infobox "Scanning for luks encrypted devices..." 0 0
        if ${_LSBLK} FSTYPE | grep -q "crypto_LUKS"; then
            for PART in $(${_LSBLK} NAME,FSTYPE | grep " crypto_LUKS$" | cut -d' ' -f 1); do
                # skip already encrypted devices, device mapper!
                if ! ${_LSBLK} TYPE "${PART}" | grep -q "crypt$"; then
                    RUN_LUKS=""
                    DIALOG --yesno "Setup detected luks encrypted device, do you want to activate ${PART} ?" 0 0 && RUN_LUKS="1"
                    [[ "${RUN_LUKS}" = "1" ]] && _enter_luks_name && _enter_luks_passphrase && _opening_luks
                    [[ "${RUN_LUKS}" = "" ]] && ACTIVATE_LUKS="no"
                else
                    ACTIVATE_LUKS="no"
                fi
            done
        else
            ACTIVATE_LUKS="no"
        fi
    fi
}

# activate_special_devices()
# activate special devices:
# activate dmraid, lvm2 and raid devices, if not already activated during bootup!
# run it more times if needed, it can be hidden by each other!
activate_special_devices()
{
    ACTIVATE_RAID=""
    ACTIVATE_LUKS=""
    ACTIVATE_LVM2=""
    activate_dmraid
    while ! [[ "${ACTIVATE_LVM2}" = "no" && "${ACTIVATE_RAID}" = "no"  && "${ACTIVATE_LUKS}" = "no" ]]; do
        activate_raid
        activate_lvm2
        activate_luks
    done
}

# set device name scheme
set_device_name_scheme() {
    NAME_SCHEME_PARAMETER=""
    NAME_SCHEME_LEVELS=""
    MENU_DESC_TEXT=""

    # check if gpt/guid formatted disks are there
    find_gpt

    ## util-linux root=PARTUUID=/root=PARTLABEL= support - https://git.kernel.org/?p=utils/util-linux/util-linux.git;a=commitdiff;h=fc387ee14c6b8672761ae5e67ff639b5cae8f27c;hp=21d1fa53f16560dacba33fffb14ffc05d275c926
    ## mkinitcpio's init root=PARTUUID= support - https://projects.archlinux.org/mkinitcpio.git/tree/init_functions#n185

    if [[ "${GUID_DETECTED}" == "1" ]]; then
        NAME_SCHEME_LEVELS="${NAME_SCHEME_LEVELS} PARTUUID PARTUUID=<partuuid> PARTLABEL PARTLABEL=<partlabel>"
        MENU_DESC_TEXT="\nPARTUUID and PARTLABEL are specific to GPT disks.\nIn GPT disks, PARTUUID is recommended.\nIn MBR/msdos disks,"
    fi

    NAME_SCHEME_LEVELS="${NAME_SCHEME_LEVELS} FSUUID UUID=<uuid> FSLABEL LABEL=<label> KERNEL /dev/<kernelname>"
    #shellcheck disable=SC2086
    DIALOG --menu "Select the device name scheme you want to use in config files. ${MENU_DESC_TEXT} FSUUID is recommended." 15 70 9 ${NAME_SCHEME_LEVELS} 2>"${ANSWER}" || return 1
    NAME_SCHEME_PARAMETER=$(cat "${ANSWER}")
    NAME_SCHEME_PARAMETER_RUN="1"
}

# set GUID (gpt) usage
set_guid() {
    GUIDPARAMETER=""
    detect_uefi_boot
    # all uefi systems should use GUID layout
    if [[ "${_DETECTED_UEFI_BOOT}" == "1" ]]; then
        GUIDPARAMETER="yes"
    else
        ## Lenovo BIOS-GPT issues - Arch Forum - https://bbs.archlinux.org/viewtopic.php?id=131149 , https://bbs.archlinux.org/viewtopic.php?id=133330 , https://bbs.archlinux.org/viewtopic.php?id=138958
        ## Lenovo BIOS-GPT issues - in Fedora - https://bugzilla.redhat.com/show_bug.cgi?id=735733, https://bugzilla.redhat.com/show_bug.cgi?id=749325 , http://git.fedorahosted.org/git/?p=anaconda.git;a=commit;h=ae74cebff312327ce2d9b5ac3be5dbe22e791f09
        DIALOG --yesno "You are running in BIOS/MBR mode.\n\nDo you want to use GUID Partition Table (GPT)?\n\nIt is a standard for the layout of the partition table on a physical storage disk. Although it forms a part of the Unified Extensible Firmware Interface (UEFI) standard, it is also used on some BIOS systems because of the limitations of MBR aka msdos partition tables, which restrict maximum disk size to 2 TiB.\n\nWindows 10 and later versions include the capability to use GPT for non-boot aka data disks (only UEFI systems can boot Windows 10 and later from GPT disks).\n\nAttention:\n- Please check if your other operating systems have GPT support!\n- Use this option for a GRUB(2) setup, which should support LVM, RAID\n  etc., which doesn't fit into the usual 30k MS-DOS post-MBR gap.\n- BIOS-GPT boot may not work in some Lenovo systems (irrespective of the\n   bootloader used). " 0 0 && GUIDPARAMETER="yes"
    fi
}

# Get a list of available disks for use in the "Available disks" dialogs.
# This will print the mountpoints as follows, getting size info from lsblk:
#   /dev/sda 64G
_getavaildisks()
{
    #shellcheck disable=SC2119
    for i in $(finddisks); do
        ${_LSBLK} NAME,SIZE -d "${i}"
    done
}

# Get a list of available partitions for use in the "Available Mountpoints" dialogs.
# This will print the mountpoints as follows, getting size info from lsblk:
#   /dev/sda1 640M
_getavailpartitions()
{
    #shellcheck disable=SC2119
    for i in $(findpartitions); do
        ${_LSBLK} NAME,SIZE -d "${i}"
    done
}

# Disable swap and all mounted partitions for the destination system. Unmount
# the destination root partition last!
_umountall()
{
    DIALOG --infobox "Disabling swapspace, unmounting already mounted disk devices..." 0 0
    swapoff -a >/dev/null 2>&1
    for i in $(findmnt --list --submounts "${DESTDIR}" -o TARGET -n | tac); do
        umount "$i"
    done
}

# Disable all software raid devices
_stopmd()
{
    if grep -q ^md /proc/mdstat 2>/dev/null; then
        DISABLEMD=""
        DIALOG --defaultno --yesno "Setup detected already running raid devices, do you want to disable them completely?" 0 0 && DISABLEMD="1"
        if [[ "${DISABLEMD}" = "1" ]]; then
            _umountall
            DIALOG --infobox "Disabling all software raid devices..." 0 0
            # shellcheck disable=SC2013
            for i in $(grep ^md /proc/mdstat | sed -e 's# :.*##g'); do
                # clear all magic strings/signatures - mdadm, lvm, partition tables etc.
                wipefs -a --force "/dev/${i}" > "${LOG}"  2>&1
                mdadm --manage --stop "/dev/${i}" > "${LOG}" 2>&1
            done
            DIALOG --infobox "Cleaning superblocks of all software raid devices..." 0 0
            for i in $(${_LSBLK} NAME,FSTYPE | grep "linux_raid_member$" | cut -d' ' -f 1); do
                # clear all magic strings/signatures - mdadm, lvm, partition tables etc.
                sgdisk --zap "${i}" > "${LOG}" 2>&1
                wipefs -a --force "${i}" > "${LOG}" 2>&1
                dd if=/dev/zero of="${i}" bs=512 count=2048 > "${LOG}" 2>&1
            done
        fi
    fi
    DISABLEMDSB=""
    if ${_LSBLK} FSTYPE | grep -q "linux_raid_member"; then
        DIALOG --defaultno --yesno "Setup detected superblock of raid devices, do you want to clean the superblock of them?" 0 0 && DISABLEMDSB="1"
        if [[ "${DISABLEMDSB}" = "1" ]]; then
            _umountall
            DIALOG --infobox "Cleaning superblocks of all software raid devices..." 0 0
            for i in $(${_LSBLK} NAME,FSTYPE | grep "linux_raid_member$" | cut -d' ' -f 1); do
                # clear all magic strings/signatures - mdadm, lvm, partition tables etc.
                sgdisk --zap "${i}" > "${LOG}" 2>&1
                wipefs -a "${i}" > "${LOG}" 2>&1
                dd if=/dev/zero of="${i}" bs=512 count=2048 > "${LOG}"  2>&1
            done
        fi
    fi
}

# Disable all lvm devices
_stoplvm()
{
    DISABLELVM=""
    DETECTED_LVM=""
    LV_VOLUMES="$(lvs -o vg_name,lv_name --noheading --separator - 2>/dev/null)"
    LV_GROUPS="$(vgs -o vg_name --noheading 2>/dev/null)"
    LV_PHYSICAL="$(pvs -o pv_name --noheading 2>/dev/null)"
    ! [[ "${LV_VOLUMES}" = "" ]] && DETECTED_LVM=1
    ! [[ "${LV_GROUPS}" = "" ]] && DETECTED_LVM=1
    ! [[ "${LV_PHYSICAL}" = "" ]] && DETECTED_LVM=1
    if [[ "${DETECTED_LVM}" = "1" ]]; then
        DIALOG --defaultno --yesno "Setup detected lvm volumes, volume groups or physical devices, do you want to remove them completely?" 0 0 && DISABLELVM="1"
    fi
    if [[ "${DISABLELVM}" = "1" ]]; then
        _umountall
        DIALOG --infobox "Removing logical volumes ..." 0 0
        for i in ${LV_VOLUMES}; do
            lvremove -f "/dev/mapper/${i}" 2>/dev/null> "${LOG}"
        done
        DIALOG --infobox "Removing logical groups ..." 0 0
        for i in ${LV_GROUPS}; do
            vgremove -f "${i}" 2>/dev/null > "${LOG}"
        done
        DIALOG --infobox "Removing physical volumes ..." 0 0
        for i in ${LV_PHYSICAL}; do
            pvremove -f "${i}" 2>/dev/null > "${LOG}"
        done
    fi
}

# Disable all luks encrypted devices
_stopluks()
{
    DISABLELUKS=""
    DETECTED_LUKS=""
    LUKSDEVICE=""

    # detect already running luks devices
    LUKSDEVICE="$(${_LSBLK} NAME,TYPE | grep " crypt$" | cut -d' ' -f1)"
    [[ "${LUKSDEVICE}" == "" ]] || DETECTED_LUKS=1
    if [[ "${DETECTED_LUKS}" = "1" ]]; then
        DIALOG --defaultno --yesno "Setup detected running luks encrypted devices, do you want to remove them completely?" 0 0 && DISABLELUKS="1"
    fi
    if [[ "${DISABLELUKS}" = "1" ]]; then
        _umountall
        DIALOG --infobox "Removing luks encrypted devices ..." 0 0
        for i in ${LUKSDEVICE}; do
            LUKS_REAL_DEVICE="$(${_LSBLK} NAME,FSTYPE -s "${LUKSDEVICE}" | grep " crypto_LUKS$" | cut -d' ' -f1)"
            cryptsetup remove "${i}" > "${LOG}"
            # delete header from device
            wipefs -a "${LUKS_REAL_DEVICE}" > "${LOG}" 2>&1
        done
    fi

    DISABLELUKS=""
    DETECTED_LUKS=""

    # detect not running luks devices
    ${_LSBLK} FSTYPE | grep -q "crypto_LUKS" && DETECTED_LUKS=1
    if [[ "${DETECTED_LUKS}" = "1" ]]; then
        DIALOG --defaultno --yesno "Setup detected not running luks encrypted devices, do you want to remove them completely?" 0 0 && DISABLELUKS="1"
    fi
    if [[ "${DISABLELUKS}" = "1" ]]; then
        DIALOG --infobox "Removing not running luks encrypted devices ..." 0 0
        for i in $(${_LSBLK} NAME,FSTYPE | grep "crypto_LUKS$" | cut -d' ' -f1); do
           # delete header from device
           wipefs -a "${i}" > "${LOG}" 2>&1
        done
    fi
    [[ -e /tmp/.crypttab ]] && rm /tmp/.crypttab
}

#_dmraid_update
_dmraid_update()
{
    printk off
    DIALOG --infobox "Deactivating dmraid devices ..." 0 0
    dmraid -an >/dev/null 2>&1
    if [[ "${DETECTED_LVM}" = "1" || "${DETECTED_LUKS}" = "1" ]]; then
        DIALOG --defaultno --yesno "Setup detected running dmraid devices and/or running lvm2, luks encrypted devices. If you reduced/deleted partitions on your dmraid device a complete reset of devicemapper devices is needed. This will reset also your created lvm2 or encrypted devices. Are you sure you want to do this?" 0 0 && RESETDM="1"
        if [[ "${RESETDM}" = "1" ]]; then
            DIALOG --infobox "Resetting devicemapper devices ..." 0 0
            dmsetup remove_all >/dev/null 2>&1
        fi
    else
        DIALOG --infobox "Resetting devicemapper devices ..." 0 0
        dmsetup remove_all >/dev/null 2>&1
    fi
    DIALOG --infobox "Reactivating dmraid devices ..." 0 0
    dmraid -ay -I -Z >/dev/null 2>&1
    printk on
}

#helpbox for raid
_helpraid()
{
DIALOG --msgbox "LINUX SOFTWARE RAID SUMMARY:\n
-----------------------------\n\n
Linear mode:\n
You have two or more partitions which are not necessarily the same size\n
(but of course can be), which you want to append to each other.\n
Spare-disks are not supported here. If a disk dies, the array dies with\n
it.\n\n
RAID-0:\n
You have two or more devices, of approximately the same size, and you want\n
to combine their storage capacity and also combine their performance by\n
accessing them in parallel. Like in Linear mode, spare disks are not\n
supported here either. RAID-0 has no redundancy, so when a disk dies, the\n
array goes with it.\n\n
RAID-1:\n
You have two devices of approximately same size, and you want the two to\n
be mirrors of each other. Eventually you have more devices, which you\n
want to keep as stand-by spare-disks, that will automatically become a\n
part of the mirror if one of the active devices break.\n\n
RAID-4:\n
You have three or more devices of roughly the same size and you want\n
a way that protects data against loss of any one disk.\n
Fault tolerance is achieved by adding an extra disk to the array, which\n
is dedicated to storing parity information. The overall capacity of the\n
array is reduced by one disk.\n
The storage efficiency is 66 percent. With six drives, the storage\n
efficiency is 87 percent. The main disadvantage is poor performance for\n
multiple,\ simultaneous, and independent read/write operations.\n
Thus, if any disk fails, all data stay intact. But if two disks fail,\n
all data is lost.\n\n
RAID-5:\n
You have three or more devices of roughly the same size, you want to\n
combine them into a larger device, but still to maintain a degree of\n
redundancy fordata safety. Eventually you have a number of devices to use\n
as spare-disks, that will not take part in the array before another device\n
fails. If you use N devices where the smallest has size S, the size of the\n
entire array will be (N-1)*S. This \"missing\" space is used for parity\n
(redundancy) information. Thus, if any disk fails, all data stay intact.\n
But if two disks fail, all data is lost.\n\n
RAID-6:\n
You have four or more devices of roughly the same size and you want\n
a way that protects data against loss of any two disks.\n
Fault tolerance is achieved by adding an two extra disk to the array,\n
which is dedicated to storing parity information. The overall capacity\n
of the array is reduced by 2 disks.\n
Thus, if any two disks fail, all data stay intact. But if 3 disks fail,\n
all data is lost.\n\n
RAID-10:\n
Shorthand for RAID1+0, a mirrored striped array and needs a minimum of\n
two disks. It provides superior data security and can survive multiple\n
disk failures. The main disadvantage is cost, because 50% of your\n
storage is duplication." 0 0
}

# Create raid or raid_partition
_raid()
{
    MDFINISH=""
    while [[ "${MDFINISH}" != "DONE" ]]; do
        activate_special_devices
        : >/tmp/.raid
        : >/tmp/.raid-spare
        # check for devices
        # Remove all raid devices with children
        RAID_BLACKLIST="$(raid_devices;partitionable_raid_devices_partitions)"
        #shellcheck disable=SC2119
        PARTS="$(for i in $(findpartitions); do
                echo "${RAID_BLACKLIST}" | grep -qw "${i}" || echo "${i}" _
                done)"
        # break if all devices are in use
        if [[ "${PARTS}" = "" ]]; then
            DIALOG --msgbox "All devices in use. No more devices left for new creation." 0 0
            return 1
        fi
        # enter raid device name
        RAIDDEVICE=""
        while [[ "${RAIDDEVICE}" = "" ]]; do
            DIALOG --inputbox "Enter the node name for the raiddevice:\n/dev/md[number]\n/dev/md0\n/dev/md1\n\n" 12 50 "/dev/md0" 2>"${ANSWER}" || return 1
            RAIDDEVICE=$(cat "${ANSWER}")
            if grep -q "^${RAIDDEVICE//\/dev\//}" /proc/mdstat; then
                DIALOG --msgbox "ERROR: You have defined 2 identical node names! Please enter another name." 8 65
                RAIDDEVICE=""
            fi
        done
        RAIDLEVELS="linear - raid0 - raid1 - raid4 - raid5 - raid6 - raid10 -"
        #shellcheck disable=SC2086
        DIALOG --menu "Select the raid level you want to use" 14 50 7 ${RAIDLEVELS} 2>"${ANSWER}" || return 1
        LEVEL=$(cat "${ANSWER}")
        # raid5 and raid10 support parity parameter
        PARITY=""
        if [[ "${LEVEL}" = "raid5" || "${LEVEL}" = "raid6" || "${LEVEL}" = "raid10" ]]; then
            PARITYLEVELS="left-asymmetric - left-symmetric - right-asymmetric - right-symmetric -"
            #shellcheck disable=SC2086
            DIALOG --menu "Select the parity layout you want to use (default is left-symmetric)" 21 50 13 ${PARITYLEVELS} 2>"${ANSWER}" || return 1
            PARITY=$(cat "${ANSWER}")
        fi
        # show all devices with sizes
        DIALOG --cr-wrap --msgbox "DISKS:\n$(_getavaildisks)\n\nPARTITIONS:\n$(_getavailpartitions)" 0 0
        # select the first device to use, no missing option available!
        RAIDNUMBER=1
        #shellcheck disable=SC2086
        DIALOG --menu "Select device ${RAIDNUMBER}" 21 50 13 ${PARTS} 2>"${ANSWER}" || return 1
        PART=$(cat "${ANSWER}")
        echo "${PART}" >>/tmp/.raid
        while [[ "${PART}" != "DONE" ]]; do
            RAIDNUMBER=$((RAIDNUMBER + 1))
            # clean loop from used partition and options
            PARTS="$(echo "${PARTS}" | sed -e "s#${PART}\ _##g" -e 's#MISSING\ _##g' -e 's#SPARE\ _##g')"
            # raid0 doesn't support missing devices
            ! [[ "${LEVEL}" = "raid0" || "${LEVEL}" = "linear" ]] && MDEXTRA="MISSING _"
            # add more devices
            #shellcheck disable=SC2086
            DIALOG --menu "Select additional device ${RAIDNUMBER}" 21 50 13 ${PARTS} ${MDEXTRA} DONE _ 2>"${ANSWER}" || return 1
            PART=$(cat "${ANSWER}")
            SPARE=""
            ! [[ "${LEVEL}" = "raid0" || "${LEVEL}" = "linear" ]] && DIALOG --yesno --defaultno "Would you like to use ${PART} as spare device?" 0 0 && SPARE="1"
            [[ "${PART}" = "DONE" ]] && break
            if [[ "${PART}" = "MISSING" ]]; then
                DIALOG --yesno "Would you like to create a degraded raid on ${RAIDDEVICE}?" 0 0 && DEGRADED="missing"
                echo "${DEGRADED}" >>/tmp/.raid
            else
                if [[ "${SPARE}" = "1" ]]; then
                    echo "${PART}" >>/tmp/.raid-spare
                else
                    echo "${PART}" >>/tmp/.raid
                fi
            fi
        done
        # final step ask if everything is ok?
        # shellcheck disable=SC2028
        DIALOG --yesno "Would you like to create ${RAIDDEVICE} like this?\n\nLEVEL:\n${LEVEL}\n\nDEVICES:\n$(while read -r i;do echo "${i}\n"; done < /tmp/.raid)\nSPARES:\n$(while read -r i;do echo "${i}\n"; done < tmp/.raid-spare)" 0 0 && MDFINISH="DONE"
    done
    _umountall
    _createraid
}

# create raid device
_createraid()
{
    DEVICES="$(echo -n "$(cat /tmp/.raid)")"
    SPARES="$(echo -n "$(cat /tmp/.raid-spare)")"
    # combine both if spares are available, spares at the end!
    [[ -n ${SPARES} ]] && DEVICES="${DEVICES} ${SPARES}"
    # get number of devices
    RAID_DEVICES="$(wc -l < /tmp/.raid)"
    SPARE_DEVICES="$(wc -l < /tmp/.raid-spare)"
    # generate options for mdadm
    RAIDOPTIONS="--force --run --level=${LEVEL}"
    ! [[ "${RAID_DEVICES}" = "0" ]] && RAIDOPTIONS="${RAIDOPTIONS} --raid-devices=${RAID_DEVICES}"
    ! [[ "${SPARE_DEVICES}" = "0" ]] && RAIDOPTIONS="${RAIDOPTIONS} --spare-devices=${SPARE_DEVICES}"
    ! [[ "${PARITY}" = "" ]] && RAIDOPTIONS="${RAIDOPTIONS} --layout=${PARITY}"
    DIALOG --infobox "Creating ${RAIDDEVICE}..." 0 0
    #shellcheck disable=SC2086
    if mdadm --create ${RAIDDEVICE} ${RAIDOPTIONS} ${DEVICES} >"${LOG}" 2>&1; then
        DIALOG --infobox "${RAIDDEVICE} created successfully.\n\nContinuing in 3 seconds..." 5 50
        sleep 3
    else
        DIALOG --msgbox "Error creating ${RAIDDEVICE} (see "${LOG}" for details)." 0 0
        return 1
    fi
    if [[ ${RAID_PARTITION} == "1" ]]; then
        # switch for mbr usage
        set_guid
        if [[ "${GUIDPARAMETER}" = "" ]]; then
            DIALOG --msgbox "Now you'll be put into the cfdisk program where you can partition your raiddevice to your needs." 6 70
            cfdisk "${RAIDDEVICE}"
        else
            DISC="${RAIDDEVICE}"
            RUN_CFDISK="1"
            CHECK_BIOS_BOOT_GRUB=""
            CHECK_UEFISYS_PART=""
            check_gpt
        fi
    fi
}

# help for lvm
_helplvm()
{
DIALOG --msgbox "LOGICAL VOLUME SUMMARY:\n
-----------------------------\n\n
LVM is a Logical Volume Manager for the Linux kernel. With LVM you can\n
abstract your storage space and have \"virtual partitions\" which are easier\n
to modify.\n\nThe basic building block of LVM are:\n
- Physical volume (PV):\n
  Partition on storage disk (or even storage disk itself or loopback file) on\n
  which you can have virtual groups. It has a special header and is\n
  divided into physical extents. Think of physical volumes as big building\n
  blocks which can be used to build your storage drive.\n
- Volume group (VG):\n
  Group of physical volumes that are used as storage volume (as one disk).\n
  They contain logical volumes. Think of volume groups as storage drives.\n
- Logical volume(LV):\n
  A \"virtual/logical partition\" that resides in a volume group and is\n
  composed of physical extents. Think of logical volumes as normal\n
  partitions." 0 0
}

# Creates physical volume
_createpv()
{
    PVFINISH=""
    while [[ "${PVFINISH}" != "DONE" ]]; do
        activate_special_devices
        : >/tmp/.pvs-create
        # Remove all lvm devices with children
        LVM_BLACKLIST="$(for i in $(${_LSBLK} NAME,TYPE | grep " lvm$" | cut -d' ' -f1 | sort -u); do
                    echo "$(${_LSBLK} NAME "${i}")" _
                    done)"
        #shellcheck disable=SC2119
        PARTS="$(for i in $(findpartitions); do
                ! echo "${LVM_BLACKLIST}" | grep -E "${i} _" && echo "${i}" _
                done)"
        # break if all devices are in use
        if [[ "${PARTS}" = "" ]]; then
            DIALOG --msgbox "No devices left for physical volume creation." 0 0
            return 1
        fi
        # show all devices with sizes
        DIALOG --cr-wrap --msgbox "DISKS:\n$(_getavaildisks)\n\nPARTITIONS:\n$(_getavailpartitions)\n\n" 0 0
        # select the first device to use
        DEVNUMBER=1
        #shellcheck disable=SC2086
        DIALOG --menu "Select device number ${DEVNUMBER} for physical volume" 8 50 5 ${PARTS} 2>"${ANSWER}" || return 1
        PART=$(cat "${ANSWER}")
        echo "${PART}" >>/tmp/.pvs-create
        while [[ "${PART}" != "DONE" ]]; do
            DEVNUMBER="$((DEVNUMBER + 1))"
            # clean loop from used partition and options
            PARTS="${PARTS//${PART}\ _/}"
            # add more devices
            #shellcheck disable=SC2086
            DIALOG --menu "Select additional device number ${DEVNUMBER} for physical volume" 21 50 13 ${PARTS} DONE _ 2>"${ANSWER}" || return 1
            PART=$(cat "${ANSWER}")
            [[ "${PART}" = "DONE" ]] && break
            echo "${PART}" >>/tmp/.pvs-create
        done
        # final step ask if everything is ok?
        DIALOG --yesno "Would you like to create physical volume on devices below?\n$(sed -e 's#$#\\n#g' /tmp/.pvs-create)" 0 0 && PVFINISH="DONE"
    done
    DIALOG --infobox "Creating physical volume on ${PART}..." 0 0
    PART="$(echo -n "$(cat /tmp/.pvs-create)")"
    #shellcheck disable=SC2028,SC2086
    _umountall
    if pvcreate -y ${PART} >"${LOG}" 2>&1; then
        DIALOG --infobox "Creating physical volume on ${PART} successful.\n\nContinuing in 5 seconds..." 6 75
        sleep 5
    else
        DIALOG --msgbox "Error creating physical volume on ${PART} (see "${LOG}" for details)." 0 0; return 1
    fi
    # run udevadm to get values exported
    udevadm trigger
    udevadm settle
}

#find physical volumes that are not in use
findpv()
{
    for i in $(${_LSBLK} NAME,FSTYPE | grep " LVM2_member$" | cut -d' ' -f1 | sort -u); do
         # exclude checks:
         #-  not part of running lvm2
         # ! "$(${_LSBLK} TYPE ${i} | grep "lvm")"
         #- not part of volume group
         # $(pvs -o vg_name --noheading ${i} | grep " $")
         if ! ${_LSBLK} TYPE "${i}" | grep -q "lvm" && pvs -o vg_name --noheading "${i}" | grep -q " $"; then
             echo "${i}"
             [[ "${1}" ]] && echo "${1}"
         fi
    done
}

getavailablepv()
{
    for i in $(${_LSBLK} NAME,FSTYPE | grep " LVM2_member$" | cut -d' ' -f1 | sort -u); do
        # exclude checks:
        #-  not part of running lvm2
        # ! "$(${_LSBLK} TYPE ${i} | grep "lvm")"
        #- not part of volume group
        # $(pvs -o vg_name --noheading ${i} | grep " $")
        if ! ${_LSBLK} TYPE "${i}" | grep "lvm" && pvs -o vg_name --noheading "${i}" | grep -q " $"; then
            ${_LSBLK} NAME,SIZE "${i}"
        fi
    done
}

#find volume groups that are not already full in use
findvg()
{
    for dev in $(vgs -o vg_name --noheading);do
        if ! vgs -o vg_free --noheading --units m "${dev}" | grep -q " 0m$"; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

getavailablevg()
{
    for i in $(vgs -o vg_name,vg_free --noheading --units m); do
        if ! echo "${i}" | grep -q " 0m$"; then
            #shellcheck disable=SC2028
            echo "${i}\n"
        fi
    done
}

# Creates volume group
_createvg()
{
    VGFINISH=""
    while [[ "${VGFINISH}" != "DONE" ]]; do
        : >/tmp/.pvs
        VGDEVICE=""
        PVS=$(findpv _)
        # break if all devices are in use
        if [[ "${PVS}" = "" ]]; then
            DIALOG --msgbox "No devices left for Volume Group creation." 0 0
            return 1
        fi
        # enter volume group name
        VGDEVICE=""
        while [[ "${VGDEVICE}" = "" ]]; do
            DIALOG --inputbox "Enter the Volume Group name:\nfoogroup\n<yourvolumegroupname>\n\n" 11 40 "foogroup" 2>"${ANSWER}" || return 1
            VGDEVICE=$(cat "${ANSWER}")
            if vgs -o vg_name --noheading 2>/dev/null | grep -q "^  ${VGDEVICE}"; then
                DIALOG --msgbox "ERROR: You have defined 2 identical Volume Group names! Please enter another name." 8 65
                VGDEVICE=""
            fi
        done
        # show all devices with sizes, which are not in use
        #shellcheck disable=SC2086
        DIALOG --cr-wrap --msgbox "Physical Volumes:\n$(getavailablepv)" 0 0
        # select the first device to use, no missing option available!
        PVNUMBER=1
        #shellcheck disable=SC2086
        DIALOG --menu "Select Physical Volume ${PVNUMBER} for ${VGDEVICE}" 11 50 5 ${PVS} 2>"${ANSWER}" || return 1
        PV=$(cat "${ANSWER}")
        echo "${PV}" >>/tmp/.pvs
        while [[ "${PVS}" != "DONE" ]]; do
            PVNUMBER=$((PVNUMBER + 1))
            # clean loop from used partition and options
            #shellcheck disable=SC2001,SC2086
            PVS="$(echo ${PVS} | sed -e "s#${PV} _##g")"
            # add more devices
            #shellcheck disable=SC2086
            DIALOG --menu "Select additional Physical Volume ${PVNUMBER} for ${VGDEVICE}" 11 50 5 ${PVS} DONE _ 2>"${ANSWER}" || return 1
            PV=$(cat "${ANSWER}")
            [[ "${PV}" = "DONE" ]] && break
            echo "${PV}" >>/tmp/.pvs
        done
        # final step ask if everything is ok?
        DIALOG --yesno "Would you like to create Volume Group like this?\n\n${VGDEVICE}\n\nPhysical Volumes:\n$(sed -e 's#$#\\n#g' /tmp/.pvs)" 0 0 && VGFINISH="DONE"
    done
    DIALOG --infobox "Creating Volume Group ${VGDEVICE}..." 0 0
    PV="$(echo -n "$(cat /tmp/.pvs)")"
    _umountall
    #shellcheck disable=SC2086
    if vgcreate ${VGDEVICE} ${PV} >"${LOG}" 2>&1; then
        DIALOG --infobox "Creating Volume Group ${VGDEVICE} successful.\n\nContinuing in 5 seconds..." 5 50
        sleep 5
    else
        DIALOG --msgbox "Error creating Volume Group ${VGDEVICE} (see "${LOG}" for details)." 0 0
        return 1
    fi
}

# Creates logical volume
_createlv()
{
    LVFINISH=""
    while [[ "${LVFINISH}" != "DONE" ]]; do
        LVDEVICE=""
        LV_SIZE_SET=""
        LVS=$(findvg _)
        # break if all devices are in use
        if [[ "${LVS}" = "" ]]; then
            DIALOG --msgbox "No Volume Groups with free space available for Logical Volume creation." 0 0
            return 1
        fi
        # show all devices with sizes, which are not 100% in use!
        DIALOG --cr-wrap --msgbox "Volume Groups:\n$(getavailablevg)" 0 0
        #shellcheck disable=SC2086
        DIALOG --menu "Select Volume Group" 11 50 5 ${LVS} 2>"${ANSWER}" || return 1
        LV=$(cat "${ANSWER}")
        # enter logical volume name
        LVDEVICE=""
        while [[ "${LVDEVICE}" = "" ]]; do
            DIALOG --inputbox "Enter the Logical Volume name:\nfooname\n<yourvolumename>\n\n" 10 65 "fooname" 2>"${ANSWER}" || return 1
            LVDEVICE=$(cat "${ANSWER}")
            if lvs -o lv_name,vg_name --noheading 2>/dev/null | grep -q " ${LVDEVICE} ${LV}$"; then
                DIALOG --msgbox "ERROR: You have defined 2 identical Logical Volume names! Please enter another name." 8 65
                LVDEVICE=""
            fi
        done
        while [[ "${LV_SIZE_SET}" = "" ]]; do
            LV_ALL=""
            DIALOG --inputbox "Enter the size (MB) of your Logical Volume,\nMinimum value is > 0.\n\nVolume space left: $(vgs -o vg_free --noheading --units m "${LV}")B\n\nIf you enter no value, all free space left will be used." 10 65 "" 2>"${ANSWER}" || return 1
                LV_SIZE=$(cat "${ANSWER}")
                if [[ "${LV_SIZE}" = "" ]]; then
                    DIALOG --yesno "Would you like to create Logical Volume with no free space left?" 0 0 && LV_ALL="1"
                    if ! [[ "${LV_ALL}" = "1" ]]; then
                         LV_SIZE=0
                    fi
                fi
                if [[ "${LV_SIZE}" = "0" ]]; then
                    DIALOG --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${LV_SIZE}" -ge "$(vgs -o vg_free --noheading --units m | sed -e 's#m##g')" ]]; then
                        DIALOG --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                    else
                        LV_SIZE_SET=1
                    fi
                fi
        done
        #Contiguous doesn't work with +100%FREE
        LV_CONTIGUOUS=""
        [[ "${LV_ALL}" = "" ]] && DIALOG --defaultno --yesno "Would you like to create Logical Volume as a contiguous partition, that means that your space doesn't get partitioned over one or more disks nor over non-contiguous physical extents.\n(usefull for swap space etc.)?" 0 0 && LV_CONTIGUOUS="1"
        if [[ "${LV_CONTIGUOUS}" = "1" ]]; then
            CONTIGUOUS=yes
            LV_EXTRA="-C y"
        else
            CONTIGUOUS=no
            LV_EXTRA=""
        fi
        [[ "${LV_SIZE}" = "" ]] && LV_SIZE="All free space left"
        # final step ask if everything is ok?
        DIALOG --yesno "Would you like to create Logical Volume ${LVDEVICE} like this?\nVolume Group:\n${LV}\nVolume Size:\n${LV_SIZE}\nContiguous Volume:\n${CONTIGUOUS}" 0 0 && LVFINISH="DONE"
    done
    _umountall
    if [[ "${LV_ALL}" = "1" ]]; then
        #shellcheck disable=SC2086
        if lvcreate ${LV_EXTRA} -l +100%FREE ${LV} -n ${LVDEVICE} >"${LOG}" 2>&1; then
            DIALOG --infobox "Creating Logical Volume ${LVDEVICE} successful.\n\nContinuing in 5 seconds..." 5 50
            sleep 5
        else
            DIALOG --msgbox "Error creating Logical Volume ${LVDEVICE} (see "${LOG}" for details)." 0 0
            return 1
        fi
    else
        #shellcheck disable=SC2086
        if lvcreate ${LV_EXTRA} -L ${LV_SIZE} ${LV} -n ${LVDEVICE} >"${LOG}" 2>&1; then
            DIALOG --infobox "Creating Logical Volume ${LVDEVICE} successful.\n\nContinuing in 5 seconds..." 5 50
            sleep 5
        else
            DIALOG --msgbox "Error creating Logical Volume ${LVDEVICE} (see "${LOG}" for details)." 0 0
            return 1
        fi
    fi
}

# enter luks name
_enter_luks_name() {
    LUKSDEVICE=""
    while [[ "${LUKSDEVICE}" = "" ]]; do
        DIALOG --inputbox "Enter the name for luks encrypted device ${PART}:\nfooname\n<yourname>\n\n" 15 65 "fooname" 2>"${ANSWER}" || return 1
        LUKSDEVICE=$(cat "${ANSWER}")
        if ! cryptsetup status "${LUKSDEVICE}" | grep -q inactive; then
            DIALOG --msgbox "ERROR: You have defined 2 identical luks encryption device names! Please enter another name." 8 65
            LUKSDEVICE=""
        fi
    done
}

# enter luks passphrase
_enter_luks_passphrase () {
    LUKSPASSPHRASE=""
    while [[ "${LUKSPASSPHRASE}" = "" ]]; do
        DIALOG --insecure --passwordbox "Enter passphrase for luks encrypted device ${PART}:" 0 0 2>"${ANSWER}" || return 1
        LUKSPASS=$(cat "${ANSWER}")
        DIALOG --insecure --passwordbox "Retype passphrase for luks encrypted device ${PART}:" 0 0 2>"${ANSWER}" || return 1
        LUKSPASS2=$(cat "${ANSWER}")
        if [[ -n "${LUKSPASS}" && -n "${LUKSPASS2}" && "${LUKSPASS}" == "${LUKSPASS2}" ]]; then
            LUKSPASSPHRASE=${LUKSPASS}
            echo "${LUKSPASSPHRASE}" > "/tmp/passphrase-${LUKSDEVICE}"
            LUKSPASSPHRASE="/tmp/passphrase-${LUKSDEVICE}"
        else
             DIALOG --msgbox "Passphrases didn't match or was empty, please enter again." 0 0
        fi
    done
}

# opening luks
_opening_luks() {
    DIALOG --infobox "Opening encrypted ${PART}..." 0 0
    luksOpen_success="0"
    while [[ "${luksOpen_success}" = "0" ]]; do
        cryptsetup luksOpen "${PART}" "${LUKSDEVICE}" <${LUKSPASSPHRASE} >"${LOG}" && luksOpen_success=1
        if [[ "${luksOpen_success}" = "0" ]]; then
            DIALOG --msgbox "Error: Passphrase didn't match, please enter again." 0 0
            _enter_luks_passphrase || return 1
        fi
    done
    DIALOG --yesno "Would you like to save the passphrase of luks device in /etc/$(basename ${LUKSPASSPHRASE})?\nName:${LUKSDEVICE}" 0 0 || LUKSPASSPHRASE="ASK"
    echo "${LUKSDEVICE}" "${PART}" "/etc/$(basename ${LUKSPASSPHRASE})" >> /tmp/.crypttab
}

# help for luks
_helpluks()
{
DIALOG --msgbox "LUKS ENCRYPTION SUMMARY:\n
-----------------------------\n\n
Encryption is useful for two (related) reasons.\n
Firstly, it prevents anyone with physical access to your computer,\n
and your storage drive in particular, from getting the data from it\n
(unless they have your passphrase/key).\n
Secondly, it allows you to wipe the data on your storage drive with\n
far more confidence in the event of you selling or discarding\n
your drive.\n
Basically, it supplements the access control mechanisms of the operating\n
system (like file permissions) by making it harder to bypass the operating\n
system by inserting a bootable medium, for example. Encrypting the root\n
partition prevents anyone from using this method to insert viruses or\n
trojans onto your computer.\n\n
ATTENTION:\n
Having encrypted partitions does not protect you from all possible\n
attacks. The encryption is only as good as your key management, and there\n
are other ways to break into computers, while they are running." 0 0
}

# create luks device
_luks()
{
    NAME_SCHEME_PARAMETER_RUN=""
    LUKSFINISH=""
    while [[ "${LUKSFINISH}" != "DONE" ]]; do
        activate_special_devices
        # Remove all crypt devices with children
        CRYPT_BLACKLIST="$(for i in $(${_LSBLK} NAME,TYPE | grep " crypt$" | cut -d' ' -f1 | sort -u); do
                    ${_LSBLK} NAME "${i}"
                    done)"
        #shellcheck disable=SC2119
        PARTS="$(for i in $(findpartitions); do
                echo "${CRYPT_BLACKLIST}" | grep -wq "${i}" || echo "${i}" _;
                done)"
        # break if all devices are in use
        if [[ "${PARTS}" = "" ]]; then
            DIALOG --msgbox "No devices left for luks encryption." 0 0
            return 1
        fi
        # show all devices with sizes
        DIALOG --cr-wrap --msgbox "DISKS:\n$(_getavaildisks)\n\nPARTITIONS:\n$(_getavailpartitions)\n\n" 0 0
        #shellcheck disable=SC2086
        DIALOG --menu "Select device for luks encryption" 21 50 13 ${PARTS} 2>"${ANSWER}" || return 1
        PART=$(cat "${ANSWER}")
        # enter luks name
        _enter_luks_name
        ### TODO: offer more options for encrypt!
        ###       defaults are used only
        # final step ask if everything is ok?
        DIALOG --yesno "Would you like to encrypt luks device below?\nName:${LUKSDEVICE}\nDevice:${PART}\n" 0 0 && LUKSFINISH="DONE"
    done
    _enter_luks_passphrase || return 1
    _umountall
    DIALOG --infobox "Encrypting ${PART}..." 0 0
    cryptsetup -q luksFormat "${PART}" <${LUKSPASSPHRASE} >"${LOG}"
    _opening_luks
}
