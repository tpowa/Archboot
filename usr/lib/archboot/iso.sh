#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_PRESET_DIR="/etc/archboot/presets"
_ISODIR="$(mktemp -d ISODIR.XXX)"

_usage () {
    echo "${_BASENAME}: usage"
    echo "CREATE ${_RUNNING_ARCH} USB/CD IMAGES"
    echo "-----------------------------"
    echo "PARAMETERS:"
    echo "  -g                  Start generation of image."
    echo "  -p=PRESET           Which preset should be used."
    echo "                      /etc/archboot/presets locates the presets"
    echo "                      default=${_RUNNING_ARCH}"
    echo "  -i=IMAGENAME        Your IMAGENAME."
    echo "  -h                  This message."
    exit 0
}

_parameters() {
    while [ $# -gt 0 ]; do
        case ${1} in
            -g|--g) export _GENERATE="1" ;;
            -p=*|--p=*) _PRESET="$(echo "${1}" | awk -F= '{print $2;}')" ;;
            -i=*|--i=*) _IMAGENAME="$(echo "${1}" | awk -F= '{print $2;}')" ;;
            -h|--h|?) _usage ;;
            *) _usage ;;
        esac
        shift
    done
}

_config() {
    # set defaults, if nothing given
    [[ -z "${_PRESET}" ]] && _PRESET="${_RUNNING_ARCH}"
    _PRESET="${_PRESET_DIR}/${_PRESET}"
    [[ -z "${_IMAGENAME}" ]] && _IMAGENAME="archboot-archlinux-$(date +%Y.%m.%d-%H.%M)-${_RUNNING_ARCH}"
}

_prepare_kernel_initramfs_files() {
    echo "Prepare kernel and initramfs ..."
    #shellcheck disable=SC1090
    source "${_PRESET}"
    mkdir -p "${_ISODIR}"/EFI/{BOOT,TOOLS}
    mkdir -p "${_ISODIR}/boot"

    #shellcheck disable=SC2154
    mkinitcpio -c "${MKINITCPIO_CONFIG}" -k "${ALL_kver}" -g "${_ISODIR}/boot/initramfs-${_RUNNING_ARCH}-pre.img" || exit 1
    # delete cachedir on archboot environment
    [[ "$(cat /etc/hostname)" == "archboot" ]] && rm -rf /var/cache/pacman/pkg
    # grub on x86_64 reports too big if near 1GB
     split -b 950M -d --additional-suffix=.img -a 1 "${_ISODIR}/boot/initramfs-${_RUNNING_ARCH}-pre.img" \
     "${_ISODIR}/boot/initramfs-${_RUNNING_ARCH}-"
    rm "${_ISODIR}/boot/initramfs-${_RUNNING_ARCH}-pre.img"
    if [[ "$(find "${_ISODIR}/boot" -name '*.img' | wc -l)" -lt "2" ]]; then
        mv "${_ISODIR}/boot/initramfs-${_RUNNING_ARCH}-0.img" "${_ISODIR}/boot/initramfs-${_RUNNING_ARCH}.img"
    fi
    install -m644 "${ALL_kver}" "${_ISODIR}/boot/vmlinuz-${_RUNNING_ARCH}"
    # needed to hash the kernel for secureboot enabled systems
    # all uppercase to avoid issues with firmware and hashing eg. DELL firmware is case sensitive!
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        install -m644 "${ALL_kver}" "${_ISODIR}/EFI/BOOT/VMLINUZ_AA64"
    fi
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        install -m644 "${ALL_kver}" "${_ISODIR}/EFI/BOOT/VMLINUZ_X64"
    fi
    # only aarch64
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        echo "Prepare dtbs ..."
        cp -r /boot/dtbs "${_ISODIR}/boot/"
    fi
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
_prepare_kernel_initramfs_files_RISCV64() {
    echo "Prepare RISCV64 u-boot ..."
    #shellcheck disable=SC1090
    source "${_PRESET}"
    mkdir -p "${_ISODIR}"/boot
    install -m644 "${ALL_kver}" "${_ISODIR}/boot/vmlinuz-${_RUNNING_ARCH}"
    mkinitcpio -c "${MKINITCPIO_CONFIG}" -k "${ALL_kver}" -g "${_ISODIR}/boot/initramfs-${_RUNNING_ARCH}.img" || exit 1
}

_prepare_ucode() {
    # only x86_64
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then
        echo "Prepare intel-ucode ..."
        cp /boot/intel-ucode.img "${_ISODIR}/boot/"
        mkdir -p "${_ISODIR}"/licenses/intel-ucode
        cp /usr/share/licenses/intel-ucode/LICENSE "${_ISODIR}/licenses/intel-ucode"
    fi
    # both x86_64 and aarch64
    if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
        echo "Prepare amd-ucode ..."
        cp /boot/amd-ucode.img "${_ISODIR}/boot/"
        mkdir -p "${_ISODIR}"/licenses/amd-ucode
        cp /usr/share/licenses/amd-ucode/LICENSE.amd-ucode "${_ISODIR}/licenses/amd-ucode"
    fi
}

_prepare_fedora_shim_bootloaders_x86_64 () {
    echo "Prepare fedora shim ..."
    # Details on shim https://www.rodsbooks.com/efi-bootloaders/secureboot.html#initial_shim
    # add shim x64 signed files from fedora
    cp "/usr/share/archboot/bootloader/mmx64.efi" "${_ISODIR}/EFI/BOOT/MMX64.EFI"
    cp "/usr/share/archboot/bootloader/BOOTX64.efi" "${_ISODIR}/EFI/BOOT/BOOTX64.EFI"
    cp "/usr/share/archboot/bootloader/mmia32.efi" "${_ISODIR}/EFI/BOOT/MMIA32.EFI"
    cp "/usr/share/archboot/bootloader/BOOTIA32.efi" "${_ISODIR}/EFI/BOOT/BOOTIA32.EFI"
}

_prepare_fedora_shim_bootloaders_aarch64 () {
    echo "Prepare fedora shim ..."
    # Details on shim https://www.rodsbooks.com/efi-bootloaders/secureboot.html#initial_shim
    # add shim aa64 signed files from fedora
    cp "/usr/share/archboot/bootloader/mmaa64.efi" "${_ISODIR}/EFI/BOOT/MMAA64.EFI"
    cp "/usr/share/archboot/bootloader/BOOTAA64.efi" "${_ISODIR}/EFI/BOOT/BOOTAA64.EFI"
}

_prepare_efitools_uefi () {
    echo "Prepare efitools ..."
    cp  "/usr/share/efitools/efi/HashTool.efi" "${_ISODIR}/EFI/TOOLS/HASHTOOL.EFI"
    cp  "/usr/share/efitools/efi/KeyTool.efi" "${_ISODIR}/EFI/TOOLS/KEYTOOL.EFI"
}

_prepare_uefi_shell_tianocore() {
    echo "Prepare uefi shell ..."
    ## Install Tianocore UDK/EDK2 EdkShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. <2.3 systems
    cp /usr/share/edk2-shell/x64/Shell_Full.efi "${_ISODIR}/EFI/TOOLS/SHELLX64.EFI"
    ## Install Tianocore UDK/EDK2 ShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. >=2.3 systems
    cp /usr/share/edk2-shell/ia32/Shell_Full.efi "${_ISODIR}/EFI/TOOLS/SHELLIA32.EFI"
}

# build grubXXX with all modules: http://bugs.archlinux.org/task/71382
_prepare_uefi_X64() {
    echo "Prepare X64 Grub ..."
    cp /usr/share/archboot/bootloader/grubx64.efi "${_ISODIR}/EFI/BOOT/GRUBX64.EFI"
}

_prepare_uefi_IA32() {
    echo "Prepare IA32 Grub ..."
    cp /usr/share/archboot/bootloader/grubia32.efi "${_ISODIR}/EFI/BOOT/GRUBIA32.EFI"
}

# build grubXXX with all modules: http://bugs.archlinux.org/task/71382
_prepare_uefi_AA64() {
    echo "Prepare AA64 Grub ..."
    cp /usr/share/archboot/bootloader/grubaa64.efi "${_ISODIR}/EFI/BOOT/GRUBAA64.EFI"
}

_prepare_memtest() {
    echo "Prepare memtest86+ ..."
    cp /boot/memtest86+/memtest.bin "${_ISODIR}/boot/"
    cp /boot/memtest86+/memtest.efi "${_ISODIR}/EFI/TOOLS/MEMTEST.EFI"
}

_prepare_background() {
    echo "Prepare Grub background ..."
    [[ -d "${_ISODIR}/boot/grub" ]] || mkdir -p "${_ISODIR}/boot/grub"
    cp ${_GRUB_BACKGROUND} "${_ISODIR}/boot/grub/archboot-background.png"
}

_reproducibility() {
    # Reproducibility: set all timestamps to 0
    # from /usr/bin/mkinitcpio
    find "${_ISODIR}" -mindepth 1 -execdir touch -hcd "@0" "{}" +
}

_prepare_uefi_image() {
    echo "Prepare UEFI image ..."
    ## get size of boot files
    BOOTSIZE=$(du -bc "${_ISODIR}"/EFI | grep total | cut -f1)
    IMGSZ=$(((BOOTSIZE*102)/100/1024 + 1)) # image size in sectors
    VFAT_IMAGE="${_ISODIR}/efi.img"
    ## Create efi.img
    mkfs.vfat --invariant -C "${VFAT_IMAGE}" "${IMGSZ}" >/dev/null
    ## Copy all files to UEFI vfat image
    mcopy -m -i "${VFAT_IMAGE}" -s "${_ISODIR}"/EFI ::/
}

_prepare_extlinux_conf() {
    mkdir -p "${_ISODIR}"/boot/extlinux
    if [[ ${_RUNNING_ARCH} == "aarch64" ]]; then
        _TITLE="Arch Linux ARM 64"
        _SMP="nr_cpus=1"
    fi
    [[ ${_RUNNING_ARCH} == "riscv64" ]] && _TITLE="Arch Linux RISC-V 64"
    echo "Prepare extlinux.conf ..."
    cat << EOF >> "${_ISODIR}/boot/extlinux/extlinux.conf"
menu title Welcome to Archboot - ${_TITLE}
timeout 100
default linux
label linux
    menu label Boot System (automatic boot in 10 seconds ...)
    kernel /boot/vmlinuz-${_RUNNING_ARCH}
    initrd /boot/initramfs-${_RUNNING_ARCH}.img
    append rootfstype=ramfs console=ttyS0,115200 console=tty0 audit=0 ${_SMP}
EOF
}

# https://github.com/CoelacanthusHex/archriscv-scriptlet/blob/master/mkimg
# https://checkmk.com/linux-knowledge/mounting-partition-loop-device
# calculate mountpoint offset: sector*start
# 512*2048=1048576 == 1M
# https://reproducible-builds.org/docs/system-images/
# mkfs.ext4 does not allow reproducibility
_uboot() {
    echo "Generating ${_RUNNING_ARCH} U-Boot image ..."
    ## get size of boot files
    BOOTSIZE=$(du -bc "${_ISODIR}"/boot | grep total | cut -f1)
    IMGSZ=$(((BOOTSIZE*102)/100/1024)) # image size in sectors
    VFAT_IMAGE="${_ISODIR}/extlinux.img"
    ## Create efi.img
    dd if=/dev/zero of="${VFAT_IMAGE}" bs="${IMGSZ}" count=1024 status=none
    sfdisk "${VFAT_IMAGE}" >/dev/null 2>&1 <<EOF
label: dos
label-id: 0x12345678
device: "${VFAT_IMAGE}"
unit: sectors
"${VFAT_IMAGE}"1 : start=        2048, type=83, bootable
EOF
    mkfs.vfat --offset=2048 --invariant "${VFAT_IMAGE}" >/dev/null
    ## Copy all files to UEFI vfat image
    mcopy -m -i "${VFAT_IMAGE}"@@1048576  -s "${_ISODIR}"/boot ::/
    mv "${VFAT_IMAGE}" "${_IMAGENAME}.img"
    echo "Remove extlinux config file ..."
    rm -r "${_ISODIR}"/boot/extlinux
}

_grub_mkrescue() {
    ## Generate the BIOS+ISOHYBRID+UEFI CD image
    #set date for reproducibility
    # --set_all_file_dates for all files
    # --modification-date= for boot.catalog
    echo "Generating ${_RUNNING_ARCH} hybrid ISO ..."
    grub-mkrescue --set_all_file_dates 'Jan 1 00:00:00 UTC 1970' --modification-date=1970010100000000 --compress=xz --fonts="unicode" --locales="" --themes="" -o "${_IMAGENAME}.iso" "${_ISODIR}"/ "boot/grub/archboot-main-grub.cfg=${_GRUB_CONFIG}" "boot/grub/grub.cfg=/usr/share/archboot/grub/archboot-iso-grub.cfg" &> "${_IMAGENAME}.log"
}

_reproducibility_iso() {
    echo "Create reproducible UUIDs on ${_IMAGENAME}.iso GPT ..."
    sgdisk -u 1:1 "${_IMAGENAME}.iso" >/dev/null 2>&1
    sgdisk -u 2:2 "${_IMAGENAME}.iso" >/dev/null 2>&1
    sgdisk -u 3:3 "${_IMAGENAME}.iso" >/dev/null 2>&1
    sgdisk -u 4:4 "${_IMAGENAME}.iso" >/dev/null 2>&1
    sgdisk -U 1 "${_IMAGENAME}.iso" >/dev/null 2>&1
}

_create_cksum() {
    ## create sha256sums.txt
    echo "Generating sha256sum ..."
    [[ -f  "sha256sums.txt" ]] && rm "sha256sums.txt"
    [[ "$(echo ./*.iso)" == "./*.iso" ]] || cksum -a sha256 ./*.iso > "sha256sums.txt"
    [[ "$(echo ./*.img)" == "./*.img" ]] || cksum -a sha256 ./*.img > "sha256sums.txt"
}

_cleanup_iso() {
    # cleanup
    echo "Cleanup... remove ${_ISODIR} ..."
    [[ -d "${_ISODIR}" ]] && rm -r "${_ISODIR}"
}
