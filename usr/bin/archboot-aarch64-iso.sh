#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
_SHIM_URL="https://kojipkgs.fedoraproject.org/packages/shim/15.4/5/aarch64"
_SHIM_VERSION="shim-aa64-15.4-5.aarch64.rpm"
_PRESET_DIR="/etc/archboot/presets"
_GRUB_CONFIG="/usr/share/archboot/grub/grub.cfg"
# covered by usage
_GENERATE=""
_PRESET=""
_IMAGENAME=""
_RELEASENAME=""
# temporary directories
_AARCH64="$(mktemp -d AARCH64.XXX)"
_SHIM="$(mktemp -d shim.XXX)"

usage () {
    echo "${_BASENAME}: usage"
    echo "CREATE AARCH64 USB/CD IMAGES"
    echo "-----------------------------"
    echo "PARAMETERS:"
    echo "  -g                  Start generation of image."
    echo "  -p=PRESET           Which preset should be used."
    echo "                      /etc/archboot/presets locates the presets"
    echo "                      default=aarch64"
    echo "  -i=IMAGENAME        Your IMAGENAME."
    echo "  -r=RELEASENAME      Use RELEASENAME in boot message."
    echo "  -h                  This message."
    exit 0
}

[[ -z "${1}" ]] && usage

# change to english locale!
export LANG="en_US"

while [ $# -gt 0 ]; do
    case ${1} in
        -g|--g) _GENERATE="1" ;;
        -p=*|--p=*) _PRESET="$(echo ${1} | awk -F= '{print $2;}')" ;;
        -i=*|--i=*) _IMAGENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
        -r=*|--r=*) _RELEASENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
        -h|--h|?) usage ;; 
        *) usage ;;
        esac
    shift
done

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
    echo "ERROR: Please run as root user!"
    exit 1
fi

### check for aarch64
if ! [[ "$(uname -m)" == "aarch64" ]]; then
    echo "ERROR: Please run on aarch64 hardware."
    exit 1
fi

[[ "${_GENERATE}" == "1" ]] || usage

#set PRESET
[[ -z "${_PRESET}" ]] && _PRESET="aarch64"
_PRESET="${_PRESET_DIR}/${_PRESET}"

# set defaults, if nothing given
[[ -z "${_RELEASENAME}" ]] && _RELEASENAME="$(date +%Y.%m.%d-%H.%M)"
[[ -z "${_IMAGENAME}" ]] && _IMAGENAME="archlinux-archboot-${_RELEASENAME}-aarch64"

if ! [[ "${_GENERATE}" == "1" ]]; then
	usage
fi

_prepare_kernel_initramfs_files() {
    source "${_PRESET}"
    mkdir -p "${_AARCH64}/EFI/BOOT"
    mkdir -p "${_AARCH64}/boot"
    # fix for mkinitcpio 31
    # https://bugs.archlinux.org/task/72882
    # remove on mkinitcpio 32 release
    cp "/usr/lib/initcpio/functions" "/usr/lib/initcpio/functions.old"
    [[ -f "/usr/share/archboot/patches/31-initcpio.functions.fixed" ]] && cp "/usr/share/archboot/patches/31-initcpio.functions.fixed" "/usr/lib/initcpio/functions"
    mkinitcpio -c "${MKINITCPIO_CONFIG}" -k "${ALL_kver}" -g "${_AARCH64}/boot/initramfs_aarch64.img" || exit 1
    mv "/usr/lib/initcpio/functions.old" "/usr/lib/initcpio/functions"
    install -m644 "${ALL_kver}" "${_AARCH64}/boot/vmlinuz_aarch64"
    # install ucode files
    cp /boot/amd-ucode.img "${_AARCH64}/boot/"
    # fix license files
    mkdir -p "${_AARCH64}/licenses/amd-ucode"
    cp /usr/share/licenses/amd-ucode/LICENSE.amd-ucode "${_AARCH64}/licenses/amd-ucode"
}

_prepare_efitools_uefi () {
    cp -f "/usr/share/efitools/efi/HashTool.efi" "${_AARCH64}/EFI/tools/HashTool.efi"
    cp -f "/usr/share/efitools/efi/KeyTool.efi" "${_AARCH64}/EFI/tools/KeyTool.efi"
}

_prepare_fedora_shim_bootloaders () {
    # Details on shim https://www.rodsbooks.com/efi-bootloaders/secureboot.html#initial_shim
    # add shim aa64 signed files from fedora
    curl -s --create-dirs -L -O --output-dir "${_SHIM}" "${_SHIM_URL}/${_SHIM_VERSION}"
    bsdtar -C "${_SHIM}" -xf "${_SHIM}"/"${_SHIM_VERSION}"
    cp "${_SHIM}/boot/efi/EFI/fedora/mmaa64.efi" "${_AARCH64}/EFI/BOOT/mmaa64.efi"
    cp "${_SHIM}/boot/efi/EFI/fedora/shimaa64.efi" "${_AARCH64}/EFI/BOOT/BOOTAA64.efi"
}

_prepare_uefi_image() {
    ## get size of boot x86_64 files
    BOOTSIZE=$(du -bc ${_AARCH64}/EFI | grep total | cut -f1)
    IMGSZ=$(( (${BOOTSIZE}*102)/100/1024 + 1)) # image size in sectors	
    ## Create cdefiboot.img
    dd if=/dev/zero of="${_AARCH64}"/efi.img bs="${IMGSZ}" count=1024
    VFAT_IMAGE="${_AARCH64}/efi.img"
    mkfs.vfat "${VFAT_IMAGE}"
    ## Copy all files to UEFI vfat image
    mcopy -i "${VFAT_IMAGE}" -s "${_AARCH64}"/EFI ::/	
}

# build grubXXX with all modules: http://bugs.archlinux.org/task/71382
# If you don't use shim use --disable-shim-lock
_prepare_uefi_AA64_GRUB_USB_files() {
    ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
    grub-mkstandalone -d /usr/lib/grub/arm64-efi -O arm64-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd chain tpm" --fonts="unicode" --locales="" --themes="" -o "${_AARCH64}/EFI/BOOT/grubaa64.efi" "boot/grub/grub.cfg=${_GRUB_CONFIG}"
}

echo "Starting ISO creation ..."
echo "Prepare kernel and initramfs ..."
_prepare_kernel_initramfs_files

echo "Prepare fedora shim ..."
_prepare_fedora_shim_bootloaders >/dev/null 2>&1

echo "Prepare efitools ..."
_prepare_efitools_uefi >/dev/null 2>&1

echo "Prepare AA64 Grub ..."
_prepare_uefi_AA64_GRUB_USB_files >/dev/null 2>&1

echo "Prepare UEFI image ..."
_prepare_uefi_image >/dev/null 2>&1

## Generate the BIOS+ISOHYBRID+UEFI CD image
grub-mkrescue --compress=xz --fonts="unicode" --locales="" --themes="" -o "${_IMAGENAME}.iso" "${_AARCH64}"/  "boot/grub/grub.cfg=${_GRUB_CONFIG}" &> "${_IMAGENAME}.log"

## create sha256sums.txt
echo "Generating sha256sum ..."
rm -f "sha256sums.txt" || true
cksum -a sha256 *.iso > "sha256sums.txt"

# cleanup
echo "Cleanup remove ${_AARCH64} and ${_SHIM} ..."
rm -rf "${_AARCH64}"
rm -rf "${_SHIM}"
echo "Finished ISO creation."
