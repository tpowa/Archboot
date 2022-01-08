#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
AARCH64="$(mktemp -d AARCH64.XXX)"
_SHIM_URL="https://kojipkgs.fedoraproject.org/packages/shim/15.4/5/aarch64"
_SHIM_VERSION="shim-aa64-15.4-5.aarch64.rpm"


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
[[ -z "${PRESET}" ]] && PRESET="aarch64"
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
    local offset=$(hexdump -s 526 -n 2 -e '"%0d"' "/boot/Image.gz")
    [[ $offset = +([0-9]) ]] || return 1

    read kver _ < \
        <(dd if="/boot/Image.gz" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)

    [[ $kver =~ $re ]] || return 1

    KERNEL="$(printf '%s' "$kver")"
}

# set defaults, if nothing given
[[ -z "${KERNEL}" ]] && kver
[[ -z "${RELEASENAME}" ]] && RELEASENAME="$(date +%Y.%m.%d-%H.%M)"
[[ -z "${IMAGENAME}" ]] && IMAGENAME="archlinux-archboot-${RELEASENAME}-aarch64"

if [[ "${TARBALL}" == "1" ]]; then
        # fix for mkinitcpio 31
        # https://bugs.archlinux.org/task/72882
        # remove on mkinitcpio 32 release
        cp "/usr/lib/initcpio/functions" "/usr/lib/initcpio/functions.old"
        [[ -f "/usr/share/archboot/patches/31-initcpio.functions.fixed" ]] && cp "/usr/share/archboot/patches/31-initcpio.functions.fixed" "/usr/lib/initcpio/functions"
	"${TARBALL_HELPER}" -c="${PRESET}" -t="${IMAGENAME}.tar"
	mv "/usr/lib/initcpio/functions.old" "/usr/lib/initcpio/functions"
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

mkdir -p "${AARCH64}/EFI/BOOT"

_prepare_kernel_initramfs_files() {

	mkdir -p "${AARCH64}/boot"
        mv "${CORE64}"/*/boot/vmlinuz "${AARCH64}/boot/vmlinuz_aarch64"
        mv "${CORE64}"/*/boot/initrd.img "${AARCH64}/boot/initramfs_aarch64.img"
	mv "${CORE64}"/*/boot/amd-ucode.img "${AARCH64}/boot/"
	mv "${CORE64}"/*/boot/dtbs  "${AARCH64}/boot/"
        
}

_prepare_efitools_uefi () {
    cp -f "/usr/share/efitools/efi/HashTool.efi" "${AARCH64}/EFI/tools/HashTool.efi"
    cp -f "/usr/share/efitools/efi/KeyTool.efi" "${AARCH64}/EFI/tools/KeyTool.efi"
}

_prepare_fedora_shim_bootloaders () {
    # Details on shim https://www.rodsbooks.com/efi-bootloaders/secureboot.html#initial_shim
    # add shim aa64 signed files from fedora
    SHIM=$(mktemp -d shim.XXXX)
    curl -s --create-dirs -L -O --output-dir "${SHIM}" "${_SHIM_URL}/${_SHIM_VERSION}"
    bsdtar -C "${SHIM}" -xf "${SHIM}"/"${_SHIM_VERSION}"
    cp "${SHIM}/boot/efi/EFI/fedora/mmaa64.efi" "${AARCH64}/EFI/BOOT/mmaa64.efi"
    cp "${SHIM}/boot/efi/EFI/fedora/shimaa64.efi" "${AARCH64}/EFI/BOOT/BOOTAA64.efi"
}

_prepare_uefi_image() {
        
        ## get size of boot x86_64 files
	BOOTSIZE=$(du -bc ${AARCH64}/EFI | grep total | cut -f1)
	IMGSZ=$(( (${BOOTSIZE}*102)/100/1024 + 1)) # image size in sectors
	
	mkdir -p "${AARCH64}"/CDEFI/
	
	## Create cdefiboot.img
	dd if=/dev/zero of="${AARCH64}"/CDEFI/cdefiboot.img bs="${IMGSZ}" count=1024
	VFAT_IMAGE="${AARCH64}/CDEFI/cdefiboot.img"
	mkfs.vfat "${VFAT_IMAGE}"
	
	## Copy all files to UEFI vfat image
	mcopy -i "${VFAT_IMAGE}" -s "${AARCH64}"/EFI ::/
	
}


# build grubXXX with all modules: http://bugs.archlinux.org/task/71382
# If you don't use shim use --disable-shim-lock
_prepare_uefi_AA64_GRUB_USB_files() {
	
	mkdir -p "${AARCH64}/EFI/BOOT"
	cat << GRUBEOF > "${AARCH64}/EFI/BOOT/grubaa64.cfg"
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

menuentry "Exit GRUB" {
    exit
}
GRUBEOF
        ### Hint: https://src.fedoraproject.org/rpms/grub2/blob/rawhide/f/grub.macros#_407
        grub-mkstandalone -d /usr/lib/grub/arm64-efi -O arm64-efi --sbat=/usr/share/grub/sbat.csv --modules="all_video boot btrfs cat configfile cryptodisk echo efi_gop efifwsetup efinet ext2 f2fs fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http iso9660 loadenv loopback linux lvm lsefi lsefimmap luks luks2 mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp video xfs zstd chain tpm" --fonts="unicode" --locales="en@quot" --themes="" -o "${AARCH64}/EFI/BOOT/grubaa64.efi" "boot/grub/grub.cfg=${AARCH64}/EFI/BOOT/grubaa64.cfg"
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

echo "Prepare UEFI image ..."
_prepare_uefi_image >/dev/null 2>&1

## Generate the BIOS+ISOHYBRID+UEFI CD image using xorriso (extra/libisoburn package) in mkisofs emulation mode
echo "Generating AARCH64 hybrid ISO ..."
xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "ARCHBOOT" \
        -preparer "prepared by ${_BASENAME}" \
        -e CDEFI/cdefiboot.img -isohybrid-gpt-basdat -no-emul-boot \
        -output "${IMAGENAME}.iso" "${AARCH64}/" &> "${IMAGENAME}.log"
## create sha256sums.txt
echo "Generating sha256sum ..."
rm -f "sha256sums.txt" || true
cksum -a sha256 *.iso > "sha256sums.txt"

# cleanup
echo "Cleanup remove ${CORE64}, ${AARCH64} and ${SHIM} ..."
rm -rf "${CORE64}"
rm -rf "${AARCH64}"
rm -rf "${SHIM}"
echo "Finished ISO creation."
