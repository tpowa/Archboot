#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
_PRESET_DIR="/etc/archboot/presets"
_SHIM_URL="https://kojipkgs.fedoraproject.org/packages/shim/15.4/5/x86_64"
_SHIM_VERSION="shim-x64-15.4-5.x86_64.rpm"
_SHIM32_VERSION="shim-ia32-15.4-5.x86_64.rpm"
_GRUB_CONFIG="/usr/share/archboot/grub/grub.cfg"
# covered by usage
_GENERATE=""
_PRESET=""
_IMAGENAME=""
_RELEASENAME=""
# temporary directories
_X86_64="$(mktemp -d X86_64.XXX)"
_SHIM="$(mktemp -d shim.XXX)"
_SHIM32="$(mktemp -d shim32.XXX)"

usage () {
	echo "${_BASENAME}: usage"
	echo "CREATE X86_64 USB/CD IMAGES"
	echo "-----------------------------"
	echo "PARAMETERS:"
        echo "  -g                  Start generation of image."
	echo "  -p=PRESET           Which preset should be used."
	echo "                      /etc/archboot/presets locates the presets"
	echo "                      default=x86_64"
	echo "  -i=IMAGENAME        Your IMAGENAME."
	echo "  -r=RELEASENAME      Use RELEASENAME in boot message."
	echo "  -h                  This message."
	exit 0
}

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
if ! [[ "$(uname -m)" == "x86_64" ]]; then
    echo "ERROR: Please run on x86_64 hardware."
    exit 1
fi

[[ "${_GENERATE}" == "1" ]] || usage

#set PRESET
[[ -z "${_PRESET}" ]] && _PRESET="x86_64"
_PRESET=""${_PRESET_DIR}"/"${_PRESET}""

# set defaults, if nothing given
[[ -z "${_RELEASENAME}" ]] && _RELEASENAME="$(date +%Y.%m.%d-%H.%M)"
[[ -z "${_IMAGENAME}" ]] && _IMAGENAME="archlinux-archboot-${_RELEASENAME}-x86_64"

_prepare_kernel_initramfs_files() {
    source "${_PRESET}"
    mkdir -p "${_X86_64}/EFI/BOOT"
    mkdir -p "${_X86_64}/boot"
    # fix for mkinitcpio 31
    # https://bugs.archlinux.org/task/72882
    # remove on mkinitcpio 32 release
    cp "/usr/lib/initcpio/functions" "/usr/lib/initcpio/functions.old"
    [[ -f "/usr/share/archboot/patches/31-initcpio.functions.fixed" ]] && cp "/usr/share/archboot/patches/31-initcpio.functions.fixed" "/usr/lib/initcpio/functions"
    mkinitcpio -c "${MKINITCPIO_CONFIG}" -k "${ALL_kver}" -g "${_X86_64}/boot/initramfs_x86_64.img" || exit 1
    mv "/usr/lib/initcpio/functions.old" "/usr/lib/initcpio/functions"
    install -m644 "${ALL_kver}" "${_X86_64}/boot/vmlinuz_x86_64"
    # install ucode files
    cp /boot/{intel-ucode.img,amd-ucode.img} "${_X86_64}/boot/"
    # fix license files
    mkdir -p "${_X86_64}/share/licenses/{amd-ucode,intel-ucode}"
    cp /usr/share/licenses/amd-ucode/LICENSE.amd-ucode "${_X86_64}/share/licenses/amd-ucode"
    cp /usr/share/licenses/intel-ucode/LICENSE "${_X86_64}/share/licenses/intel-ucode"
}

_prepare_efitools_uefi () {
    cp -f "/usr/share/efitools/efi/HashTool.efi" "${_X86_64}/EFI/tools/HashTool.efi"
    cp -f "/usr/share/efitools/efi/KeyTool.efi" "${_X86_64}/EFI/tools/KeyTool.efi"
}

_prepare_fedora_shim_bootloaders () {
    # Details on shim https://www.rodsbooks.com/efi-bootloaders/secureboot.html#initial_shim
    # add shim x64 signed files from fedora
    curl -s --create-dirs -L -O --output-dir "${_SHIM}" "${_SHIM_URL}/${_SHIM_VERSION}"
    bsdtar -C "${_SHIM}" -xf "${_SHIM}"/"${_SHIM_VERSION}"
    cp "${_SHIM}/boot/efi/EFI/fedora/mmx64.efi" "${_X86_64}/EFI/BOOT/mmx64.efi"
    cp "${_SHIM}/boot/efi/EFI/fedora/shimx64.efi" "${_X86_64}/EFI/BOOT/BOOTX64.efi"
    # add shim ia32 signed files from fedora
    curl -s --create-dirs -L -O --output-dir "${_SHIM32}" "${_SHIM_URL}/${_SHIM32_VERSION}"
    bsdtar -C "${_SHIM32}" -xf "${_SHIM32}/${_SHIM32_VERSION}"
    cp "${_SHIM32}/boot/efi/EFI/fedora/mmia32.efi" "${_X86_64}/EFI/BOOT/mmia32.efi"
    cp "${_SHIM32}/boot/efi/EFI/fedora/shimia32.efi" "${_X86_64}/EFI/BOOT/BOOTIA32.efi"
    ### adding this causes boot loop in ovmf and only tries create a boot entry
    #cp "${SHIM}/boot/efi/EFI/BOOT/fbx64.efi" "${_X86_64}/EFI/BOOT/fbx64.efi"
}

_prepare_uefi_image() {
    ## get size of boot x86_64 files
    BOOTSIZE=$(du -bc ${_X86_64}/EFI | grep total | cut -f1)
    IMGSZ=$(( (${BOOTSIZE}*102)/100/1024 + 1)) # image size in sectors
    ## Create cdefiboot.img
    dd if=/dev/zero of="${_X86_64}"/efi.img bs="${IMGSZ}" count=1024
    VFAT_IMAGE="${_X86_64}/efi.img"
    mkfs.vfat "${VFAT_IMAGE}"
    ## Copy all files to UEFI vfat image
    mcopy -i "${VFAT_IMAGE}" -s "${_X86_64}"/EFI ::/
}

_download_uefi_shell_tianocore() {
    mkdir -p "${_X86_64}/EFI/tools/"
    ## Install Tianocore UDK/EDK2 ShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. >=2.3 systems
    cp /usr/share/edk2-shell/x64/Shell.efi "${_X86_64}/EFI/tools/shellx64_v2.efi" 
    ## Install Tianocore UDK/EDK2 EdkShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. <2.3 systems
    cp /usr/share/edk2-shell/x64/Shell_Full.efi "${_X86_64}/EFI/tools/shellx64_v1.efi" 	
    ## Install Tianocore UDK/EDK2 ShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. >=2.3 systems
    cp /usr/share/edk2-shell/ia32/Shell.efi "${_X86_64}/EFI/tools/shellia32_v2.efi"
    ## InstallTianocore UDK/EDK2 EdkShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. <2.3 systems
    cp /usr/share/edk2-shell/ia32/Shell_Full.efi "${_X86_64}/EFI/tools/shellia32_v1.efi" 
}

# build grubXXX with all modules: http://bugs.archlinux.org/task/71382
# If you don't use shim use --disable-shim-lock
_prepare_uefi_X64_GRUB_USB_files() {
    ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
    grub-mkstandalone -d /usr/lib/grub/x86_64-efi -O x86_64-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efi_uga efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd backtrace chain tpm usb usbserial_common usbserial_pl2303 usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard" --fonts="unicode" --locales="" --themes="" -o "${_X86_64}/EFI/BOOT/grubx64.efi" "boot/grub/grub.cfg=${_GRUB_CONFIG}"
}

_prepare_uefi_IA32_GRUB_USB_files() {
    ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
    grub-mkstandalone -d /usr/lib/grub/i386-efi -O i386-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efi_uga efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd backtrace chain tpm usb usbserial_common usbserial_pl2303 usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard" --fonts="unicode" --locales="" --themes="" -o "${_X86_64}/EFI/BOOT/grubia32.efi" "boot/grub/grub.cfg=${_GRUB_CONFIG}"
}

echo "Starting ISO creation ..."
echo "Prepare kernel and initramfs ..."
_prepare_kernel_initramfs_files

echo "Prepare fedora shim ..."
_prepare_fedora_shim_bootloaders >/dev/null 2>&1

echo "Prepare uefi shells ..."
_download_uefi_shell_tianocore >/dev/null 2>&1

echo "Prepare efitools ..."
_prepare_efitools_uefi >/dev/null 2>&1

echo "Prepare X64 Grub ..."
_prepare_uefi_X64_GRUB_USB_files >/dev/null 2>&1

echo "Prepare IA32 Grub ..."
_prepare_uefi_IA32_GRUB_USB_files >/dev/null 2>&1

echo "Prepare UEFI image ..."
_prepare_uefi_image >/dev/null 2>&1

## Generate the BIOS+ISOHYBRID+UEFI CD image
echo "Generating X86_64 hybrid ISO ..."
grub-mkrescue --compress="xz" --fonts="unicode" --locales="" --themes="" -o "${_IMAGENAME}.iso" "${_X86_64}"/ "boot/grub/grub.cfg=${_GRUB_CONFIG}" &> "${_IMAGENAME}.log"

## create sha256sums.txt
echo "Generating sha256sum ..."
rm -f "sha256sums.txt" || true
cksum -a sha256 *.iso > "sha256sums.txt"

# cleanup
echo "Cleanup remove ${_X86_64}, ${_SHIM} and ${_SHIM32} ..."
rm -rf "${_X86_64}"
rm -rf "${_SHIM}"
rm -rf "${_SHIM32}"
echo "Finished ISO creation."
