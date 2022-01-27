#!/usr/bin/env bash
# we rely on some output which is parsed in english!
unset LANG
ANSWER="/tmp/.setup"
TITLE="Arch Linux Installation"
# use the first VT not dedicated to a running console
LOG="/dev/tty7"
# don't use /mnt because it's intended to mount other things there!
DESTDIR="/install"
RUNNING_ARCH="$(uname -m)"
EDITOR=""
_BLKID="blkid -c /dev/null"
_LSBLK="lsblk -rpno"

# name of kernel package
KERNELPKG="linux"
# name of the kernel image
[[ "${RUNNING_ARCH}" == "x86_64" ]] && VMLINUZ="vmlinuz-${KERNELPKG}"
if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
    VMLINUZ="Image.gz"
    VMLINUZ_EFISTUB="Image"
fi
# name of the initramfs filesystem
INITRAMFS="initramfs-${KERNELPKG}"
# name of intel ucode initramfs image
INTEL_UCODE="intel-ucode.img"
# name of amd ucode initramfs image
AMD_UCODE="amd-ucode.img"

# abstract the common pacman args
PACMAN="pacman --root ${DESTDIR} --cachedir=${DESTDIR}/var/cache/pacman/pkg --noconfirm --noprogressbar"
# downloader
DLPROG="wget"
# sources
SYNC_URL=""
MIRRORLIST="/etc/pacman.d/mirrorlist"
unset PACKAGES

# partitions
PART_ROOT=""
ROOTFS=""

# install stages
S_SRC=0         # choose mirror
S_NET=0         # network configuration
S_MKFS=0        # formatting
S_MKFSAUTO=0    # auto fs part/formatting
S_CONFIG=0      # configuration editing

# menu item tracker- autoselect the next item
NEXTITEM=""

# DIALOG()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
DIALOG() {
    dialog --backtitle "${TITLE}" --aspect 15 "$@"
    return $?
}

# chroot_mount()
# prepares target system as a chroot
#
chroot_mount()
{
    [[ -e "${DESTDIR}/proc" ]] || mkdir -m 555 "${DESTDIR}/proc"
    [[ -e "${DESTDIR}/sys" ]] || mkdir -m 555 "${DESTDIR}/sys"
    [[ -e "${DESTDIR}/dev" ]] || mkdir -m 755 "${DESTDIR}/dev"
    mount proc "${DESTDIR}/proc" -t proc -o nosuid,noexec,nodev 
    mount sys "${DESTDIR}/sys" -t sysfs -o nosuid,noexec,nodev,ro
    mount udev "${DESTDIR}/dev" -t devtmpfs -o mode=0755,nosuid 
    mount devpts "${DESTDIR}/dev/pts" -t devpts -o mode=0620,gid=5,nosuid,noexec
    mount shm "${DESTDIR}/dev/shm" -t tmpfs -o mode=1777,nosuid,nodev
}

# chroot_umount()
# tears down chroot in target system
#
chroot_umount()
{
    umount -R "${DESTDIR}/proc"
    umount -R "${DESTDIR}/sys"
    umount -R "${DESTDIR}/dev"
}

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

# list all net devices with mac adress
net_interfaces() {
    find /sys/class/net/* -type l -printf '%f ' -exec cat {}/address \;
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

# destdir_mounts()
# check if PART_ROOT is set and if something is mounted on ${DESTDIR}
destdir_mounts(){
    # Don't ask for filesystem and create new filesystems
    ASK_MOUNTPOINTS=""
    PART_ROOT=""
    # check if something is mounted on ${DESTDIR}
    PART_ROOT="$(mount | grep "${DESTDIR} " | cut -d' ' -f 1)"
    # Run mountpoints, if nothing is mounted on ${DESTDIR}
    if [[ "${PART_ROOT}" = "" ]]; then
        DIALOG --msgbox "Setup couldn't detect mounted partition(s) in ${DESTDIR}, please set mountpoints first." 0 0
        detect_uefi_boot
        mountpoints || return 1
    fi
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
         if ! ${_LSBLK} TYPE "${dev}" | grep -q "dmraid" || ${_LSBLK} FSTYPE "${dev}" | grep -q "iso9660" || ${_LSBLK} FSTYPE "${dev}" | grep -q "isw_raid_member" || ${_LSBLK} FSTYPE "${dev}" | grep -q "ddf_raid_member"; then
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
    for part in $(${_LSBLK} NAME,TYPE | grep "part$"| cut -d' ' -f1); do
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
        if ! (${_LSBLK} FSTYPE "${part}" | grep -q "linux_raid_member" || ${_LSBLK} FSTYPE "${part}" | grep -q "LVM2_member" || ${_LSBLK} FSTYPE "${part}" | grep -q "crypto_LUKS" || sfdisk -l 2>/dev/null | grep "${part}" | grep -q "Extended$" || sfdisk -l 2>/dev/null | grep "${part}" | grep -q "(LBA)$" || echo "${part}" | grep -q "[a-z]$(parted -s "$(${_LSBLK} PKNAME "${part}")" print 2>/dev/null | grep bios_grub | cut -d " " -f 2)$" || ${_LSBLK} FSTYPE -s "${part}" | grep -q "iso9660"); then
            echo "${part}"
            [[ "${1}" ]] && echo "${1}"
        fi           
    done
    printk on
}

# list none partitionable raid md devices
raid_devices() {
    for dev in $(${_LSBLK} NAME,TYPE | grep " raid.*$" | cut -d' ' -f 1 | grep -v "_d.*$" | sort -u); do
        # exclude checks:
        # - part of lvm2 device_found
        #   ${_LSBLK} FSTYPE ${dev} | grep "LVM2_member"
        # - part of luks device
        #   ${_LSBLK} FSTYPE ${dev} | grep "crypto_LUKS"
        # - part of isw fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s | grep "isw_raid_member"
        # - part of ddf fakeraid
        #   ${_LSBLK} FSTYPE ${dev} -s | grep "ddf_raid_member"
        if ! (${_LSBLK} FSTYPE "${dev}" | grep -q "LVM2_member" || ${_LSBLK} FSTYPE "${dev}" | grep -q "crypto_LUKS" || ${_LSBLK} FSTYPE "${dev}" -s | grep -q "isw_raid_member" || ${_LSBLK} FSTYPE "${dev}" -s | grep -q "ddf_raid_member"); then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

# lists default linux partitionable raid devices
partitionable_raid_devices() {
    for dev in $(${_LSBLK} NAME,TYPE | grep " raid.*$" | cut -d' ' -f 1 | grep "_d.*$" | sort -u); do
        echo "${dev}"
        [[ "${1}" ]] && echo "${1}"
    done
}

# lists linux partitionable raid devices partitions
partitionable_raid_devices_partitions() {
    for part in $(${_LSBLK} NAME,TYPE | grep "md$" | cut -d' ' -f 1 | sort -u) ; do
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
        if ! (${_LSBLK} FSTYPE "${part}" | grep -q "LVM2_member" || ${_LSBLK} FSTYPE "${part}" | grep -q "crypto_LUKS" || sfdisk -l 2>/dev/null | grep "${part}" | grep -q "Extended$" || sfdisk -l 2>/dev/null | grep "${part}" | grep -q "(LBA)$" || ${_LSBLK} FSTYPE "${dev}" -s | grep -q "isw_raid_member" || ${_LSBLK} FSTYPE "${dev}" -s | grep -q "ddf_raid_member"); then
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
    for dev in $(${_LSBLK} NAME,TYPE "${i}" | grep " raid.*$" | cut -d' ' -f 1 | sort -u); do
        if [[ "$(${_LSBLK} NAME,FSTYPE -s | grep "isw_raid_member$" | cut -d' ' -f 1)" ]]; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
    # ddf_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE "${i}" | grep " raid.*$" | cut -d' ' -f 1 | sort -u); do
        if [[ "$(${_LSBLK} NAME,FSTYPE -s | grep "ddf_raid_member$" | cut -d' ' -f 1)" ]]; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

# dmraid_partitions
# - show dmraid partitions
dmraid_partitions() {
    for part in $(${_LSBLK} NAME,TYPE  | grep "dmraid$" | cut -d' ' -f 1 | grep "_.*p.*$" | sort -u); do
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
        if ! (${_LSBLK} FSTYPE "${part}" | grep -q "crypto_LUKS$" || ${_LSBLK} FSTYPE "${part}" | grep -q "LVM2_member$" || ${_LSBLK} FSTYPE "${part}" | grep -q "linux_raid_member$" || sfdisk -l 2>/dev/null | grep "${part}" | grep -q "Extended$"|| sfdisk -l 2>/dev/null | grep "${part}" | grep -q "(LBA)$"); then
            echo "${part}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
    # isw_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE "${i}" | grep " md$" | cut -d' ' -f 1 | sort -u); do
        if [[ "$(${_LSBLK} NAME,FSTYPE -s | grep "isw_raid_member$" | cut -d' ' -f 1)" ]]; then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
    # ddf_raid_member, managed by mdadm
    for dev in $(${_LSBLK} NAME,TYPE "${i}" | grep " md$" | cut -d' ' -f 1 | sort -u); do
        if [[ "$(${_LSBLK} NAME,FSTYPE -s | grep "ddf_raid_member$" | cut -d' ' -f 1)" ]]; then
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
        if ! (${_LSBLK} FSTYPE "${dev}" | grep -q "crypto_LUKS$" || ${_LSBLK} FSTYPE "${dev}" | grep -q "LVM2_member$" || ${_LSBLK} FSTYPE "${dev}" | grep -q "linux_raid_member$" || ${_LSBLK} TYPE "${dev}" | grep -q "raid.*$"); then
            echo "${dev}"
            [[ "${1}" ]] && echo "${1}"
        fi
    done
}

finddisks() {
    blockdevices "${1}"
    dmraid_devices "${1}"
    partitionable_raid_devices "${1}"
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
    for i in $(finddisks); do
        [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${i}")" == "gpt" ]] && GUID_DETECTED="1"
    done
}

# freeze and unfreeze xfs, as hack for grub(2) installing
freeze_xfs() {
    sync
    if [[ -x /usr/bin/xfs_freeze ]]; then
        if grep -q "${DESTDIR}/boot " /proc/mounts | grep -q " xfs "; then
            xfs_freeze -f ${DESTDIR}/boot >/dev/null 2>&1
            xfs_freeze -u ${DESTDIR}/boot >/dev/null 2>&1
        fi
        if grep -q "${DESTDIR} " /proc/mounts | grep -q " xfs "; then
            xfs_freeze -f ${DESTDIR} >/dev/null 2>&1
            xfs_freeze -u ${DESTDIR} >/dev/null 2>&1
        fi
    fi
}

printk()
{
    case ${1} in
        "on")  echo 4 >/proc/sys/kernel/printk ;;
        "off") echo 0 >/proc/sys/kernel/printk ;;
    esac
}

getdest() {
    [[ "${DESTDIR}" ]] && return 0
    DIALOG --inputbox "Enter the destination directory where your target system is mounted" 8 65 "${DESTDIR}" 2>${ANSWER} || return 1
    DESTDIR=$(cat ${ANSWER})
}

# geteditor()
# prompts the user to choose an editor
# sets EDITOR global variable
#
geteditor() {
    if ! [[ "${EDITOR}" ]]; then
        DIALOG --menu "Select a Text Editor to Use" 10 35 3 \
        "1" "nano (easier)" \
        "2" "vi" 2>${ANSWER} || return 1
        case $(cat ${ANSWER}) in
            "1") EDITOR="nano" ;;
            "2") EDITOR="vi" ;;
        esac
    fi
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
    DIALOG --menu "Select the device name scheme you want to use in config files. ${MENU_DESC_TEXT} FSUUID is recommended." 15 70 9 ${NAME_SCHEME_LEVELS} 2>${ANSWER} || return 1
    NAME_SCHEME_PARAMETER=$(cat ${ANSWER})
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
    for i in $(finddisks); do
        ${_LSBLK} NAME,SIZE -d "${i}"
    done
}

# Get a list of available partitions for use in the "Available Mountpoints" dialogs. 
# This will print the mountpoints as follows, getting size info from lsblk:
#   /dev/sda1 640M
_getavailpartitions()
{
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
            DIALOG --infobox "Disabling all software raid devices..." 0 0
            while read -r i; do
               mdadm --manage --stop "/dev/$(echo "${i}" | sed -e 's# :.*##g')" > ${LOG}
            done < /proc/mdstat 
            DIALOG --infobox "Cleaning superblocks of all software raid devices..." 0 0
            for i in $(${_LSBLK} NAME,FSTYPE | grep "linux_raid_member$" | cut -d' ' -f 1); do
                mdadm --zero-superblock "${i}" > ${LOG}
            done
        fi
    fi
    DISABLEMDSB=""
    if ${_LSBLK} FSTYPE | grep -q "linux_raid_member"; then
        DIALOG --defaultno --yesno "Setup detected superblock of raid devices, do you want to clean the superblock of them?" 0 0 && DISABLEMDSB="1"
        if [[ "${DISABLEMDSB}" = "1" ]]; then
            DIALOG --infobox "Cleaning superblocks of all software raid devices..." 0 0
            for i in $(${_LSBLK} NAME,FSTYPE | grep "linux_raid_member$" | cut -d' ' -f 1); do
                mdadm --zero-superblock "${i}" > ${LOG}
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
        DIALOG --infobox "Removing logical volumes ..." 0 0
        for i in ${LV_VOLUMES}; do
            lvremove -f "/dev/mapper/${i}" 2>/dev/null> ${LOG}
        done
        DIALOG --infobox "Removing logical groups ..." 0 0
        for i in ${LV_GROUPS}; do
            vgremove -f "${i}" 2>/dev/null > ${LOG}
        done
        DIALOG --infobox "Removing physical volumes ..." 0 0
        for i in ${LV_PHYSICAL}; do
            pvremove -f "${i}" 2>/dev/null > ${LOG}
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
    ! [[ "${LUKSDEVICE}" = "" ]] && DETECTED_LUKS=1
    if [[ "${DETECTED_LUKS}" = "1" ]]; then
        DIALOG --defaultno --yesno "Setup detected running luks encrypted devices, do you want to remove them completely?" 0 0 && DISABLELUKS="1"
    fi
    if [[ "${DISABLELUKS}" = "1" ]]; then
        DIALOG --infobox "Removing luks encrypted devices ..." 0 0
        for i in ${LUKSDEVICE}; do
            LUKS_REAL_DEVICE="$(${_LSBLK} NAME,FSTYPE -s "${LUKSDEVICE}" | grep " crypto_LUKS$" | cut -d' ' -f1)"
            cryptsetup remove "${i}" > ${LOG}
            # delete header from device
            wipefs -a "${LUKS_REAL_DEVICE}" >/dev/null 2>&1
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
           wipefs -a "${i}" >/dev/null 2>&1
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
        RAID_BLACKLIST="$(for i in $(${_LSBLK} NAME,TYPE | grep " raid.*$" | cut -d' ' -f1 | sort -u); do 
                    echo "$(${_LSBLK} NAME "${i}")" _
                    done)"
        PARTS="$(for i in $(findpartitions); do 
                ! echo "${RAID_BLACKLIST}" | grep -qE "${i} _" && echo "${i}" _ 
                done)"
        # break if all devices are in use
        if [[ "${PARTS}" = "" ]]; then
            DIALOG --msgbox "All devices in use. No more devices left for new creation." 0 0
            return 1
        fi
        # enter raid device name
        RAIDDEVICE=""
        while [[ "${RAIDDEVICE}" = "" ]]; do
            if [[ "${RAID_PARTITION}" = "" ]]; then
                DIALOG --inputbox "Enter the node name for the raiddevice:\n/dev/md[number]\n/dev/md0\n/dev/md1\n\n" 15 65 "/dev/md0" 2>${ANSWER} || return 1
            fi
            if [[ "${RAID_PARTITION}" = "1" ]]; then
                DIALOG --inputbox "Enter the node name for partitionable raiddevice:\n/dev/md_d[number]\n/dev/md_d0\n/dev/md_d1" 15 65 "/dev/md_d0" 2>${ANSWER} || return 1
            fi
            RAIDDEVICE=$(cat ${ANSWER})
            if grep -q "^${RAIDDEVICE//\/dev\//}" /proc/mdstat; then
                DIALOG --msgbox "ERROR: You have defined 2 identical node names! Please enter another name." 8 65
                RAIDDEVICE=""
            fi
        done
        RAIDLEVELS="linear - raid0 - raid1 - raid4 - raid5 - raid6 - raid10 -"
        #shellcheck disable=SC2086
        DIALOG --menu "Select the raid level you want to use" 21 50 11 ${RAIDLEVELS} 2>${ANSWER} || return 1
        LEVEL=$(cat ${ANSWER})
        # raid5 and raid10 support parity parameter
        PARITY=""
        if [[ "${LEVEL}" = "raid5" || "${LEVEL}" = "raid6" || "${LEVEL}" = "raid10" ]]; then
            PARITYLEVELS="left-asymmetric - left-symmetric - right-asymmetric - right-symmetric -"
            #shellcheck disable=SC2086
            DIALOG --menu "Select the parity layout you want to use (default is left-symmetric)" 21 50 13 ${PARITYLEVELS} 2>${ANSWER} || return 1
            PARITY=$(cat ${ANSWER})
        fi
        # show all devices with sizes
        DIALOG --cr-wrap --msgbox "DISKS:\n$(_getavaildisks)\n\nPARTITIONS:\n$(_getavailpartitions)" 0 0
        # select the first device to use, no missing option available!
        RAIDNUMBER=1
        #shellcheck disable=SC2086
        DIALOG --menu "Select device ${RAIDNUMBER}" 21 50 13 ${PARTS} 2>${ANSWER} || return 1
        PART=$(cat ${ANSWER})
        echo "${PART}" >>/tmp/.raid
        while [[ "${PART}" != "DONE" ]]; do
            RAIDNUMBER=$((RAIDNUMBER + 1))
            # clean loop from used partition and options
            PARTS="$(echo "${PARTS}" | sed -e "s#${PART}\ _##g" -e 's#MISSING\ _##g' -e 's#SPARE\ _##g')"
            # raid0 doesn't support missing devices
            ! [[ "${LEVEL}" = "raid0" || "${LEVEL}" = "linear" ]] && MDEXTRA="MISSING _"
            # add more devices
            #shellcheck disable=SC2086
            DIALOG --menu "Select additional device ${RAIDNUMBER}" 21 50 13 ${PARTS} ${MDEXTRA} DONE _ 2>${ANSWER} || return 1
            PART=$(cat ${ANSWER})
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
        DIALOG --yesno "Would you like to create ${RAIDDEVICE} like this?\n\nLEVEL:\n${LEVEL}\n\nDEVICES:\n$(while read -r i;do echo "${i}\n"; done < /tmp/.raid)\nSPARES:\n$(while read -r i;do echo "${i}\n"; done < tmp/.raid-spare)" 0 0 && MDFINISH="DONE"
    done
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
    echo "${RAIDDEVICE}" | grep -q "/md_d[0-9]" && RAIDOPTIONS="${RAIDOPTIONS} -a mdp"
    ! [[ "${RAID_DEVICES}" = "0" ]] && RAIDOPTIONS="${RAIDOPTIONS} --raid-devices=${RAID_DEVICES}"
    ! [[ "${SPARE_DEVICES}" = "0" ]] && RAIDOPTIONS="${RAIDOPTIONS} --spare-devices=${SPARE_DEVICES}"
    ! [[ "${PARITY}" = "" ]] && RAIDOPTIONS="${RAIDOPTIONS} --layout=${PARITY}"
    DIALOG --infobox "Creating ${RAIDDEVICE}..." 0 0
    mdadm --create ${RAIDDEVICE} ${RAIDOPTIONS} ${DEVICES} >${LOG} 2>&1 || \
    (DIALOG --msgbox "Error creating ${RAIDDEVICE} (see ${LOG} for details)." 0 0; return 1)
    if echo "${RAIDDEVICE}" | grep -q "/md_d[0-9"]; then
        # switch for mbr usage
        set_guid
        if [[ "${GUIDPARAMETER}" = "" ]]; then
            DIALOG --msgbox "Now you'll be put into the parted program where you can partition your raiddevice to your needs." 18 70
            parted -a optimal -s "${RAIDDEVICE}" mktable msdos
            clear
            parted "${RAIDDEVICE}" print
            parted "${RAIDDEVICE}"
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
        DIALOG --menu "Select device number ${DEVNUMBER} for physical volume" 21 50 13 ${PARTS} 2>${ANSWER} || return 1
        PART=$(cat ${ANSWER})
        echo "${PART}" >>/tmp/.pvs-create
        while [[ "${PART}" != "DONE" ]]; do
            DEVNUMBER="$((DEVNUMBER + 1))"
            # clean loop from used partition and options
            PARTS="${PARTS//${PART}\ _/}"
            # add more devices
            #shellcheck disable=SC2086
            DIALOG --menu "Select additional device number ${DEVNUMBER} for physical volume" 21 50 13 ${PARTS} DONE _ 2>${ANSWER} || return 1
            PART=$(cat ${ANSWER})
            [[ "${PART}" = "DONE" ]] && break
            echo "${PART}" >>/tmp/.pvs-create
        done
        # final step ask if everything is ok?
        DIALOG --yesno "Would you like to create physical volume on devices below?\n$(sed -e 's#$#\\n#g' /tmp/.pvs-create)" 0 0 && PVFINISH="DONE"
    done
    DIALOG --infobox "Creating physical volume on ${PART}..." 0 0
    PART="$(echo -n "$(cat /tmp/.pvs-create)")"
    pvcreate -y ${PART} >${LOG} 2>&1 || (DIALOG --msgbox "Error creating physical volume on ${PART} (see ${LOG} for details)." 0 0; return 1)
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
            DIALOG --inputbox "Enter the Volume Group name:\nfoogroup\n<yourvolumegroupname>\n\n" 15 65 "foogroup" 2>${ANSWER} || return 1
            VGDEVICE=$(cat ${ANSWER})
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
        DIALOG --menu "Select Physical Volume ${PVNUMBER} for ${VGDEVICE}" 21 50 13 ${PVS} 2>${ANSWER} || return 1
        PV=$(cat ${ANSWER})
        echo "${PV}" >>/tmp/.pvs
        while [[ "${PVS}" != "DONE" ]]; do
            PVNUMBER=$((PVNUMBER + 1))
            # clean loop from used partition and options
            PVS="$(echo ${PVS} | sed -e "s#${PV} _##g")"
            # add more devices
            #shellcheck disable=SC2086
            DIALOG --menu "Select additional Physical Volume ${PVNUMBER} for ${VGDEVICE}" 21 50 13 ${PVS} DONE _ 2>${ANSWER} || return 1
            PV=$(cat ${ANSWER})
            [[ "${PV}" = "DONE" ]] && break
            echo "${PV}" >>/tmp/.pvs
        done
        # final step ask if everything is ok?
        DIALOG --yesno "Would you like to create Volume Group like this?\n\n${VGDEVICE}\n\nPhysical Volumes:\n$(sed -e 's#$#\\n#g' /tmp/.pvs)" 0 0 && VGFINISH="DONE"
    done
    DIALOG --infobox "Creating Volume Group ${VGDEVICE}..." 0 0
    PV="$(echo -n "$(cat /tmp/.pvs)")"
    vgcreate ${VGDEVICE} ${PV} >${LOG} 2>&1 || (DIALOG --msgbox "Error creating Volume Group ${VGDEVICE} (see ${LOG} for details)." 0 0; return 1)
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
        DIALOG --menu "Select Volume Group" 21 50 13 ${LVS} 2>${ANSWER} || return 1
        LV=$(cat ${ANSWER})
        # enter logical volume name
        LVDEVICE=""
        while [[ "${LVDEVICE}" = "" ]]; do
            DIALOG --inputbox "Enter the Logical Volume name:\nfooname\n<yourvolumename>\n\n" 15 65 "fooname" 2>${ANSWER} || return 1
            LVDEVICE=$(cat ${ANSWER})
            if lvs -o lv_name,vg_name --noheading 2>/dev/null | grep -q " ${LVDEVICE} ${LV}$"; then
                DIALOG --msgbox "ERROR: You have defined 2 identical Logical Volume names! Please enter another name." 8 65
                LVDEVICE=""
            fi
        done
        while [[ "${LV_SIZE_SET}" = "" ]]; do
            LV_ALL=""
            DIALOG --inputbox "Enter the size (MB) of your Logical Volume,\nMinimum value is > 0.\n\nVolume space left: $(vgs -o vg_free --noheading --units m "${LV}")B\n\nIf you enter no value, all free space left will be used." 10 65 "" 2>${ANSWER} || return 1
                LV_SIZE=$(cat ${ANSWER})
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
    DIALOG --infobox "Creating Logical Volume ${LVDEVICE}..." 0 0
    if [[ "${LV_ALL}" = "1" ]]; then
        lvcreate ${LV_EXTRA} -l +100%FREE ${LV} -n ${LVDEVICE} >${LOG} 2>&1 || (DIALOG --msgbox "Error creating Logical Volume ${LVDEVICE} (see ${LOG} for details)." 0 0; return 1)
    else
        lvcreate ${LV_EXTRA} -L ${LV_SIZE} ${LV} -n ${LVDEVICE} >${LOG} 2>&1 || (DIALOG --msgbox "Error creating Logical Volume ${LVDEVICE} (see ${LOG} for details)." 0 0; return 1)
    fi
}

# enter luks name
_enter_luks_name() {
    LUKSDEVICE=""
    while [[ "${LUKSDEVICE}" = "" ]]; do
        DIALOG --inputbox "Enter the name for luks encrypted device ${PART}:\nfooname\n<yourname>\n\n" 15 65 "fooname" 2>${ANSWER} || return 1
        LUKSDEVICE=$(cat ${ANSWER})
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
        DIALOG --insecure --passwordbox "Enter passphrase for luks encrypted device ${PART}:" 0 0 2>${ANSWER} || return 1
        LUKSPASS=$(cat ${ANSWER})
        DIALOG --insecure --passwordbox "Retype passphrase for luks encrypted device ${PART}:" 0 0 2>${ANSWER} || return 1
        LUKSPASS2=$(cat ${ANSWER})
        if [[ -n "${LUKSPASS}" && -n "${LUKSPASS2}" && "${LUKSPASS}" = "${LUKSPASS2}" ]]; then
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
        cryptsetup luksOpen "${PART}" "${LUKSDEVICE}" >${LOG} <${LUKSPASSPHRASE} && luksOpen_success=1
        if [[ "${luksOpen_success}" = "0" ]]; then
            DIALOG --msgbox "Error: Passphrases didn't match, please enter again." 0 0
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
system by inserting a boot CD, for example. Encrypting the root partition\n
prevents anyone from using this method to insert viruses or trojans onto\n
your computer.\n\n
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
                    ${_LSBLK} NAME "${i}" _
                    done)"
        PARTS="$(for i in $(findpartitions); do 
                ! echo "${CRYPT_BLACKLIST}" | grep -Eq "${i} _" && echo "${i}" _ 
                done)"
        # break if all devices are in use
        if [[ "${PARTS}" = "" ]]; then
            DIALOG --msgbox "No devices left for luks encryption." 0 0
            return 1
        fi
        # show all devices with sizes
        DIALOG --cr-wrap --msgbox "DISKS:\n$(_getavaildisks)\n\nPARTITIONS:\n$(_getavailpartitions)\n\n" 0 0
        #shellcheck disable=SC2086
        DIALOG --menu "Select device for luks encryption" 21 50 13 ${PARTS} 2>${ANSWER} || return 1
        PART=$(cat ${ANSWER})
        # enter luks name
        _enter_luks_name
        ### TODO: offer more options for encrypt!
        ###       defaults are used only
        # final step ask if everything is ok?
        DIALOG --yesno "Would you like to encrypt luks device below?\nName:${LUKSDEVICE}\nDevice:${PART}\n" 0 0 && LUKSFINISH="DONE"
    done
    _enter_luks_passphrase || return 1
    DIALOG --infobox "Encrypting ${PART}..." 0 0
    cryptsetup luksFormat "${PART}" >${LOG} <${LUKSPASSPHRASE}
    _opening_luks
}

autoprepare() {
    # check on encrypted devices, else weird things can happen!
    _stopluks
    # check on raid devices, else weird things can happen during partitioning!
    _stopmd
    # check on lvm devices, else weird things can happen during partitioning!
    _stoplvm
    NAME_SCHEME_PARAMETER_RUN=""
    # switch for mbr usage
    set_guid
    : >/tmp/.device-names
    DISCS=$(blockdevices)
    if [[ "$(echo "${DISCS}" | wc -w)" -gt 1 ]]; then
        DIALOG --cr-wrap --msgbox "Available Disks:\n\n$(_getavaildisks)\n" 0 0
        #shellcheck disable=SC2046
        DIALOG --menu "Select the storage drive to use" 14 55 7 $(blockdevices _) 2>"${ANSWER}" || return 1
        DISC=$(cat ${ANSWER})
    else
        DISC="${DISCS}"
        if [[ "${DISC}" = "" ]]; then
            DIALOG --msgbox "ERROR: Setup cannot find available disk device, please use normal installation routine for partitioning and mounting devices." 0 0
            return 1
        fi
    fi
    BOOT_PART_SIZE=""
    GUID_PART_SIZE=""
    UEFISYS_PART_SIZE=""
    DEFAULTFS=""
    _UEFISYS_BOOTPART=""
    UEFISYS_MOUNTPOINT=""
    UEFISYS_PART_SET=""
    BOOT_PART_SET=""
    SWAP_PART_SET=""
    ROOT_PART_SET=""
    CHOSEN_FS=""
    # get just the disk size in 1000*1000 MB
    DISC_SIZE="$(($(${_LSBLK} SIZE -d -b "${DISC}")/1000000))"
    if [[ "${DISC_SIZE}" = "" ]]; then
        DIALOG --msgbox "ERROR: Setup cannot detect size of your device, please use normal installation routine for partitioning and mounting devices." 0 0
        return 1
    fi
    
    if [[  "${GUIDPARAMETER}" = "yes" ]]; then
        DIALOG --inputbox "Enter the mountpoint of your UEFI SYSTEM PARTITION (Default is /boot) : " 0 0 "/boot" 2>"${ANSWER}" || return 1
        UEFISYS_MOUNTPOINT="$(cat ${ANSWER})"
    fi
    
    if [[ "${UEFISYS_MOUNTPOINT}" == "/boot" ]]; then
        DIALOG --msgbox "You have chosen to use /boot as the UEFISYS Mountpoint. The minimum partition size is 260 MiB and only FAT32 FS is supported" 0 0
        _UEFISYS_BOOTPART="1"
    fi
    
    while [[ "${DEFAULTFS}" = "" ]]; do
        FSOPTS=""
        [[ "$(which mkfs.ext2 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext2 Ext2"
        [[ "$(which mkfs.ext3 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext3 Ext3"
        [[ "$(which mkfs.ext4 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext4 Ext4"
        [[ "$(which mkfs.btrfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} btrfs Btrfs"
        [[ "$(which mkfs.nilfs2 2>/dev/null)" ]] && FSOPTS="${FSOPTS} nilfs2 Nilfs2"
        [[ "$(which mkfs.f2fs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} f2fs F2FS"
        [[ "$(which mkreiserfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} reiserfs Reiser3"
        [[ "$(which mkfs.xfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} xfs XFS"
        [[ "$(which mkfs.jfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} jfs JFS"

        # create 1 MB bios_grub partition for grub BIOS GPT support
        if [[ "${GUIDPARAMETER}" = "yes" ]]; then
            GUID_PART_SIZE="2"
            GPT_BIOS_GRUB_PART_SIZE="${GUID_PART_SIZE}"
            _PART_NUM="1"
            _GPT_BIOS_GRUB_PART_NUM="${_PART_NUM}"
            DISC_SIZE="$((DISC_SIZE-GUID_PART_SIZE))"
        fi
        
        if [[ "${GUIDPARAMETER}" = "yes" ]]; then
            if [[ "${_UEFISYS_BOOTPART}" == "1" ]]; then
                while [[ "${UEFISYS_PART_SET}" = "" ]]; do
                    DIALOG --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 260.\n\nDisk space left: ${DISC_SIZE} MB" 10 65 "1024" 2>${ANSWER} || return 1
                    UEFISYS_PART_SIZE="$(cat ${ANSWER})"
                    if [[ "${UEFISYS_PART_SIZE}" = "" ]]; then
                        DIALOG --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                    else
                        if [[ "${UEFISYS_PART_SIZE}" -ge "${DISC_SIZE}" || "${UEFISYS_PART_SIZE}" -lt "260" || "${UEFISYS_PART_SIZE}" = "${DISC_SIZE}" ]]; then
                            DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                        else
                            BOOT_PART_SET=1
                            UEFISYS_PART_SET=1
                            _PART_NUM="$((_PART_NUM+1))"
                            _UEFISYS_PART_NUM="${_PART_NUM}"
                        fi
                    fi
                done
            else
                while [[ "${UEFISYS_PART_SET}" = "" ]]; do
                    DIALOG --inputbox "Enter the size (MB) of your UEFI SYSTEM PARTITION,\nMinimum value is 260.\n\nDisk space left: ${DISC_SIZE} MB" 10 65 "1024" 2>${ANSWER} || return 1
                    UEFISYS_PART_SIZE="$(cat ${ANSWER})"
                    if [[ "${UEFISYS_PART_SIZE}" = "" ]]; then
                        DIALOG --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                    else
                        if [[ "${UEFISYS_PART_SIZE}" -ge "${DISC_SIZE}" || "${UEFISYS_PART_SIZE}" -lt "260" || "${UEFISYS_PART_SIZE}" = "${DISC_SIZE}" ]]; then
                            DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                        else
                            UEFISYS_PART_SET=1
                            _PART_NUM="$((_PART_NUM+1))"
                            _UEFISYS_PART_NUM="${_PART_NUM}"
                        fi
                    fi
                done
            fi
            DISC_SIZE="$((DISC_SIZE-UEFISYS_PART_SIZE))"
            
            while [[ "${BOOT_PART_SET}" = "" ]]; do
                DIALOG --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 16.\n\nDisk space left: ${DISC_SIZE} MB" 10 65 "512" 2>${ANSWER} || return 1
                BOOT_PART_SIZE="$(cat ${ANSWER})"
                if [[ "${BOOT_PART_SIZE}" = "" ]]; then
                    DIALOG --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${BOOT_PART_SIZE}" -ge "${DISC_SIZE}" || "${BOOT_PART_SIZE}" -lt "16" || "${BOOT_PART_SIZE}" = "${DISC_SIZE}" ]]; then
                        DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                    else
                        BOOT_PART_SET=1
                        _PART_NUM="$((_UEFISYS_PART_NUM+1))"
                        _BOOT_PART_NUM="${_PART_NUM}"
                        DISC_SIZE="$((DISC_SIZE-BOOT_PART_SIZE))"
                    fi
                fi
            done

        else
            while [[ "${BOOT_PART_SET}" = "" ]]; do
                DIALOG --inputbox "Enter the size (MB) of your /boot partition,\nMinimum value is 16.\n\nDisk space left: ${DISC_SIZE} MB" 10 65 "512" 2>${ANSWER} || return 1
                BOOT_PART_SIZE="$(cat ${ANSWER})"
                if [[ "${BOOT_PART_SIZE}" = "" ]]; then
                    DIALOG --msgbox "ERROR: You have entered a invalid size, please enter again." 0 0
                else
                    if [[ "${BOOT_PART_SIZE}" -ge "${DISC_SIZE}" || "${BOOT_PART_SIZE}" -lt "16" || "${BOOT_PART_SIZE}" = "${DISC_SIZE}" ]]; then
                        DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                    else
                         BOOT_PART_SET=1
                        _PART_NUM="1"
                        _BOOT_PART_NUM="${_PART_NUM}"
                        DISC_SIZE="$((DISC_SIZE-BOOT_PART_SIZE))"
                    fi
                fi
            done
        fi
        
        SWAP_SIZE="256"
        [[ "${DISC_SIZE}" -lt "256" ]] && SWAP_SIZE="${DISC_SIZE}"
        while [[ "${SWAP_PART_SET}" = "" ]]; do
            DIALOG --inputbox "Enter the size (MB) of your swap partition,\nMinimum value is > 0.\n\nDisk space left: ${DISC_SIZE} MB" 10 65 "${SWAP_SIZE}" 2>"${ANSWER}" || return 1
            SWAP_PART_SIZE=$(cat ${ANSWER})
            if [[ "${SWAP_PART_SIZE}" = "" || "${SWAP_PART_SIZE}" = "0" ]]; then
                DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
            else
                if [[ "${SWAP_PART_SIZE}" -ge "${DISC_SIZE}" ]]; then
                    DIALOG --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                else
                    SWAP_PART_SET=1
                    _PART_NUM="$((_PART_NUM+1))"
                    _SWAP_PART_NUM="${_PART_NUM}"
                fi
            fi
        done
        
        while [[ "${CHOSEN_FS}" = "" ]]; do
            #shellcheck disable=SC2086
            DIALOG --menu "Select a filesystem for / and /home:" 16 45 9 ${FSOPTS} 2>${ANSWER} || return 1
            FSTYPE=$(cat ${ANSWER})
            DIALOG --yesno "${FSTYPE} will be used for / and /home. Is this OK?" 0 0 && CHOSEN_FS=1
        done
        # / and /home are subvolumes on btrfs
        if ! [[ "${FSTYPE}" = "btrfs" ]]; then
            DISC_SIZE="$((DISC_SIZE-SWAP_PART_SIZE))"
            ROOT_SIZE="7500"
            [[ "${DISC_SIZE}" -lt "7500" ]] && ROOT_SIZE="${DISC_SIZE}"
            while [[ "${ROOT_PART_SET}" = "" ]]; do
            DIALOG --inputbox "Enter the size (MB) of your / partition\nMinimum value is 2000,\nthe /home partition will use the remaining space.\n\nDisk space left:  ${DISC_SIZE} MB" 10 65 "${ROOT_SIZE}" 2>"${ANSWER}" || return 1
            ROOT_PART_SIZE=$(cat ${ANSWER})
                if [[ "${ROOT_PART_SIZE}" = "" || "${ROOT_PART_SIZE}" = "0" || "${ROOT_PART_SIZE}" -lt "2000" ]]; then
                    DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
                else
                    if [[ "${ROOT_PART_SIZE}" -ge "${DISC_SIZE}" ]]; then
                        DIALOG --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                    else
                        DIALOG --yesno "$((DISC_SIZE-ROOT_PART_SIZE)) MB will be used for your /home partition. Is this OK?" 0 0 && ROOT_PART_SET=1
                    fi
                fi
            done
        fi
        _PART_NUM="$((_PART_NUM+1))"
        _ROOT_PART_NUM="${_PART_NUM}"
        if ! [[ "${FSTYPE}" = "btrfs" ]]; then            
            _PART_NUM="$((_PART_NUM+1))"
        fi
        _HOME_PART_NUM="${_PART_NUM}"
        DEFAULTFS=1
    done
    
    DIALOG --defaultno --yesno "${DISC} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 \
    || return 1
    DEVICE=${DISC}

    # validate DEVICE
    if [[ ! -b "${DEVICE}" ]]; then
      DIALOG --msgbox "Device '${DEVICE}' is not valid" 0 0
      return 1
    fi

    # validate DEST
    if [[ ! -d "${DESTDIR}" ]]; then
        DIALOG --msgbox "Destination directory '${DESTDIR}' is not valid" 0 0
        return 1
    fi

    [[ -e /tmp/.fstab ]] && rm -f /tmp/.fstab
    # disable swap and all mounted partitions, umount / last!
    _umountall
    
    # we assume a /dev/sdX,/dev/vdX or /dev/nvmeXnY format
    if [[ "${GUIDPARAMETER}" == "yes" ]]; then
        # GPT (GUID) is supported only by 'parted' or 'sgdisk'
        printk off
        DIALOG --infobox "Partitioning ${DEVICE}" 0 0
        # clean partition table to avoid issues!
        sgdisk --zap "${DEVICE}" &>/dev/null
        # clear all magic strings/signatures - mdadm, lvm, partition tables etc.
        dd if=/dev/zero of="${DEVICE}" bs=512 count=2048 &>/dev/null
        wipefs -a "${DEVICE}" &>/dev/null
        # create fresh GPT
        sgdisk --clear "${DEVICE}" &>/dev/null
        # create actual partitions
        sgdisk --set-alignment="2048" --new=${_GPT_BIOS_GRUB_PART_NUM}:0:+${GPT_BIOS_GRUB_PART_SIZE}M --typecode=${_GPT_BIOS_GRUB_PART_NUM}:EF02 --change-name=${_GPT_BIOS_GRUB_PART_NUM}:BIOS_GRUB "${DEVICE}" > ${LOG}
        sgdisk --set-alignment="2048" --new=${_UEFISYS_PART_NUM}:0:+"${UEFISYS_PART_SIZE}"M --typecode=${_UEFISYS_PART_NUM}:EF00 --change-name=${_UEFISYS_PART_NUM}:UEFI_SYSTEM "${DEVICE}" > ${LOG}
        
        if [[ "${_UEFISYS_BOOTPART}" == "1" ]]; then
            sgdisk --attributes=${_UEFISYS_PART_NUM}:set:2 "${DEVICE}" > ${LOG}
        else
            sgdisk --set-alignment="2048" --new=${_BOOT_PART_NUM}:0:+"${BOOT_PART_SIZE}"M --typecode=${_BOOT_PART_NUM}:8300 --attributes=${_BOOT_PART_NUM}:set:2 --change-name=${_BOOT_PART_NUM}:ARCHLINUX_BOOT "${DEVICE}" > ${LOG}
        fi
        
        sgdisk --set-alignment="2048" --new=${_SWAP_PART_NUM}:0:+"${SWAP_PART_SIZE}"M --typecode=${_SWAP_PART_NUM}:8200 --change-name=${_SWAP_PART_NUM}:ARCHLINUX_SWAP "${DEVICE}" > ${LOG}
        if [[ "${FSTYPE}" = "btrfs" ]]; then
            sgdisk --set-alignment="2048" --new=${_ROOT_PART_NUM}:0:0 --typecode=${_ROOT_PART_NUM}:8300 --change-name=${_ROOT_PART_NUM}:ARCHLINUX_ROOT "${DEVICE}" > ${LOG}
        else
            sgdisk --set-alignment="2048" --new=${_ROOT_PART_NUM}:0:+"${ROOT_PART_SIZE}"M --typecode=${_ROOT_PART_NUM}:8300 --change-name=${_ROOT_PART_NUM}:ARCHLINUX_ROOT "${DEVICE}" > ${LOG}
            sgdisk --set-alignment="2048" --new=${_HOME_PART_NUM}:0:0 --typecode=${_HOME_PART_NUM}:8302 --change-name=${_HOME_PART_NUM}:ARCHLINUX_HOME "${DEVICE}" > ${LOG}
        fi
        sgdisk --print "${DEVICE}" > ${LOG}
    else
        # start at sector 1 for 4k drive compatibility and correct alignment
        printk off
        DIALOG --infobox "Partitioning ${DEVICE}" 0 0
        # clean partitiontable to avoid issues!
        dd if=/dev/zero of="${DEVICE}" bs=512 count=2048 >/dev/null 2>&1
        wipefs -a "${DEVICE}" &>/dev/null
        # create DOS MBR with parted
        parted -a optimal -s "${DEVICE}" unit MiB mktable msdos >/dev/null 2>&1
        parted -a optimal -s "${DEVICE}" unit MiB mkpart primary 1 $((GUID_PART_SIZE+BOOT_PART_SIZE)) >${LOG}
        parted -a optimal -s "${DEVICE}" unit MiB set 1 boot on >${LOG}
        parted -a optimal -s "${DEVICE}" unit MiB mkpart primary $((GUID_PART_SIZE+BOOT_PART_SIZE)) $((GUID_PART_SIZE+BOOT_PART_SIZE+SWAP_PART_SIZE)) >${LOG}
        # $(sgdisk -E ${DEVICE}) | grep ^[0-9] as end of last partition to keep the possibilty to convert to GPT later, instead of 100%
        if [[ "${FSTYPE}" = "btrfs" ]]; then
            parted -a optimal -s "${DEVICE}" unit MiB mkpart primary $((GUID_PART_SIZE+BOOT_PART_SIZE+SWAP_PART_SIZE)) "$(sgdisk -E "${DEVICE}" | grep "^[0-9]")S" >${LOG}
        else
            parted -a optimal -s "${DEVICE}" unit MiB mkpart primary $((GUID_PART_SIZE+BOOT_PART_SIZE+SWAP_PART_SIZE)) $((GUID_PART_SIZE+BOOT_PART_SIZE+SWAP_PART_SIZE+ROOT_PART_SIZE)) >${LOG}
            parted -a optimal -s "${DEVICE}" unit MiB mkpart primary $((GUID_PART_SIZE+BOOT_PART_SIZE+SWAP_PART_SIZE+ROOT_PART_SIZE)) "$(sgdisk -E "${DEVICE}" | grep "^[0-9]")S" >${LOG}
        fi
    fi
    if [[ $? -gt 0 ]]; then
        DIALOG --msgbox "Error partitioning ${DEVICE} (see ${LOG} for details)" 0 0
        printk on
        return 1
    fi
    # reread partitiontable for kernel
    partprobe "${DEVICE}"
    printk on
    ## wait until /dev initialized correct devices
    udevadm settle

    if [[ "${NAME_SCHEME_PARAMETER_RUN}" == "" ]]; then
        set_device_name_scheme || return 1
    fi
    ## FSSPECS - default filesystem specs (the + is bootable flag)
    ## <partnum>:<mountpoint>:<partsize>:<fstype>[:<fsoptions>][:+]:labelname
    ## The partitions in FSSPECS list should be listed in the "mountpoint" order.
    ## Make sure the "root" partition is defined first in the FSSPECS list
    
    _FSSPEC_ROOT_PART="${_ROOT_PART_NUM}:/:${FSTYPE}::ROOT_ARCH"
    _FSSPEC_HOME_PART="${_HOME_PART_NUM}:/home:${FSTYPE}::HOME_ARCH"
    _FSSPEC_SWAP_PART="${_SWAP_PART_NUM}:swap:swap::SWAP_ARCH"
    
    _FSSPEC_BOOT_PART="${_BOOT_PART_NUM}:/boot:ext2::BOOT_ARCH"
    _FSSPEC_UEFISYS_PART="${_UEFISYS_PART_NUM}:${UEFISYS_MOUNTPOINT}:vfat:-F32:EFISYS"
    
    if [[ "${GUIDPARAMETER}" == "yes" ]]; then
        if [[ "${_UEFISYS_BOOTPART}" == "1" ]]; then
            FSSPECS="${_FSSPEC_ROOT_PART} ${_FSSPEC_UEFISYS_PART} ${_FSSPEC_HOME_PART} ${_FSSPEC_SWAP_PART}"
        else
            FSSPECS="${_FSSPEC_ROOT_PART} ${_FSSPEC_BOOT_PART} ${_FSSPEC_UEFISYS_PART} ${_FSSPEC_HOME_PART} ${_FSSPEC_SWAP_PART}"
        fi
    else
        FSSPECS="${_FSSPEC_ROOT_PART} ${_FSSPEC_BOOT_PART} ${_FSSPEC_HOME_PART} ${_FSSPEC_SWAP_PART}"
    fi

    ## make and mount filesystems
    for fsspec in ${FSSPECS}; do
        DOMKFS="yes"
        PART="${DEVICE}$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d:)"
        # Add check on nvme controller: Uses /dev/nvme0n1pX name scheme 
        echo "${DEVICE}" | grep -q "nvme" && PART="${DEVICE}p$(echo "${fsspec}" | tr -d ' ' | cut -f1 -d:)"
        MP="$(echo "${fsspec}" | tr -d ' ' | cut -f2 -d:)"
        FSTYPE="$(echo "${fsspec}" | tr -d ' ' | cut -f3 -d:)"
        FS_OPTIONS="$(echo "${fsspec}" | tr -d ' ' | cut -f4 -d:)"
        [[ "${FS_OPTIONS}" == "" ]] && FS_OPTIONS="NONE"
        LABEL_NAME="$(echo "${fsspec}" | tr -d ' ' | cut -f5 -d:)"
        BTRFS_DEVICES="${PART}"
        if [[ "${FSTYPE}" = "btrfs" ]]; then
            BTRFS_COMPRESS="compress=lzo"
            [[ "${MP}" = "/" ]] && BTRFS_SUBVOLUME="root"
            [[ "${MP}" = "/home" ]] && BTRFS_SUBVOLUME="home" && DOMKFS="no"
            DOSUBVOLUME="yes"
        else
            BTRFS_COMPRESS="NONE"
            BTRFS_SUBVOLUME="NONE"
            DOSUBVOLUME="no"
        fi
        BTRFS_LEVEL="NONE"
        if ! [[ "${FSTYPE}" = "swap" ]]; then
            DIALOG --infobox "Creating ${FSTYPE} on ${PART}\nwith FSLABEL ${LABEL_NAME} ,\nmounting to ${DESTDIR}${MP}" 0 0
        else
            DIALOG --infobox "Creating and activating swapspace on ${PART}" 0 0
        fi
        _mkfs "${DOMKFS}" "${PART}" "${FSTYPE}" "${DESTDIR}" "${MP}" "${LABEL_NAME}" "${FS_OPTIONS}" "${BTRFS_DEVICES}" ${BTRFS_LEVEL} ${BTRFS_SUBVOLUME} ${DOSUBVOLUME} ${BTRFS_COMPRESS} || return 1
        sleep 1
    done

    DIALOG --msgbox "Auto-prepare was successful" 0 0
    S_MKFSAUTO=1
}

detect_DISC() {
    
    if [[ "${DISC}" == "" ]] || ! echo "${DISC}" | grep -q '/dev/'; then
        DISC="$(${_LSBLK} PKNAME "$(findmnt -vno SOURCE "${DESTDIR}/boot")")"
    fi
    
    if [[ "${DISC}" == "" ]]; then
        DISC="$(${_LSBLK} PKNAME "$(findmnt -vno SOURCE "${DESTDIR}/")")"
    fi
    
}

check_gpt() {
    
    GUID_DETECTED=""
    [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${DISC}")" == "gpt" ]] && GUID_DETECTED="1"
    
    if [[ "${GUID_DETECTED}" == "" ]]; then
        DIALOG --defaultno --yesno "Setup detected no GUID (gpt) partition table on ${DISC}.\n\nDo you want to convert the existing MBR table in ${DISC} to a GUID (gpt) partition table?" 0 0 || return 1
        sgdisk --mbrtogpt "${DISC}" > ${LOG} && GUID_DETECTED="1"
        # reread partitiontable for kernel
        partprobe "${DISC}" > ${LOG}
        if [[ "${GUID_DETECTED}" == "" ]]; then
            DIALOG --defaultno --yesno "Conversion failed on ${DISC}.\nSetup detected no GUID (gpt) partition table on ${DISC}.\n\nDo you want to create a new GUID (gpt) table now on ${DISC}?\n\n${DISC} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 || return 1
            # clean partition table to avoid issues!
            sgdisk --zap "${DISC}" &>/dev/null
            # clear all magic strings/signatures - mdadm, lvm, partition tables etc.
            dd if=/dev/zero of="${DISC}" bs=512 count=2048 &>/dev/null
            wipefs -a "${DISC}" &>/dev/null
            # create fresh GPT
            sgdisk --clear "${DISC}" &>/dev/null
            GUID_DETECTED="1"
        fi
    fi
    
    if [[ "${GUID_DETECTED}" == "1" ]]; then
        ### This check is not enabled in any function yet!
        if [[ "${CHECK_UEFISYS_PART}" == "1" ]]; then
            check_efisys_part
        fi
        
        if [[ "${CHECK_BIOS_BOOT_GRUB}" == "1" ]]; then
            if ! sgdisk -p "${DISC}" | grep -q 'EF02'; then
                DIALOG --msgbox "Setup detected no BIOS BOOT PARTITION in ${DISC}. Please create a >=1 MB BIOS Boot partition for grub BIOS GPT support." 0 0
                RUN_CFDISK="1"
            fi
        fi
    fi
    
    if [[ "${RUN_CFDISK}" == "1" ]]; then
        DIALOG --msgbox "Now you'll be put into cfdisk where you can partition your storage drive.\nYou should make a swap partition and as many data partitions as you will need." 18 70
        clear && cfdisk "${DISC}"
        # reread partitiontable for kernel
        partprobe "${DEVICE}"
    fi
}

## check and mount EFISYS partition at ${UEFISYS_MOUNTPOINT}
check_efisys_part() {
    
    detect_DISC
    
    if [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${DISC}")" != "gpt" ]]; then
        GUID_DETECTED=""
        DIALOG --defaultno --yesno "Setup detected no GUID (gpt) partition table on ${DISC}.\nUEFI boot requires ${DISC} to be partitioned as GPT.\n\nDo you want to convert the existing MBR table in ${DISC} to a GUID (gpt) partition table?" 0 0 || return 1
        DIALOG --msgbox "Setup will now try to non-destructively convert ${DISC} to GPT using sgdisk." 0 0
        sgdisk --mbrtogpt "${DISC}" > ${LOG} && GUID_DETECTED="1"
        partprobe "${DISC}" > ${LOG}
        if [[ "${GUID_DETECTED}" == "" ]]; then
            DIALOG --msgbox "Conversion failed on ${DISC}.\nSetup detected no GUID (gpt) partition table on ${DISC}.\n\n You need to fix your partition table first, before setup can proceed." 0 0
            return 1
        fi
    fi
    
    if ! sgdisk -p "${DISC}" | grep -q 'EF00'; then
        # Windows 10 recommends a minimum of 260MB Efi Systen Partition
        DIALOG --msgbox "Setup detected no EFI System partition in ${DISC}. You will now be put into cfdisk. Please create a >= 260 MB partition with cfdisk type EFI System .\nWhen prompted (later) to format as FAT32, say YES.\nIf you already have a >=260 MB FAT32 EFI System partition, check whether that partition has EFI System cfdisk type code." 0 0
        clear && cfdisk "${DISC}"
        RUN_CFDISK=""
    fi
    
    if sgdisk -p "${DISC}" | grep -q 'EF00'; then
        # check on unique PARTTYPE c12a7328-f81f-11d2-ba4b-00a0c93ec93b for EFI System Partition type UUID
        UEFISYS_PART="$(${_LSBLK} NAME,PARTTYPE "${DISC}" | grep 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b' | cut -d " " -f1)"
        
        if [[ "$(${_LSBLK} FSTYPE "${UEFISYS_PART}")" != "vfat" ]]; then
            ## Check whether EFISYS is FAT, otherwise inform the user and offer to format the partition as FAT32.
            DIALOG --defaultno --yesno "Detected EFI System partition ${UEFISYS_PART} does not appear to be FAT formatted. UEFI Specification requires EFI System partition to be FAT32 formatted. Do you want to format ${UEFISYS_PART} as FAT32?\nNote: Setup will proceed even if you select NO. Some systems like Apple Macs may work with Non-FAT EFI System partition. However the installed system is not in conformance with UEFI Spec., and MAY NOT boot properly." 0 0 && _FORMAT_UEFISYS_FAT32="1"
        fi
        
        if [[ "$(${_LSBLK} FSTYPE "${UEFISYS_PART}")" == "vfat" ]] && [[ "$(${_BLKID} -p -i -o value -s VERSION "${UEFISYS_PART}")" != "FAT32" ]]; then
            ## Check whether EFISYS is FAT32 (specifically), otherwise warn the user about compatibility issues with UEFI Spec.
            DIALOG --defaultno --yesno "Detected EFI System partition ${UEFISYS_PART} does not appear to be FAT32 formatted. Do you want to format ${UEFISYS_PART} as FAT32?\nNote: Setup will proceed even if you select NO. Most systems will boot fine even with FAT16 or FAT12 EFI System partition, however some firmwares may refuse to boot with a non-FAT32 EFI System partition. It is recommended to use FAT32 for maximum compatibility with UEFI Spec." 0 0 && _FORMAT_UEFISYS_FAT32="1"
        fi
        
        #autodetect efisys mountpoint, on fail ask for mountpoint
        UEFISYS_MOUNTPOINT="/$(basename "$(mount | grep "${UEFISYS_PART}" | cut -d " " -f 3)")"
        if [[ "${UEFISYS_MOUNTPOINT}" == "/" ]]; then
            DIALOG --inputbox "Enter the mountpoint of your EFI System partition (Default is /boot): " 0 0 "/boot" 2>${ANSWER} || return 1
            UEFISYS_MOUNTPOINT="$(cat ${ANSWER})"
        fi
        
        umount "${DESTDIR}/${UEFISYS_MOUNTPOINT}" &> /dev/null
        umount "${UEFISYS_PART}" &> /dev/null
        
        if [[ "${_FORMAT_UEFISYS_FAT32}" == "1" ]]; then
            mkfs.vfat -F32 -n "EFISYS" "${UEFISYS_PART}"
        fi
        
        mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}"
        
        if [[ "$(${_LSBLK} FSTYPE "${UEFISYS_PART}")" == "vfat" ]]; then
            mount -o rw,flush -t vfat "${UEFISYS_PART}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}"
        else
            DIALOG --msgbox "${UEFISYS_PART} is not formatted using FAT filesystem. Setup will go ahead but there might be issues using non-FAT FS for EFI System partition." 0 0
            
            mount -o rw "${UEFISYS_PART}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}"
        fi
        
        mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI" || true
    else
        DIALOG --msgbox "Setup did not find any EFI System partition in ${DISC}. Please create >= 260 MB FAT32 partition with cfdisk type EFI System code and try again." 0 0
        return 1
    fi
    
}

partition() {
    # disable swap and all mounted partitions, umount / last!
    _umountall
    # activate dmraid
    activate_dmraid
    # check on encrypted devices, else weird things can happen!
    _stopluks
    # check on raid devices, else weird things can happen during partitioning!
    _stopmd
    # check on lvm devices, else weird things can happen during partitioning!
    _stoplvm
    # update dmraid
    ! [[ "$(dmraid_devices)" = "" ]] && _dmraid_update
    # switch for mbr usage
    set_guid
    # Select disk to partition
    DISCS=$(finddisks _)
    DISCS="${DISCS} OTHER _ DONE +"
    DIALOG --cr-wrap --msgbox "Available Disks:\n\n$(_getavaildisks)\n" 0 0
    DISC=""
    while true; do
        # Prompt the user with a list of known disks
        #shellcheck disable=SC2086
        DIALOG --menu "Select the disk you want to partition\n(select DONE when finished)" 14 55 7 ${DISCS} 2>${ANSWER} || return 1
        DISC=$(cat ${ANSWER})
        if [[ "${DISC}" == "OTHER" ]]; then
            DIALOG --inputbox "Enter the full path to the device you wish to partition" 8 65 "/dev/sda" 2>${ANSWER} || DISC=""
            DISC=$(cat ${ANSWER})
        fi
        # Leave our loop if the user is done partitioning
        [[ "${DISC}" == "DONE" ]] && break
        MSDOS_DETECTED=""
        if ! [[ "${DISC}" == "" ]]; then
            if [[ "${GUIDPARAMETER}" == "yes" ]]; then
                CHECK_BIOS_BOOT_GRUB=""
                CHECK_UEFISYS_PART=""
                RUN_CFDISK="1"
                check_gpt
            else
                [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${DISC}")" == "dos" ]] && MSDOS_DETECTED="1"
                
                if [[ "${MSDOS_DETECTED}" == "" ]]; then
                    DIALOG --defaultno --yesno "Setup detected no MS-DOS partition table on ${DISC}.\nDo you want to create a MS-DOS partition table now on ${DISC}?\n\n${DISC} will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 || return 1
                    # clean partitiontable to avoid issues!
                    dd if=/dev/zero of="${DEVICE}" bs=512 count=2048 >/dev/null 2>&1
                    wipefs -a "${DEVICE}" /dev/null 2>&1
                    parted -a optimal -s "${DISC}" mktable msdos >${LOG}
                fi
                # Partition disc
                DIALOG --msgbox "Now you'll be put into cfdisk where you can partition your storage drive. You should make a swap partition and as many data partitions as you will need." 18 70
                clear
                cfdisk "${DISC}"
                # reread partitiontable for kernel
                partprobe "${DISC}"
            fi
        fi
    done
    # update dmraid
    _dmraid_update
    NEXTITEM="4"
}

# scan and update btrfs devices
btrfs_scan() {
    btrfs device scan >/dev/null 2>&1
}

# mount btrfs for checks
mount_btrfs() {
    btrfs_scan
    BTRFSMP="$(mktemp -d /tmp/brtfsmp.XXXX)"
    mount "${PART}" "${BTRFSMP}"
}

# unmount btrfs after checks done
umount_btrfs() {
    umount "${BTRFSMP}"
    rm -r "${BTRFSMP}"
}

# Set BTRFS_DEVICES on detected btrfs devices
find_btrfs_raid_devices() {
    btrfs_scan
    if [[ "${DETECT_CREATE_FILESYSTEM}" = "no" && "${FSTYPE}" = "btrfs" ]]; then
        for i in $(btrfs filesystem show "${PART}" | cut -d " " -f 11); do
            BTRFS_DEVICES="${BTRFS_DEVICES}#${i}"
        done
    fi
}

find_btrfs_raid_bootloader_devices() {
    btrfs_scan
    BTRFS_COUNT=1
    if [[ "$(${_LSBLK} FSTYPE "${bootdev}")" = "btrfs" ]]; then
        BTRFS_DEVICES=""
        for i in $(btrfs filesystem show "${bootdev}" | cut -d " " -f 11); do
            BTRFS_DEVICES="${BTRFS_DEVICES}#${i}"
            BTRFS_COUNT=$((BTRFS_COUNT+1))
        done
    fi
}

# find btrfs subvolume
find_btrfs_subvolume() {
    if [[ "${DETECT_CREATE_FILESYSTEM}" = "no" ]]; then
        # existing btrfs subvolumes
        mount_btrfs
        for i in $(btrfs subvolume list "${BTRFSMP}" | cut -d " " -f 9); do
            echo "${i}"
            [[ "${1}" ]] && echo "${1}"
        done
        umount_btrfs
    fi
}

find_btrfs_bootloader_subvolume() {
    if [[ "$(${_LSBLK} FSTYPE "${bootdev}")" = "btrfs" ]]; then
        BTRFS_SUBVOLUMES=""
        PART="${bootdev}"
        mount_btrfs
        for i in $(btrfs subvolume list "${BTRFSMP}" | cut -d " " -f 7); do
            BTRFS_SUBVOLUMES="${BTRFS_SUBVOLUMES}#${i}"
        done
        umount_btrfs
    fi
}

# subvolumes already in use
subvolumes_in_use() {
    SUBVOLUME_IN_USE=""
    while read -r i; do
        grep -q ":btrfs:" "${i}" && SUBVOLUME_IN_USE="${SUBVOLUME_IN_USE} $(echo "${i}" | cut -d: -f 9)"
    done
}

# ask for btrfs compress option
btrfs_compress() {
    BTRFS_COMPRESS="NONE"
    BTRFS_COMPRESSLEVELS="lzo - zlib - zstd -"
    if [[ "${BTRFS_SUBVOLUME}" = "NONE" ]]; then
        DIALOG --yesno "Would you like to compress the data on ${PART}?" 0 0 && BTRFS_COMPRESS="compress"
    else
        DIALOG --yesno "Would you like to compress the data on ${PART} subvolume=${BTRFS_SUBVOLUME}?" 0 0 && BTRFS_COMPRESS="compress"
    fi
    if [[ "${BTRFS_COMPRESS}" = "compress" ]]; then
        #shellcheck disable=SC2086
        DIALOG --menu "Select the compression method you want to use" 21 50 9 ${BTRFS_COMPRESSLEVELS} 2>${ANSWER} || return 1
        BTRFS_COMPRESS="compress=$(cat ${ANSWER})"
    fi
}

# values that are needed for fs creation
clear_fs_values() {
    : >/tmp/.btrfs-devices
    DOMKFS="no"
    LABEL_NAME=""
    FS_OPTIONS=""
    BTRFS_DEVICES=""
    BTRFS_LEVEL=""
    BTRFS_SUBVOLUME=""
    DOSUBVOLUME=""
    BTRFS_COMPRESS=""
}

# do not ask for btrfs filesystem creation, if already prepared for creation!
check_btrfs_filesystem_creation() {
    DETECT_CREATE_FILESYSTEM="no"
    SKIP_FILESYSTEM="no"
    SKIP_ASK_SUBVOLUME="no"
    for i in $(grep "${PART}[:#]" /tmp/.parts); do
        if echo "${i}" | grep -q ":btrfs:"; then
            FSTYPE="btrfs"
            SKIP_FILESYSTEM="yes"
            # check on filesystem creation, skip subvolume asking then!
            echo "${i}" | cut -d: -f 4 | grep -q yes && DETECT_CREATE_FILESYSTEM="yes"
            [[ "${DETECT_CREATE_FILESYSTEM}" = "yes" ]] && SKIP_ASK_SUBVOLUME="yes"
        fi
    done
}

# remove devices with no subvolume from list and generate raid device list
btrfs_parts() {
     if [[ -s /tmp/.btrfs-devices ]]; then
         BTRFS_DEVICES=""
         while read -r i; do
             BTRFS_DEVICES="${BTRFS_DEVICES}#${i}"
             # remove device if no subvolume is used!
             [[ "${BTRFS_SUBVOLUME}" = "NONE" ]] && PARTS="${PARTS//${i}\ _/}"
         done < /tmp/.btrfs-devices
     else
         [[ "${BTRFS_SUBVOLUME}" = "NONE" ]] && PARTS="${PARTS//${PART}\ _/}"
     fi
}

# choose raid level to use on btrfs device
btrfs_raid_level() {
    BTRFS_RAIDLEVELS="NONE - raid0 - raid1 - raid5 - raid6 - raid10 - single -"
    BTRFS_RAID_FINISH=""
    BTRFS_LEVEL=""
    BTRFS_DEVICE="${PART}"
    : >/tmp/.btrfs-devices
    DIALOG --msgbox "BTRFS DATA RAID OPTIONS:\n\nRAID5/6 are for testing purpose. Use with extreme care!\n\nIf you don't need this feature select NONE." 0 0
    while [[ "${BTRFS_RAID_FINISH}" != "DONE" ]]; do
        #shellcheck disable=SC2086
        DIALOG --menu "Select the raid data level you want to use" 21 50 9 ${BTRFS_RAIDLEVELS} 2>${ANSWER} || return 1
        BTRFS_LEVEL=$(cat ${ANSWER})
        if [[ "${BTRFS_LEVEL}" = "NONE" ]]; then
            echo "${BTRFS_DEVICE}" >>/tmp/.btrfs-devices
            break
        else
            # take selected device as 1st device, add additional devices in part below.
            select_btrfs_raid_devices
        fi
    done
}

# select btrfs raid devices
select_btrfs_raid_devices () {
    # show all devices with sizes
    # DIALOG --msgbox "DISKS:\n$(_getavaildisks)\n\nPARTITIONS:\n$(_getavailpartitions)" 0 0
    # select the second device to use, no missing option available!
    : >/tmp/.btrfs-devices
    BTRFS_PART="${BTRFS_DEVICE}"
    BTRFS_PARTS="${PARTS}"
    echo "${BTRFS_PART}" >>/tmp/.btrfs-devices
    BTRFS_PARTS="${BTRFS_PARTS//${BTRFS_PART}\ _/}"
    RAIDNUMBER=2
    #shellcheck disable=SC2086
    DIALOG --menu "Select device ${RAIDNUMBER}" 21 50 13 ${BTRFS_PARTS} 2>${ANSWER} || return 1
    BTRFS_PART=$(cat ${ANSWER})
    echo "${BTRFS_PART}" >>/tmp/.btrfs-devices
    while [[ "${BTRFS_PART}" != "DONE" ]]; do
        BTRFS_DONE=""
        RAIDNUMBER=$((RAIDNUMBER + 1))
        # RAID5 needs 3 devices
        # RAID6, RAID10 need 4 devices!
        [[ "${RAIDNUMBER}" -ge 3 && ! "${BTRFS_LEVEL}" = "raid10" && ! "${BTRFS_LEVEL}" = "raid6" && ! "${BTRFS_LEVEL}" = "raid5" ]] && BTRFS_DONE="DONE _"
        [[ "${RAIDNUMBER}" -ge 4 && "${BTRFS_LEVEL}" = "raid5" ]] && BTRFS_DONE="DONE _"
        [[ "${RAIDNUMBER}" -ge 5 && "${BTRFS_LEVEL}" = "raid10" || "${BTRFS_LEVEL}" = "raid6" ]] && BTRFS_DONE="DONE _"
        # clean loop from used partition and options
        BTRFS_PARTS="${BTRFS_PARTS//${BTRFS_PART}\ _/}"
        # add more devices
        #shellcheck disable=SC2086
        DIALOG --menu "Select device ${RAIDNUMBER}" 21 50 13 ${BTRFS_PARTS} ${BTRFS_DONE} 2>${ANSWER} || return 1
        BTRFS_PART=$(cat ${ANSWER})
        [[ "${BTRFS_PART}" = "DONE" ]] && break
        echo "${BTRFS_PART}" >>/tmp/.btrfs-devices
     done
     # final step ask if everything is ok?
     DIALOG --yesno "Would you like to create btrfs raid data like this?\n\nLEVEL:\n${BTRFS_LEVEL}\n\nDEVICES:\n$(while read -r i; do echo "${i}\n"; done </tmp/.btrfs-devices)" 0 0 && BTRFS_RAID_FINISH="DONE"
}

# prepare new btrfs device
prepare_btrfs() {
    btrfs_raid_level || return 1
    prepare_btrfs_subvolume || return 1
}

# prepare btrfs subvolume
prepare_btrfs_subvolume() {
    DOSUBVOLUME="no"
    BTRFS_SUBVOLUME="NONE"
    if [[ "${SKIP_ASK_SUBVOLUME}" = "no" ]]; then
        DIALOG --defaultno --yesno "Would you like to create a new subvolume on ${PART}?" 0 0 && DOSUBVOLUME="yes"
    else
        DOSUBVOLUME="yes"
    fi
    if [[ "${DOSUBVOLUME}" = "yes" ]]; then
        BTRFS_SUBVOLUME="NONE"
        while [[ "${BTRFS_SUBVOLUME}" = "NONE" ]]; do
            DIALOG --inputbox "Enter the SUBVOLUME name for the device, keep it short\nand use no spaces or special\ncharacters." 10 65 2>${ANSWER} || return 1
            BTRFS_SUBVOLUME=$(cat ${ANSWER})
            check_btrfs_subvolume
        done
    else
        BTRFS_SUBVOLUME="NONE"
    fi
}

# check btrfs subvolume
check_btrfs_subvolume(){
    [[ "${DOMKFS}" = "yes" && "${FSTYPE}" = "btrfs" ]] && DETECT_CREATE_FILESYSTEM="yes"
    if [[ "${DETECT_CREATE_FILESYSTEM}" = "no" ]]; then
        mount_btrfs
        for i in $(btrfs subvolume list "${BTRFSMP}" | cut -d " " -f 7); do
            if echo "${i}" | grep -q "${BTRFS_SUBVOLUME}"; then
                DIALOG --msgbox "ERROR: You have defined 2 identical SUBVOLUME names or an empty name! Please enter another name." 8 65
                BTRFS_SUBVOLUME="NONE"
            fi
        done
        umount_btrfs
    else
        subvolumes_in_use
        if echo "${SUBVOLUME_IN_USE}" | grep -Eq "${BTRFS_SUBVOLUME}"; then
            DIALOG --msgbox "ERROR: You have defined 2 identical SUBVOLUME names or an empty name! Please enter another name." 8 65
            BTRFS_SUBVOLUME="NONE"
        fi
    fi
}

# create btrfs subvolume
create_btrfs_subvolume() {
    mount_btrfs
    btrfs subvolume create "${BTRFSMP}"/"${_btrfssubvolume}" >${LOG}
    # change permission from 700 to 755 
    # to avoid warnings during package installation
    chmod 755 "${BTRFSMP}"/"${_btrfssubvolume}"
    umount_btrfs
}

# choose btrfs subvolume from list
choose_btrfs_subvolume () {
    BTRFS_SUBVOLUME="NONE"
    SUBVOLUMES_DETECTED="no"
    SUBVOLUMES=$(find_btrfs_subvolume _)
    # check if subvolumes are present
    [[ -n "${SUBVOLUMES}" ]] && SUBVOLUMES_DETECTED="yes"
    subvolumes_in_use
    for i in ${SUBVOLUME_IN_USE}; do
        SUBVOLUMES=${SUBVOLUMES//${i}\ _/}
    done
    if [[ -n "${SUBVOLUMES}" ]]; then
    #shellcheck disable=SC2086
        DIALOG --menu "Select the subvolume to mount" 21 50 13 ${SUBVOLUMES} 2>${ANSWER} || return 1
        BTRFS_SUBVOLUME=$(cat ${ANSWER})
    else
        if [[ "${SUBVOLUMES_DETECTED}" = "yes" ]]; then
            DIALOG --msgbox "ERROR: All subvolumes of the device are already in use. Switching to create a new one now." 8 65
            SKIP_ASK_SUBVOLUME=yes
            prepare_btrfs_subvolume || return 1
        fi
    fi
}

# btrfs subvolume menu
btrfs_subvolume() {
    FILESYSTEM_FINISH=""
    if [[ "${FSTYPE}" = "btrfs" && "${DOMKFS}" = "no" ]]; then
        if [[ "${ASK_MOUNTPOINTS}" = "1" ]]; then
            # create subvolume if requested
            # choose btrfs subvolume if present
            prepare_btrfs_subvolume || return 1
            if [[ "${BTRFS_SUBVOLUME}" = "NONE" ]]; then
                choose_btrfs_subvolume || return 1
            fi
        else
            # use device if no subvolume is present
            choose_btrfs_subvolume || return 1
        fi
        btrfs_compress
    fi
    FILESYSTEM_FINISH="yes"
}

# add ssd mount options
ssd_optimization() {
    # ext4, jfs, xfs, btrfs, nilfs2, f2fs  have ssd mount option support
    ssd_mount_options=""
    if echo "${_fstype}" | grep -Eq 'ext4|jfs|btrfs|xfs|nilfs2|f2fs'; then
        # check all underlying devices on ssd
        for i in $(${_LSBLK} NAME,TYPE "${_device}" -s | grep "disk$" | cut -d' ' -f 1); do
            # check for ssd
            if [[ "$(cat /sys/block/"$(basename "${i}")"/queue/rotational)" == "0" ]]; then
                ssd_mount_options="noatime"
            fi
        done
    fi
}

select_filesystem() {
    FILESYSTEM_FINISH=""
    # don't allow vfat as / filesystem, it will not work!
    # don't allow ntfs as / filesystem, this is stupid!
    FSOPTS=""
    [[ "$(which mkfs.ext2 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext2 Ext2"
    [[ "$(which mkfs.ext3 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext3 Ext3"
    [[ "$(which mkfs.ext4 2>/dev/null)" ]] && FSOPTS="${FSOPTS} ext4 Ext4"
    [[ "$(which mkfs.btrfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} btrfs Btrfs"
    [[ "$(which mkfs.nilfs2 2>/dev/null)" ]] && FSOPTS="${FSOPTS} nilfs2 Nilfs2"
    [[ "$(which mkfs.f2fs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} f2fs F2FS"
    [[ "$(which mkreiserfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} reiserfs Reiser3"
    [[ "$(which mkfs.xfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} xfs XFS"
    [[ "$(which mkfs.jfs 2>/dev/null)" ]] && FSOPTS="${FSOPTS} jfs JFS"
    [[ "$(which mkfs.ntfs 2>/dev/null)" && "${DO_ROOT}" = "DONE" ]] && FSOPTS="${FSOPTS} ntfs3 NTFS"
    [[ "$(which mkfs.vfat 2>/dev/null)" && "${DO_ROOT}" = "DONE" ]] && FSOPTS="${FSOPTS} vfat FAT32"
    #shellcheck disable=SC2086
    DIALOG --menu "Select a filesystem for ${PART}" 21 50 13 ${FSOPTS} 2>${ANSWER} || return 1
    FSTYPE=$(cat ${ANSWER})
}

enter_mountpoint() {
    FILESYSTEM_FINISH=""
    MP=""
    while [[ "${MP}" = "" ]]; do
        DIALOG --inputbox "Enter the mountpoint for ${PART}" 8 65 "/boot" 2>${ANSWER} || return 1
        MP=$(cat ${ANSWER})
        if grep ":${MP}:" /tmp/.parts; then
            DIALOG --msgbox "ERROR: You have defined 2 identical mountpoints! Please select another mountpoint." 8 65
            MP=""
        fi
    done
}

# set sane values for paramaters, if not already set
check_mkfs_values() {
    # Set values, to not confuse mkfs call!
    [[ "${FS_OPTIONS}" = "" ]] && FS_OPTIONS="NONE"
    [[ "${BTRFS_DEVICES}" = "" ]] && BTRFS_DEVICES="NONE"
    [[ "${BTRFS_LEVEL}" = "" ]] && BTRFS_LEVEL="NONE"
    [[ "${BTRFS_SUBVOLUME}" = "" ]] && BTRFS_SUBVOLUME="NONE"
    [[ "${DOSUBVOLUME}" = "" ]] && DOSUBVOLUME="no"
    [[ "${LABEL_NAME}" = "" && -n "$(${_LSBLK} LABEL "${PART}")" ]] && LABEL_NAME="$(${_LSBLK} LABEL "${PART}")"
    [[ "${LABEL_NAME}" = "" ]] && LABEL_NAME="NONE"
}

create_filesystem() {
    FILESYSTEM_FINISH=""
    LABEL_NAME=""
    FS_OPTIONS=""
    BTRFS_DEVICES=""
    BTRFS_LEVEL=""
    DIALOG --yesno "Would you like to create a filesystem on ${PART}?\n\n(This will overwrite existing data!)" 0 0 && DOMKFS="yes"
    if [[ "${DOMKFS}" = "yes" ]]; then
        while [[ "${LABEL_NAME}" = "" ]]; do
            DIALOG --inputbox "Enter the LABEL name for the device, keep it short\n(not more than 12 characters) and use no spaces or special\ncharacters." 10 65 \
            "$(${_LSBLK} LABEL "${PART}")" 2>${ANSWER} || return 1
            LABEL_NAME=$(cat ${ANSWER})
            if grep ":${LABEL_NAME}$" /tmp/.parts; then
                DIALOG --msgbox "ERROR: You have defined 2 identical LABEL names! Please enter another name." 8 65
                LABEL_NAME=""
            fi
        done
        if [[ "${FSTYPE}" = "btrfs" ]]; then
            prepare_btrfs || return 1
            btrfs_compress
        fi
        DIALOG --inputbox "Enter additional options to the filesystem creation utility.\nUse this field only, if the defaults are not matching your needs,\nelse just leave it empty." 10 70  2>${ANSWER} || return 1
        FS_OPTIONS=$(cat ${ANSWER})
    fi
    FILESYSTEM_FINISH="yes"
}

mountpoints() {
    NAME_SCHEME_PARAMETER_RUN=""
    while [[ "${PARTFINISH}" != "DONE" ]]; do
        activate_special_devices
        : >/tmp/.device-names
        : >/tmp/.fstab
        : >/tmp/.parts
        #
        # Select mountpoints
        #
        DIALOG --cr-wrap --msgbox "Available partitions:\n\n$(_getavailpartitions)\n" 0 0
        PARTS=$(findpartitions _)
        DO_SWAP=""
        while [[ "${DO_SWAP}" != "DONE" ]]; do
            FSTYPE="swap"
            #shellcheck disable=SC2086
            DIALOG --menu "Select the partition to use as swap" 21 50 13 NONE - ${PARTS} 2>${ANSWER} || return 1
            PART=$(cat ${ANSWER})
            if [[ "${PART}" != "NONE" ]]; then
                clear_fs_values
                if [[ "${ASK_MOUNTPOINTS}" = "1" ]]; then
                    create_filesystem
                else
                    FILESYSTEM_FINISH="yes"
                fi
            else
                FILESYSTEM_FINISH="yes"
            fi
            [[ "${FILESYSTEM_FINISH}" = "yes" ]] && DO_SWAP=DONE
        done
        check_mkfs_values
        if [[ "${PART}" != "NONE" ]]; then
            PARTS="${PARTS//${PART}\ _/}"
            echo "${PART}:swap:swap:${DOMKFS}:${LABEL_NAME}:${FS_OPTIONS}:${BTRFS_DEVICES}:${BTRFS_LEVEL}:${BTRFS_SUBVOLUME}:${DOSUBVOLUME}:${BTRFS_COMPRESS}" >>/tmp/.parts
        fi
        DO_ROOT=""
        while [[ "${DO_ROOT}" != "DONE" ]]; do
            #shellcheck disable=SC2086
            DIALOG --menu "Select the partition to mount as /" 21 50 13 ${PARTS} 2>${ANSWER} || return 1
            PART=$(cat ${ANSWER})
            PART_ROOT=${PART}
            # Select root filesystem type
            FSTYPE="$(${_LSBLK} FSTYPE "${PART}")"
            # clear values first!
            clear_fs_values
            check_btrfs_filesystem_creation
            if [[ "${ASK_MOUNTPOINTS}" = "1" && "${SKIP_FILESYSTEM}" = "no" ]]; then
                select_filesystem && create_filesystem && btrfs_subvolume
            else                   
                btrfs_subvolume
            fi
            [[ "${FILESYSTEM_FINISH}" = "yes" ]] && DO_ROOT=DONE
        done
        find_btrfs_raid_devices
        btrfs_parts
        check_mkfs_values
        echo "${PART}:${FSTYPE}:/:${DOMKFS}:${LABEL_NAME}:${FS_OPTIONS}:${BTRFS_DEVICES}:${BTRFS_LEVEL}:${BTRFS_SUBVOLUME}:${DOSUBVOLUME}:${BTRFS_COMPRESS}" >>/tmp/.parts
        ! [[ "${FSTYPE}" = "btrfs" ]] && PARTS="${PARTS//${PART}\ _/}"
        #
        # Additional partitions
        #
        while [[ "${PART}" != "DONE" ]]; do
            DO_ADDITIONAL=""
            while [[ "${DO_ADDITIONAL}" != "DONE" ]]; do
                #shellcheck disable=SC2086
                DIALOG --menu "Select any additional partitions to mount under your new root (select DONE when finished)" 21 52 13 ${PARTS} DONE _ 2>${ANSWER} || return 1
                PART=$(cat ${ANSWER})
                if [[ "${PART}" != "DONE" ]]; then
                    FSTYPE="$(${_LSBLK} FSTYPE "${PART}")"
                    # clear values first!
                    clear_fs_values
                    check_btrfs_filesystem_creation
                    # Select a filesystem type
                    if [[ "${ASK_MOUNTPOINTS}" = "1" && "${SKIP_FILESYSTEM}" = "no" ]]; then
                        enter_mountpoint && select_filesystem && create_filesystem && btrfs_subvolume
                    else
                        enter_mountpoint
                        btrfs_subvolume
                    fi
                else
                    FILESYSTEM_FINISH="yes"
                fi
                [[ "${FILESYSTEM_FINISH}" = "yes" ]] && DO_ADDITIONAL="DONE"
            done
            if [[ "${PART}" != "DONE" ]]; then
                find_btrfs_raid_devices
                btrfs_parts
                check_mkfs_values
                echo "${PART}:${FSTYPE}:${MP}:${DOMKFS}:${LABEL_NAME}:${FS_OPTIONS}:${BTRFS_DEVICES}:${BTRFS_LEVEL}:${BTRFS_SUBVOLUME}:${DOSUBVOLUME}:${BTRFS_COMPRESS}" >>/tmp/.parts
                ! [[ "${FSTYPE}" = "btrfs" ]] && PARTS="${PARTS//${PART}\ _/}"
            fi
        done
        DIALOG --yesno "Would you like to create and mount the filesytems like this?\n\nSyntax\n------\nDEVICE:TYPE:MOUNTPOINT:FORMAT:LABEL:FSOPTIONS:BTRFS_DETAILS\n\n$(while read -r i;do echo "${i}\n" | sed -e 's, ,#,g';done </tmp/.parts)" 0 0 && PARTFINISH="DONE"
    done
    # disable swap and all mounted partitions
    _umountall
    if [[ "${NAME_SCHEME_PARAMETER_RUN}" = "" ]]; then
        set_device_name_scheme || return 1
    fi
    printk off
    while read -r line; do
        PART=$(echo "${line}" | cut -d: -f 1)
        FSTYPE=$(echo "${line}" | cut -d: -f 2)
        MP=$(echo "${line}" | cut -d: -f 3)
        DOMKFS=$(echo "${line}" | cut -d: -f 4)
        LABEL_NAME=$(echo "${line}" | cut -d: -f 5)
        FS_OPTIONS=$(echo "${line}" | cut -d: -f 6)
        BTRFS_DEVICES=$(echo "${line}" | cut -d: -f 7)
        BTRFS_LEVEL=$(echo "${line}" | cut -d: -f 8)
        BTRFS_SUBVOLUME=$(echo "${line}" | cut -d: -f 9)
        DOSUBVOLUME=$(echo "${line}" | cut -d: -f 10)
        BTRFS_COMPRESS=$(echo "${line}" | cut -d: -f 11)
        if [[ "${DOMKFS}" = "yes" ]]; then
            if [[ "${FSTYPE}" = "swap" ]]; then
                DIALOG --infobox "Creating and activating swapspace on ${PART}" 0 0
            else
                DIALOG --infobox "Creating ${FSTYPE} on ${PART},\nmounting to ${DESTDIR}${MP}" 0 0
            fi
            _mkfs yes "${PART}" "${FSTYPE}" "${DESTDIR}" "${MP}" "${LABEL_NAME}" "${FS_OPTIONS}" "${BTRFS_DEVICES}" "${BTRFS_LEVEL}" "${BTRFS_SUBVOLUME}" "${DOSUBVOLUME}" "${BTRFS_COMPRESS}" || return 1
        else
            if [[ "${FSTYPE}" = "swap" ]]; then
                DIALOG --infobox "Activating swapspace on ${PART}" 0 0
            else
                DIALOG --infobox "Mounting ${FSTYPE} on ${PART} to ${DESTDIR}${MP}" 0 0
            fi
            _mkfs no "${PART}" "${FSTYPE}" "${DESTDIR}" "${MP}" "${LABEL_NAME}" "${FS_OPTIONS}" "${BTRFS_DEVICES}" "${BTRFS_LEVEL}" "${BTRFS_SUBVOLUME}" "${DOSUBVOLUME}" "${BTRFS_COMPRESS}" || return 1
        fi
        sleep 1
    done < /tmp/.parts
    printk on
    DIALOG --msgbox "Partitions were successfully mounted." 0 0
    NEXTITEM="5"
    S_MKFS=1
}

# _mkfs()
# Create and mount filesystems in our destination system directory.
#
# args:
#  domk: Whether to make the filesystem or use what is already there
#  device: Device filesystem is on
#  fstype: type of filesystem located at the device (or what to create)
#  dest: Mounting location for the destination system
#  mountpoint: Mount point inside the destination system, e.g. '/boot'

# returns: 1 on failure
_mkfs() {
    local _domk=${1}
    local _device=${2}
    local _fstype=${3}
    local _dest=${4}
    local _mountpoint=${5}
    local _labelname=${6}
    local _fsoptions=${7}
    local _btrfsdevices="${8//#/ /}"
    local _btrfslevel=${9}
    local _btrfssubvolume=${10}
    local _dosubvolume=${11}
    local _btrfscompress=${12}
    # correct empty entries
    [[ "${_fsoptions}" = "NONE" ]] && _fsoptions=""
    [[ "${_btrfscompress}" = "NONE" ]] && _btrfscompress=""
    [[ "${_btrfssubvolume}" = "NONE" ]] && _btrfssubvolume=""
    # add btrfs raid level, if needed
    [[ ! "${_btrfslevel}" = "NONE" && "${_fstype}" = "btrfs" ]] && _fsoptions="${_fsoptions} -m ${_btrfslevel} -d ${_btrfslevel}"
    # add btrfs options, minimum requirement linux 3.14 -O no-holes
    [[ "${_fstype}" = "btrfs" ]] && _fsoptions="${_fsoptions} -O no-holes"
    # we have two main cases: "swap" and everything else.
    if [[ "${_fstype}" = "swap" ]]; then
        swapoff "${_device}" >/dev/null 2>&1
        if [[ "${_domk}" = "yes" ]]; then
            mkswap -L "${_labelname}" "${_device}" >${LOG} 2>&1
            if [[ $? != 0 ]]; then
                DIALOG --msgbox "Error creating swap: mkswap ${_device}" 0 0
                return 1
            fi
        fi
        swapon "${_device}" >${LOG} 2>&1
        if [[ $? != 0 ]]; then
            DIALOG --msgbox "Error activating swap: swapon ${_device}" 0 0
            return 1
        fi
    else
        # make sure the fstype is one we can handle
        local knownfs=0
        for fs in xfs jfs reiserfs ext2 ext3 ext4 f2fs btrfs nilfs2 ntfs3 vfat; do
            [[ "${_fstype}" = "${fs}" ]] && knownfs=1 && break
        done
        if [[ ${knownfs} -eq 0 ]]; then
            DIALOG --msgbox "unknown fstype ${_fstype} for ${_device}" 0 0
            return 1
        fi
        # if we were tasked to create the filesystem, do so
        if [[ "${_domk}" = "yes" ]]; then
            local ret
            #shellcheck disable=SC2086
            case ${_fstype} in
                xfs)      mkfs.xfs ${_fsoptions} -L "${_labelname}" -f "${_device}" >${LOG} 2>&1; ret=$? ;;
                jfs)      yes | mkfs.jfs ${_fsoptions} -L "${_labelname}" "${_device}" >${LOG} 2>&1; ret=$? ;;
                reiserfs) yes | mkreiserfs ${_fsoptions} -l "${_labelname}" "${_device}" >${LOG} 2>&1; ret=$? ;;
                ext2)     mkfs.ext2 -F -L ${_fsoptions} "${_labelname}" "${_device}" >${LOG} 2>&1; ret=$? ;;
                ext3)     mke2fs -F ${_fsoptions} -L "${_labelname}" -t ext3 "${_device}" >${LOG} 2>&1; ret=$? ;;
                ext4)     mke2fs -F ${_fsoptions} -L "${_labelname}" -t ext4 "${_device}" >${LOG} 2>&1; ret=$? ;;
                f2fs)     mkfs.f2fs ${_fsoptions} -l "${_labelname}" "${_device}" >${LOG} 2>&1; ret=$? ;;
                btrfs)    mkfs.btrfs -f ${_fsoptions} -L "${_labelname}" "${_btrfsdevices}" >${LOG} 2>&1; ret=$? ;;
                nilfs2)   mkfs.nilfs2 -f ${_fsoptions} -L "${_labelname}" "${_device}" >${LOG} 2>&1; ret=$? ;;
                ntfs3)    mkfs.ntfs ${_fsoptions} -L "${_labelname}" "${_device}" >${LOG} 2>&1; ret=$? ;;
                vfat)     mkfs.vfat -F32 ${_fsoptions} -n "${_labelname}" "${_device}" >${LOG} 2>&1; ret=$? ;;
                # don't handle anything else here, we will error later
            esac
            if [[ ${ret} != 0 ]]; then
                DIALOG --msgbox "Error creating filesystem ${_fstype} on ${_device}" 0 0
                return 1
            fi
            sleep 2
        fi
        if [[ "${_fstype}" = "btrfs" && -n "${_btrfssubvolume}" && "${_dosubvolume}" = "yes" ]]; then
            create_btrfs_subvolume
        fi
        btrfs_scan
        sleep 2
        # create our mount directory
        mkdir -p "${_dest}""${_mountpoint}"
        # add ssd optimization before mounting
        ssd_optimization
        _mountoptions=""
        # prepare btrfs mount options
        [[ -n "${_btrfssubvolume}" ]] && _mountoptions="${_mountoptions} subvol=${_btrfssubvolume}"
        [[ -n "${_btrfscompress}" ]] && _mountoptions="${_mountoptions} ${_btrfscompress}"
        _mountoptions="${_mountoptions} ${ssd_mount_options}"
        # eleminate spaces at beginning and end, replace other spaces with ,
        _mountoptions="$(echo "${_mountoptions}" | sed -e 's#^ *##g' -e 's# *$##g' | sed -e 's# #,#g')"
        # mount the bad boy
        mount -t "${_fstype}" -o "${_mountoptions}" "${_device}" "${_dest}""${_mountpoint}" >${LOG} 2>&1
        if [[ $? != 0 ]]; then
            DIALOG --msgbox "Error mounting ${_dest}${_mountpoint}" 0 0
            return 1
        fi
	# btrfs needs balancing, else weird things could happen
        [[ "${_fstype}" = "btrfs" ]] && btrfs balance start --full-balance "${_dest}""${_mountpoint}" >${LOG} 2>&1
        # change permission of base directories to correct permission
        # to avoid btrfs issues
        if [[ "${_mountpoint}" = "/tmp" ]]; then
            chmod 1777 "${_dest}""${_mountpoint}"
        elif [[ "${_mountpoint}" = "/root" ]]; then
            chmod 750 "${_dest}""${_mountpoint}"
        else
            chmod 755 "${_dest}""${_mountpoint}"
        fi
    fi
    # add to .device-names for config files
    local _fsuuid="$(getfsuuid "${_device}")"
    local _fslabel="$(getfslabel "${_device}")"
    
    if [[ "${GUID_DETECTED}" == "1" ]]; then
        local _partuuid="$(getpartuuid "${_device}")"
        local _partlabel="$(getpartlabel "${_device}")"
        
        echo "# DEVICE DETAILS: ${_device} PARTUUID=${_partuuid} PARTLABEL=${_partlabel} UUID=${_fsuuid} LABEL=${_fslabel}" >> /tmp/.device-names
    else
        echo "# DEVICE DETAILS: ${_device} UUID=${_fsuuid} LABEL=${_fslabel}" >> /tmp/.device-names
    fi
    
    # add to temp fstab
    if [[ "${NAME_SCHEME_PARAMETER}" == "FSUUID" ]]; then
        if [[ -n "${_fsuuid}" ]]; then
            _device="UUID=${_fsuuid}"
        fi
    elif [[ "${NAME_SCHEME_PARAMETER}" == "FSLABEL" ]]; then
        if [[ -n "${_fslabel}" ]]; then
            _device="LABEL=${_fslabel}"
        fi
    else
        if [[ "${GUID_DETECTED}" == "1" ]]; then
           if [[ "${NAME_SCHEME_PARAMETER}" == "PARTUUID" ]]; then
               if [[ -n "${_partuuid}" ]]; then
                   _device="PARTUUID=${_partuuid}"
               fi
           elif [[ "${NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]]; then
               if [[ -n "${_partlabel}" ]]; then
                   _device="PARTLABEL=${_partlabel}"
               fi
           fi 
        fi
    fi
    # / root is not needed in fstab, it's mounted automatically
    # systemd supports detection on GPT disks:
    # /boot as ESP: c12a7328-f81f-11d2-ba4b-00a0c93ec93b
    # swap:  0657fd6d-a4ab-43c4-84e5-0933c84b4f4f
    # /home: 933ac7e1-2eb4-4f13-b844-0e14e2aef915
    # Complex devices, like mdadm, encrypt or lvm are not supported
    # _GUID_VALUE:
    # get real device name from lsblk first to get GUID_VALUE from blkid
    _GUID_VALUE="$(${_BLKID} -p -i -s PART_ENTRY_TYPE -o value "$(${_LSBLK} NAME,UUID,LABEL,PARTLABEL,PARTUUID | grep "$(echo "${_device}" | cut -d"=" -f2)" | cut -d" " -f 1)")"
    if ! [[ "${_GUID_VALUE}" == "933ac7e1-2eb4-4f13-b844-0e14e2aef915" &&  "${_mountpoint}" == "/home" || "${_GUID_VALUE}" == "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f" && "${_mountpoint}" == "swap" || "${_GUID_VALUE}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" && "${_mountpoint}" == "/boot" && "${_DETECTED_UEFI_BOOT}" == "1" || "${_mountpoint}" == "/" ]]; then
        if [[ "${_mountoptions}" == "" ]]; then
            echo -n "${_device} ${_mountpoint} ${_fstype} defaults 0 " >>/tmp/.fstab
        else
            echo -n "${_device} ${_mountpoint} ${_fstype} defaults,${_mountoptions} 0 " >>/tmp/.fstab
        fi
        if [[ "${_fstype}" = "swap" || "${_fstype}" = "btrfs" ]]; then
            echo "0" >>/tmp/.fstab
        else
            echo "1" >>/tmp/.fstab
        fi
    fi
    unset _mountoptions
    unset _btrfssubvolume
    unset _btrfscompress
}

getsource() {
    S_SRC=0
    select_mirror || return 1
    S_SRC=1
}

# select_mirror()
# Prompt user for preferred mirror and set ${SYNC_URL}
#
# args: none
# returns: nothing
select_mirror() {
    NEXTITEM="4"
    ## Download updated mirrorlist, if possible (only on x86_64)
    if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
        dialog --infobox "Downloading latest mirrorlist ..." 0 0
        ${DLPROG} -q "https://www.archlinux.org/mirrorlist/?country=all&protocol=http&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on" -O /tmp/pacman_mirrorlist.txt -o ${LOG} 2>/dev/null
    
        if grep -q '#Server = http:' /tmp/pacman_mirrorlist.txt; then
            mv "${MIRRORLIST}" "${MIRRORLIST}.bak"
            cp /tmp/pacman_mirrorlist.txt "${MIRRORLIST}"
        fi
    fi
    # FIXME: this regex doesn't honor commenting
    MIRRORS=$(grep -E -o '((http)|(https))://[^/]*' "${MIRRORLIST}" | sed 's|$| _|g')
    DIALOG --menu "Select a mirror" 14 55 7 \
        ${MIRRORS} \
        "Custom" "_" 2>${ANSWER} || return 1
    local _server=$(cat ${ANSWER})
    if [[ "${_server}" = "Custom" ]]; then
        DIALOG --inputbox "Enter the full URL to repositories." 8 65 \
            "" 2>${ANSWER} || return 1
            SYNC_URL=$(cat ${ANSWER})
    else
        # Form the full URL for our mirror by grepping for the server name in
        # our mirrorlist and pulling the full URL out. Substitute 'core' in
        # for the repository name, and ensure that if it was listed twice we
        # only return one line for the mirror.
        SYNC_URL=$(grep -E -o "${_server}.*" "${MIRRORLIST}" | head -n1)
    fi
    echo "Using mirror: ${SYNC_URL}" >${LOG}
    echo "Server = "${SYNC_URL}"" >> /etc/pacman.d/mirrorlist
    if [[ "${DOTESTING}" == "yes" ]]; then
        echo "[testing]" >> /etc/pacman.conf
        echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
        echo "[community-testing]" >> /etc/pacman.conf
        echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
    fi
}

# dotesting()
# enable testing repository on network install
dotesting() {
    DOTESTING=""
    DIALOG --defaultno --yesno "Do you want to enable [testing] repository?\n\nOnly enable this if you need latest available packages for testing purposes!" 8 60 && DOTESTING="yes"
}

# configures pacman and syncs db on destination system
# params: none
# returns: 1 on error
prepare_pacman() {
    # Set up the necessary directories for pacman use
    [[ ! -d "${DESTDIR}/var/cache/pacman/pkg" ]] && mkdir -p "${DESTDIR}/var/cache/pacman/pkg"
    [[ ! -d "${DESTDIR}/var/lib/pacman" ]] && mkdir -p "${DESTDIR}/var/lib/pacman"
    DIALOG --infobox "Refreshing package database..." 6 45
    ${PACMAN} -Sy >${LOG} 2>&1 || (DIALOG --msgbox "Pacman preparation failed! Check ${LOG} for errors." 6 60; return 1)
    return 0
}

# Set PACKAGES parameter before running to install wanted packages
run_pacman(){
    # create chroot environment on target system
    # code straight from mkarchroot
    chroot_mount

    # execute pacman in a subshell so we can follow its progress
    # pacman output goes /tmp/pacman.log
    # /tmp/setup-pacman-running acts as a lockfile
    ( \
        echo "Installing Packages..." >/tmp/pacman.log ; \
        echo >>/tmp/pacman.log ; \
        touch /tmp/setup-pacman-running ; \
        ${PACMAN} -S ${PACKAGES} 2>&1 >> /tmp/pacman.log ; \
        echo $? > /tmp/.pacman-retcode ; \
        if [[ $(cat /tmp/.pacman-retcode) -ne 0 ]]; then
            echo -e "\nPackage Installation FAILED." >>/tmp/pacman.log
        else
            echo -e "\nPackage Installation Complete." >>/tmp/pacman.log
        fi
        rm /tmp/setup-pacman-running
    ) &

    # display pacman output while it's running
    sleep 2
    dialog --backtitle "${TITLE}" --title " Installing... Please Wait " \
        --no-kill --tailboxbg "/tmp/pacman.log" 18 70 2>${ANSWER}
    while [[ -f /tmp/setup-pacman-running ]]; do
        /usr/bin/true
    done
    kill $(cat ${ANSWER})

    # pacman finished, display scrollable output
    local _result=''
    if [[ $(cat /tmp/.pacman-retcode) -ne 0 ]]; then
        _result="Installation Failed (see errors below)"
    else
        _result="Installation Complete"
    fi
    rm /tmp/.pacman-retcode
    DIALOG --title "${_result}" --exit-label "Continue" \
        --textbox "/tmp/pacman.log" 18 70 || return 1
    # ensure the disk is synced
    sync
    chroot_umount
}

# install_packages()
# performs package installation to the target system
#
install_packages() {
    destdir_mounts || return 1
    if [[ "${S_MKFS}" != "1" && "${S_MKFSAUTO}" != "1" ]]; then
        getdest
    fi
    if [[ "${S_SRC}" = "0" ]]; then
        select_source || return 1
    fi
    prepare_pacman
    PACKAGES=""
    DIALOG --yesno "Next step will install base, linux, linux-firmware, netctl and filesystem tools for a minimal system.\n\nDo you wish to continue?" 10 50 || return 1
    PACKAGES="base linux linux-firmware"
    # Add packages which are not in core repository
    if [[ -n "$(pgrep dhclient)" ]]; then
        ! echo "${PACKAGES}" | grep -qw dhclient && PACKAGES="${PACKAGES} dhclient"
    fi
    # Add filesystem packages
    if lsblk -rnpo FSTYPE | grep -q ntfs; then
        ! echo "${PACKAGES}" | grep -qw ntfs-3g && PACKAGES="${PACKAGES} ntfs-3g"
    fi
    if lsblk -rnpo FSTYPE | grep -q btrfs; then
        ! echo "${PACKAGES}" | grep -qw btrfs-progs && PACKAGES="${PACKAGES} btrfs-progs"
    fi
    if lsblk -rnpo FSTYPE | grep -q nilfs2; then
        ! echo "${PACKAGES}" | grep -qw nilfs-utils && PACKAGES="${PACKAGES} nilfs-utils"
    fi
    if lsblk -rnpo FSTYPE | grep -q ext; then
        ! echo "${PACKAGES}" | grep -qw e2fsprogs && PACKAGES="${PACKAGES} e2fsprogs"
    fi
    if lsblk -rnpo FSTYPE | grep -q reiserfs; then
        ! echo "${PACKAGES}" | grep -qw reiserfsprogs && PACKAGES="${PACKAGES} reiserfsprogs"
    fi
    if lsblk -rnpo FSTYPE | grep -q xfs; then
        ! echo "${PACKAGES}" | grep -qw xfsprogs && PACKAGES="${PACKAGES} xfsprogs"
    fi
    if lsblk -rnpo FSTYPE | grep -q jfs; then
        ! echo "${PACKAGES}" | grep -qw jfsutils && PACKAGES="${PACKAGES} jfsutils"
    fi
    if lsblk -rnpo FSTYPE | grep -q f2fs; then
        ! echo "${PACKAGES}" | grep -qw f2fs-tools && PACKAGES="${PACKAGES} f2fs-tools"
    fi
    if lsblk -rnpo FSTYPE | grep -q vfat; then
        ! echo "${PACKAGES}" | grep -qw dosfstools && PACKAGES="${PACKAGES} dosfstools"
    fi
    if ! [[ "$(dmraid_devices)" = "" ]]; then
        ! echo "${PACKAGES}" | grep -w dmraid && PACKAGES="${PACKAGES} dmraid"
    fi
    ### HACK:
    # always add systemd-sysvcompat components
    PACKAGES="${PACKAGES//\ systemd-sysvcompat\ / }"
    PACKAGES="${PACKAGES} systemd-sysvcompat"
    ### HACK:
    # always add intel-ucode
    if [[ "$(uname -m)" == "x86_64" ]]; then
        PACKAGES="${PACKAGES//\ intel-ucode\ / }"
        PACKAGES="${PACKAGES} intel-ucode"
    fi
    # always add amd-ucode
    PACKAGES="${PACKAGES//\ amd-ucode\ / }"
    PACKAGES="${PACKAGES} amd-ucode"
    ### HACK:
    # always add netctl with optdepends
    PACKAGES="${PACKAGES//\ netctl\ / }"
    PACKAGES="${PACKAGES} netctl"
    PACKAGES="${PACKAGES//\ dhcpd\ / }"
    PACKAGES="${PACKAGES} dhcpcd"
    PACKAGES="${PACKAGES//\ wpa_supplicant\ / }"
    PACKAGES="${PACKAGES} wpa_supplicant"
    ### HACK:
    # always add lvm2, cryptsetup and mdadm
    PACKAGES="${PACKAGES//\ lvm2\ / }"
    PACKAGES="${PACKAGES} lvm2"
    PACKAGES="${PACKAGES//\ cryptsetup\ / }"
    PACKAGES="${PACKAGES} cryptsetup"
    PACKAGES="${PACKAGES//\ mdadm\ / }"
    PACKAGES="${PACKAGES} mdadm"
    ### HACK
    # always add nano and vi
    PACKAGES="${PACKAGES//\ nano\ / }"
    PACKAGES="${PACKAGES} nano"
    PACKAGES="${PACKAGES//\ vi\ / }"
    PACKAGES="${PACKAGES} vi"
    ### HACK: circular depends are possible in base, install filesystem first!
    PACKAGES="${PACKAGES//\ filesystem\ / }"
    PACKAGES="filesystem ${PACKAGES}"
    DIALOG --infobox "Package installation will begin in 3 seconds. You can watch the output in the progress window. Please be patient." 0 0
    sleep 3
    run_pacman
    NEXTITEM="6"
    chroot_mount
    # automagic time!
    # any automatic configuration should go here
    DIALOG --infobox "Writing base configuration..." 6 40
    auto_fstab
    auto_ssd
    auto_mdadm
    auto_luks
    auto_pacman
    auto_testing
    # tear down the chroot environment
    chroot_umount
}

# auto_fstab()
# preprocess fstab file
# comments out old fields and inserts new ones
# according to partitioning/formatting stage
#
auto_fstab(){
    # Modify fstab
    if [[ "${S_MKFS}" = "1" || "${S_MKFSAUTO}" = "1" ]]; then
        if [[ -f /tmp/.device-names ]]; then
            sort /tmp/.device-names >>"${DESTDIR}"/etc/fstab
        fi
        if [[ -f /tmp/.fstab ]]; then
            # clean fstab first from entries
            sed -i -e '/^\#/!d' "${DESTDIR}"/etc/fstab
            sort /tmp/.fstab >>"${DESTDIR}"/etc/fstab
        fi
    fi
}

# auto_ssd()
# add udev rule for ssd disks using the deadline scheduler by default
# add sysctl file for swaps
auto_ssd () {
    [[ ! -f ${DESTDIR}/etc/udev/rules.d/60-ioschedulers.rules ]] && cp /etc/udev/rules.d/60-ioschedulers.rules "${DESTDIR}"/etc/udev/rules.d/60-ioschedulers.rules
    [[ ! -f ${DESTDIR}/etc/sysctl.d/99-sysctl.conf ]] && cp /etc/sysctl.d/99-sysctl.conf "${DESTDIR}"/etc/sysctl.d/99-sysctl.conf
}

# auto_mdadm()
# add mdadm setup to existing /etc/mdadm.conf
auto_mdadm()
{
    if [[ -e ${DESTDIR}/etc/mdadm.conf ]]; then
        if grep -q ^md /proc/mdstat 2>/dev/null; then
            DIALOG --infobox "Adding raid setup to ${DESTDIR}/etc/mdadm.conf ..." 4 40
            mdadm -Ds >> "${DESTDIR}"/etc/mdadm.conf
        fi
    fi
}

# auto_network()
# configures network on host system according to installer
# settings if user wishes to do so
#
auto_network()
{
    # exit if network wasn't configured in installer
    if [[ ${S_NET} -eq 0 ]]; then
        return 1
    fi
    # copy netctl profiles
    [[ -d ${DESTDIR}/etc/netctl ]] && cp /etc/netctl/* "${DESTDIR}"/etc/netctl/ 2>/dev/null
    # enable netctl profiles
    for i in $(echo /etc/netctl/*); do
         [[ -f $i ]] && chroot "${DESTDIR}" /usr/bin/netctl enable "$(basename "${i}")"
    done
    # copy proxy settings
    if [[ "${PROXY_HTTP}" != "" ]]; then
        echo "export http_proxy=${PROXY_HTTP}" >> "${DESTDIR}"/etc/profile.d/proxy.sh;
        chmod a+x "${DESTDIR}"/etc/profile.d/proxy.sh
    fi
    if [[ "${PROXY_FTP}" != "" ]]; then
        echo "export ftp_proxy=${PROXY_FTP}" >> "${DESTDIR}"/etc/profile.d/proxy.sh;
        chmod a+x "${DESTDIR}"/etc/profile.d/proxy.sh
    fi
}

# Pacman signature check is enabled by default
# add gnupg pacman files to installed system
# in order to have a working pacman on installed system
auto_pacman()
{
    if ! [[ -d ${DESTDIR}/etc/pacman.d/gnupg ]]; then
        DO_PACMAN_GPG=""
        DIALOG --yesno "Would you like to copy pacman's GPG files to installed system?\nDuring boot pacman GPG entropy was generated by haveged,\nif you need your own entropy answer NO." 0 0 && DO_PACMAN_GPG="yes"
        if [[ "${DO_PACMAN_GPG}" = "yes" ]]; then
            DIALOG --infobox "Copy /etc/pacman.d/gnupg directory to ${DESTDIR}/etc/pacman.d/gnupg ..." 0 0
            cp -ar /etc/pacman.d/gnupg "${DESTDIR}"/etc/pacman.d 2>&1
        fi
    fi
}

# If [testing] repository was enabled during installation, 
# enable it on installed system too!
auto_testing()
{  
   if [[ "${DOTESTING}" == "yes" ]]; then
       sed -i -e '/^#\[testing\]/ { n ; s/^#// }' "${DESTDIR}"/etc/pacman.conf
       sed -i -e '/^#\[community-testing\]/ { n ; s/^#// }' "${DESTDIR}"/etc/pacman.conf
       sed -i -e 's:^#\[testing\]:\[testing\]:g' -e  's:^#\[community-testing\]:\[community-testing\]:g' "${DESTDIR}"/etc/pacman.conf
   fi
}

# check for already active profile
check_nework() {
    for i in /etc/netctl/*; do
        [[ -f "${i}" ]] && netctl is-active "$(basename "${i}")" && S_NET=1
    done
    [[ "${S_NET}" == "1" ]] || donetwork
}

# donetwork()
# Hand-hold through setting up networking
#
# args: none
# returns: 1 on failure
donetwork() {
    NETPARAMETERS=""
    while [[ "${NETPARAMETERS}" = "" ]]; do
        # select network interface
        INTERFACE=
        ifaces=$(net_interfaces)
        while [[ "${INTERFACE}" = "" ]]; do
            #shellcheck disable=SC2086
            DIALOG --ok-label "Select" --menu "Select a network interface" 14 55 7 ${ifaces} 2>${ANSWER}
            case $? in
                1) return 1 ;;
                0) INTERFACE=$(cat ${ANSWER}) ;;
            esac
        done
        # wireless switch
        CONNECTION=""
        WLAN_HIDDEN=""
        WLAN_ESSID=""
        WLAN_SECURITY=""
        WLAN_KEY=""
        DIALOG --defaultno --yesno "Is your network device wireless?" 5 40
        if [[ $? -eq 0 ]]; then
            CONNECTION="wireless"
            DIALOG --inputbox "Enter your ESSID" 7 40 "MyNetwork" 2>${ANSWER} || return 1
            WLAN_ESSID=$(cat ${ANSWER})
            DIALOG --defaultno --yesno "Is your wireless network hidden?" 5 40
            [[ $? -eq 0 ]] && WLAN_HIDDEN="yes"
            DIALOG --yesno "Is your wireless network encrypted?" 5 40
            if [[ $? -eq 0 ]]; then
                while [[ "${WLAN_SECURITY}" = "" ]]; do
                DIALOG --ok-label "Select" --menu "Select encryption type" 9 40 7 \
                    "wep" "WEP encryption" \
                    "wpa" "WPA encryption" 2>${ANSWER}
                    case $? in
                        1) return 1 ;;
                        0) WLAN_SECURITY=$(cat ${ANSWER}) ;;
                    esac
                done
                DIALOG --inputbox "Enter your KEY" 5 40 "WirelessKey" 2>${ANSWER} || return 1
                WLAN_KEY=$(cat ${ANSWER})
            else
                WLAN_SECURITY="none"
            fi
        else
            CONNECTION="ethernet"
        fi
        # dhcp switch
        IP=""
        DHCLIENT=""
        DIALOG --yesno "Do you want to use DHCP?" 5 40
        if [[ $? -eq 0 ]]; then
            IP="dhcp"
            DIALOG --defaultno --yesno "Do you want to use dhclient instead of dhcpcd?" 5 55
            [[ $? -eq 0 ]] && DHCLIENT="yes"

        else
            IP="static"
            DIALOG --inputbox "Enter your IP address and netmask" 7 40 "192.168.1.23/24" 2>${ANSWER} || return 1
            IPADDR=$(cat ${ANSWER})
            DIALOG --inputbox "Enter your gateway" 7 40 "192.168.1.1" 2>${ANSWER} || return 1
            GW=$(cat ${ANSWER})
            DIALOG --inputbox "Enter your DNS server IP" 7 40 "192.168.1.1" 2>${ANSWER} || return 1
            DNS=$(cat ${ANSWER})
        fi
        DIALOG --yesno "Are these settings correct?\n\nInterface:    ${INTERFACE}\nConnection:   ${CONNECTION}\nESSID:      ${WLAN_ESSID}\nHidden:     ${WLAN_HIDDEN}\nEncryption: ${WLAN_SECURITY}\nKey:        ${WLAN_KEY}\ndhcp or static: ${IP}\nUse dhclient:   ${DHCLIENT}\nIP address: ${IPADDR}\nGateway:    ${GW}\nDNS server: ${DNS}" 0 0
        case $? in
            1) ;;
            0) NETPARAMETERS="1" ;;
        esac
    done
    # profile name
    NETWORK_PROFILE=""
    DIALOG --inputbox "Enter your network profile name" 7 40 "${INTERFACE}-${CONNECTION}" 2>${ANSWER} || return 1
    NETWORK_PROFILE=/etc/netctl/$(cat ${ANSWER})
    # write profile
    echo "Connection=${CONNECTION}" >"${NETWORK_PROFILE}"
    echo "Description='$NETWORK_PROFILE generated by archboot setup'" >>"${NETWORK_PROFILE}"
    echo "Interface=${INTERFACE}"  >>"${NETWORK_PROFILE}"
    if [[ "${CONNECTION}" = "wireless" ]]; then
        echo "Security=${WLAN_SECURITY}" >>"${NETWORK_PROFILE}"
        echo "ESSID='${WLAN_ESSID}'" >>"${NETWORK_PROFILE}"
        echo "Key='${WLAN_KEY}'" >>"${NETWORK_PROFILE}"
        [[ "${WLAN_HIDDEN}" = "yes" ]] && echo "Hidden=yes" >>"${NETWORK_PROFILE}"
    fi
    echo "IP=${IP}" >>"${NETWORK_PROFILE}"
    if [[ "${IP}" = "dhcp" ]]; then
        [[ "${DHCLIENT}" = "yes" ]] && echo "DHCPClient=dhclient" >>"${NETWORK_PROFILE}"
    else
        echo "Address='${IPADDR}'" >>"${NETWORK_PROFILE}"
        echo "Gateway='${GW}'" >>"${NETWORK_PROFILE}"
        echo "DNS=('${DNS}')" >>"${NETWORK_PROFILE}"
    fi
    # bring down interface first
    systemctl stop dhcpcd@"${INTERFACE}".service
    ip link set dev "${INTERFACE}" down
    # run netctl
    netctl restart "$(basename "${NETWORK_PROFILE}")" >${LOG}
    if [[ $? -gt 0 ]]; then
        DIALOG --msgbox "Error occured while running netctl. (see 'journalctl -xn' for output)" 0 0
        return 1
    fi
    # http/ftp proxy settings
    DIALOG --inputbox "Enter your HTTP proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." 13 65 "" 2>${ANSWER} || return 1
    PROXY_HTTP=$(cat ${ANSWER})
    DIALOG --inputbox "Enter your FTP proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." 13 65 "" 2>${ANSWER} || return 1
    PROXY_FTP=$(cat ${ANSWER})
    if [[ "${PROXY_HTTP}" = "" ]]; then
        unset http_proxy
    else
        export http_proxy=${PROXY_HTTP}
    fi
    if [[ "${PROXY_FTP}" = "" ]]; then
        unset ftp_proxy
    else
        export ftp_proxy=${PROXY_FTP}
    fi
    # add sleep here dhcp can need some time to get link
    DIALOG --infobox "Please wait 5 seconds for network link to come up ..." 0 0
    sleep 5
    NEXTITEM="2"
    S_NET=1
}

getrootfstype() {
    ROOTFS="$(getfstype "${PART_ROOT}")"
}

getrootflags() {
    ROOTFLAGS=""
    ROOTFLAGS="$(findmnt -m -n -o options -T "${DESTDIR}")"
    # add subvolume for btrfs
    if [[ "${ROOTFS}" == "btrfs" ]]; then 
        findmnt -m -n -o SOURCE -T "${DESTDIR}" | grep -q "\[" && ROOTFLAGS="${ROOTFLAGS},subvol=$(basename "$(findmnt -m -n -o SOURCE -T "${DESTDIR}" | cut -d "]" -f1)")"
    fi
    [[ -n "${ROOTFLAGS}" ]] && ROOTFLAGS="rootflags=${ROOTFLAGS}"
}

getraidarrays() {
    RAIDARRAYS=""
    if ! grep -q ^ARRAY "${DESTDIR}"/etc/mdadm.conf; then
        RAIDARRAYS="$(echo -n "$(grep ^md /proc/mdstat 2>/dev/null | sed -e 's#\[[0-9]\]##g' -e 's# :.* raid[0-9]##g' -e 's#md#md=#g' -e 's# #,/dev/#g' -e 's#_##g')")"
    fi
}

getcryptsetup() {
    CRYPTSETUP=""
    if ! cryptsetup status "$(basename "${PART_ROOT}")" | grep -q inactive; then
        #avoid clash with dmraid here
        if cryptsetup status "$(basename "${PART_ROOT}")"; then
            if [[ "${NAME_SCHEME_PARAMETER}" == "FSUUID" ]]; then
                CRYPTDEVICE="UUID=$(${_LSBLK} UUID "$(cryptsetup status "$(basename "${PART_ROOT}")" | grep device: | sed -e 's#device:##g')")"
            elif [[ "${NAME_SCHEME_PARAMETER}" == "FSLABEL" ]]; then
                CRYPTDEVICE="LABEL=$(${_LSBLK} LABEL "$(cryptsetup status "$(basename "${PART_ROOT}")" | grep device: | sed -e 's#device:##g')")"
            else
                CRYPTDEVICE="$(cryptsetup status "$(basename "${PART_ROOT}")" | grep device: | sed -e 's#device:##g'))"    
            fi
            CRYPTNAME="$(basename "${PART_ROOT}")"
            CRYPTSETUP="cryptdevice=${CRYPTDEVICE}:${CRYPTNAME}"
        fi
    fi
}

getrootpartuuid() {
    _rootpart="${PART_ROOT}"
    _partuuid="$(getpartuuid "${PART_ROOT}")"
    if [[ -n "${_partuuid}" ]]; then
        _rootpart="PARTUUID=${_partuuid}"
    fi
}

getrootpartlabel() {
    _rootpart="${PART_ROOT}"
    _partlabel="$(getpartlabel "${PART_ROOT}")"
    if [[ -n "${_partlabel}" ]]; then
        _rootpart="PARTLABEL=${_partlabel}"
    fi
}

getrootfsuuid() {
    _rootpart="${PART_ROOT}"
    _fsuuid="$(getfsuuid "${PART_ROOT}")"
    if [[ -n "${_fsuuid}" ]]; then
        _rootpart="UUID=${_fsuuid}"
    fi
}

getrootfslabel() {
    _rootpart="${PART_ROOT}"
    _fslabel="$(getfslabel "${PART_ROOT}")"
    if [[ -n "${_fslabel}" ]]; then
        _rootpart="LABEL=${_fslabel}"
    fi
}

## Setup kernel cmdline parameters to be added to bootloader configs
bootloader_kernel_parameters() {
    
    if [[ "${GUID_DETECTED}" == "1" ]]; then
        [[ "${NAME_SCHEME_PARAMETER}" == "PARTUUID" ]] && getrootpartuuid
        [[ "${NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]] && getrootpartlabel
    fi
    
    [[ "${NAME_SCHEME_PARAMETER}" == "FSUUID" ]] && getrootfsuuid
    [[ "${NAME_SCHEME_PARAMETER}" == "FSLABEL" ]] && getrootfslabel
    
    [[ "${_rootpart}" == "" ]] && _rootpart="${PART_ROOT}"
    
    _KERNEL_PARAMS_COMMON_UNMOD="root=${_rootpart} rootfstype=${ROOTFS} rw ${ROOTFLAGS} ${RAIDARRAYS} ${CRYPTSETUP} cgroup_disable=memory"
    # add uncommonn options here
    _KERNEL_PARAMS_BIOS_UNMOD="${_KERNEL_PARAMS_COMMON_UNMOD}"
    _KERNEL_PARAMS_UEFI_UNMOD="${_KERNEL_PARAMS_COMMON_UNMOD}"
    _KERNEL_PARAMS_BIOS_MOD="$(echo "${_KERNEL_PARAMS_BIOS_UNMOD}" | sed -e 's#   # #g' | sed -e 's#  # #g')"
    _KERNEL_PARAMS_UEFI_MOD="$(echo "${_KERNEL_PARAMS_UEFI_UNMOD}" | sed -e 's#   # #g' | sed -e 's#  # #g')"
    
}

# basic checks needed for all bootloaders
common_bootloader_checks() {
    activate_special_devices
    getrootfstype
    getraidarrays
    getcryptsetup
    getrootflags
    bootloader_kernel_parameters
}

# look for a separately-mounted /boot partition
check_bootpart() {
    subdir=""
    bootdev="$(mount | grep "${DESTDIR}/boot " | cut -d' ' -f 1)"
    if [[ "${bootdev}" == "" ]]; then
        subdir="/boot"
        bootdev="${PART_ROOT}"
    fi
}

# check for nilfs2 bootpart and abort if detected
abort_nilfs_bootpart() {
        FSTYPE="$(${_LSBLK} FSTYPE "${bootdev}")"
        if [[ "${FSTYPE}" = "nilfs2" ]]; then
            DIALOG --msgbox "Error:\nYour selected bootloader cannot boot from nilfs2 partition with /boot on it." 0 0
            return 1
        fi
}

# check for f2fs bootpart and abort if detected
abort_f2fs_bootpart() {
        FSTYPE="$(${_LSBLK} FSTYPE "${bootdev}")"
        if [[ "${FSTYPE}" = "f2fs" ]]; then
            DIALOG --msgbox "Error:\nYour selected bootloader cannot boot from f2fs partition with /boot on it." 0 0
            return 1
        fi
}

uefi_mount_efivarfs() {
    
    ## Mount efivarfs if it is not already mounted
    if ! mount | grep -q /sys/firmware/efi/efivars; then
        modprobe -q efivarfs
        mount -t efivarfs efivarfs /sys/firmware/efi/efivars
    fi
    
}

detect_uefi_secure_boot() {
    
    export _DETECTED_UEFI_SECURE_BOOT="0"
    
    if [[ "${_DETECTED_UEFI_BOOT}" == "1" ]]; then
        uefi_mount_efivarfs
        _SECUREBOOT_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SecureBoot 2>/dev/null | tail -n -1 | awk '{print $2}')"
        _SETUPMODE_VAR_VALUE="$(efivar -n 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode  2>/dev/null | tail -n -1 | awk '{print $2}')"
        
        if [[ "${_SECUREBOOT_VAR_VALUE}" == "01" ]] && [[ "${_SETUPMODE_VAR_VALUE}" == "00" ]]; then
            export _DETECTED_UEFI_SECURE_BOOT="1"
        fi
    fi
    
}

detect_uefi_boot() {
    
    export _DETECTED_UEFI_BOOT="0"
    
    [[ -e "/sys/firmware/efi" ]] && _DETECTED_UEFI_BOOT="1"
    
    detect_uefi_secure_boot
    
}

do_uefi_setup_env_vars() {
    
    if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
        if grep -q '_IA32_UEFI=1' /proc/cmdline 1>/dev/null; then
            export _EFI_MIXED="1"
            export _UEFI_ARCH="IA32"
            export _SPEC_UEFI_ARCH="ia32"
        else
            export _EFI_MIXED="0"
            export _UEFI_ARCH="X64"
            export _SPEC_UEFI_ARCH="x64"
        fi
    fi
    if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
        export _EFI_MIXED="0"
        export _UEFI_ARCH="AA64"
        export _SPEC_UEFI_ARCH="aa64"
    fi

}

do_uefi_common() {
    
    do_uefi_setup_env_vars
    
    PACKAGES=""
    [[ ! -f "${DESTDIR}/usr/bin/mkfs.vfat" ]] && PACKAGES="${PACKAGES} dosfstools"
    [[ ! -f "${DESTDIR}/usr/bin/efivar" ]] && PACKAGES="${PACKAGES} efivar"
    [[ ! -f "${DESTDIR}/usr/bin/efibootmgr" ]] && PACKAGES="${PACKAGES} efibootmgr"
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        [[ ! -f "${DESTDIR}/usr/bin/mokutil" ]] && PACKAGES="${PACKAGES} mokutil"
        [[ ! -f "${DESTDIR}/usr/bin/efi-readvar" ]] && PACKAGES="${PACKAGES} efitools"
        [[ ! -f "${DESTDIR}/usr/bin/sbsign" ]] && PACKAGES="${PACKAGES} sbsigntools"
    fi
    ! [[ "${PACKAGES}" == "" ]] && run_pacman
    unset PACKAGES
    
    check_efisys_part
    
}

do_uefi_efibootmgr() {
    
    uefi_mount_efivarfs
    
    if [[ "$(/usr/bin/efivar -l)" ]]; then
        cat << EFIBEOF > "/tmp/efibootmgr_run.sh"
#!/usr/bin/env bash

_EFIBOOTMGR_LOADER_PARAMETERS="${_EFIBOOTMGR_LOADER_PARAMETERS}"

for _bootnum in \$(efibootmgr | grep '^Boot[0-9]' | fgrep -i "${_EFIBOOTMGR_LABEL}" | cut -b5-8) ; do
    efibootmgr --quiet --bootnum "\${_bootnum}" --delete-bootnum
done

if [[ "\${_EFIBOOTMGR_LOADER_PARAMETERS}" != "" ]]; then
    efibootmgr --quiet --create --disk "${_EFIBOOTMGR_DISC}" --part "${_EFIBOOTMGR_PART_NUM}" --loader "${_EFIBOOTMGR_LOADER_PATH}" --label "${_EFIBOOTMGR_LABEL}" --unicode "\${_EFIBOOTMGR_LOADER_PARAMETERS}" -e "3"
else
    efibootmgr --quiet --create --disk "${_EFIBOOTMGR_DISC}" --part "${_EFIBOOTMGR_PART_NUM}" --loader "${_EFIBOOTMGR_LOADER_PATH}" --label "${_EFIBOOTMGR_LABEL}" -e "3"
fi

EFIBEOF
        
        chmod a+x "/tmp/efibootmgr_run.sh"
        /tmp/efibootmgr_run.sh &>"/tmp/efibootmgr_run.log"
    else
        DIALOG --msgbox "Boot entry could not be created. Check whether you have booted in UEFI boot mode and create a boot entry for ${UEFISYS_MOUNTPOINT}/${_EFIBOOTMGR_LOADER_PATH} using efibootmgr." 0 0
    fi
    
    unset _EFIBOOTMGR_LABEL
    unset _EFIBOOTMGR_DISC
    unset _EFIBOOTMGR_PART_NUM
    unset _EFIBOOTMGR_LOADER_PATH
    unset _EFIBOOTMGR_LOADER_PARAMETERS
    
}

do_apple_efi_hfs_bless() {
    
    ## Grub upstream bzr mactel branch => http://bzr.savannah.gnu.org/lh/grub/branches/mactel/changes
    ## Fedora's mactel-boot => https://bugzilla.redhat.com/show_bug.cgi?id=755093
    DIALOG --msgbox "TODO: Apple Mac EFI Bootloader Setup" 0 0
    
}

do_uefi_bootmgr_setup() {
    
    _uefisysdev="$(findmnt -vno SOURCE "${DESTDIR}/${UEFISYS_MOUNTPOINT}")"
    _DISC="$(${_LSBLK} KNAME "${_uefisysdev}")"
    UEFISYS_PART_NUM="$(${_BLKID} -p -i -s PART_ENTRY_NUMBER -o value "${_uefisysdev}")"
    
    _BOOTMGR_DISC="${_DISC}"
    _BOOTMGR_PART_NUM="${UEFISYS_PART_NUM}"
    
    if [[ "$(cat "/sys/class/dmi/id/sys_vendor")" == 'Apple Inc.' ]] || [[ "$(cat "/sys/class/dmi/id/sys_vendor")" == 'Apple Computer, Inc.' ]]; then
        do_apple_efi_hfs_bless
    else
        ## For all the non-Mac UEFI systems
        _EFIBOOTMGR_LABEL="${_BOOTMGR_LABEL}"
        _EFIBOOTMGR_DISC="${_BOOTMGR_DISC}"
        _EFIBOOTMGR_PART_NUM="${_BOOTMGR_PART_NUM}"
        _EFIBOOTMGR_LOADER_PATH="${_BOOTMGR_LOADER_PATH}"
        _EFIBOOTMGR_LOADER_PARAMETERS="${_BOOTMGR_LOADER_PARAMETERS}"
        do_uefi_efibootmgr
    fi
    
    unset _BOOTMGR_LABEL
    unset _BOOTMGR_DISC
    unset _BOOTMGR_PART_NUM
    unset _BOOTMGR_LOADER_PATH
    unset _BOOTMGR_LOADER_PARAMETERS
    
}

do_uefi_secure_boot_efitools() {
    
    do_uefi_common
    # install helper tools and create entries in UEFI boot manager, if not present
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        chroot_mount
        if [[ ! -f "${UEFISYS_MOUNTPOINT}/EFI/BOOT/HashTool.efi" ]]; then 
            chroot "${DESTDIR}" cp "/usr/share/efitools/efi/HashTool.efi" "${UEFISYS_MOUNTPOINT}/EFI/BOOT/HashTool.efi"
            _BOOTMGR_LABEL="HashTool (Secure Boot)"
            _BOOTMGR_LOADER_DIR="/EFI/BOOT/HashTool.efi"
            do_uefi_bootmgr_setup
        fi
        if [[ ! -f "${UEFISYS_MOUNTPOINT}/EFI/BOOT/KeyTool.efi" ]]; then 
            chroot "${DESTDIR}" cp "/usr/share/efitools/efi/KeyTool.efi" "${UEFISYS_MOUNTPOINT}/EFI/BOOT/KeyTool.efi"
            _BOOTMGR_LABEL="KeyTool (Secure Boot)"
            _BOOTMGR_LOADER_DIR="/EFI/BOOT/KeyTool.efi"
            do_uefi_bootmgr_setup
        fi
        chroot_umount
    fi
    
}

do_secureboot_keys() {
    CN=""
    MOK_PW=""
    KEYDIR=""
    while [[ "${KEYDIR}" = "" ]]; do
        DIALOG --inputbox "Setup keys:\nEnter the directory to store the keys on ${DESTDIR}.\nPlease leave the leading slash \"/\"." 8 65 "etc/secureboot/keys" 2>${ANSWER} || KEYDIR=""
        KEYDIR=$(cat ${ANSWER})
    done
    if [[ ! -d "${DESTDIR}/${KEYDIR}" ]]; then 
        while [[ "${CN}" = "" ]]; do
            DIALOG --inputbox "Setup keys:\nEnter a common name(CN) for your keys, eg. Your Name" 8 65 "" 2>${ANSWER} || CN=""
            CN=$(cat ${ANSWER})
        done
        secureboot-keys.sh -name="${CN}" "${DESTDIR}/${KEYDIR}" > ${LOG} 2>&1 || return 1
         DIALOG --msgbox "Setup keys created:\nCommon name(CN) ${CN} used for your keys in ${DESTDIR}/${KEYDIR} " 8 65
    else
         DIALOG --msgbox "Setup keys:\n-Directory ${DESTDIR}/${KEYDIR} exists\n-assuming keys are already created\n-trying to use existing keys now" 8 65 ""
    fi
}

do_mok_sign () {
    UEFI_BOOTLOADER_DIR="${UEFISYS_MOUNTPOINT}/EFI/BOOT"
    INSTALL_MOK=""
    MOK_PW=""
    DIALOG --yesno "Do you want to install the MOK certificate to the UEFI keys?" 0 0 && INSTALL_MOK="1"
    if [[ "${INSTALL_MOK}" == "1" ]]; then
        while [[ "${MOK_PW}" = "" ]]; do
            DIALOG --insecure --passwordbox "Enter a one time MOK password for SHIM on reboot:" 8 65 2>${ANSWER} || return 1
            PASS=$(cat ${ANSWER})
            DIALOG --insecure --passwordbox "Retype one time MOK password:" 8 65 2>${ANSWER} || return 1
            PASS2=$(cat ${ANSWER})
            if [[ "${PASS}" = "${PASS2}" ]]; then
                MOK_PW=${PASS}
                echo "${MOK_PW}" > /tmp/.password
                echo "${MOK_PW}" >> /tmp/.password
                MOK_PW=/tmp/.password
            else
                DIALOG --msgbox "Password didn't match, please enter again." 8 65
            fi
        done
        mokutil -i "${DESTDIR}"/"${KEYDIR}"/MOK/MOK.cer < ${MOK_PW} > ${LOG}
        rm /tmp/.password
        DIALOG --msgbox "MOK keys have been installed successfully." 8 65
    fi
    SIGN_MOK=""
    DIALOG --yesno "Do you want to sign /boot/${VMLINUZ} and ${UEFI_BOOTLOADER_DIR}/grub${_SPEC_UEFI_ARCH}.efi with the MOK certificate?" 0 0 && SIGN_MOK="1"
    if [[ "${SIGN_MOK}" == "1" ]]; then
        chroot_mount
        chroot "${DESTDIR}" sbsign --key /"${KEYDIR}"/MOK/MOK.key --cert /"${KEYDIR}"/MOK/MOK.crt --output /boot/${VMLINUZ} /boot/${VMLINUZ} > ${LOG} 
        chroot "${DESTDIR}" sbsign --key /"${KEYDIR}"/MOK/MOK.key --cert /"${KEYDIR}"/MOK/MOK.crt --output "${UEFI_BOOTLOADER_DIR}"/grub${_SPEC_UEFI_ARCH}.efi "${UEFI_BOOTLOADER_DIR}"/grub${_SPEC_UEFI_ARCH}.efi > ${LOG}
        chroot_umount
        DIALOG --msgbox "/boot/${VMLINUZ} and ${UEFI_BOOTLOADER_DIR}/grub${_SPEC_UEFI_ARCH}.efi\nbeen signed successfully." 8 65
    fi
}

do_pacman_sign() {
    SIGN_KERNEL=""
    DIALOG --yesno "Do you want to install a pacman hook for automatic signing /boot/${VMLINUZ} on updates?" 0 0 && SIGN_KERNEL="1"
    if [[ "${SIGN_KERNEL}" == "1" ]]; then
        [[ ! -d "${DESTDIR}/etc/pacman.d/hooks" ]] &&  mkdir -p  "${DESTDIR}"/etc/pacman.d/hooks/
        HOOKNAME="${DESTDIR}/etc/pacman.d/hooks/999-sign_kernel_for_secureboot.hook"
        cat << EOF > "${HOOKNAME}"
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux

[Action]
Description = Signing kernel with Machine Owner Key for Secure Boot
When = PostTransaction
Exec = /usr/bin/find /boot/ -maxdepth 1 -name 'vmlinuz-*' -exec /usr/bin/sh -c 'if ! /usr/bin/sbverify --list {} 2>/dev/null | /usr/bin/grep -q "signature certificates"; then /usr/bin/sbsign --key /${KEYDIR}/MOK/MOK.key --cert /${KEYDIR}/MOK/MOK.crt --output {} {}; fi' ;
Depends = sbsigntools
Depends = findutils
Depends = grep
EOF
        DIALOG --msgbox "Pacman hook for automatic signing has been installed successfully:\n${HOOKNAME}" 8 75
    fi
}

do_efistub_copy_to_efisys() {
    
    if [[ "${UEFISYS_MOUNTPOINT}" != "/boot" ]]; then
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            _EFISTUB_KERNEL="linux/arch/${VMLINUZ_EFISTUB}.efi"
        else
            _EFISTUB_KERNEL="linux/arch/${VMLINUZ}.efi"
        fi
        _EFISTUB_INITRAMFS="linux/arch/${INITRAMFS}"
        
        ! [[ -d "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch" ]] && mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/"
        
        rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_KERNEL}"
        rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}.img"
        rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}-fallback.img"
        
        cp -f "${DESTDIR}/boot/${VMLINUZ}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_KERNEL}"
        cp -f "${DESTDIR}/boot/${INITRAMFS}.img" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}.img"
        cp -f "${DESTDIR}/boot/${INITRAMFS}-fallback.img" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}-fallback.img"
        
        #######################
        
        cat << CONFEOF > "${DESTDIR}/etc/systemd/system/efistub_copy.path"
[Unit]
Description=Copy EFISTUB Kernel and Initramfs files to EFI SYSTEM PARTITION

[Path]
PathChanged=/boot/${VMLINUZ}
PathChanged=/boot/${INTEL_UCODE}
PathChanged=/boot/${AMD_UCODE}
PathChanged=/boot/${INITRAMFS}.img
PathChanged=/boot/${INITRAMFS}-fallback.img
Unit=efistub_copy.service

[Install]
WantedBy=multi-user.target
CONFEOF
        
        cat << CONFEOF > "${DESTDIR}/etc/systemd/system/efistub_copy.service"
[Unit]
Description=Copy EFISTUB Kernel and Initramfs files to EFI SYSTEM PARTITION

[Service]
Type=oneshot
ExecStart=/usr/bin/cp -f /boot/${VMLINUZ} ${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_KERNEL}
ExecStart=/usr/bin/cp -f /boot/${INTEL_UCODE} ${UEFISYS_MOUNTPOINT}/EFI/arch/${INTEL_UCODE}
ExecStart=/usr/bin/cp -f /boot/${AMD_UCODE} ${UEFISYS_MOUNTPOINT}/EFI/arch/${AMD_UCODE}
ExecStart=/usr/bin/cp -f /boot/${INITRAMFS}.img ${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}.img
ExecStart=/usr/bin/cp -f /boot/${INITRAMFS}-fallback.img ${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}-fallback.img
CONFEOF
        
        chroot "${DESTDIR}" /usr/bin/systemctl enable efistub_copy.path
    fi
     
    ###########################
    
    _bootdev="$(findmnt -vno SOURCE "${DESTDIR}/boot")"
    _uefisysdev="$(findmnt -vno SOURCE "${DESTDIR}/${UEFISYS_MOUNTPOINT}")"
    
    UEFISYS_PART_FS_UUID="$(getfsuuid "${_uefisysdev}")"
    
    if [[ "${UEFISYS_MOUNTPOINT}" == "/boot" ]]; then
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
             _KERNEL_NORMAL="/${VMLINUZ_EFISTUB}"
        else
            _KERNEL_NORMAL="/${VMLINUZ}"
            _INITRD_INTEL_UCODE="/${INTEL_UCODE}"
        fi
        
        _INITRD_AMD_UCODE="/${AMD_UCODE}"
        
        _INITRD_NORMAL="/${INITRAMFS}.img"
        
        _INITRD_FALLBACK_NORMAL="/${INITRAMFS}-fallback.img"
    else
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            _KERNEL_NORMAL="/EFI/arch/${VMLINUZ_EFISTUB}"
        else
            _KERNEL_NORMAL="/EFI/arch/${_EFISTUB_KERNEL}"
            _INITRD_INTEL_UCODE="/EFI/arch/${INTEL_UCODE}"
        fi
        _INITRD_AMD_UCODE="/EFI/arch/${AMD_UCODE}"

        _INITRD_NORMAL="/EFI/arch/${_EFISTUB_INITRAMFS}.img"
        
        _INITRD_FALLBACK_NORMAL="/EFI/arch/${_EFISTUB_INITRAMFS}-fallback.img"
    fi
    
}

do_efistub_uefi() {
    
    do_uefi_common
    
    bootdev=""
    FAIL_COMPLEX=""
    USE_DMRAID=""
    RAID_ON_LVM=""
    common_bootloader_checks
    
    do_efistub_copy_to_efisys
    
    ###################################
    
    if [[ "${UEFISYS_MOUNTPOINT}" == "/boot" ]]; then
        _CONTINUE="1"
    else
        if [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_KERNEL}" ]] && [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}.img" ]]; then
            DIALOG --msgbox "The EFISTUB Kernel and initramfs have been copied to ${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_KERNEL} and ${UEFISYS_MOUNTPOINT}/EFI/arch/${_EFISTUB_INITRAMFS}.img respectively." 0 0
            _CONTINUE="1"
        else
            DIALOG --msgbox "Error setting up EFISTUB kernel and initramfs in ${UEFISYS_MOUNTPOINT}." 0 0
            _CONTINUE="0"
        fi
    fi
    
    if [[ "${_CONTINUE}" == "1" ]]; then
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            do_systemd_boot_uefi
        else
            DIALOG --menu "Select which UEFI Boot Manager to install, to provide a menu for the EFISTUB kernels?" 11 55 3 \
                "Systemd-boot" "Systemd-boot for ${_UEFI_ARCH} UEFI" \
                "rEFInd" "rEFInd for ${_UEFI_ARCH} UEFI" \
                "NONE" "No Boot Manager" 2>${ANSWER} || CANCEL=1
            case $(cat ${ANSWER}) in
                "Systemd-boot") do_systemd_boot_uefi ;;
                "rEFInd") do_refind_uefi;;
                "NONE") return 0 ;;
            esac
        fi
    fi
    
}

do_systemd_boot_uefi() {
    
    DIALOG --msgbox "Setting up Systemd-boot now ..." 0 0
    
    # create directory structure, if it doesn't exist
    ! [[ -d "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries" ]] && mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries"
    cat << GUMEOF > "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-main.conf"
title    Arch Linux
linux    ${_KERNEL_NORMAL}
GUMEOF

    if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
    cat << GUMEOF >> "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-main.conf"
initrd   ${_INITRD_INTEL_UCODE}
GUMEOF
    fi
    
    cat << GUMEOF >> "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-main.conf"
initrd   ${_INITRD_AMD_UCODE}
initrd   ${_INITRD_NORMAL}
options  ${_KERNEL_PARAMS_UEFI_MOD}
GUMEOF
    
    cat << GUMEOF > "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-fallback.conf"
title    Arch Linux Fallback
linux    ${_KERNEL_NORMAL}
GUMEOF

    if [[ "${RUNNING_ARCH}" == "x86_64" ]]; then
    cat << GUMEOF >> "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-fallback.conf"
initrd   ${_INITRD_INTEL_UCODE}
GUMEOF
    fi
    
    cat << GUMEOF >> "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-fallback.conf"
initrd   ${_INITRD_AMD_UCODE}
initrd   ${_INITRD_FALLBACK_NORMAL}
options  ${_KERNEL_PARAMS_UEFI_MOD}
GUMEOF
    
    cat << GUMEOF > "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/loader.conf"
timeout 5
default archlinux-core-main
GUMEOF
    
    uefi_mount_efivarfs
    
    chroot_mount
    chroot "${DESTDIR}" "/usr/bin/bootctl" --path="${UEFISYS_MOUNTPOINT}" install
    chroot "${DESTDIR}" "/usr/bin/bootctl" --path="${UEFISYS_MOUNTPOINT}" update
    chroot_umount
    
    if [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi" ]]; then
        DIALOG --msgbox "You will now be put into the editor to edit loader.conf and Systemd-boot menu entry files . After you save your changes, exit the editor." 0 0
        geteditor || return 1
        
        "${EDITOR}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-main.conf"
        "${EDITOR}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/entries/archlinux-core-fallback.conf"
        
        "${EDITOR}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/loader/loader.conf"
        
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            _UEFISYS_EFI_BOOT_DIR="1"
        else
            DIALOG --defaultno --yesno "Do you want to copy ${UEFISYS_MOUNTPOINT}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi to ${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi ?\n\nThis might be needed in some systems where efibootmgr may not work due to firmware issues." 0 0 && _UEFISYS_EFI_BOOT_DIR="1"
        fi
        
        if [[ "${_UEFISYS_EFI_BOOT_DIR}" == "1" ]]; then
            mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT"
            rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi" || true
            cp -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/systemd/systemd-boot${_SPEC_UEFI_ARCH}.efi" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi"
        fi
    else
        DIALOG --msgbox "Error installing Systemd-boot..." 0 0
    fi
}

do_refind_uefi() {
    
    DIALOG --msgbox "Setting up rEFInd now ..." 0 0
    
    if [[ ! -f "${DESTDIR}/usr/bin/refind-install" ]]; then
        DIALOG --infobox "Couldn't find ${DESTDIR}/usr/bin/refind-install, installing refind pkg in 3 seconds ..." 0 0
        sleep 3
        PACKAGES="refind"
        run_pacman
        unset PACKAGES
    fi
    
    ! [[ -d "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind" ]] && mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/"
    cp -f "${DESTDIR}/usr/share/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi"
    cp -r "${DESTDIR}/usr/share/refind/icons" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/icons"
    cp -r "${DESTDIR}/usr/share/refind/fonts" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/fonts"
    
     ! [[ -d "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/tools" ]] &&  mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/tools/"
    cp -rf "${DESTDIR}/usr/share/refind/drivers_${_SPEC_UEFI_ARCH}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/tools/drivers_${_SPEC_UEFI_ARCH}"
    mv "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/tools/drivers_${_SPEC_UEFI_ARCH}"/ext2_x64.{,_}efi
    
    _REFIND_CONFIG="${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/refind.conf"
    cp -f "${DESTDIR}/usr/share/refind/refind.conf-sample" "${_REFIND_CONFIG}"

    sed 's|^#resolution 1024 768|resolution 1024 768|g' -i "${_REFIND_CONFIG}"
    sed 's|^#scan_driver_dirs EFI/tools/drivers,drivers|scan_driver_dirs EFI/tools/drivers_${_SPEC_UEFI_ARCH}|g' -i "${_REFIND_CONFIG}"
    sed 's|^#scanfor internal,external,optical,manual|scanfor manual,internal,external,optical|g' -i "${_REFIND_CONFIG}"
    sed 's|^#also_scan_dirs boot,ESP2:EFI/linux/kernels|also_scan_dirs boot|g' -i "${_REFIND_CONFIG}"
    sed 's|^#scan_all_linux_kernels|scan_all_linux_kernels|g' -i "${_REFIND_CONFIG}"
    
    if [[ "${UEFISYS_MOUNTPOINT}" == "/boot" ]]; then
        _REFIND_LINUX_CONF="${DESTDIR}/${UEFISYS_MOUNTPOINT}/refind_linux.conf"
    else
        _REFIND_LINUX_CONF="${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/arch/refind_linux.conf"
    fi
    
    cat << REFINDEOF > "${_REFIND_LINUX_CONF}"
"Boot with Defaults"              "${_KERNEL_PARAMS_UEFI_MOD} initrd=${_INITRD_INTEL_UCODE} initrd=${_INITRD_AMD_UCODE} initrd=${_INITRD_NORMAL}"
"Boot with fallback initramfs"    "${_KERNEL_PARAMS_UEFI_MOD} initrd=${_INITRD_INTEL_UCODE} initrd=${_INITRD_AMD_UCODE} initrd=${_INITRD_FALLBACK_NORMAL}"
REFINDEOF
    
    if [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" ]]; then
        _BOOTMGR_LABEL="rEFInd"
        _BOOTMGR_LOADER_DIR="/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi"
        do_uefi_bootmgr_setup
        
        DIALOG --msgbox "refind has been setup successfully." 0 0
        
        DIALOG --msgbox "You will now be put into the editor to edit refind.conf and refind_linux.conf . After you save your changes, exit the editor." 0 0
        geteditor || return 1
        "${EDITOR}" "${_REFIND_CONFIG}"
        
        DIALOG --defaultno --yesno "Do you want to copy ${UEFISYS_MOUNTPOINT}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi to ${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi ?\n\nThis might be needed in some systems where efibootmgr may not work due to firmware issues." 0 0 && _UEFISYS_EFI_BOOT_DIR="1"
        
        if [[ "${_UEFISYS_EFI_BOOT_DIR}" == "1" ]]; then
            mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT"
            
            rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi" || true
            rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/refind.conf" || true
            rm -rf "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/icons" || true
            
            cp -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi"
            cp -f "${_REFIND_CONFIG}" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/refind.conf"
            cp -rf "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/refind/icons" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/icons"
        fi
    else
        DIALOG --msgbox "Error setting up refind." 0 0
    fi
    
}

do_grub_common_before() {
    ##### Check whether the below limitations still continue with ver 2.00~beta4
    ### Grub(2) restrictions:
    ## - Encryption is not recommended for grub(2) /boot!
    
    bootdev=""
    FAIL_COMPLEX=""
    USE_DMRAID=""
    RAID_ON_LVM=""
    common_bootloader_checks
    abort_f2fs_bootpart || return 1
    
    if ! dmraid -r | grep -q ^no; then
        DIALOG --yesno "Setup detected dmraid device.\nDo you want to install grub on this device?" 0 0 && USE_DMRAID="1"
    fi
    if [[ ! -d "${DESTDIR}/usr/lib/grub" ]]; then
        DIALOG --infobox "Couldn't find ${DESTDIR}/usr/lib/grub, installing grub pkg in 3 seconds ..." 0 0
        sleep 3
        PACKAGES="grub"
        run_pacman
        # reset PACKAGES after installing
        unset PACKAGES
    fi
}

do_grub_config() {
    
    chroot_mount 
    
    ########
    
    BOOT_PART_FS_UUID="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs_uuid" "/boot" 2>/dev/null)"
    BOOT_PART_FS_LABEL="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs_label" "/boot" 2>/dev/null)"
    BOOT_PART_HINTS_STRING="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="hints_string" "/boot" 2>/dev/null)"
    BOOT_PART_FS="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs" "/boot" 2>/dev/null)"
    
    BOOT_PART_DRIVE="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="drive" "/boot" 2>/dev/null)"
    
    ########
    
    ROOT_PART_FS_UUID="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs_uuid" "/" 2>/dev/null)"
    ROOT_PART_HINTS_STRING="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="hints_string" "/" 2>/dev/null)"
    ROOT_PART_FS="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs" "/" 2>/dev/null)"
    
    ########
    
    USR_PART_FS_UUID="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs_uuid" "/usr" 2>/dev/null)"
    USR_PART_HINTS_STRING="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="hints_string" "/usr" 2>/dev/null)"
    USR_PART_FS="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs" "/usr" 2>/dev/null)"
    
    ########
    
    if [[ "${GRUB_UEFI}" == "1" ]]; then
        UEFISYS_PART_FS_UUID="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="fs_uuid" "/${UEFISYS_MOUNTPOINT}" 2>/dev/null)"
        UEFISYS_PART_HINTS_STRING="$(chroot "${DESTDIR}" /usr/bin/grub-probe --target="hints_string" "/${UEFISYS_MOUNTPOINT}" 2>/dev/null)"
    fi
    
    ########
    
    if [[ "${ROOT_PART_FS_UUID}" == "${BOOT_PART_FS_UUID}" ]]; then
        subdir="/boot"
        # on btrfs we need to check on subvol
        if mount | grep "${DESTDIR} " | grep btrfs | grep subvol; then
            subdir="/$(btrfs subvolume show "${DESTDIR}/" | grep Name | cut -d ":" -f2)"/boot
        fi
    else
        subdir=""
        # on btrfs we need to check on subvol
        if mount | grep "${DESTDIR}/boot " | grep btrfs | grep subvol; then
            subdir="/$(btrfs subvolume show "${DESTDIR}/boot" | grep Name | cut -d ":" -f2)"
        fi
    fi
    
    ########
    
    ## Move old config file, if any
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        GRUB_CFG="grub${_SPEC_UEFI_ARCH}.cfg"
    else
        GRUB_CFG="grub.cfg"
    fi
    [[ -f "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}" ]] && (mv "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}" "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}.bak" || true)
    ## Ignore if the insmod entries are repeated - there are possibilities of having /boot in one disk and root-fs in altogether different disk
    ## with totally different configuration.
    
    cat << EOF > "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

if [ "\${grub_platform}" == "efi" ]; then
    set _UEFI_ARCH="\${grub_cpu}"
    
    if [ "\${grub_cpu}" == "x86_64" ]; then
        set _SPEC_UEFI_ARCH="x64"
    fi
    
    if [ "\${grub_cpu}" == "i386" ]; then
        set _SPEC_UEFI_ARCH="ia32"
    fi
    if [ "\${grub_cpu}" == "aarch64" ]; then
        set _SPEC_UEFI_ARCH="aa64"
    fi
fi

EOF
    
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

insmod part_gpt
insmod part_msdos

# Include fat fs module - required for uefi systems.
insmod fat

insmod ${BOOT_PART_FS}
insmod ${ROOT_PART_FS}
insmod ${USR_PART_FS}

insmod search_fs_file
insmod search_fs_uuid
insmod search_label

insmod linux
insmod chain

set pager="1"
# set debug="all"

set locale_dir="\${prefix}/locale"

EOF
    
    [[ "${USE_RAID}" == "1" ]] && echo "insmod raid" >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    ! [[ "${RAID_ON_LVM}" == "" ]] && echo "insmod lvm" >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

if [ -e "\${prefix}/\${grub_cpu}-\${grub_platform}/all_video.mod" ]; then
    insmod all_video
else
    if [ "\${grub_platform}" == "efi" ]; then
        insmod efi_gop
        insmod efi_uga
    fi
    
    if [ "\${grub_platform}" == "pc" ]; then
        insmod vbe
        insmod vga
    fi
    
    insmod video_bochs
    insmod video_cirrus
fi

insmod font

search --fs-uuid --no-floppy --set=usr_part ${USR_PART_HINTS_STRING} ${USR_PART_FS_UUID}
search --fs-uuid --no-floppy --set=root_part ${ROOT_PART_HINTS_STRING} ${ROOT_PART_FS_UUID}

if [ -e "\${prefix}/fonts/unicode.pf2" ]; then
    set _fontfile="\${prefix}/fonts/unicode.pf2"
else
    if [ -e "(\${root_part})/usr/share/grub/unicode.pf2" ]; then
        set _fontfile="(\${root_part})/usr/share/grub/unicode.pf2"
    else
        if [ -e "(\${usr_part})/share/grub/unicode.pf2" ]; then
            set _fontfile="(\${usr_part})/share/grub/unicode.pf2"
        fi
    fi
fi

if loadfont "\${_fontfile}" ; then
    insmod gfxterm
    set gfxmode="auto"
    
    terminal_input console
    terminal_output gfxterm
fi

EOF
    
    echo "" >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    sort "/tmp/.device-names" >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    echo "" >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    
    if [[ "${NAME_SCHEME_PARAMETER}" == "PARTUUID" ]] || [[ "${NAME_SCHEME_PARAMETER}" == "FSUUID" ]] ; then
        GRUB_ROOT_DRIVE="search --fs-uuid --no-floppy --set=root ${BOOT_PART_HINTS_STRING} ${BOOT_PART_FS_UUID}"
    else
        if [[ "${NAME_SCHEME_PARAMETER}" == "PARTLABEL" ]] || [[ "${NAME_SCHEME_PARAMETER}" == "FSLABEL" ]] ; then
            GRUB_ROOT_DRIVE="search --label --no-floppy --set=root ${BOOT_PART_HINTS_STRING} ${BOOT_PART_FS_LABEL}"
        else
            GRUB_ROOT_DRIVE="set root=${BOOT_PART_DRIVE}"
        fi
    fi
    
    if [[ "${GRUB_UEFI}" == "1" ]]; then
        LINUX_UNMOD_COMMAND="linux ${subdir}/${VMLINUZ} ${_KERNEL_PARAMS_UEFI_MOD}"
    else
        LINUX_UNMOD_COMMAND="linux ${subdir}/${VMLINUZ} ${_KERNEL_PARAMS_BIOS_MOD}"
    fi
    
    LINUX_MOD_COMMAND=$(echo "${LINUX_UNMOD_COMMAND}" | sed -e 's#   # #g' | sed -e 's#  # #g')
    
    ## create default kernel entry
    
    NUMBER="0"

if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

# (${NUMBER}) Arch Linux
menuentry "Arch Linux" {
    set gfxpayload="keep"
    ${GRUB_ROOT_DRIVE}
    ${LINUX_MOD_COMMAND}
    initrd ${subdir}/${AMD_UCODE} ${subdir}/${INITRAMFS}.img
}

EOF
    
    NUMBER=$((NUMBER+1))
    
    ## create kernel fallback entry
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

# (${NUMBER}) Arch Linux Fallback
menuentry "Arch Linux Fallback" {
    set gfxpayload="keep"
    ${GRUB_ROOT_DRIVE}
    ${LINUX_MOD_COMMAND}
    initrd ${subdir}/${AMD_UCODE} ${subdir}/${INITRAMFS}-fallback.img
}

EOF

else
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

# (${NUMBER}) Arch Linux
menuentry "Arch Linux" {
    set gfxpayload="keep"
    ${GRUB_ROOT_DRIVE}
    ${LINUX_MOD_COMMAND}
    initrd ${subdir}/${INTEL_UCODE} ${subdir}/${AMD_UCODE} ${subdir}/${INITRAMFS}.img
}

EOF
    
    NUMBER=$((NUMBER+1))
    
    ## create kernel fallback entry
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

# (${NUMBER}) Arch Linux Fallback
menuentry "Arch Linux Fallback" {
    set gfxpayload="keep"
    ${GRUB_ROOT_DRIVE}
    ${LINUX_MOD_COMMAND}
    initrd ${subdir}/${INTEL_UCODE} ${subdir}/${AMD_UCODE} ${subdir}/${INITRAMFS}-fallback.img
}

EOF
    
    NUMBER=$((NUMBER+1))
    
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

if [ "\${grub_platform}" == "efi" ]; then
    
    ## UEFI Shell 2.0
    #menuentry "UEFI Shell \${_UEFI_ARCH} v2" {
    #    search --fs-uuid --no-floppy --set=root ${UEFISYS_PART_HINTS_STRING} ${UEFISYS_PART_FS_UUID}
    #    chainloader /EFI/tools/shell\${_SPEC_UEFI_ARCH}_v2.efi
    #}
    
    ## UEFI Shell 1.0
    #menuentry "UEFI Shell \${_UEFI_ARCH} v1" {
    #    search --fs-uuid --no-floppy --set=root ${UEFISYS_PART_HINTS_STRING} ${UEFISYS_PART_FS_UUID}
    #    chainloader /EFI/tools/shell\${_SPEC_UEFI_ARCH}_v1.efi
    #}
    
fi

EOF
    
    NUMBER=$((NUMBER+1))
    
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

if [ "\${grub_platform}" == "efi" ]; then
    if [ "\${grub_cpu}" == "x86_64" ]; then
        ## Microsoft Windows 10/11 via x86_64 UEFI
        #menuentry \"Microsoft Windows 10/11 x86_64 UEFI-GPT\" {
        #    insmod part_gpt
        #    insmod fat
        #    insmod search_fs_uuid
        #    insmod chain
        #    search --fs-uuid --no-floppy --set=root ${UEFISYS_PART_HINTS_STRING} ${UEFISYS_PART_FS_UUID}
        #    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
        #}
    fi
fi

EOF
    
    NUMBER=$((NUMBER+1))
    
    ## TODO: Detect actual Windows installation if any
    ## create example file for windows
    cat << EOF >> "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"

if [ "\${grub_platform}" == "pc" ]; then
    
    ## Microsoft Windows 10/11 BIOS
    #menuentry \"Microsoft Windows 10/11 BIOS-MBR\" {
    #    insmod part_msdos
    #    insmod ntfs
    #    insmod search_fs_uuid
    #    insmod ntldr
    #    search --fs-uuid --no-floppy --set=root <FS_UUID of Windows SYSTEM Partition>
    #    ntldr /bootmgr
    #}
    
fi

EOF

fi
    ## copy unicode.pf2 font file
    cp -f "${DESTDIR}/usr/share/grub/unicode.pf2" "${DESTDIR}/${GRUB_PREFIX_DIR}/fonts/unicode.pf2"
    
    chroot_umount
    
    ## Edit grub.cfg config file
    DIALOG --msgbox "You must now review the grub(2) configuration file.\n\nYou will now be put into the editor. After you save your changes, exit the editor." 0 0
    geteditor || return 1
    "${EDITOR}" "${DESTDIR}/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
    
    unset BOOT_PART_FS_UUID
    unset BOOT_PART_FS
    unset BOOT_PART_FS_LABEL
    unset BOOT_PART_DRIVE
    
    unset ROOT_PART_FS_UUID
    unset ROOT_PART_FS
    
    unset GRUB_ROOT_DRIVE
    unset LINUX_UNMOD_COMMAND
    unset LINUX_MOD_COMMAND
    
}

do_grub_bios() {
    
    do_grub_common_before
        
    # try to auto-configure GRUB(2)...
    if [[ "${PART_ROOT}" != "" ]]; then
        check_bootpart
        
        # check if raid, raid partition, dmraid or device devicemapper is used
        if echo "${bootdev}" | grep -q /dev/md || echo "${bootdev}" | grep /dev/mapper; then
            # boot from lvm, raid, partitioned raid and dmraid devices is supported
            FAIL_COMPLEX="0"
            
            if cryptsetup status "${bootdev}"; then
                # encryption devices are not supported
                FAIL_COMPLEX="1"
            fi
        fi
        
        if [[ "${FAIL_COMPLEX}" == "0" ]]; then
            # check if mapper is used
            if  echo "${bootdev}" | grep -q /dev/mapper; then
                RAID_ON_LVM="0"
                
                #check if mapper contains a md device!
                for devpath in $(pvs -o pv_name --noheading); do
                    if echo "${devpath}" | grep -v "/dev/md*p" | grep /dev/md; then
                        detectedvolumegroup="$(pvs -o vg_name --noheading "${devpath}")"
                        
                        if echo /dev/mapper/"${detectedvolumegroup}"-* | grep "${bootdev}"; then
                            # change bootdev to md device!
                            bootdev=$(pvs -o pv_name --noheading "${devpath}")
                            RAID_ON_LVM="1"
                            break
                        fi
                    fi
                done
            fi
            
            #check if raid is used
            USE_RAID=""
            if echo "${bootdev}" | grep -q /dev/md; then
                USE_RAID="1"
            fi
        fi
    fi
    
    
    # A switch is needed if complex ${bootdev} is used!
    # - LVM and RAID ${bootdev} needs the MBR of a device and cannot be used itself as ${bootdev}
    if [[ "${FAIL_COMPLEX}" == "0" ]]; then
        DEVS="$(findbootloaderdisks _)"
        
        if [[ "${DEVS}" == "" ]]; then
            DIALOG --msgbox "No storage drives were found" 0 0
            return 1
        fi
        #shellcheck disable=SC2086
        DIALOG --menu "Select the boot device where the GRUB(2) bootloader will be installed." 14 55 7 ${DEVS} 2>${ANSWER} || return 1
        bootdev=$(cat ${ANSWER})
    else
        DEVS="$(findbootloaderdisks _)"
        
        ## grub BIOS install to partition is not supported
        # DEVS="${DEVS} $(findbootloaderpartitions _)"
        
        if [[ "${DEVS}" == "" ]]; then
            DIALOG --msgbox "No storage drives were found" 0 0
            return 1
        fi
        #shellcheck disable=SC2086
        DIALOG --menu "Select the boot device where the GRUB(2) bootloader will be installed." 14 55 7 ${DEVS} 2>${ANSWER} || return 1
        bootdev=$(cat ${ANSWER})
    fi
    
    if [[ "$(${_BLKID} -p -i -o value -s PTTYPE "${bootdev}")" == "gpt" ]]; then
        CHECK_BIOS_BOOT_GRUB="1"
        CHECK_UEFISYS_PART=""
        RUN_CFDISK=""
        DISC="${bootdev}"
        check_gpt
    else
        if [[ "${FAIL_COMPLEX}" == "0" ]]; then
            DIALOG --defaultno --yesno "Warning:\nSetup detected no GUID (gpt) partition table.\n\nGrub(2) has only space for approx. 30k core.img file. Depending on your setup, it might not fit into this gap and fail.\n\nDo you really want to install grub(2) to a msdos partition table?" 0 0 || return 1
        fi
    fi
    
    if [[ "${FAIL_COMPLEX}" == "1" ]]; then
        DIALOG --msgbox "Error:\nGrub(2) cannot boot from ${bootdev}, which contains /boot!\n\nPossible error sources:\n- encrypted devices are not supported" 0 0
        return 1
    fi
    
    DIALOG --infobox "Installing the GRUB(2) BIOS bootloader..." 0 0
    # freeze and unfreeze xfs filesystems to enable grub(2) installation on xfs filesystems
    freeze_xfs
    chroot_mount
    
    chroot "${DESTDIR}" "/usr/bin/grub-install" \
        --directory="/usr/lib/grub/i386-pc" \
        --target="i386-pc" \
        --boot-directory="/boot" \
        --recheck \
        --debug \
        "${bootdev}" &>"/tmp/grub_bios_install.log"
    
    chroot_umount
    
    mkdir -p "${DESTDIR}/boot/grub/locale"
    cp -f "${DESTDIR}/usr/share/locale/en@quot/LC_MESSAGES/grub.mo" "${DESTDIR}/boot/grub/locale/en.mo"
     
    if [[ -e "${DESTDIR}/boot/grub/i386-pc/core.img" ]]; then
        DIALOG --msgbox "GRUB(2) BIOS has been successfully installed." 0 0
        
        GRUB_PREFIX_DIR="/boot/grub/"
        do_grub_config
    else
        DIALOG --msgbox "Error installing GRUB(2) BIOS.\nCheck /tmp/grub_bios_install.log for more info.\n\nYou probably need to install it manually by chrooting into ${DESTDIR}.\nDon't forget to bind mount /dev and /proc into ${DESTDIR} before chrooting." 0 0
        return 1
    fi
    
}

do_grub_uefi() {
    
    do_uefi_common
    
    [[ "${_UEFI_ARCH}" == "X64" ]] && _GRUB_ARCH="x86_64"
    [[ "${_UEFI_ARCH}" == "IA32" ]] && _GRUB_ARCH="i386"
    [[ "${_UEFI_ARCH}" == "AA64" ]] && _GRUB_ARCH="arm64"
    
    do_grub_common_before
    
    chroot_mount
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        # install fedora shim
        [[ ! -d  ${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT ]] && mkdir -p "${DESTDIR}"/"${UEFISYS_MOUNTPOINT}"/EFI/BOOT/
        cp -f /usr/share/archboot/fedora-shim/shim${_SPEC_UEFI_ARCH}.efi "${DESTDIR}"/"${UEFISYS_MOUNTPOINT}"/EFI/BOOT/BOOT${_UEFI_ARCH}.efi
        cp -f /usr/share/archboot/fedora-shim/mm${_SPEC_UEFI_ARCH}.efi "${DESTDIR}"/"${UEFISYS_MOUNTPOINT}"/EFI/BOOT/
        GRUB_PREFIX_DIR="${UEFISYS_MOUNTPOINT}/EFI/BOOT/"
    else
        ## Create GRUB Standalone EFI image - https://wiki.archlinux.org/index.php/GRUB#GRUB_Standalone
        echo 'configfile ${cmdpath}/grub.cfg' > /tmp/grub.cfg
        chroot "${DESTDIR}" "/usr/bin/grub-mkstandalone" \
            --directory="/usr/lib/grub/${_GRUB_ARCH}-efi" \
            --format="${_GRUB_ARCH}-efi" \
            --modules="part_gpt part_msdos" \
            --install-modules="all" \
            --fonts="unicode" \
            --locales="en@quot" \
            --themes="" \
            --verbose \
            --output="${UEFISYS_MOUNTPOINT}/EFI/grub/grub${_SPEC_UEFI_ARCH}_standalone.efi" \
            "/boot/grub/grub.cfg=/tmp/grub.cfg" &> "/tmp/grub_uefi_${_UEFI_ARCH}_mkstandalone.log"
    
        ## Install GRUB normally
        chroot "${DESTDIR}" "/usr/bin/grub-install" \
            --directory="/usr/lib/grub/${_GRUB_ARCH}-efi" \
            --target="${_GRUB_ARCH}-efi" \
            --efi-directory="${UEFISYS_MOUNTPOINT}" \
            --bootloader-id="grub" \
            --boot-directory="/boot" \
            --no-nvram \
            --recheck \
            --debug &> "/tmp/grub_uefi_${_UEFI_ARCH}_install.log"
    
        cat "/tmp/grub_uefi_${_UEFI_ARCH}_mkstandalone.log" >> "${LOG}"
        cat "/tmp/grub_uefi_${_UEFI_ARCH}_install.log" >> "${LOG}"
        GRUB_PREFIX_DIR="/boot/grub/"
    fi
    chroot_umount
    GRUB_UEFI="1"
    do_grub_config
    GRUB_UEFI=""
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        # generate GRUB with config embeded
        chroot_mount
        #remove existing, else weird things are happening
        [[ -f "${DESTDIR}/${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" ]] && rm "${DESTDIR}"/${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi
        ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
        # add -v for verbose
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
                chroot "${DESTDIR}" grub-mkstandalone -d /usr/lib/grub/${_GRUB_ARCH}-efi -O ${_GRUB_ARCH}-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd chain tpm" --fonts="unicode" --locales="en@quot" --themes="" -o "${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg=/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
            else
                chroot "${DESTDIR}" grub-mkstandalone -d /usr/lib/grub/${_GRUB_ARCH}-efi -O ${_GRUB_ARCH}-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efi_uga efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd backtrace chain tpm usb usbserial_common usbserial_pl2303 usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard" --fonts="unicode" --locales="en@quot" --themes="" -o "${GRUB_PREFIX_DIR}/grub${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg=/${GRUB_PREFIX_DIR}/${GRUB_CFG}"
            fi
        cp /${GRUB_PREFIX_DIR}/${GRUB_CFG} "${UEFISYS_MOUNTPOINT}"/EFI/BOOT/grub${_SPEC_UEFI_ARCH}.cfg
        chroot_umount
    fi
    if [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/grub/grub${_SPEC_UEFI_ARCH}_standalone.efi" ]]; then
        cp -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/${GRUB_PREFIX_DIR}/grub.cfg" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/grub/grub.cfg"
        
        _BOOTMGR_LABEL="GRUB_Standalone"
        _BOOTMGR_LOADER_DIR="/EFI/grub/grub${_SPEC_UEFI_ARCH}_standalone.efi"
        do_uefi_bootmgr_setup
        
        DIALOG --msgbox "GRUB(2) Standalone for ${_UEFI_ARCH} UEFI has been installed successfully." 8 65
    elif [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi" ]] && [[ -e "${DESTDIR}/boot/grub/${_GRUB_ARCH}-efi/core.efi" ]]; then
        _BOOTMGR_LABEL="GRUB_Normal"
        _BOOTMGR_LOADER_DIR="/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi"
        do_uefi_bootmgr_setup
        
        DIALOG --msgbox "GRUB(2) for ${_UEFI_ARCH} UEFI has been installed successfully." 8 65
        
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            _UEFISYS_EFI_BOOT_DIR="1"
        else
            DIALOG --defaultno --yesno "Do you want to copy ${UEFISYS_MOUNTPOINT}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi to ${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi ?\n\nThis might be needed in some systems where efibootmgr may not work due to firmware issues." 0 0 && _UEFISYS_EFI_BOOT_DIR="1"
        fi
        
        if [[ "${_UEFISYS_EFI_BOOT_DIR}" == "1" ]]; then
            mkdir -p "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT"
            rm -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi" || true
            cp -f "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/grub/grub${_SPEC_UEFI_ARCH}.efi" "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/boot${_SPEC_UEFI_ARCH}.efi"
        fi
    elif [[ -e "${DESTDIR}/${UEFISYS_MOUNTPOINT}/EFI/BOOT/grub${_SPEC_UEFI_ARCH}.efi" ]]; then
        do_secureboot_keys
        do_mok_sign
        do_pacman_sign
        do_uefi_secure_boot_efitools
        _BOOTMGR_LABEL="SHIM with GRUB Secure Boot"
        _BOOTMGR_LOADER_DIR="/EFI/BOOT/BOOT${_UEFI_ARCH}.efi"
        do_uefi_bootmgr_setup
        DIALOG --msgbox "SHIM and GRUB Secure Boot for ${_UEFI_ARCH} UEFI has been installed successfully." 8 75
    else
        DIALOG --msgbox "Error installing GRUB(2) for ${_UEFI_ARCH} UEFI.\nCheck /tmp/grub_uefi_${_UEFI_ARCH}_install.log for more info.\n\nYou probably need to install it manually by chrooting into ${DESTDIR}.\nDon't forget to bind mount /dev, /sys and /proc into ${DESTDIR} before chrooting." 0 0
        return 1
    fi
}

select_source() {
    NEXTITEM="2"
    if [[ ${S_NET} -eq 0 ]]; then
            check_nework || return 1
    fi
    [[ "${RUNNING_ARCH}" == "x86_64" ]] && dotesting
    TITLE="Arch Linux Installation"
    getsource || return 1
    NEXTITEM="3"
}

# check for updating complete environment with packages
update_environment() {
    if [[ -d "/var/cache/pacman/pkg" ]] && [[ -n "$(ls -A "/var/cache/pacman/pkg")" ]]; then
        echo "Packages are already in pacman cache...  > ${LOG}"
    else
        detect_uefi_boot
        UPDATE_ENVIRONMENT=""
        if [[ -e "/usr/bin/update-installer.sh" && "${_DETECTED_UEFI_SECURE_BOOT}" == "0" && "${RUNNING_ARCH}" ==  "x86_64" ]]; then
            DIALOG --defaultno --yesno "Do you want to update the archboot environment to latest packages with caching packages for installation?\n\nATTENTION:\nRequires at least 4GB RAM and will reboot the system using kexec!" 0 0 && UPDATE_ENVIRONMENT="1"
            if [[ "${UPDATE_ENVIRONMENT}" == "1" ]]; then
                DIALOG --infobox "Now setting up new archboot environment and dowloading latest packages.\n\nRunning at the moment: update-installer.sh -latest-install\nCheck ${LOG} for progress...\n\nGet a cup of coffee ...\nThis needs approx. 5 minutes on a fast internet connection (100Mbit)." 0 0
                /usr/bin/update-installer.sh -latest-install > "${LOG}" 2>&1
            fi
        fi
    fi
}

set_clock() {
    if [[ -e /usr/bin/tz ]]; then
        tz --setup && NEXTITEM="4"
    else
        DIALOG --msgbox "Error:\ntz script not found, aborting clock setting" 0 0
    fi
}

set_keyboard() {
    if [[ -e /usr/bin/km ]]; then
        km --setup && NEXTITEM="1"
    else
        DIALOG --msgbox "Error:\nkm script not found, aborting keyboard and console setting" 0 0
    fi
}

# run_mkinitcpio()
# runs mkinitcpio on the target system, displays output
#
run_mkinitcpio() {
    chroot_mount
    # all mkinitcpio output goes to /tmp/mkinitcpio.log, which we tail into a dialog
    ( \
    touch /tmp/setup-mkinitcpio-running
    echo "Initramfs progress ..." > /tmp/initramfs.log; echo >> /tmp/mkinitcpio.log
    if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
        chroot "${DESTDIR}" /usr/bin/mkinitcpio -p ${KERNELPKG}-"${RUNNING_ARCH}" >>/tmp/mkinitcpio.log 2>&1
    else
        chroot "${DESTDIR}" /usr/bin/mkinitcpio -p ${KERNELPKG} >>/tmp/mkinitcpio.log 2>&1
    fi
    echo >> /tmp/mkinitcpio.log
    rm -f /tmp/setup-mkinitcpio-running
    ) &
    sleep 2
    dialog --backtitle "${TITLE}" --title "Rebuilding initramfs images ..." --no-kill --tailboxbg "/tmp/mkinitcpio.log" 18 70
    while [[ -f /tmp/setup-mkinitcpio-running ]]; do
        /usr/bin/true
    done
    chroot_umount
}

prepare_storagedrive() {
    S_MKFSAUTO=0
    S_MKFS=0
    DONE=0
    NEXTITEM=""
    detect_
    while [[ "${DONE}" = "0" ]]; do
        if [[ -n "${NEXTITEM}" ]]; then
            DEFAULT="--default-item ${NEXTITEM}"
        else
            DEFAULT=""
        fi
        CANCEL=""
        #shellcheck disable=SC2086
        dialog ${DEFAULT} --backtitle "${TITLE}" --menu "Prepare Storage Drive" 12 60 5 \
            "1" "Auto-Prepare (erases the ENTIRE storage drive)" \
            "2" "Partition Storage Drives" \
            "3" "Create Software Raid, Lvm2 and Luks encryption" \
            "4" "Set Filesystem Mountpoints" \
            "5" "Return to Main Menu" 2>${ANSWER} || CANCEL="1"
        NEXTITEM="$(cat ${ANSWER})"
        [[ "${S_MKFSAUTO}" = "1" ]] && DONE=1
        case $(cat ${ANSWER}) in
            "1")
                autoprepare
                [[ "${S_MKFSAUTO}" = "1" ]] && DONE=1
                ;;
            "2")
                partition ;;
            "3")
                create_special ;;
            "4")
                PARTFINISH=""
                ASK_MOUNTPOINTS="1"
                mountpoints ;;
            *)
                DONE=1 ;;
        esac
    done
    if [[ "${CANCEL}" = "1" ]]; then
        NEXTITEM="4"
    else
        NEXTITEM="5"
    fi
}

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
        dialog ${DEFAULT} --backtitle "${TITLE}" --menu "Create Software Raid, LVM2 and Luks encryption" 14 60 5 \
            "1" "Create Software Raid" \
            "2" "Create LVM2" \
            "3" "Create Luks encryption" \
            "4" "Return to Previous Menu" 2>${ANSWER} || CANCEL="1"
        NEXTITEM="$(cat ${ANSWER})"
        case $(cat ${ANSWER}) in
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
        dialog ${DEFAULT} --backtitle "${TITLE}" --menu "Create Software Raid" 12 60 5 \
            "1" "Raid Help" \
            "2" "Reset Software Raid completely" \
            "3" "Create Software Raid" \
            "4" "Create Partitionable Software Raid" \
            "5" "Return to Previous Menu" 2>${ANSWER} || CANCEL="1"
        NEXTITEM="$(cat ${ANSWER})"
        case $(cat ${ANSWER}) in
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
        dialog ${DEFAULT} --backtitle "${TITLE}" --menu "Create physical volume, volume group or logical volume" 13 60 7 \
            "1" "LVM Help" \
            "2" "Reset Logical Volume completely" \
            "3" "Create Physical Volume" \
            "4" "Create Volume Group" \
            "5" "Create Logical Volume" \
            "6" "Return to Previous Menu" 2>${ANSWER} || CANCEL="1"
        NEXTITEM="$(cat ${ANSWER})"
        case $(cat ${ANSWER}) in
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
        dialog ${DEFAULT} --backtitle "${TITLE}" --menu "Create Luks Encryption" 12 60 5 \
            "1" "Luks Help" \
            "2" "Reset Luks Encryption completely" \
            "3" "Create Luks" \
            "4" "Return to Previous Menu" 2>${ANSWER} || CANCEL="1"
        NEXTITEM="$(cat ${ANSWER})"
        case $(cat ${ANSWER}) in
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

auto_hwdetect() {
    HWDETECT=""
    FBPARAMETER=""
    HWPARAMETER=""
    HWDETECTMODULES=""
    HWDETECTHOOKS=""
    HWKVER=""
    DIALOG --yesno "PRECONFIGURATION?\n-----------------\n\nDo you want to use 'hwdetect' for:\n'/etc/mkinitcpio.conf'?\n\nThis ensures consistent ordering of your storage disk / usb controllers.\n\nIt is recommended to say 'YES' here." 18 70 && HWDETECT="yes"
    if [[ "${HWDETECT}" = "yes" ]]; then
        # check on framebuffer modules and kms FBPARAMETER
        grep -q "^radeon" /proc/modules && FBPARAMETER="--ati-kms"
        grep -q "^amdgpu" /proc/modules && FBPARAMETER="--amd-kms"
        grep -q "^i915" /proc/modules && FBPARAMETER="--intel-kms"
        grep -q "^nouveau" /proc/modules && FBPARAMETER="--nvidia-kms"
        # check on nfs,dmraid and keymap HWPARAMETER
        # check on used keymap, if not us keyboard layout
        ! grep -q '^KEYMAP="us"' "${DESTDIR}"/etc/vconsole.conf && HWPARAMETER="${HWPARAMETER} --keymap"
        # check on nfs
        if lsmod | grep -q ^nfs; then
            DIALOG --defaultno --yesno "Setup detected nfs driver...\nDo you need support for booting from nfs shares?" 0 0 && HWPARAMETER="${HWPARAMETER} --nfs"
        fi
        # check on dmraid
        if [[ -e ${DESTDIR}/lib/initcpio/hooks/dmraid ]]; then
            if ! dmraid -r | grep ^no; then
                HWPARAMETER="${HWPARAMETER} --dmraid"
            fi
        fi
        # get kernel version
        offset=$(hexdump -s 526 -n 2 -e '"%0d"' "${DESTDIR}/boot/${VMLINUZ}")
        read HWKVER _ < <(dd if="${DESTDIR}/boot/${VMLINUZ}" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)
        # arrange MODULES for mkinitcpio.conf
        HWDETECTMODULES="$(hwdetect --kernel_directory="${DESTDIR}" --kernel_version="${HWKVER}" --hostcontroller --filesystem ${FBPARAMETER})"
        # arrange HOOKS for mkinitcpio.conf
        HWDETECTHOOKS="$(hwdetect --kernel_directory="${DESTDIR}" --kernel_version="${HWKVER}" --rootdevice="${PART_ROOT}" --hooks-dir="${DESTDIR}"/usr/lib/initcpio/install "${HWPARAMETER}" --hooks)"
        # change mkinitcpio.conf
        [[ -n "${HWDETECTMODULES}" ]] && sed -i -e "s/^MODULES=.*/${HWDETECTMODULES}/g" "${DESTDIR}"/etc/mkinitcpio.conf
        [[ -n "${HWDETECTHOOKS}" ]] && sed -i -e "s/^HOOKS=.*/${HWDETECTHOOKS}/g" "${DESTDIR}"/etc/mkinitcpio.conf
    fi
}

auto_parameters() {
    if [[ ! -f ${DESTDIR}/etc/vconsole.conf ]]; then
        : >"${DESTDIR}"/etc/vconsole.conf
        if [[ -s /tmp/.keymap ]]; then
            DIALOG --infobox "Setting the keymap: $(sed -e 's/\..*//g' /tmp/.keymap) in vconsole.conf ..." 0 0
            echo KEYMAP="$(sed -e 's/\..*//g' /tmp/.keymap)" >> "${DESTDIR}"/etc/vconsole.conf
        fi
        if [[ -s /tmp/.font ]]; then
            DIALOG --infobox "Setting the consolefont: $(sed -e 's/\..*//g'/tmp/.font) in vconsole.conf ..." 0 0
            echo FONT="$(sed -e 's/\..*//g' /tmp/.font)" >> "${DESTDIR}"/etc/vconsole.conf
        fi
    fi
}

auto_luks() {
    # remove root device from crypttab
    if [[ -e /tmp/.crypttab && "$(grep -v '^#' "${DESTDIR}"/etc/crypttab)"  = "" ]]; then
        # add to temp crypttab
        sed -i -e "/^$(basename "${PART_ROOT}") /d" /tmp/.crypttab
        cat /tmp/.crypttab >> "${DESTDIR}"/etc/crypttab
        chmod 600 /tmp/passphrase-* 2>/dev/null
        cp /tmp/passphrase-* "${DESTDIR}"/etc/ 2>/dev/null
    fi
}

auto_timesetting() {
    if [[ -e /etc/localtime && ! -e "${DESTDIR}"/etc/localtime ]]; then
        cp -a /etc/localtime "${DESTDIR}"/etc/localtime
    fi
    if [[ ! -f "${DESTDIR}"/etc/adjtime ]]; then
        echo "0.0 0 0.0" > "${DESTDIR}"/etc/adjtime
        echo "0" >> "${DESTDIR}"/etc/adjtime
        [[ -s /tmp/.hardwareclock ]] && cat /tmp/.hardwareclock >>"${DESTDIR}"/etc/adjtime
    fi
}

auto_pacman_mirror() {
    # /etc/pacman.d/mirrorlist
    # add installer-selected mirror to the top of the mirrorlist
    if [[ "${SYNC_URL}" != "" ]]; then
        awk "BEGIN { printf(\"# Mirror used during installation\nServer = "${SYNC_URL}"\n\n\") } 1 " "${DESTDIR}"/etc/pacman.d/mirrorlist > /tmp/inst-mirrorlist
        mv /tmp/inst-mirrorlist "${DESTDIR}/etc/pacman.d/mirrorlist"
    fi
}

auto_system_files () {
    if [[ ! -f ${DESTDIR}/etc/hostname ]]; then
        echo "myhostname" > "${DESTDIR}"/etc/hostname
    fi
    if [[ ! -f ${DESTDIR}/etc/locale.conf ]]; then
        echo "LANG=en_US.UTF-8" > "${DESTDIR}"/etc/locale.conf
        echo "LC_COLLATE=C" >> "${DESTDIR}"/etc/locale.conf
    fi
}

configure_system() {
    destdir_mounts || return 1
    ## PREPROCESSING ##
    # only done on first invocation of configure_system and redone on canceled configure system
    if [[ ${S_CONFIG} -eq 0 ]]; then
        auto_pacman_mirror
        auto_network
        auto_parameters
        auto_system_files
        auto_hwdetect
    fi
    ## END PREPROCESS ##
    geteditor || return 1
    FILE=""

    # main menu loop
    while true; do
        S_CONFIG=0
        if [[ -n "${FILE}" ]]; then
            DEFAULT="--default-item ${FILE}"
        else
            DEFAULT=""
        fi
        #shellcheck disable=SC2086
        DIALOG ${DEFAULT} --menu "Configuration" 21 80 16 \
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
            "Return"                        "Return to Main Menu" 2>${ANSWER} || break
        FILE="$(cat ${ANSWER})"
        if [[ "${FILE}" = "Return" || -z "${FILE}" ]]; then       # exit
            S_CONFIG=1
            break           
        elif [[ "${FILE}" = "/etc/mkinitcpio.conf" ]]; then    # non-file
            DIALOG --msgbox "The mkinitcpio.conf file controls which modules will be placed into the initramfs for your system's kernel.\n\n- Non US keymap users should add 'keymap' to HOOKS= array\n- If you install under VMWARE add 'BusLogic' to MODULES= array\n- raid, lvm2, encrypt are not enabled by default\n- 2 or more disk controllers, please specify the correct module\n  loading order in MODULES= array \n\nMost of you will not need to change anything in this file." 18 70
            HOOK_ERROR=""
            ${EDITOR} "${DESTDIR}""${FILE}"
            for i in $(grep ^HOOKS "${DESTDIR}"/etc/mkinitcpio.conf | sed -e 's/"//g' -e 's/HOOKS=\(//g' -e 's/\)//g'); do
                [[ -e ${DESTDIR}/usr/lib/initcpio/install/${i} ]] || HOOK_ERROR=1
            done
            if [[ "${HOOK_ERROR}" = "1" ]]; then
                DIALOG --msgbox "ERROR: Detected error in 'HOOKS=' line, please correct HOOKS= in /etc/mkinitcpio.conf!" 18 70
            fi
        elif [[ "${FILE}" = "/etc/locale.gen" ]]; then          # non-file
            # enable glibc locales from locale.conf
                for i in $(grep "^LANG" "${DESTDIR}"/etc/locale.conf | sed -e 's/.*=//g' -e's/\..*//g'); do
                    sed -i -e "s/^#${i}/${i}/g" "${DESTDIR}"/etc/locale.gen
                done
            ${EDITOR} "${DESTDIR}""${FILE}"
        elif [[ "${FILE}" = "Root-Password" ]]; then            # non-file
            PASSWORD=""
            while [[ "${PASSWORD}" = "" ]]; do
                DIALOG --insecure --passwordbox "Enter root password:" 0 0 2>${ANSWER} || return 1
                PASS=$(cat ${ANSWER})
                DIALOG --insecure --passwordbox "Retype root password:" 0 0 2>${ANSWER} || return 1
                PASS2=$(cat ${ANSWER})
                if [[ "${PASS}" = "${PASS2}" ]]; then
                    PASSWORD=${PASS}
                    echo "${PASSWORD}" > /tmp/.password
                    echo "${PASSWORD}" >> /tmp/.password
                    PASSWORD=/tmp/.password
                else
                    DIALOG --msgbox "Password didn't match, please enter again." 0 0
                fi
            done
            chroot "${DESTDIR}" passwd root < /tmp/.password
            rm /tmp/.password
        else                                                #regular file
            ${EDITOR} "${DESTDIR}""${FILE}"
        fi
    done
    if [[ ${S_CONFIG} -eq 1 ]]; then
        # only done on normal exit of configure menu
        ## POSTPROCESSING ##
        # adjust time
        auto_timesetting
        # /etc/initcpio.conf
        run_mkinitcpio
        # /etc/locale.gen
        # enable at least en_US.UTF8 if nothing was changed, else weird things happen on reboot!
        ! grep -q "^[a-z]" "${DESTDIR}"/etc/locale.gen && sed -i -e 's:^#en_US.UTF-8:en_US.UTF-8:g' "${DESTDIR}"/etc/locale.gen
        chroot "${DESTDIR}" locale-gen >/dev/null 2>&1
        ## END POSTPROCESSING ##
        NEXTITEM="7"
    fi
}

install_bootloader_uefi() {
    
    do_uefi_setup_env_vars
    
    if [[ "${_EFI_MIXED}" == "1" ]]; then
        _EFISTUB_MENU_LABEL=""
        _EFISTUB_MENU_TEXT=""
    else
        _EFISTUB_MENU_LABEL="EFISTUB"
        _EFISTUB_MENU_TEXT="EFISTUB for ${_UEFI_ARCH} UEFI"
    fi
    if [[ "${_DETECTED_UEFI_SECURE_BOOT}" == "1" ]]; then
        do_grub_uefi
    else
        if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
        DIALOG --menu "Which ${_UEFI_ARCH} UEFI bootloader would you like to use?" 12 55 5 \
            "${_EFISTUB_MENU_LABEL}" "${_EFISTUB_MENU_TEXT}" \
            "GRUB_UEFI" "GRUB(2) for ${_UEFI_ARCH} UEFI" 2>${ANSWER} || CANCEL=1
        else    
            DIALOG --menu "Which ${_UEFI_ARCH} UEFI bootloader would you like to use?" 12 55 5 \
                "${_EFISTUB_MENU_LABEL}" "${_EFISTUB_MENU_TEXT}" \
                "GRUB_UEFI" "GRUB(2) for ${_UEFI_ARCH} UEFI" 2>${ANSWER} || CANCEL=1
        fi
        case $(cat ${ANSWER}) in
            "EFISTUB") do_efistub_uefi ;;
            "GRUB_UEFI") do_grub_uefi ;;
        esac
    fi
    
}

install_bootloader_bios() {
    
    DIALOG --menu "Which BIOS bootloader would you like to use?" 11 50 4 \
        "GRUB_BIOS" "GRUB(2) BIOS" 2>${ANSWER} || CANCEL=1
    case $(cat ${ANSWER}) in
        "GRUB_BIOS") do_grub_bios ;;
    esac
    
}

install_bootloader() {
    destdir_mounts || return 1
    if [[ "${NAME_SCHEME_PARAMETER_RUN}" == "" ]]; then
        set_device_name_scheme || return 1
    fi
    if [[ "${S_SRC}" = "0" ]]; then
        select_source || return 1
    fi
    prepare_pacman
    CANCEL=""
    detect_uefi_boot
    _ANOTHER="1"
    NEXTITEM="7"
    if [[ "${_DETECTED_UEFI_BOOT}" == "1" ]]; then
        do_uefi_setup_env_vars
         _ANOTHER="0"
        if [[ "${_DETECTED_UEFI_SECURE_BOOT}" ==  "1" ]]; then
            DIALOG --yesno "Setup has detected that you are using Secure Boot ...\nDo you like to install SHIM and GRUB ${_UEFI_ARCH} UEFI bootloader?" 0 0 || CANCEL="1"
            if [[ "${CANCEL}" == "" ]]; then
                install_bootloader_uefi
                NEXTITEM="8"
            else
                NEXTITEM="7"
            fi
        else
            DIALOG --yesno "Setup has detected that you are using ${_UEFI_ARCH} UEFI ...\nDo you like to install a ${_UEFI_ARCH} UEFI bootloader?" 0 0 && install_bootloader_uefi
            DIALOG --defaultno --yesno "Do you want to install another bootloader?" 0 0 && _ANOTHER="1"
            NEXTITEM="8"
        fi
    fi
    while [[ "${_ANOTHER}" == "1" ]]; do
        install_bootloader_menu
        _ANOTHER="0"
        DIALOG --defaultno --yesno "Do you want to install another bootloader?" 0 0 && _ANOTHER="1"
    done
}

install_bootloader_menu() {
    if [[ "${RUNNING_ARCH}" == "aarch64" ]]; then
            ANSWER="UEFI"
    else
        DIALOG --menu "What is your boot system type?" 10 40 2 \
            "UEFI" "UEFI" \
            "BIOS" "BIOS" 2>${ANSWER} || CANCEL=1 
        case $(cat ${ANSWER}) in
            "UEFI") install_bootloader_uefi ;;
            "BIOS") install_bootloader_bios ;;
        esac
    fi
    
    if [[ "${CANCEL}" = "1" ]]; then
        NEXTITEM="7"
    else
        NEXTITEM="8"
    fi
}

mainmenu() {
    if [[ -n "${NEXTITEM}" ]]; then
        DEFAULT="--default-item ${NEXTITEM}"
    else
        DEFAULT=""
    fi
    #shellcheck disable=SC2086
    dialog ${DEFAULT} --backtitle "${TITLE}" --title " MAIN MENU " \
    --menu "Use the UP and DOWN arrows to navigate menus.\nUse TAB to switch between buttons and ENTER to select." 18 58 14 \
    "0" "Set Keyboard And Console Font" \
    "1" "Set up Network" \
    "2" "Select Source" \
    "3" "Set Time And Date" \
    "4" "Prepare Storage Drive" \
    "5" "Install Packages" \
    "6" "Configure System" \
    "7" "Install Bootloader" \
    "8" "Exit Install" 2>${ANSWER}
    NEXTITEM="$(cat ${ANSWER})"
    case $(cat ${ANSWER}) in
        "0")
            set_keyboard ;;
        "1")
            donetwork ;;
        "2")
            select_source
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
    echo "HINT:"
    echo "setup already runs on a different console!"
    echo "Please remove /tmp/.setup-running first to launch setup!"
    exit 1
fi
: >/tmp/.setup-running
: >/tmp/.setup

DIALOG --msgbox "Welcome to the Arch Linux Installation program.\n\nThe install process is fairly straightforward, and you should run through the options in the order they are presented.\n\nIf you are unfamiliar with partitioning/making filesystems, you may want to consult some documentation before continuing.\n\nYou can view all output from commands by viewing your VC7 console (ALT-F7). ALT-F1 will bring you back here." 14 65

while true; do
    mainmenu
done

clear
exit 0

# vim: set ts=4 sw=4 et:
