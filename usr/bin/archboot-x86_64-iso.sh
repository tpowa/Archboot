#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
X86_64="$(mktemp -d X86_64.XXX)"
_SHIM_URL="https://kojipkgs.fedoraproject.org/packages/shim/15.4/5/x86_64"
_SHIM_VERSION="shim-x64-15.4-5.x86_64.rpm"
_SHIM32_VERSION="shim-ia32-15.4-5.x86_64.rpm"


usage () {
	echo "${_BASENAME}: usage"
	echo "CREATE X86_64 USB/CD IMAGES"
	echo "-----------------------------"
	echo "Run in archboot x86_64 chroot first ..."
	echo "archboot-x86_64-iso.sh -t"
	echo ""
	echo "PARAMETERS:"
	echo "  -t                  Start generation of tarball."
	echo "  -g                  Start generation of image."
	echo "  -p=PRESET           Which preset should be used."
	echo "                      /etc/archboot/presets locates the presets"
	echo "                      default=x86_64"
	echo "  -i=IMAGENAME        Your IMAGENAME."
	echo "  -r=RELEASENAME      Use RELEASENAME in boot message."
	echo "  -k=KERNELNAME       Use KERNELNAME in boot message."
	echo "  -T=tarball          Use this tarball for image creation."
	echo "  -h                  This message."
	exit 0
}

[[ -z "${1}" ]] && usage


PRESET_DIR="/etc/archboot/presets"
TARBALL_HELPER="/usr/bin/archboot-tarball-helper.sh"

# change to english locale!
export LANG="en_US"

while [ $# -gt 0 ]; do
	case ${1} in
		-g|--g) GENERATE="1" ;;
		-t|--t) TARBALL="1" ;;
                -p=*|--p=*) PRESET="$(echo ${1} | awk -F= '{print $2;}')" ;;
		-i=*|--i=*) IMAGENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
		-r=*|--r=*) RELEASENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
		-k=*|--k=*) KERNEL="$(echo ${1} | awk -F= '{print $2;}')" ;;
                -T=*|--T=*) TARBALL_NAME="$(echo ${1} | awk -F= '{print $2;}')" ;;	
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

#set PRESET
[[ -z "${PRESET}" ]] && PRESET="x86_64"
PRESET=""${PRESET_DIR}"/"${PRESET}""

# from initcpio functions
kver() {
    # this is intentionally very loose. only ensure that we're
    # dealing with some sort of string that starts with something
    # resembling dotted decimal notation. remember that there's no
    # requirement for CONFIG_LOCALVERSION to be set.
    local kver re='^[[:digit:]]+(\.[[:digit:]]+)+'

    # scrape the version out of the kernel image. locate the offset
    # to the version string by reading 2 bytes out of image at at
    # address 0x20E. this leads us to a string of, at most, 128 bytes.
    # read the first word from this string as the kernel version.
    local offset=$(hexdump -s 526 -n 2 -e '"%0d"' "/boot/vmlinuz-linux")
    [[ $offset = +([0-9]) ]] || return 1

    read kver _ < \
        <(dd if="/boot/vmlinuz-linux" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)

    [[ $kver =~ $re ]] || return 1

    KERNEL="$(printf '%s' "$kver")"
}

# set defaults, if nothing given
[[ -z "${KERNEL}" ]] && kver
[[ -z "${RELEASENAME}" ]] && RELEASENAME="$(date +%Y.%m.%d-%H.%M)"
[[ -z "${IMAGENAME}" ]] && IMAGENAME="archlinux-archboot-${RELEASENAME}-x86_64"

if [[ "${TARBALL}" == "1" ]]; then
	"${TARBALL_HELPER}" -c="${PRESET}" -t="${IMAGENAME}.tar"
	exit 0
fi

if ! [[ "${GENERATE}" == "1" ]]; then
	usage
fi

if ! [[ "${TARBALL_NAME}" == "" ]]; then
        CORE64="$(mktemp -d core64.XXX)"
        tar xf ${TARBALL_NAME} -C "${CORE64}" || exit 1
    else
        echo "Please enter a tarball name with parameter -T=tarball"
        exit 1
fi

mkdir -p "${X86_64}/EFI/BOOT"

_prepare_kernel_initramfs_files() {

	mkdir -p "${X86_64}/boot"
        mv "${CORE64}"/*/boot/vmlinuz "${X86_64}/boot/vmlinuz_x86_64"
        mv "${CORE64}"/*/boot/initrd.img "${X86_64}/boot/initramfs_x86_64.img"
	mv "${CORE64}"/*/boot/{intel-ucode.img,amd-ucode.img} "${X86_64}/boot/"
	[[ -f "${CORE64}/*/boot/memtest" ]] && mv "${CORE64}"/*/boot/memtest "${X86_64}/boot/"
        
}

_prepare_efitools_uefi () {
    cp -f "/usr/share/efitools/efi/HashTool.efi" "${X86_64}/EFI/tools/HashTool.efi"
    cp -f "/usr/share/efitools/efi/KeyTool.efi" "${X86_64}/EFI/tools/KeyTool.efi"
}

_prepare_fedora_shim_bootloaders () {
    # Details on shim https://www.rodsbooks.com/efi-bootloaders/secureboot.html#initial_shim
    # add shim x64 signed files from fedora
    SHIM=$(mktemp -d shim.XXXX)
    curl -s --create-dirs -L -O --output-dir "${SHIM}" "${_SHIM_URL}/${_SHIM_VERSION}"
    bsdtar -C "${SHIM}" -xf "${SHIM}"/"${_SHIM_VERSION}"
    cp "${SHIM}/boot/efi/EFI/fedora/mmx64.efi" "${X86_64}/EFI/BOOT/mmx64.efi"
    cp "${SHIM}/boot/efi/EFI/fedora/shimx64.efi" "${X86_64}/EFI/BOOT/BOOTX64.efi"
    # add shim ia32 signed files from fedora
    SHIM32=$(mktemp -d shim32.XXXX)
    curl -s --create-dirs -L -O --output-dir "${SHIM32}" "${_SHIM_URL}/${_SHIM32_VERSION}"
    bsdtar -C "${SHIM32}" -xf "${SHIM32}/${_SHIM32_VERSION}"
    cp "${SHIM32}/boot/efi/EFI/fedora/mmia32.efi" "${X86_64}/EFI/BOOT/mmia32.efi"
    cp "${SHIM32}/boot/efi/EFI/fedora/shimia32.efi" "${X86_64}/EFI/BOOT/BOOTIA32.efi"
    ### adding this causes boot loop in ovmf and only tries create a boot entry
    #cp "${SHIM}/boot/efi/EFI/BOOT/fbx64.efi" "${X86_64}/EFI/BOOT/fbx64.efi"
}

_prepare_uefi_image() {
        
        ## get size of boot x86_64 files
	BOOTSIZE=$(du -bc ${X86_64} | grep total | cut -f1)
	IMGSZ=$(( (${BOOTSIZE}*102)/100/1024 + 1)) # image size in sectors
	
	mkdir -p "${X86_64}"/CDEFI/
	
	## Create cdefiboot.img
	dd if=/dev/zero of="${X86_64}"/CDEFI/cdefiboot.img bs="${IMGSZ}" count=1024
	VFAT_IMAGE="${X86_64}/CDEFI/cdefiboot.img"
	mkfs.vfat "${VFAT_IMAGE}"
	
	## Copy all files to UEFI vfat image
	mcopy -i "${VFAT_IMAGE}" -s "${X86_64}"/{EFI,boot} ::/
	
}

_download_uefi_shell_tianocore() {
	
	mkdir -p "${X86_64}/EFI/tools/"
	
	## Install Tianocore UDK/EDK2 ShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. >=2.3 systems
	cp /usr/share/edk2-shell/x64/Shell.efi "${X86_64}/EFI/tools/shellx64_v2.efi" 
	
	## Install Tianocore UDK/EDK2 EdkShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. <2.3 systems
	cp /usr/share/edk2-shell/x64/Shell_Full.efi "${X86_64}/EFI/tools/shellx64_v1.efi" 
	
	## Install Tianocore UDK/EDK2 ShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. >=2.3 systems
	cp /usr/share/edk2-shell/ia32/Shell.efi "${X86_64}/EFI/tools/shellia32_v2.efi"
	
	## InstallTianocore UDK/EDK2 EdkShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. <2.3 systems
	cp /usr/share/edk2-shell/ia32/Shell_Full.efi "${X86_64}/EFI/tools/shellia32_v1.efi" 
}

_uefi_GRUB_sbat() {
	# create Arch Linux sbat file
        # add sbat file: https://bugs.archlinux.org/task/72415
        echo "sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md" > /tmp/sbat.csv
        echo "grub,1,Free Software Foundation,grub,2.06,https//www.gnu.org/software/grub/" >> /tmp/sbat.csv
        echo "arch,1,Arch Linux,\$pkgname,\$pkgver,https://archlinux.org/packages/core/x86_64/grub/" >> /tmp/sbat.csv
}

# build grubXXX with all modules: http://bugs.archlinux.org/task/71382
# If you don't use shim use --disable-shim-lock
_prepare_uefi_X64_GRUB_USB_files() {
	
	mkdir -p "${X86_64}/EFI/BOOT"
	cat << GRUBEOF > "${X86_64}/EFI/BOOT/grubx64.cfg"
insmod part_gpt
insmod part_msdos
insmod fat

insmod efi_gop
insmod efi_uga
insmod video_bochs
insmod video_cirrus

insmod font

if loadfont "${prefix}/fonts/unicode.pf2" ; then
    insmod gfxterm
    set gfxmode="1366x768x32;1280x800x32;1024x768x32;auto"
    terminal_input console
    terminal_output gfxterm
fi

set default="Arch Linux x86_64 Archboot"
set timeout="10"

menuentry "Arch Linux x86_64 Archboot" {
    set gfxpayload=keep
    search --no-floppy --set=root --file /boot/vmlinuz_x86_64
    linux /boot/vmlinuz_x86_64 cgroup_disable=memory add_efi_memmap _X64_UEFI=1 rootfstype=ramfs
    initrd /boot/intel-ucode.img  /boot/amd-ucode.img /boot/initramfs_x86_64.img
}

menuentry "Secure Boot KeyTool" {
    search --no-floppy --set=root --file /EFI/tools/KeyTool.efi
    chainloader /EFI/tools/KeyTool.efi
}

menuentry "Secure Boot HashTool" {
    search --no-floppy --set=root --file /EFI/tools/HashTool.efi
    chainloader /EFI/tools/HashTool.efi
}

menuentry "UEFI Shell X64 v2" {
    search --no-floppy --set=root --file /EFI/tools/shellx64_v2.efi
    chainloader /EFI/tools/shellx64_v2.efi
}

menuentry "UEFI Shell X64 v1" {
    search --no-floppy --set=root --file /EFI/tools/shellx64_v1.efi
    chainloader /EFI/tools/shellx64_v1.efi
}

if [ "${grub_platform}" == "efi" ]; then
	menuentry "Microsoft Windows" {
		insmod part_gpt
		insmod fat
		insmod chain
		search --no-floppy --fs-uuid --set=root $hints_string $fs_uuid
		chainloader /EFI/Microsoft/Boot/bootmgfw.efi
	}
fi

menuentry "Exit GRUB" {
    exit
}
GRUBEOF
        ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
        grub-mkstandalone -d /usr/lib/grub/x86_64-efi -O x86_64-efi --sbat=/tmp/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efi_uga efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd backtrace chain tpm usb usbserial_common usbserial_pl2303 usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard" --fonts="unicode" --locales="en@quot" --themes="" -o "${X86_64}/EFI/BOOT/grubx64.efi" "boot/grub/grub.cfg=${X86_64}/EFI/BOOT/grubx64.cfg"
}

_prepare_uefi_IA32_GRUB_USB_files() {
	
	mkdir -p "${X86_64}/EFI/BOOT"
	
	cat << GRUBEOF > "${X86_64}/EFI/BOOT/grubia32.cfg"
insmod part_gpt
insmod part_msdos
insmod fat

insmod efi_gop
insmod efi_uga
insmod video_bochs
insmod video_cirrus

insmod font

if loadfont "${prefix}/fonts/unicode.pf2" ; then
    insmod gfxterm
    set gfxmode="1366x768x32;1280x800x32;1024x768x32;auto"
    terminal_input console
    terminal_output gfxterm
fi

set default="Arch Linux x86_64 Archboot - EFI MIXED MODE"
set timeout="10"

menuentry "Arch Linux x86_64 Archboot - EFI MIXED MODE" {
    set gfxpayload=keep
    search --no-floppy --set=root --file /boot/vmlinuz_x86_64
    linux /boot/vmlinuz_x86_64 cgroup_disable=memory add_efi_memmap _IA32_UEFI=1 rootfstype=ramfs
    initrd /boot/intel-ucode.img  /boot/amd-ucode.img /boot/initramfs_x86_64.img
}

menuentry "UEFI Shell IA32 v2" {
    search --no-floppy --set=root --file /EFI/tools/shellia32_v2.efi
    chainloader /EFI/tools/shellia32_v2.efi
}

menuentry "UEFI Shell IA32 v1" {
    search --no-floppy --set=root --file /EFI/tools/shellia32_v1.efi
    chainloader /EFI/tools/shellia32_v1.efi
}

if [ "${grub_platform}" == "efi" ]; then
	menuentry "Microsoft Windows" {
		insmod part_gpt
		insmod fat
		insmod chain
		search --no-floppy --fs-uuid --set=root $hints_string $fs_uuid
		chainloader /EFI/Microsoft/Boot/bootmgfw.efi
	}
fi

menuentry "Exit GRUB" {
    exit
}
GRUBEOF
        ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
        grub-mkstandalone -d /usr/lib/grub/i386-efi -O i386-efi --sbat=/tmp/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efi_uga efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd backtrace chain tpm usb usbserial_common usbserial_pl2303 usbserial_ftdi usbserial_usbdebug keylayouts at_keyboard" --fonts="unicode" --locales="en@quot" --themes="" -o "${X86_64}/EFI/BOOT/grubia32.efi" "boot/grub/grub.cfg=${X86_64}/EFI/BOOT/grubia32.cfg"

}

echo "Starting ISO creation ..."
echo "Prepare fedora shim ..."
_prepare_fedora_shim_bootloaders >/dev/null 2>&1

echo "Prepare kernel and initramfs ..."
_prepare_kernel_initramfs_files >/dev/null 2>&1

echo "Prepare uefi shells ..."
_download_uefi_shell_tianocore >/dev/null 2>&1

echo "Prepare efitools ..."
_prepare_efitools_uefi >/dev/null 2>&1

echo "Prepare UEFI Grub sbat file..."
_uefi_GRUB_sbat

echo "Prepare X64 Grub ..."
_prepare_uefi_X64_GRUB_USB_files >/dev/null 2>&1

echo "Prepare IA32 Grub ..."
_prepare_uefi_IA32_GRUB_USB_files >/dev/null 2>&1

echo "Prepare UEFI image ..."
_prepare_uefi_image >/dev/null 2>&1

# place syslinux files
mkdir -p "${X86_64}/boot/syslinux"
mv "${CORE64}"/*/boot/syslinux/* "${X86_64}/boot/syslinux/"

# Change parameters in boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/ISOLINUX/g" "${X86_64}/boot/syslinux/boot.msg"

## Generate the BIOS+ISOHYBRID+UEFI CD image using xorriso (extra/libisoburn package) in mkisofs emulation mode
echo "Generating X86_64 hybrid ISO ..."
xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "ARCHBOOT" \
        -preparer "prepared by ${_BASENAME}" \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -isohybrid-mbr /usr/lib/syslinux/bios/isohdpfx.bin \
        -eltorito-alt-boot -e CDEFI/cdefiboot.img -isohybrid-gpt-basdat -no-emul-boot \
        -output "${IMAGENAME}.iso" "${X86_64}/" &> "${IMAGENAME}.log"

## create sha256sums.txt
echo "Generating sha256sum ..."
rm -f "sha256sums.txt" || true
cksum -a sha256 *.iso > "sha256sums.txt"

# cleanup
echo "Cleanup remove ${CORE64} and ${X86_64} ..."
rm -rf "${CORE64}"
rm -rf "${X86_64}"
echo "Finished ISO creation."
