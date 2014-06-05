#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

[[ -z "${_DO_x86_64}" ]] && _DO_x86_64="1"
[[ -z "${_DO_i686}" ]] && _DO_i686="1"

[[ -z "${WD}" ]] && WD="${PWD}/"

_BASENAME="$(basename "${0}")"

[[ -z "${_CARCH}" ]] && _CARCH="x86_64"

if [[ "${_CARCH}" == "x86_64" ]]; then
	_UEFI_ARCH="X64"
	_SPEC_UEFI_ARCH="x64"
else
	_UEFI_ARCH="IA32"
	_SPEC_UEFI_ARCH="ia32"
fi

usage () {
	echo "${_BASENAME}: usage"
	echo "CREATE ALLINONE USB/CD IMAGES"
	echo "-----------------------------"
	echo "Run in archboot x86_64 chroot first ..."
	echo "archboot-allinone.sh -t"
	echo "Run in archboot 686 chroot then ..."
	echo "archboot-allinone.sh -t"
	echo "Copy the generated tarballs to your favorite directory and run:"
	echo "${_BASENAME} -g <any other option>"
	echo ""
	echo "PARAMETERS:"
	echo "  -g                  Start generation of images."
	echo "  -i=IMAGENAME        Your IMAGENAME."
	echo "  -r=RELEASENAME      Use RELEASENAME in boot message."
	echo "  -k=KERNELNAME       Use KERNELNAME in boot message."
	echo "  -h                  This message."
	exit 0
}

[[ -z "${1}" ]] && usage

ALLINONE_PRESET="/etc/archboot/presets/allinone"
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
	"${TARBALL_HELPER}" -c="${ALLINONE_PRESET}" -t="core-$(uname -m).tar"
	exit 0
fi

if ! [[ "${GENERATE}" == "1" ]]; then
	usage
fi

# set defaults, if nothing given
[[ -z "${KERNEL}" ]] && KERNEL="$(uname -r)"
[[ -z "${RELEASENAME}" ]] && RELEASENAME="2k14-R2"
[[ -z "${IMAGENAME}" ]] && IMAGENAME="Archlinux-allinone-$(date +%Y.%m)"

IMAGENAME_OLD="${IMAGENAME}"

if [[ "${_DO_x86_64}" == "1" ]] && [[ "${_DO_i686}" == "1" ]]; then
	IMAGENAME="${IMAGENAME}-dual"
fi

if [[ "${_DO_x86_64}" == "1" ]] && [[ "${_DO_i686}" != "1" ]]; then
	IMAGENAME="${IMAGENAME}-x86_64"
fi

if [[ "${_DO_x86_64}" != "1" ]] && [[ "${_DO_i686}" == "1" ]]; then
	IMAGENAME="${IMAGENAME}-i686"
fi

ALLINONE="$(mktemp -d /tmp/allinone.XXX)"

# create directories
mkdir -p "${ALLINONE}/arch"
mkdir -p "${ALLINONE}/boot/syslinux"
mkdir -p "${ALLINONE}/packages/"

_merge_initramfs_files() {
	
	if [[ "${_DO_x86_64}" == "1" ]]; then
		mkdir -p "${CORE64}/tmp/initrd"
		cd "${CORE64}/tmp/initrd"
		
		bsdtar xf "${CORE64}/tmp"/*/boot/initrd.img
		
		cd  "${CORE64}/tmp/initrd"
		find . -print0 | bsdcpio -0oH newc | lzma > "${CORE64}/tmp/initramfs_x86_64.img"
	fi
	
	if [[ "${_DO_i686}" == "1" ]]; then
		mkdir -p "${CORE}/tmp/initrd"
		cd "${CORE}/tmp/initrd"
		
		bsdtar xf "${CORE}/tmp"/*/boot/initrd.img
		
		cd  "${CORE}/tmp/initrd"
		find . -print0 | bsdcpio -0oH newc | lzma > "${CORE}/tmp/initramfs_i686.img"
	fi
	
	cd "${WD}/"
	
}

_prepare_kernel_initramfs_files() {
	
	if [[ "${_DO_x86_64}" == "1" ]]; then
		mv "${CORE64}/tmp"/*/boot/vmlinuz "${ALLINONE}/boot/vmlinuz_x86_64"
		mv "${CORE64}/tmp/initramfs_x86_64.img" "${ALLINONE}/boot/initramfs_x86_64.img"
	fi
	
	if [[ "${_DO_i686}" == "1" ]]; then
		mv "${CORE}/tmp"/*/boot/vmlinuz "${ALLINONE}/boot/vmlinuz_i686"
		mv "${CORE}/tmp/initramfs_i686.img" "${ALLINONE}/boot/initramfs_i686.img"
	fi
	
	mv "${CORE}/tmp"/*/boot/memtest "${ALLINONE}/boot/memtest"
	
}

_prepare_packages() {
	
	PACKAGES_TEMP_DIR="$(mktemp -d /tmp/pkgs_temp.XXX)"
	
	if [[ "${_DO_x86_64}" == "1" ]]; then
		CORE64="$(mktemp -d /tmp/core64.XXX)"
		
		tar xvf core-x86_64.tar -C "${CORE64}" || exit 1
		
		cp -rf "${CORE64}/tmp"/*/core-x86_64 "${PACKAGES_TEMP_DIR}/core-x86_64"
		rm -rf "${CORE64}/tmp"/*/core-x86_64
		mksquashfs "${PACKAGES_TEMP_DIR}/core-x86_64/" "${PACKAGES_TEMP_DIR}/archboot_packages_x86_64.squashfs" -comp xz -noappend -all-root
		mv "${PACKAGES_TEMP_DIR}/archboot_packages_x86_64.squashfs" "${ALLINONE}/packages/"
	fi
	
	if [[ "${_DO_i686}" == "1" ]]; then
		CORE="$(mktemp -d /tmp/core.XXX)"
		
		tar xvf core-i686.tar -C "${CORE}" || exit 1
		
		cp -rf "${CORE}/tmp"/*/core-i686 "${PACKAGES_TEMP_DIR}/core-i686"
		rm -rf "${CORE}/tmp"/*/core-i686
		mksquashfs "${PACKAGES_TEMP_DIR}/core-i686/" "${PACKAGES_TEMP_DIR}/archboot_packages_i686.squashfs" -comp xz -noappend -all-root
		mv "${PACKAGES_TEMP_DIR}/archboot_packages_i686.squashfs" "${ALLINONE}/packages/"
	fi
	
	# move in 'any' packages
	cp -rf "${CORE}/tmp"/*/core-any "${PACKAGES_TEMP_DIR}/core-any"
	rm -rf "${CORE}/tmp"/*/core-any
	mksquashfs "${PACKAGES_TEMP_DIR}/core-any/" "${PACKAGES_TEMP_DIR}/archboot_packages_any.squashfs" -comp xz -noappend -all-root
	
	cd "${WD}/"
	mv "${PACKAGES_TEMP_DIR}/archboot_packages_any.squashfs" "${ALLINONE}/packages/"
	
}

_prepare_other_files() {
	
	# move in doc
	mkdir -p "${ALLINONE}/arch/"
	mv "${CORE}/tmp"/*/arch/archboot.txt "${ALLINONE}/arch/"
	
}

_download_uefi_shell_tianocore() {
	
	mkdir -p "${ALLINONE}/EFI/tools/"
	
	## Download Tianocore UDK/EDK2 ShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. >=2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${ALLINONE}/EFI/tools/shellx64_v2.efi" "https://svn.code.sf.net/p/edk2/code/trunk/edk2/ShellBinPkg/UefiShell/X64/Shell.efi"
	
	## Download Tianocore UDK/EDK2 EdkShellBinPkg UEFI X64 "Full Shell" - For UEFI Spec. <2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${ALLINONE}/EFI/tools/shellx64_v1.efi" "https://svn.code.sf.net/p/edk2/code/trunk/edk2/EdkShellBinPkg/FullShell/X64/Shell_Full.efi"
	
	## Download Tianocore UDK/EDK2 ShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. >=2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${ALLINONE}/EFI/tools/shellia32_v2.efi" "https://svn.code.sf.net/p/edk2/code/trunk/edk2/ShellBinPkg/UefiShell/Ia32/Shell.efi"
	
	## Download Tianocore UDK/EDK2 EdkShellBinPkg UEFI IA32 "Full Shell" - For UEFI Spec. <2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${ALLINONE}/EFI/tools/shellia32_v1.efi" "https://svn.code.sf.net/p/edk2/code/trunk/edk2/EdkShellBinPkg/FullShell/Ia32/Shell_Full.efi"
	
}

_prepare_uefi_gummiboot_USB_files() {
	
	mkdir -p "${ALLINONE}/EFI/boot"
	cp -f "/usr/lib/gummiboot/gummibootx64.efi" "${ALLINONE}/EFI/boot/loader.efi"
	cp -f "/usr/lib/gummiboot/gummibootia32.efi" "${ALLINONE}/EFI/boot/bootia32.efi"
	
	mkdir -p "${ALLINONE}/loader/entries"
	
	cat << GUMEOF > "${ALLINONE}/loader/loader.conf"
timeout  5
default  default*
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/archboot-x86_64-efistub.conf"
title           Arch Linux x86_64 Archboot EFISTUB
linux           /boot/vmlinuz_x86_64
initrd          /boot/initramfs_x86_64.img
options         cgroup_disable=memory loglevel=7 add_efi_memmap _X64_UEFI=1
architecture    x64
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/archboot-i686-efistub.conf"
title           Arch Linux i686 Archboot EFISTUB
linux           /boot/vmlinuz_i686
initrd          /boot/initramfs_i686.img
options         cgroup_disable=memory loglevel=7 add_efi_memmap _IA32_UEFI=1
architecture    ia32
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/uefi-shell-x64-v2.conf"
title           UEFI Shell X64 v2
efi             /EFI/tools/shellx64_v2.efi
architecture    x64
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/uefi-shell-x64-v1.conf"
title           UEFI Shell X64 v1
efi             /EFI/tools/shellx64_v1.efi
architecture    x64
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/uefi-shell-ia32-v2.conf"
title           UEFI Shell IA32 v2
efi             /EFI/tools/shellia32_v2.efi
architecture    ia32
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/uefi-shell-ia32-v1.conf"
title           UEFI Shell IA32 v1
efi             /EFI/tools/shellia32_v1.efi
architecture    ia32
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/grub-x64-gummiboot.conf"
title           GRUB X64 - if EFISTUB boot fails
efi             /EFI/grub/grubx64.efi
architecture    x64
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/syslinux-ia32-gummiboot.conf"
title           Syslinux IA32 - for x86_64 kernel boot
efi             /EFI/syslinux/efi32/syslinux.efi
architecture    ia32
GUMEOF
	
	mv "${ALLINONE}/loader/entries/archboot-x86_64-efistub.conf" "${ALLINONE}/loader/entries/default-x64.conf"
	mv "${ALLINONE}/loader/entries/syslinux-ia32-gummiboot.conf" "${ALLINONE}/loader/entries/default-ia32.conf"
	
}

_prepare_uefi_X64_GRUB_USB_files() {
	
	mkdir -p "${ALLINONE}/EFI/grub"
	
	echo 'configfile ${cmdpath}/grubx64.cfg' > /tmp/grubx64.cfg
	grub-mkstandalone -d /usr/lib/grub/x86_64-efi/ -O x86_64-efi --modules="part_gpt part_msdos" --fonts="unicode" --locales="en@quot" --themes="" -o "${ALLINONE}/EFI/grub/grubx64.efi"  "/boot/grub/grub.cfg=/tmp/grubx64.cfg" -v
	
	cat << GRUBEOF > "${ALLINONE}/EFI/grub/grubx64.cfg"
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

menuentry "Arch Linux x86_64 Archboot Non-EFISTUB" {
    set gfxpayload=keep
    search --no-floppy --set=root --file /boot/vmlinuz_x86_64
    linux /boot/vmlinuz_x86_64 cgroup_disable=memory loglevel=7 add_efi_memmap _X64_UEFI=1
    initrd /boot/initramfs_x86_64.img
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

_prepare_uefi_IA32_syslinux_USB_files() {
	
	mkdir -p "${ALLINONE}/EFI/syslinux"
	cp -rf "/usr/lib/syslinux/efi32" "${ALLINONE}/EFI/syslinux/efi32"
	
	cat << EOF > "${ALLINONE}/EFI/syslinux/efi32/syslinux.cfg"
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
    APPEND cgroup_disable=memory loglevel=7 add_efi_memmap _IA32_UEFI=1
    INITRD /boot/initramfs_x86_64.img

LABEL archboot-i686
    MENU LABEL Arch Linux i686 Archboot - EFI HANDOVER PROTOCOL
    LINUX /boot/vmlinuz_i686
    APPEND cgroup_disable=memory loglevel=7 add_efi_memmap _IA32_UEFI=1
    INITRD /boot/initramfs_i686.img
EOF
	
}

_prepare_packages

_prepare_other_files

_merge_initramfs_files

_prepare_kernel_initramfs_files

_download_uefi_shell_tianocore

_prepare_uefi_gummiboot_USB_files

_prepare_uefi_X64_GRUB_USB_files

_prepare_uefi_IA32_syslinux_USB_files

# place syslinux files
mv "${CORE}/tmp"/*/boot/syslinux/* "${ALLINONE}/boot/syslinux/"

# Change parameters in boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/ISOLINUX/g" "${ALLINONE}/boot/syslinux/boot.msg"

cd "${WD}/"

## Generate the BIOS+ISOHYBRID CD image using xorriso (extra/libisoburn package) in mkisofs emulation mode
echo "Generating ALLINONE hybrid ISO ..."
xorriso -as mkisofs \
        -iso-level 3 -rock -joliet \
        -max-iso9660-filenames -omit-period \
        -omit-version-number -allow-leading-dots \
        -relaxed-filenames -allow-lowercase -allow-multidot \
        -volid "ARCHBOOT" \
        -preparer "prepared by ${_BASENAME}" \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -isohybrid-mbr /usr/lib/syslinux/bios/isohdpfx.bin \
        --sort-weight 1 boot/syslinux/isolinux.bin \
        -output "${IMAGENAME}.iso" "${ALLINONE}/" &> "/tmp/archboot_allinone_xorriso.log"

# create x86_64 iso, if not present
if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-x86_64.iso" ]]; then
	_REMOVE_i686="1" _REMOVE_x86_64="0" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-x86_64.iso" "${WD}/${IMAGENAME_OLD}-x86_64.iso"
fi

# create i686 iso, if not present
if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-i686.iso" ]]; then
	_REMOVE_i686="0" _REMOVE_x86_64="1" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-i686.iso" "${WD}/${IMAGENAME_OLD}-i686.iso"
fi

# create i686 network iso, if not present
if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-i686-network.iso" ]]; then
	_REMOVE_PACKAGES="1" _REMOVE_i686="0" _REMOVE_x86_64="1" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-i686-network.iso" "${WD}/${IMAGENAME_OLD}-i686-network.iso"
fi

# create dual iso with uefi cd boot support, if not present
if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-dual-uefi.iso" ]]; then
	_UPDATE_CD_UEFI="1" _REMOVE_i686="0" _REMOVE_x86_64="0" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-dual-uefi.iso" "${WD}/${IMAGENAME_OLD}-dual-uefi.iso"
fi

# create dual network iso with uefi cd boot support, if not present
if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-dual-uefi-network.iso" ]]; then
	_REMOVE_PACKAGES="1" _UPDATE_CD_UEFI="1" _REMOVE_i686="0" _REMOVE_x86_64="0" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-dual-uefi-network.iso" "${WD}/${IMAGENAME_OLD}-dual-uefi-network.iso"
fi

# create dual network iso, if not present
if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-dual-network.iso" ]]; then
	_REMOVE_PACKAGES="1" _REMOVE_i686="0" _REMOVE_x86_64="0" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-dual-network.iso" "${WD}/${IMAGENAME_OLD}-dual-network.iso"
fi

# create x86_64 iso with uefi cd boot support, if not present
if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-x86_64-uefi.iso" ]]; then
	_UPDATE_CD_UEFI="1" _REMOVE_i686="1" _REMOVE_x86_64="0" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-x86_64-uefi.iso" "${WD}/${IMAGENAME_OLD}-x86_64-uefi.iso"
fi

# create x86_64 network iso with uefi cd boot support, if not present
if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-x86_64-uefi-network.iso" ]]; then
	_REMOVE_PACKAGES="1" _UPDATE_CD_UEFI="1" _REMOVE_i686="1" _REMOVE_x86_64="0" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-x86_64-uefi-network.iso" "${WD}/${IMAGENAME_OLD}-x86_64-uefi-network.iso"
fi

# create x86_64 network iso, if not present
if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-x86_64-network.iso" ]]; then
	_REMOVE_PACKAGES="1" _REMOVE_i686="1" _REMOVE_x86_64="0" _UPDATE_UEFI_SHELL="0" _UPDATE_SYSLINUX_BIOS_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-x86_64-network.iso" "${WD}/${IMAGENAME_OLD}-x86_64-network.iso"
fi

## create sha256sums.txt
cd "${WD}/"
rm -f "${WD}/sha256sums.txt" || true
sha256sum *.iso > "${WD}/sha256sums.txt"

# cleanup
rm -rf "${CORE}"
rm -rf "${CORE64}"
rm -rf "${PACKAGES_TEMP_DIR}"
rm -rf "${ALLINONE}"
