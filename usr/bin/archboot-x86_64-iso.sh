#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

[[ -z "${_DO_x86_64}" ]] && _DO_x86_64="1"
[[ -z "${WD}" ]] && WD="${PWD}/"

_BASENAME="$(basename "${0}")"

_CARCH="x86_64"
_UEFI_ARCH="X64"
_SPEC_UEFI_ARCH="x64"


usage () {
	echo "${_BASENAME}: usage"
	echo "CREATE X86_64 USB/CD IMAGES"
	echo "-----------------------------"
	echo "Run in archboot x86_64 chroot first ..."
	echo "archboot-x86_64-iso.sh -t"
	echo ""
	echo "PARAMETERS:"
	echo "  -t                  Start generation of tarball."
	echo "  -g                  Start generation of images."
	echo "  -i=IMAGENAME        Your IMAGENAME."
	echo "  -r=RELEASENAME      Use RELEASENAME in boot message."
	echo "  -k=KERNELNAME       Use KERNELNAME in boot message."
	echo "  -h                  This message."
	exit 0
}

[[ -z "${1}" ]] && usage


PRESET="/etc/archboot/presets/x86_64"
TARBALL_HELPER="/usr/bin/archboot-tarball-helper.sh"
UPDATEISO_HELPER="/usr/bin/archboot-update-iso.sh"

# change to english locale!
export LANG="en_US"

while [ $# -gt 0 ]; do
	case ${1} in
		-g|--g) GENERATE="1" ;;
		-t|--t) TARBALL="1" ;;
		-i=*|--i=*) IMAGENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
		-r=*|--r=*) RELEASENAME="$(echo ${1} | awk -F= '{print $2;}')" ;;
		-k=*|--k=*) KERNEL="$(echo ${1} | awk -F= '{print $2;}')" ;;
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

### check for available loop devices in a container
for i in $(seq 0 7); do
    ! [[ -e /dev/loop$i ]] && mknod /dev/loop$i b 7 $i
done
! [[ -e /dev/loop-control ]] && mknod /dev/loop-control c 10 237

if [[ "${TARBALL}" == "1" ]]; then
	"${TARBALL_HELPER}" -c="${PRESET}" -t="core-$(uname -m).tar"
	exit 0
fi

if ! [[ "${GENERATE}" == "1" ]]; then
	usage
fi

# set defaults, if nothing given
[[ -z "${KERNEL}" ]] && KERNEL="$(uname -r)"
[[ -z "${RELEASENAME}" ]] && RELEASENAME="2k21-R1"
[[ -z "${IMAGENAME}" ]] && IMAGENAME="Archlinux-$(date +%Y.%m)"

if [[ "${_DO_x86_64}" == "1" ]]; then
	IMAGENAME="${IMAGENAME}-x86_64"
fi

X86_64="$(mktemp -d /var/tmp/X86_64.XXX)"

# create directories
mkdir -p "${X86_64}/arch"
mkdir -p "${X86_64}/boot/syslinux"
mkdir -p "${X86_64}/packages/"

_merge_initramfs_files() {
	
	if [[ "${_DO_x86_64}" == "1" ]]; then
		mkdir -p "${CORE64}/var/tmp/initrd"
		cd "${CORE64}/var/tmp/initrd"
		
		bsdtar xf "${CORE64}/var/tmp"/*/boot/initrd.img
		
		cd  "${CORE64}/var/tmp/initrd"
		find . -print0 | bsdcpio -0oH newc | lzma > "${CORE64}/var/tmp/initramfs_x86_64.img"
	fi
	
	cd "${WD}/"
	
}

_prepare_kernel_initramfs_files() {
	
	if [[ "${_DO_x86_64}" == "1" ]]; then
		mv "${CORE64}/var/tmp"/*/boot/vmlinuz "${X86_64}/boot/vmlinuz_x86_64"
		mv "${CORE64}/var/tmp/initramfs_x86_64.img" "${X86_64}/boot/initramfs_x86_64.img"
	fi
		
	mv "${CORE64}/var/tmp"/*/boot/memtest "${X86_64}/boot/memtest"
	mv "${CORE64}/var/tmp"/*/boot/intel-ucode.img "${X86_64}/boot/intel-ucode.img"
	mv "${CORE64}/var/tmp"/*/boot/amd-ucode.img "${X86_64}/boot/amd-ucode.img"
	
}

_prepare_packages() {
	
	PACKAGES_TEMP_DIR="$(mktemp -d /var/tmp/pkgs_temp.XXX)"
	
	if [[ "${_DO_x86_64}" == "1" ]]; then
		CORE64="$(mktemp -d /var/tmp/core64.XXX)"
		
		tar xvf core-x86_64.tar -C "${CORE64}" || exit 1
		
		cp -rf "${CORE64}/var/tmp"/*/core-x86_64 "${PACKAGES_TEMP_DIR}/core-x86_64"
		rm -rf "${CORE64}/var/tmp"/*/core-x86_64
		mksquashfs "${PACKAGES_TEMP_DIR}/core-x86_64/" "${PACKAGES_TEMP_DIR}/archboot_packages_x86_64.squashfs" -comp xz -noappend -all-root
		mv "${PACKAGES_TEMP_DIR}/archboot_packages_x86_64.squashfs" "${X86_64}/packages/"
	fi
	
	# move in 'any' packages
	cp -rf "${CORE64}/var/tmp"/*/core-any "${PACKAGES_TEMP_DIR}/core-any"
	rm -rf "${CORE64}/var/tmp"/*/core-any
	mksquashfs "${PACKAGES_TEMP_DIR}/core-any/" "${PACKAGES_TEMP_DIR}/archboot_packages_any.squashfs" -comp xz -noappend -all-root
	
	cd "${WD}/"
	mv "${PACKAGES_TEMP_DIR}/archboot_packages_any.squashfs" "${X86_64}/packages/"
	
}

_prepare_other_files() {
	
	# move in doc
	mkdir -p "${X86_64}/arch/"
	mv "${CORE64}/var/tmp"/*/arch/archboot.txt "${X86_64}/arch/"
	
}

_download_uefi_shell_tianocore() {
	
	mkdir -p "${X86_64}/EFI/tools/"
	
	## Download Tianocore UDK/EDK2 ShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. >=2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${X86_64}/EFI/tools/shellx64_v2.efi" "https://raw.githubusercontent.com/tianocore/edk2/master/ShellBinPkg/UefiShell/X64/Shell.efi"
	
	## Download Tianocore UDK/EDK2 EdkShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. <2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${X86_64}/EFI/tools/shellx64_v1.efi" "https://raw.githubusercontent.com/tianocore/edk2/master/EdkShellBinPkg/FullShell/X64/Shell_Full.efi"
	
	## Download Tianocore UDK/EDK2 ShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. >=2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${X86_64}/EFI/tools/shellia32_v2.efi" "https://raw.githubusercontent.com/tianocore/edk2/master/ShellBinPkg/UefiShell/Ia32/Shell.efi"
	
	## Download Tianocore UDK/EDK2 EdkShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. <2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${X86_64}/EFI/tools/shellia32_v1.efi" "https://raw.githubusercontent.com/tianocore/edk2/master/EdkShellBinPkg/FullShell/Ia32/Shell_Full.efi"
	
}

_prepare_uefi_gummiboot_USB_files() {
	
	mkdir -p "${X86_64}/EFI/BOOT"
	cp -f "/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "${X86_64}/EFI/BOOT/loader.efi"
	
	mkdir -p "${X86_64}/loader/entries"
	
	cat << GUMEOF > "${X86_64}/loader/loader.conf"
timeout  4
default  default-*
GUMEOF
	
	cat << GUMEOF > "${X86_64}/loader/entries/archboot-x86_64-efistub.conf"
title           Arch Linux x86_64 Archboot EFISTUB
linux           /boot/vmlinuz_x86_64
initrd          /boot/intel-ucode.img
initrd          /boot/amd-ucode.img
initrd          /boot/initramfs_x86_64.img
options         cgroup_disable=memory add_efi_memmap _X64_UEFI=1 rootfstype=ramfs
architecture    x64
GUMEOF
	
	cat << GUMEOF > "${X86_64}/loader/entries/uefi-shell-x64-v2.conf"
title           UEFI Shell X64 v2
efi             /EFI/tools/shellx64_v2.efi
architecture    x64
GUMEOF
	
	cat << GUMEOF > "${X86_64}/loader/entries/uefi-shell-x64-v1.conf"
title           UEFI Shell X64 v1
efi             /EFI/tools/shellx64_v1.efi
architecture    x64
GUMEOF
	
	cat << GUMEOF > "${X86_64}/loader/entries/grub-x64-gummiboot.conf"
title           GRUB X64 - if EFISTUB boot fails
efi             /EFI/grub/grubx64.efi
architecture    x64
GUMEOF
	
	mv "${X86_64}/loader/entries/archboot-x86_64-efistub.conf" "${X86_64}/loader/entries/default-x64.conf"
	
}

_prepare_uefi_X64_GRUB_USB_files() {
	
	mkdir -p "${X86_64}/EFI/grub"
	
	echo 'configfile ${cmdpath}/grubx64.cfg' > /var/tmp/grubx64.cfg
	grub-mkstandalone -d /usr/lib/grub/x86_64-efi/ -O x86_64-efi --modules="part_gpt part_msdos" --fonts="unicode" --locales="en@quot" --themes="" -o "${X86_64}/EFI/grub/grubx64.efi" "boot/grub/grub.cfg=/var/tmp/grubx64.cfg" -v
	
	cat << GRUBEOF > "${X86_64}/EFI/grub/grubx64.cfg"
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

set default="Arch Linux x86_64 Archboot Non-EFISTUB"
set timeout="2"

menuentry "Arch Linux x86_64 Archboot Non-EFISTUB" {
    set gfxpayload=keep
    search --no-floppy --set=root --file /boot/vmlinuz_x86_64
    linux /boot/vmlinuz_x86_64 cgroup_disable=memory add_efi_memmap _X64_UEFI=1 rootfstype=ramfs
    initrd /boot/intel-ucode.img  /boot/amd-ucode.img /boot/initramfs_x86_64.img
}

menuentry "UEFI Shell X64 v2" {
    search --no-floppy --set=root --file /EFI/tools/shellx64_v2.efi
    chainloader /EFI/tools/shellx64_v2.efi
}

menuentry "UEFI Shell X64 v1" {
    search --no-floppy --set=root --file /EFI/tools/shellx64_v1.efi
    chainloader /EFI/tools/shellx64_v1.efi
}

menuentry "Exit GRUB" {
    exit
}
GRUBEOF
	
}

_prepare_uefi_IA32_GRUB_USB_files() {
	
	mkdir -p "${X86_64}/EFI/BOOT"
	
	echo 'configfile ${cmdpath}/bootia32.cfg' > /var/tmp/bootia32.cfg
	grub-mkstandalone -d /usr/lib/grub/i386-efi/ -O i386-efi --modules="part_gpt part_msdos" --fonts="unicode" --locales="en@quot" --themes="" -o "${X86_64}/EFI/BOOT/BOOTIA32.EFI" "boot/grub/grub.cfg=/var/tmp/bootia32.cfg" -v
	
	cat << GRUBEOF > "${X86_64}/EFI/BOOT/bootia32.cfg"
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
set timeout="2"

menuentry "Arch Linux x86_64 Archboot - EFI MIXED MODE" {
    set gfxpayload=keep
    search --no-floppy --set=root --file /boot/vmlinuz_x86_64
    linux /boot/vmlinuz_x86_64 cgroup_disable=memory add_efi_memmap _IA32_UEFI=1 rootfstype=ramfs
    initrd /boot/intel-ucode.img  /boot/amd-ucode.img /boot/initramfs_x86_64.img
}

# menuentry "Syslinux for x86_64 Kernel in IA32 UEFI" {
    # search --no-floppy --set=root --file /EFI/syslinux/efi32/syslinux.efi
    # chainloader /EFI/syslinux/efi32/syslinux.efi
# }

menuentry "UEFI Shell IA32 v2" {
    search --no-floppy --set=root --file /EFI/tools/shellia32_v2.efi
    chainloader /EFI/tools/shellia32_v2.efi
}

menuentry "UEFI Shell IA32 v1" {
    search --no-floppy --set=root --file /EFI/tools/shellia32_v1.efi
    chainloader /EFI/tools/shellia32_v1.efi
}

menuentry "Exit GRUB" {
    exit
}
GRUBEOF
	
}

_prepare_uefi_IA32_syslinux_USB_files() {
	
	mkdir -p "${X86_64}/EFI/syslinux"
	cp -rf "/usr/lib/syslinux/efi32" "${X86_64}/EFI/syslinux/efi32"
	
	cat << EOF > "${X86_64}/EFI/syslinux/efi32/syslinux.cfg"
PATH /EFI/syslinux/efi32

# UI vesamenu.c32
UI menu.c32

DEFAULT archboot-x86_64

PROMPT 1
TIMEOUT 40

MENU TITLE SYSLINUX
MENU RESOLUTION 1280 800

LABEL archboot-x86_64
    MENU LABEL Arch Linux x86_64 Archboot - EFI MIXED MODE
    LINUX /boot/vmlinuz_x86_64
    APPEND cgroup_disable=memory add_efi_memmap _IA32_UEFI=1 rootfstype=ramfs
    INITRD /boot/intel-ucode.img,/boot/amd-ucode.img,/boot/initramfs_x86_64.img
EOF

}

_prepare_packages

_prepare_other_files

_merge_initramfs_files

_prepare_kernel_initramfs_files

_download_uefi_shell_tianocore

_prepare_uefi_gummiboot_USB_files

_prepare_uefi_X64_GRUB_USB_files

_prepare_uefi_IA32_GRUB_USB_files

# _prepare_uefi_IA32_syslinux_USB_files

# place syslinux files
mv "${CORE64}/var/tmp"/*/boot/syslinux/* "${X86_64}/boot/syslinux/"

# Change parameters in boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/ISOLINUX/g" "${X86_64}/boot/syslinux/boot.msg"

cd "${WD}/"

## Generate the BIOS+ISOHYBRID CD image using xorriso (extra/libisoburn package) in mkisofs emulation mode
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
        -output "${IMAGENAME}.iso" "${X86_64}/" &> "/var/tmp/archboot_allinone_xorriso.log"

# create x86_64 iso with uefi cd boot support, if not present
if [[ -e "${WD}/${IMAGENAME}.iso" ]] && [[ ! -e "${WD}/${IMAGENAME}-uefi.iso" ]]; then
	_UPDATE_CD_UEFI="1" _REMOVE_x86_64="0" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME}.iso"
	mv "${WD}/${IMAGENAME}-updated-dual-uefi.iso" "${WD}/${IMAGENAME}-uefi.iso"
fi

# create x86_64 network iso with uefi cd boot support, if not present
if [[ -e "${WD}/${IMAGENAME}.iso" ]] && [[ ! -e "${WD}/${IMAGENAME}-uefi-network.iso" ]]; then
	_REMOVE_PACKAGES="1" _UPDATE_CD_UEFI="1" _REMOVE_x86_64="0" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME}.iso"
	mv "${WD}/${IMAGENAME}-updated-dual-uefi-network.iso" "${WD}/${IMAGENAME}-uefi-network.iso"
fi

# create x86_64 network iso, if not present
if [[ -e "${WD}/${IMAGENAME}.iso" ]] && [[ ! -e "${WD}/${IMAGENAME}-network.iso" ]]; then
	_REMOVE_PACKAGES="1" _REMOVE_x86_64="0" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME}.iso"
	mv "${WD}/${IMAGENAME}-updated-dual-network.iso" "${WD}/${IMAGENAME}-network.iso"
fi

## create sha256sums.txt
cd "${WD}/"
rm -f "${WD}/sha256sums.txt" || true
sha256sum *.iso > "${WD}/sha256sums.txt"

# cleanup
rm -rf "${CORE64}"
rm -rf "${CORE64}"
rm -rf "${PACKAGES_TEMP_DIR}"
rm -rf "${X86_64}"
