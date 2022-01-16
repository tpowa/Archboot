#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
_SHIM_URL="https://kojipkgs.fedoraproject.org/packages/shim/15.4/5/aarch64"
_SHIM_VERSION="shim-aa64-15.4-5.aarch64.rpm"
_PRESET_DIR="/etc/archboot/presets"
_TARBALL_HELPER="/usr/bin/archboot-tarball-helper.sh"
# covered by usage
_GENERATE=""
_TARBALL=""
_PRESET=""
_IMAGENAME=""
_RELEASENAME=""
_KERNEL=""
_TARBALL_NAME=""
# temporary directories
_AARCH64="$(mktemp -d AARCH64.XXX)"
_CORE64="$(mktemp -d core64.XXX)"
_SHIM="$(mktemp -d shim.XXX)"

usage () {
	echo "${_BASENAME}: usage"
	echo "CREATE AARCH64 USB/CD IMAGES"
	echo "-----------------------------"
	echo "Run in archboot aarch64 chroot first ..."
	echo "archboot-aarch64-iso.sh -t"
	echo ""
	echo "PARAMETERS:"
	echo "  -t                  Start generation of tarball."
	echo "  -g                  Start generation of image."
	echo "  -p=PRESET           Which preset should be used."
	echo "                      /etc/archboot/presets locates the presets"
	echo "                      default=aarch64"
	echo "  -i=IMAGENAME        Your IMAGENAME."
	echo "  -r=RELEASENAME      Use RELEASENAME in boot message."
	echo "  -k=KERNELNAME       Use KERNELNAME in boot message."
	echo "  -T=tarball          Use this tarball for image creation."
	echo "  -h                  This message."
	exit 0
}

[[ -z "${1}" ]] && usage

# change to english locale!
export LANG="en_US"

while [ $# -gt 0 ]; do
	case ${1} in
		-g|--g) _GENERATE="1" ;;
		-t|--t) _TARBALL="1" ;;
                -p=*|--p=*) _PRESET="$(echo ${1} | awk -F= '{print $2;}')" ;;
		-i=*|--i=*) _IMAGENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
		-r=*|--r=*) _RELEASENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
		-k=*|--k=*) _KERNEL="$(echo ${1} | awk -F= '{print $2;}')" ;;
                -T=*|--T=*) _TARBALL_NAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
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

#set PRESET
[[ -z "${_PRESET}" ]] && _PRESET="aarch64"
_PRESET="${_PRESET_DIR}/${_PRESET}"

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
    local offset=$(hexdump -s 526 -n 2 -e '"%0d"' "/boot/Image.gz")
    [[ $offset = +([0-9]) ]] || return 1

    read kver _ < \
        <(dd if="/boot/Image.gz" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)

    [[ $kver =~ $re ]] || return 1

    _KERNEL="$(printf '%s' "$kver")"
}

# set defaults, if nothing given
[[ -z "${_KERNEL}" ]] && kver
[[ -z "${_RELEASENAME}" ]] && _RELEASENAME="$(date +%Y.%m.%d-%H.%M)"
[[ -z "${_IMAGENAME}" ]] && _IMAGENAME="archlinux-archboot-${_RELEASENAME}-aarch64"

if [[ "${_TARBALL}" == "1" ]]; then
        # fix for mkinitcpio 31
        # https://bugs.archlinux.org/task/72882
        # remove on mkinitcpio 32 release
        cp "/usr/lib/initcpio/functions" "/usr/lib/initcpio/functions.old"
        [[ -f "/usr/share/archboot/patches/31-initcpio.functions.fixed" ]] && cp "/usr/share/archboot/patches/31-initcpio.functions.fixed" "/usr/lib/initcpio/functions"
	"${_TARBALL_HELPER}" -c="${_PRESET}" -t="${_IMAGENAME}.tar"
	mv "/usr/lib/initcpio/functions.old" "/usr/lib/initcpio/functions"
	exit 0
fi

if ! [[ "${_GENERATE}" == "1" ]]; then
	usage
fi

if ! [[ "${_TARBALL_NAME}" == "" ]]; then
        tar xf ${_TARBALL_NAME} -C "${_CORE64}" || exit 1
    else
        echo "Please enter a tarball name with parameter -T=tarball"
        exit 1
fi

mkdir -p "${_AARCH64}/EFI/BOOT"

_prepare_kernel_initramfs_files() {

	mkdir -p "${_AARCH64}/boot"
        mv "${_CORE64}"/*/boot/vmlinuz "${_AARCH64}/boot/vmlinuz_aarch64"
        mv "${_CORE64}"/*/boot/initrd.img "${_AARCH64}/boot/initramfs_aarch64.img"
	mv "${_CORE64}"/*/boot/amd-ucode.img "${_AARCH64}/boot/"
	mv "${_CORE64}"/*/boot/dtbs  "${_AARCH64}/boot/"
        
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
	dd if=/dev/zero of="${_AARCH64}"/CDEFI/cdefiboot.img bs="${IMGSZ}" count=1024
	VFAT_IMAGE="${_AARCH64}/efi.img"
	mkfs.vfat "${VFAT_IMAGE}"
	
	## Copy all files to UEFI vfat image
	mcopy -i "${VFAT_IMAGE}" -s "${_AARCH64}"/EFI ::/
	
}


# build grubXXX with all modules: http://bugs.archlinux.org/task/71382
# If you don't use shim use --disable-shim-lock
_prepare_uefi_AA64_GRUB_USB_files() {
	
	mkdir -p "${_AARCH64}/EFI/BOOT"
	cat << GRUBEOF > "${_AARCH64}/EFI/BOOT/grubaa64.cfg"
insmod part_gpt
insmod part_msdos
insmod fat

insmod efi_gop
insmod video_bochs
insmod video_cirrus

insmod font

if loadfont "${prefix}/fonts/unicode.pf2" ; then
    insmod gfxterm
    set gfxmode="1366x768x32;1280x800x32;1024x768x32;auto"
    terminal_input console
    terminal_output gfxterm
fi

set default="Arch Linux AA64 Archboot"
set timeout="10"

menuentry "Arch Linux AA64 Archboot" {
    set gfxpayload=keep
    search --no-floppy --set=root --file /boot/vmlinuz_aarch64
    linux /boot/vmlinuz_aarch64 cgroup_disable=memory add_efi_memmap rootfstype=ramfs audit=0 nr_cpus=1
    initrd /boot/amd-ucode.img /boot/initramfs_aarch64.img
}

menuentry "Secure Boot KeyTool" {
    search --no-floppy --set=root --file /EFI/tools/KeyTool.efi
    chainloader /EFI/tools/KeyTool.efi
}

menuentry "Secure Boot HashTool" {
    search --no-floppy --set=root --file /EFI/tools/HashTool.efi
    chainloader /EFI/tools/HashTool.efi
}

menuentry "Enter Firmware Setup" {
    fwsetup
}

menuentry "System restart" {
	echo "System rebooting..."
	reboot
}

menuentry "System shutdown" {
	echo "System shutting down..."
	halt
}

menuentry "Exit GRUB" {
    exit
}
GRUBEOF
        ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
        grub-mkstandalone -d /usr/lib/grub/arm64-efi -O arm64-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd chain tpm" --fonts="unicode" --locales="" --themes="" -o "${_AARCH64}/EFI/BOOT/grubaa64.efi" "boot/grub/grub.cfg=${_AARCH64}/EFI/BOOT/grubaa64.cfg"
}

_prepare_bios_GRUB_USB_files() {
	
	mkdir -p "${_X86_64}/boot/grub"
	
	cat << GRUBEOF > "${_X86_64}/boot/grub/grub.cfg"
insmod part_gpt
insmod part_msdos
insmod fat

insmod video_bochs
insmod video_cirrus

insmod font

if loadfont "${prefix}/fonts/unicode.pf2" ; then
    insmod gfxterm
    set gfxmode="1366x768x32;1280x800x32;1024x768x32;auto"
    terminal_input console
    terminal_output gfxterm
fi

set default="Arch Linux aarch64 Archboot - BIOS Mode"
set timeout="10"

menuentry "Arch Linux aarch64 Archboot - BIOS Mode" {
    set gfxpayload=keep
    search --no-floppy --set=root --file /boot/vmlinuz_x86_64
    linux /boot/vmlinuz_x86_64 cgroup_disable=memory rootfstype=ramfs
    initrd /boot/intel-ucode.img  /boot/amd-ucode.img /boot/initramfs_x86_64.img
}

menuentry "System restart" {
	echo "System rebooting..."
	reboot
}

menuentry "System shutdown" {
	echo "System shutting down..."
	halt
}

menuentry "Exit GRUB" {
    exit
}
GRUBEOF
}

echo "Starting ISO creation ..."
echo "Prepare fedora shim ..."
_prepare_fedora_shim_bootloaders >/dev/null 2>&1

echo "Prepare kernel and initramfs ..."
_prepare_kernel_initramfs_files >/dev/null 2>&1

echo "Prepare efitools ..."
_prepare_efitools_uefi >/dev/null 2>&1

echo "Prepare AA64 Grub ..."
_prepare_uefi_AA64_GRUB_USB_files >/dev/null 2>&1

echo "Prepare BIOS Grub ..."
_prepare_bios_GRUB_USB_files >/dev/null 2>&1

echo "Prepare UEFI image ..."
_prepare_uefi_image >/dev/null 2>&1

## Generate the BIOS+ISOHYBRID+UEFI CD image using xorriso (extra/libisoburn package) in mkisofs emulation mode
grub-mkrescue --compress=xz --fonts="unicode" --product-name="Arch Linux ARCHBOOT" --product-version="${_RELEASENAME}" --locales="" --themes="" -o "${_IMAGENAME}.iso" "${_X86_64}"/  &> "${_IMAGENAME}.log"

## create sha256sums.txt
echo "Generating sha256sum ..."
rm -f "sha256sums.txt" || true
cksum -a sha256 *.iso > "sha256sums.txt"

# cleanup
echo "Cleanup remove ${_CORE64}, ${_AARCH64} and ${_SHIM} ..."
rm -rf "${_CORE64}"
rm -rf "${_AARCH64}"
rm -rf "${_SHIM}"
echo "Finished ISO creation."
