#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
_BOOTLOADER="/usr/share/archboot/bootloader"
_GRUB_ISO="/usr/share/archboot/grub/archboot-iso-grub.cfg"

_usage () {
    echo -e "\e[1m\e[36mArchboot\e[m\e[1m - Create ${_ARCH} ISO Image\e[m"
    echo -e "\e[1m----------------------------------------\e[m"
    echo "Create an Archboot ISO image: <name>.iso"
    echo
    echo "Options:"
    echo -e " \e[1m-g\e[m              Start generation of an ISO image"
    echo -e " \e[1m-c=CONFIG\e[m       CONFIG from ${_CONFIG_DIR}: default=${_ARCH}.conf"
    echo -e " \e[1m-i=ISO\e[m          Customize ISO name"
    echo -e " \e[1m-s\e[m              Save initramfs files in current work directory"
    echo
    echo -e "Usage: \e[1m${_BASENAME} <options>\e[m"
    exit 0
}

_parameters() {
    while [ $# -gt 0 ]; do
        case ${1} in
            -g|--g) export _GENERATE="1" ;;
            -s|--s) _SAVE_INIT="1" ;;
            -c=*|--c=*) _CONFIG="$(rg -o '=(.*)' -r '$1' <<< "${1}")" ;;
            -i=*|--i=*) _IMAGENAME="$(rg -o '=(.*)' -r '$1' <<< "${1}")" ;;
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
        archboot-cpio.sh -c "/etc/archboot/${_ARCH}-init.conf" -firmware \
                         -g "${_ISODIR}/boot/init-${_ARCH}.img" || exit 1
        # save init ramdisk for further images
        if [[ -n "${_SAVE_INIT}" ]]; then
            cp "${_ISODIR}/boot/init-${_ARCH}.img" ./
        fi
    fi
    _INITRD="initrd-${_ARCH}.img"
    _FW="firmware"
    rg -qw local <<< "${_CONFIG}" && _INITRD="initrd-local-${_ARCH}.img" && _FW="firmware-local"
    rg -qw latest <<< "${_CONFIG}" && _INITRD="initrd-latest-${_ARCH}.img" && _FW="firmware-latest"
    if [[ -f "${_INITRD}" ]]; then
        echo "Using existing ${_INITRD}..."
        mv "./${_INITRD}" "${_ISODIR}/boot/initrd-${_ARCH}.img"
    fi
    if [[ -f "${_ISODIR}/boot/initrd-${_ARCH}.img" ]]; then
        echo "Using existing ${_FW}..."
        mv "./${_FW}" "${_ISODIR}/boot/firmware"
    else
        echo "Running archboot-cpio.sh for initrd-${_ARCH}.img..."
        archboot-cpio.sh -c "${_CONFIG}" -firmware \
                         -g "${_ISODIR}/boot/initrd-${_ARCH}.img" || exit 1
    fi
    # delete cachedir on Archboot environment
    if rg -qw 'archboot' /etc/hostname; then
        if [[ -d "${_CACHEDIR}" ]]; then
            echo "Removing ${_CACHEDIR}..."
            rm -rf "${_CACHEDIR}"
        fi
    fi
}

_prepare_doc() {
    cp -r /usr/share/archboot/doc "${_ISODIR}/"
}

_prepare_ucode() {
    # only x86_64
    if [[ "${_ARCH}" == "x86_64" ]]; then
        echo "Preparing intel-ucode..."
        cp "/${_INTEL_UCODE}" "${_ISODIR}/boot/"
    fi
    # both x86_64 and aarch64
    if ! [[ "${_ARCH}" == "riscv64" ]]; then
        echo "Preparing amd-ucode..."
        cp "/${_AMD_UCODE}" "${_ISODIR}/boot/"
    fi
}

_prepare_uefi_shell_tianocore() {
    echo "Preparing UEFI shell..."
    ## Installing Tianocore UDK/EDK2 UEFI X64 "Full Shell"
    cp /usr/share/edk2-shell/x64/Shell_Full.efi "${_ISODIR}/EFI/TOOLS/SHELLX64.EFI"
    ## Installing Tianocore UDK/EDK2 UEFI IA32 "Full Shell"
    cp /usr/share/edk2-shell/ia32/Shell_Full.efi "${_ISODIR}/EFI/TOOLS/SHELLIA32.EFI"
}

_prepare_efi_bootloaders() {
    if [[ ${_ARCH} == "x86_64" ]]; then
        _GRUB_ARCH="i386-efi x86_64-efi"
        _UEFI_ARCH="ia32 x64"
    elif [[ ${_ARCH} == "aarch64" ]]; then
        _GRUB_ARCH="arm64-efi"
        _UEFI_ARCH="aa64"
    fi
    # Grub
    for i in ${_GRUB_ARCH}; do
        [[ "${i}" == "i386-efi" ]] && _GRUB_EFI="${_ISODIR}/EFI/BOOT/GRUBIA32.EFI"
        [[ "${i}" == "x86_64-efi" ]] && _GRUB_EFI="${_ISODIR}/EFI/BOOT/GRUBX64.EFI"
        [[ "${i}" == "arm64-efi" ]] && _GRUB_EFI="${_ISODIR}/EFI/BOOT/GRUBAA64.EFI"
        echo "Preparing ${i} grub..."
        grub-mkstandalone -d "/usr/lib/grub/${i}" -O "${i}" \
        --sbat=/usr/share/grub/sbat.csv --fonts=ter-u16n --locales="" --themes="" \
        -o "${_GRUB_EFI}" "boot/grub/grub.cfg=${_GRUB_ISO}" &>"${_NO_LOG}"
    done
    # SHIM and IPXE
    # Details on shim https://www.rodsbooks.com/efi-bootloaders/secureboot.html#initial_shim
    # add shim x64 signed files from fedora
    for i in ${_UEFI_ARCH}; do
        _CAP_I=$(echo "${i}" | tr '[:lower:]' '[:upper:]')
        echo "Preparing ${_CAP_I} Fedora SHIM and IPXE..."
        cp "${_BOOTLOADER}/ipxe${i}.efi" "${_ISODIR}/EFI/BOOT/IPXE${_CAP_I}.EFI"
        cp "${_BOOTLOADER}/mm${i}.efi" "${_ISODIR}/EFI/BOOT/MM${_CAP_I}.EFI"
        cp "${_BOOTLOADER}/boot${i}.efi" "${_ISODIR}/EFI/BOOT/BOOT${_CAP_I}.EFI"
    done
}

_prepare_bios_ipxe() {
    echo "Preparing Bios IPXE..."
    cp "${_BOOTLOADER}/ipxe.lkrn" "${_ISODIR}/boot/"
}

_prepare_memtest() {
    echo "Preparing memtest86+..."
    cp /boot/memtest86+/memtest.bin "${_ISODIR}/boot/"
    cp /boot/memtest86+/memtest.efi "${_ISODIR}/EFI/TOOLS/MEMTEST.EFI"
}

_prepare_background() {
    echo "Preparing grub background..."
    [[ -d "${_ISODIR}/boot/grub" ]] || mkdir -p "${_ISODIR}/boot/grub"
    cp "${_GRUB_BACKGROUND}" "${_ISODIR}/boot/grub/archboot-background.png"
}

_prepare_uefi_image() {
    echo "Preparing UEFI image..."
    ## get size of boot files
    # 2048 first sector
    # 8192 to avoid disk full errors
    BOOTSIZE=$(LC_ALL=C.UTF-8 du -bc "${_ISODIR}"/EFI "${_ISODIR}"/boot | rg '([0-9]+).*total' -r '$1')
    IMGSZ=$((BOOTSIZE/1024 + 2048 + 8192)) # image size in KB
    VFAT_IMAGE="${_ISODIR}/efi.img"
    ## Creating efi.img
    mkfs.vfat -n ARCHBOOT --invariant -C "${VFAT_IMAGE}" "${IMGSZ}" >"${_NO_LOG}"
    ## Copying all files to UEFI vfat image
    mcopy -m -i "${VFAT_IMAGE}" -s "${_ISODIR}"/EFI "${_ISODIR}"/boot ::/
    # leave EFI/ and /boot/kernel for virtualbox and other restricted VM emulators :(
    if [[ "${_ARCH}" == "x86_64" || "${_ARCH}" == "riscv64" ]]; then
        fd -u -t f -E "vmlinuz-${_ARCH}" . "${_ISODIR}"/boot/ -X rm
    fi
    if [[ "${_ARCH}" == "aarch64" ]]; then
        fd -u -t f -E "Image-${_ARCH}.gz" . "${_ISODIR}"/boot/ -X rm
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

_prepare_release_txt() {
    echo "Preparing Release.txt..."
    (echo "ARCHBOOT - ARCH LINUX INSTALLATION / RESCUE SYSTEM"
    echo "archboot.com | (c) 2006 - $(date +%Y)"
    echo "Tobias Powalowski <tpowa@archlinux.org>"
    echo ""
    echo "The release is based on these main packages:"
    echo "Archboot: $(pacman -Qi "${_ARCHBOOT[@]}" |\
    rg -o 'Version.* (.*)' -r '$1')"
    [[ "${_ARCH}" == "riscv64" ]] || echo "Grub: $(pacman -Qi grub |\
                                     rg -o 'Version.* (.*)' -r '$1')"
    echo "Linux: $(pacman -Qi linux |\
    rg -o 'Version.* (.*)' -r '$1')"
    echo "Pacman: $(pacman -Qi pacman |\
    rg -o 'Version.* (.*)' -r '$1')"
    echo "Systemd: $(pacman -Qi systemd |\
    rg -o 'Version.* (.*)' -r '$1')"
    echo ""
    if [[ -f /etc/archboot/ssh/archboot-key ]]; then
        cat /etc/archboot/ssh/archboot-key
    fi
    echo ""
    echo "---Complete Package List---"
    pacman -Q | sd '\r|\x1b\[[0-9;]*m|\x1b\[.[0-9]+[h;l]' '') >"${_ISODIR}/Release.txt"
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
    BOOTSIZE=$(LC_ALL=C.UTF-8 du -bc "${_ISODIR}"/boot | rg '([0-9]+).*total' -r '$1')
    IMGSZ=$((BOOTSIZE/1024 + 2048 + 8192)) # image size in KB
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
    # -J enable Joliet filesystem for correct file names on Windows
    # -- -rm_r /efi .disk/ /boot/grub/{roms,locale} ${_RESCUE_REMOVE} for removing reproducibility breakers
    echo "Generating ${_ARCH} hybrid ISO..."
    [[ "${_ARCH}" == "x86_64" ]] && _RESCUE_REMOVE=(mach_kernel /System /boot/grub/i386-efi /boot/grub/x86_64-efi)
    [[ "${_ARCH}" == "aarch64" ]] && _RESCUE_REMOVE=(/boot/grub/arm64-efi)
    grub-mkrescue --set_all_file_dates 'Jan 1 00:00:00 UTC 1970' \
                  --modification-date=1970010100000000 --compress=xz --fonts="ter-u16n" \
                  --locales="" --themes="" -o "${_IMAGENAME}.iso" "${_ISODIR}"/ \
                  "boot/grub/archboot-main-grub.cfg=${_GRUB_CONFIG}" \
                  "boot/grub/grub.cfg=/usr/share/archboot/grub/archboot-iso-grub.cfg" \
                  -volid "ARCHBOOT" -J -- -rm_r /boot/{firmware,grub/{roms,locale}} /efi .disk/ \
                  "${_RESCUE_REMOVE[@]}" &> "${_IMAGENAME}.log"
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
    for i in $(seq 1 "$(sfdisk -J "${_IMAGENAME}.iso" | rg -cw 'node')"); do
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
