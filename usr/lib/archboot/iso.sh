#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_CONFIG_DIR="/etc/archboot"
_ISODIR="$(mktemp -d ISODIR.XXX)"

_usage () {
    echo "CREATE ${_ARCH} USB/CD IMAGES"
    echo "-----------------------------"
    echo "This will create an archboot iso image."
    echo ""
    echo " -g                  Starting generation of image."
    echo " -c=CONFIG           Which CONFIG should be used."
    echo "                     ${_CONFIG_DIR} locates the configs"
    echo "                     default=${_ARCH}.conf"
    echo " -i=IMAGENAME        Your IMAGENAME."
    echo " -s                  Save init ramdisk to $(pwd)"
    echo " -h                  This message."
    echo ""
    echo "usage: ${_BASENAME} <options>"
    exit 0
}

_parameters() {
    while [ $# -gt 0 ]; do
        case ${1} in
            -g|--g) export _GENERATE="1" ;;
            -s|--s) _SAVE_INIT="1" ;;
            -c=*|--c=*) _CONFIG="$(echo "${1}" | awk -F= '{print $2;}')" ;;
            -i=*|--i=*) _IMAGENAME="$(echo "${1}" | awk -F= '{print $2;}')" ;;
            -h|--h|?) _usage ;;
            *) _usage ;;
        esac
        shift
    done
}

_config() {
    # set defaults, if nothing given
    [[ -z "${_CONFIG}" ]] && _CONFIG="${_ARCH}.conf"
    _CONFIG="${_CONFIG_DIR}/${_CONFIG}"
    #shellcheck disable=SC1090
    . "${_CONFIG}"
    #shellcheck disable=SC2116,2086
    _KERNEL="$(echo ${_KERNEL})"
    #shellcheck disable=SC2154
    [[ -z "${_IMAGENAME}" ]] && _IMAGENAME="archboot-$(date +%Y.%m.%d-%H.%M)-$(_kver "${_KERNEL}")-${_ARCH}"
}

### EFI status of RISCV64:
#----------------------------------------------------
# EFI is not yet working for RISCV64!
# - grub does not allow linux command in memdisk mode
# - grub itself cannot initialize efi system partion
# - refind bails out with error
# - systemd-boot does not support loading of initrd
# - unified EFI is not possible because of this:
#   https://sourceware.org/bugzilla/show_bug.cgi?id=29009
# - only left option is extlinux support in u-boot loader
_prepare_kernel_initrd_files() {
    mkdir -p "${_ISODIR}"/EFI/{BOOT,TOOLS}
    mkdir -p "${_ISODIR}/boot"
    # needed to hash the kernel for secureboot enabled systems
    echo "Preparing kernel..."
    if [[ "${_ARCH}" == "x86_64" || "${_ARCH}" == "riscv64" ]]; then
        install -m644 "${_KERNEL}" "${_ISODIR}/boot/vmlinuz-${_ARCH}"
    fi
    if [[ "${_ARCH}" == "aarch64" ]]; then
        install -m644 "${_KERNEL}" "${_ISODIR}/boot/Image-${_ARCH}.gz"
    fi
    if [[ -f "./init-${_ARCH}.img" ]]; then
        echo "Using existing init-${_ARCH}.img..."
        cp "./init-${_ARCH}.img" "${_ISODIR}/boot/"
    else
        echo "Running archboot-cpio.sh for init-${_ARCH}.img..."
        archboot-cpio.sh -c "/etc/archboot/${_ARCH}-init.conf" -k "${_KERNEL}" \
                         -g "${_ISODIR}/boot/init-${_ARCH}.img" || exit 1
        # save init ramdisk for further images
        if [[ -n "${_SAVE_INIT}" ]]; then
            cp "${_ISODIR}/boot/init-${_ARCH}.img" ./
        fi
    fi
    _INITRD="initrd-${_ARCH}.img"
    echo "${_CONFIG}" | grep -qw local && _INITRD="initrd-local-${_ARCH}.img"
    echo "${_CONFIG}" | grep -qw latest && _INITRD="initrd-latest-${_ARCH}.img"
    if [[ -f "${_INITRD}" ]]; then
        echo "Using existing ${_INITRD}..."
        mv "./${_INITRD}" "${_ISODIR}/boot/initrd-${_ARCH}.img"
    fi
    if ! [[ -f "${_ISODIR}/boot/initrd-${_ARCH}.img" ]]; then
        echo "Running archboot-cpio.sh for initrd-${_ARCH}.img..."
        #shellcheck disable=SC2154
        archboot-cpio.sh -c "${_CONFIG}" -k "${_KERNEL}" \
                         -g "${_ISODIR}/boot/initrd-${_ARCH}.img" || exit 1
    fi
    # delete cachedir on archboot environment
    if grep -qw 'archboot' /etc/hostname; then
        if [[ -d "${_CACHEDIR}" ]]; then
            echo "Removing ${_CACHEDIR}..."
            rm -rf "${_CACHEDIR}"
        fi
    fi
}

_prepare_ucode() {
    # only x86_64
    if [[ "${_ARCH}" == "x86_64" ]]; then
        echo "Preparing intel-ucode..."
        cp /boot/intel-ucode.img "${_ISODIR}/boot/"
        mkdir -p "${_ISODIR}"/licenses/intel-ucode
        cp /usr/share/licenses/intel-ucode/LICENSE "${_ISODIR}/licenses/intel-ucode"
    fi
    # both x86_64 and aarch64
    if ! [[ "${_ARCH}" == "riscv64" ]]; then
        echo "Preparing amd-ucode..."
        cp /boot/amd-ucode.img "${_ISODIR}/boot/"
        mkdir -p "${_ISODIR}"/licenses/amd-ucode
        cp /usr/share/licenses/amd-ucode/LICENSE.amd-ucode "${_ISODIR}/licenses/amd-ucode"
    fi
}

_prepare_fedora_shim_bootloaders_x86_64 () {
    echo "Preparing fedora shim..."
    # Details on shim https://www.rodsbooks.com/efi-bootloaders/secureboot.html#initial_shim
    # add shim x64 signed files from fedora
    cp "/usr/share/archboot/bootloader/mmx64.efi" "${_ISODIR}/EFI/BOOT/MMX64.EFI"
    cp "/usr/share/archboot/bootloader/BOOTX64.efi" "${_ISODIR}/EFI/BOOT/BOOTX64.EFI"
    cp "/usr/share/archboot/bootloader/mmia32.efi" "${_ISODIR}/EFI/BOOT/MMIA32.EFI"
    cp "/usr/share/archboot/bootloader/BOOTIA32.efi" "${_ISODIR}/EFI/BOOT/BOOTIA32.EFI"
}

_prepare_fedora_shim_bootloaders_aarch64 () {
    echo "Preparing fedora shim..."
    # Details on shim https://www.rodsbooks.com/efi-bootloaders/secureboot.html#initial_shim
    # add shim aa64 signed files from fedora
    cp "/usr/share/archboot/bootloader/mmaa64.efi" "${_ISODIR}/EFI/BOOT/MMAA64.EFI"
    cp "/usr/share/archboot/bootloader/BOOTAA64.efi" "${_ISODIR}/EFI/BOOT/BOOTAA64.EFI"
}

_prepare_uefi_shell_tianocore() {
    echo "Preparing UEFI shell..."
    ## Installing Tianocore UDK/EDK2 UEFI X64 "Full Shell"
    cp /usr/share/edk2-shell/x64/Shell_Full.efi "${_ISODIR}/EFI/TOOLS/SHELLX64.EFI"
    ## Installing Tianocore UDK/EDK2 UEFI IA32 "Full Shell"
    cp /usr/share/edk2-shell/ia32/Shell_Full.efi "${_ISODIR}/EFI/TOOLS/SHELLIA32.EFI"
}

# build grubXXX with all modules: http://bugs.archlinux.org/task/71382
_prepare_uefi_X64() {
    echo "Preparing X64 grub..."
    cp /usr/share/archboot/bootloader/grubx64.efi "${_ISODIR}/EFI/BOOT/GRUBX64.EFI"
}

_prepare_uefi_IA32() {
    echo "Preparing IA32 grub..."
    cp /usr/share/archboot/bootloader/grubia32.efi "${_ISODIR}/EFI/BOOT/GRUBIA32.EFI"
}

# build grubXXX with all modules: http://bugs.archlinux.org/task/71382
_prepare_uefi_AA64() {
    echo "Preparing AA64 grub..."
    cp /usr/share/archboot/bootloader/grubaa64.efi "${_ISODIR}/EFI/BOOT/GRUBAA64.EFI"
}

_prepare_memtest() {
    echo "Preparing memtest86+..."
    cp /boot/memtest86+/memtest.bin "${_ISODIR}/boot/"
    cp /boot/memtest86+/memtest.efi "${_ISODIR}/EFI/TOOLS/MEMTEST.EFI"
}

_prepare_background() {
    echo "Preparing grub background..."
    [[ -d "${_ISODIR}/boot/grub" ]] || mkdir -p "${_ISODIR}/boot/grub"
    cp ${_GRUB_BACKGROUND} "${_ISODIR}/boot/grub/archboot-background.png"
}

_reproducibility() {
    # Reproducibility: set all timestamps to 0
    # from /usr/bin/mkinitcpio
    find "${_ISODIR}" -mindepth 1 -execdir touch -hcd "@0" "{}" +
}

_prepare_uefi_image() {
    echo "Preparing UEFI image..."
    ## get size of boot files
    BOOTSIZE=$(du -bc "${_ISODIR}"/EFI "${_ISODIR}"/boot | grep total | cut -f1)
    IMGSZ=$((BOOTSIZE/1024 + 2048)) # image size in KB
    VFAT_IMAGE="${_ISODIR}/efi.img"
    ## Creating efi.img
    mkfs.vfat -n ARCHBOOT --invariant -C "${VFAT_IMAGE}" "${IMGSZ}" >"${_NO_LOG}"
    ## Copying all files to UEFI vfat image
    mcopy -m -i "${VFAT_IMAGE}" -s "${_ISODIR}"/EFI "${_ISODIR}"/boot ::/
    # leave EFI/ and /boot/kernel for virtualbox and other restricted VM emulators :(
    if [[ "${_ARCH}" == "x86_64" || "${_ARCH}" == "riscv64" ]]; then
        find "${_ISODIR}"/boot/* ! -name "vmlinuz-${_ARCH}" -delete
    fi
    if [[ "${_ARCH}" == "aarch64" ]]; then
        find "${_ISODIR}"/boot/* ! -name "Image-${_ARCH}.gz" -delete
    fi
}

_prepare_extlinux_conf() {
    mkdir -p "${_ISODIR}"/boot/extlinux
    _TITLE="Arch Linux RISC-V 64"
    echo "Preparing extlinux.conf..."
    cat << EOF >> "${_ISODIR}/boot/extlinux/extlinux.conf"
menu title Welcome to Archboot - ${_TITLE}
timeout 100
default linux
label linux
    menu label Boot System (automatic boot in 10 seconds...)
    kernel /boot/vmlinuz-${_ARCH}
    initrd /boot/init-${_ARCH}.img
    append console=ttyS0,115200 console=tty0 audit=0 systemd.show_status=auto
EOF
}

# https://github.com/CoelacanthusHex/archriscv-scriptlet/blob/master/mkimg
# https://checkmk.com/linux-knowledge/mounting-partition-loop-device
# calculate mountpoint offset: sector*start
# 512*2048=1048576 == 1M
# https://reproducible-builds.org/docs/system-images/
# mkfs.ext4 does not allow reproducibility
_uboot() {
    echo "Generating ${_ARCH} U-Boot image..."
    ## get size of boot files
    BOOTSIZE=$(du -bc "${_ISODIR}"/boot | grep total | cut -f1)
    IMGSZ=$((BOOTSIZE/1024 + 2048)) # image size in KB
    VFAT_IMAGE="${_ISODIR}/extlinux.img"
    dd if=/dev/zero of="${VFAT_IMAGE}" bs="${IMGSZ}" count=1024 status=none
    sfdisk "${VFAT_IMAGE}" &>"${_NO_LOG}" <<EOF
label: dos
label-id: 0x12345678
device: "${VFAT_IMAGE}"
unit: sectors
"${VFAT_IMAGE}"1 : start=        2048, type=83, bootable
EOF
    mkfs.vfat -n "ARCHBOOT" --offset=2048 --invariant "${VFAT_IMAGE}" >"${_NO_LOG}"
    ## Copying all files to UEFI vfat image
    mcopy -m -i "${VFAT_IMAGE}"@@1048576  -s "${_ISODIR}"/boot ::/
    mv "${VFAT_IMAGE}" "${_IMAGENAME}.img"
    echo "Removing extlinux config file..."
    rm -r "${_ISODIR}"/boot/extlinux
}

_grub_mkrescue() {
    ## Generating the BIOS+ISOHYBRID+UEFI CD image
    #set date for reproducibility
    # --set_all_file_dates for all files
    # --modification-date= for boot.catalog
    # --volid set ISO label ARCHBOOT
    # -- -rm_r /efi .disk/ /boot/grub/{roms,locale} ${_RESCUE_REMOVE} for removing reproducibility breakers
    echo "Generating ${_ARCH} hybrid ISO..."
    [[ "${_ARCH}" == "x86_64" ]] && _RESCUE_REMOVE="mach_kernel /System /boot/grub/i386-efi /boot/grub/x86_64-efi"
    [[ "${_ARCH}" == "aarch64" ]] && _RESCUE_REMOVE="/boot/grub/arm64-efi"
    #shellcheck disable=SC2086
    grub-mkrescue --set_all_file_dates 'Jan 1 00:00:00 UTC 1970' \
                  --modification-date=1970010100000000 --compress=xz --fonts="ter-u16n" \
                  --locales="" --themes="" -o "${_IMAGENAME}.iso" "${_ISODIR}"/ \
                  "boot/grub/archboot-main-grub.cfg=${_GRUB_CONFIG}" \
                  "boot/grub/grub.cfg=/usr/share/archboot/grub/archboot-iso-grub.cfg" \
                  -volid "ARCHBOOT" -- -rm_r /boot/grub/{roms,locale} /efi .disk/ \
                  ${_RESCUE_REMOVE} &> "${_IMAGENAME}.log"
}

_unify_gpt_partitions() {
    # GPT partition layout:
    # 1: Gap0 | 2: EFI System Partition | 3: HFS/HFS+ | 4: GAP1
    echo "Creating reproducible GUID, UUIDs, hide partitions and disable automount on ISO GPT..."
    sfdisk -q --disk-id "${_IMAGENAME}.iso" "00000000-0000-0000-0000-000000000000"
    # --> already set 0: system partition (does not allow delete on Windows)
    # --> already set 60: readonly
    # --> 62: hide all partitions, Windows cannot access any files on this ISO
    #         Windows will now only error on 1 drive and not on all partitions
    # --> 63: disable freedesktop/systemd automount by default on this ISO
    for i in 1 2 3 4; do
       sfdisk -q --part-attrs "${_IMAGENAME}.iso" "${i}" "RequiredPartition,60,62,63"
       sfdisk -q --part-uuid "${_IMAGENAME}.iso" "${i}" "${i}0000000-0000-0000-0000-000000000000"
    done
}

_create_cksum() {
    ## create b2sums.txt
    echo "Generating b2sum..."
    [[ -f  "b2sums.txt" ]] && rm "b2sums.txt"
    [[ "$(echo ./*.iso)" == "./*.iso" ]] || cksum -a blake2b ./*.iso > "b2sums.txt"
    [[ "$(echo ./*.img)" == "./*.img" ]] || cksum -a blake2b ./*.img > "b2sums.txt"
}

_cleanup_iso() {
    # cleanup
    echo "Removing ${_ISODIR}..."
    [[ -d "${_ISODIR}" ]] && rm -r "${_ISODIR}"
}
# vim: set ft=sh ts=4 sw=4 et:
