#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

[[ -z "${_DO_x86_64}" ]] && _DO_x86_64="1"
[[ -z "${_DO_i686}" ]] && _DO_i686="1"

[[ -z "${WD}" ]] && WD="${PWD}/"

_BASENAME="$(basename "${0}")"

[[ -z "${_UEFI_ARCH}" ]] && _UEFI_ARCH="x86_64"

[[ "${_UEFI_ARCH}" == "x86_64" ]] && _SPEC_UEFI_ARCH="x64"
[[ "${_UEFI_ARCH}" == "i386" ]] && _SPEC_UEFI_ARCH="ia32"

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
	echo "  -lts=LTSKERNELNAME  Use LTSKERNELNAME in boot message."
	echo "  -h                  This message."
	exit 0
}

[[ -z "${1}" ]] && usage

ALLINONE_PRESET="/etc/archboot/presets/allinone"
ALLINONE_LTS_PRESET="/etc/archboot/presets/allinone-lts"
TARBALL_HELPER="/usr/bin/archboot-tarball-helper.sh"
USBIMAGE_HELPER="/usr/bin/archboot-usbimage-helper.sh"
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
		-lts=*|--lts=*) LTS_KERNEL="$(echo ${1} | awk -F= '{print $2;}')" ;;
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

if [[ "${TARBALL}" == "1" ]]; then
	"${TARBALL_HELPER}" -c="${ALLINONE_PRESET}" -t="core-$(uname -m).tar"
	"${TARBALL_HELPER}" -c="${ALLINONE_LTS_PRESET}" -t="core-lts-$(uname -m).tar"
	exit 0
fi

if ! [[ "${GENERATE}" == "1" ]]; then
	usage
fi

# set defaults, if nothing given
[[ -z "${KERNEL}" ]] && KERNEL="$(uname -r)"
[[ -z "${LTS_KERNEL}" ]] && LTS_KERNEL="$(cat /lib/modules/extramodules-3.0-lts/version)"
[[ -z "${RELEASENAME}" ]] && RELEASENAME="2k13-R2"
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
		bsdtar xf "${CORE64_LTS}/tmp"/*/boot/initrd.img
		
		cd  "${CORE64}/tmp/initrd"
		find . -print0 | bsdcpio -0oH newc | lzma > "${CORE64}/tmp/initramfs_x86_64.img"
	fi
	
	if [[ "${_DO_i686}" == "1" ]]; then
		mkdir -p "${CORE}/tmp/initrd"
		cd "${CORE}/tmp/initrd"
		
		bsdtar xf "${CORE}/tmp"/*/boot/initrd.img
		bsdtar xf "${CORE_LTS}/tmp"/*/boot/initrd.img
		
		cd  "${CORE}/tmp/initrd"
		find . -print0 | bsdcpio -0oH newc | lzma > "${CORE}/tmp/initramfs_i686.img"
	fi
	
	cd "${WD}/"
	
}

_prepare_kernel_initramfs_files() {
	
	if [[ "${_DO_x86_64}" == "1" ]]; then
		mv "${CORE64}/tmp"/*/boot/vmlinuz "${ALLINONE}/boot/vmlinuz_x86_64"
		mv "${CORE64_LTS}/tmp"/*/boot/vmlinuz "${ALLINONE}/boot/vmlinuz_x86_64_lts"
		mv "${CORE64}/tmp/initramfs_x86_64.img" "${ALLINONE}/boot/initramfs_x86_64.img"
	fi
	
	if [[ "${_DO_i686}" == "1" ]]; then
		mv "${CORE}/tmp"/*/boot/vmlinuz "${ALLINONE}/boot/vmlinuz_i686"
		mv "${CORE_LTS}/tmp"/*/boot/vmlinuz "${ALLINONE}/boot/vmlinuz_i686_lts"
		mv "${CORE}/tmp/initramfs_i686.img" "${ALLINONE}/boot/initramfs_i686.img"
	fi
	
	mv "${CORE}/tmp"/*/boot/memtest "${ALLINONE}/boot/memtest"
	
}

_prepare_packages() {
	
	PACKAGES_TEMP_DIR="$(mktemp -d /tmp/pkgs_temp.XXX)"
	
	if [[ "${_DO_x86_64}" == "1" ]]; then
		CORE64="$(mktemp -d /tmp/core64.XXX)"
		CORE64_LTS="$(mktemp -d /tmp/core64-lts.XXX)"
		
		tar xvf core-x86_64.tar -C "${CORE64}" || exit 1
		tar xvf core-lts-x86_64.tar -C "${CORE64_LTS}" || exit 1
		
		cp -rf "${CORE64_LTS}/tmp"/*/core-x86_64 "${PACKAGES_TEMP_DIR}/core-x86_64"
		rm -rf "${CORE64_LTS}/tmp"/*/core-x86_64
		mksquashfs "${PACKAGES_TEMP_DIR}/core-x86_64/" "${PACKAGES_TEMP_DIR}/archboot_packages_x86_64.squashfs" -comp xz -noappend -all-root
		mv "${PACKAGES_TEMP_DIR}/archboot_packages_x86_64.squashfs" "${ALLINONE}/packages/"
	fi
	
	if [[ "${_DO_i686}" == "1" ]]; then
		CORE="$(mktemp -d /tmp/core.XXX)"
		CORE_LTS="$(mktemp -d /tmp/core-lts.XXX)"
		
		tar xvf core-i686.tar -C "${CORE}" || exit 1
		tar xvf core-lts-i686.tar -C "${CORE_LTS}" || exit 1
		
		cp -rf "${CORE_LTS}/tmp"/*/core-i686 "${PACKAGES_TEMP_DIR}/core-i686"
		rm -rf "${CORE_LTS}/tmp"/*/core-i686
		mksquashfs "${PACKAGES_TEMP_DIR}/core-i686/" "${PACKAGES_TEMP_DIR}/archboot_packages_i686.squashfs" -comp xz -noappend -all-root
		mv "${PACKAGES_TEMP_DIR}/archboot_packages_i686.squashfs" "${ALLINONE}/packages/"
	fi
	
	# move in 'any' packages
	cp -rf "${CORE_LTS}/tmp"/*/core-any "${PACKAGES_TEMP_DIR}/core-any"
	rm -rf "${CORE_LTS}/tmp"/*/core-any
	mksquashfs "${PACKAGES_TEMP_DIR}/core-any/" "${PACKAGES_TEMP_DIR}/archboot_packages_any.squashfs" -comp xz -noappend -all-root
	
	cd "${WD}/"
	mv "${PACKAGES_TEMP_DIR}/archboot_packages_any.squashfs" "${ALLINONE}/packages/"
	
}

_prepare_other_files() {
	
	# move in doc
	mkdir -p "${ALLINONE}/arch/"
	mv "${CORE}/tmp"/*/arch/archboot.txt "${ALLINONE}/arch/"
	
	# copy in clamav db files
	if [[ -d /var/lib/clamav && -x /usr/bin/freshclam ]]; then
		mkdir -p "${ALLINONE}/clamav"
		rm -f /var/lib/clamav/*
		freshclam --user=root
		cp /var/lib/clamav/{daily,main,bytecode}.cvd "${ALLINONE}/clamav/"
		cp /var/lib/clamav/mirrors.dat "${ALLINONE}/clamav/"
	fi
	
}

_download_uefi_shell_tianocore() {
	
	mkdir -p "${ALLINONE}/EFI/tools/"
	
	## Download Tianocore UDK/EDK2 ShellBinPkg UEFI "Full Shell" - For UEFI Spec. >=2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${ALLINONE}/EFI/tools/shellx64_v2.efi" "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/ShellBinPkg/UefiShell/X64/Shell.efi"
	
	## Download Tianocore UDK/EDK2 EdkShellBinPkg UEFI "Full Shell" - For UEFI Spec. <2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${ALLINONE}/EFI/tools/shellx64_v1.efi" "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/EdkShellBinPkg/FullShell/X64/Shell_Full.efi"
	
}

_prepare_uefi_gummiboot_USB_files() {
	
	mkdir -p "${ALLINONE}/EFI/boot"
	cp -f "/usr/lib/gummiboot/gummiboot${_SPEC_UEFI_ARCH}.efi" "${ALLINONE}/EFI/boot/boot${_SPEC_UEFI_ARCH}.efi"
	
	mkdir -p "${ALLINONE}/loader/entries"
	
	cat << GUMEOF > "${ALLINONE}/loader/loader.conf"
timeout 5
default archboot-${_UEFI_ARCH}-main
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/archboot-${_UEFI_ARCH}-main.conf"
title    Arch Linux ${_UEFI_ARCH} Archboot
linux    /boot/vmlinuz_${_UEFI_ARCH}
initrd   /boot/initramfs_${_UEFI_ARCH}.img
options  gpt loglevel=7 efivars.pstore_disable=1 efi_pstore.pstore_disable=1 efi_no_storage_paranoia add_efi_memmap none=UEFI_ARCH_${_UEFI_ARCH}
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/archboot-${_UEFI_ARCH}-lts-efilinux.conf"
title    Arch Linux LTS ${_UEFI_ARCH} Archboot via EFILINUX
efi      /EFI/efilinux/efilinux${_SPEC_UEFI_ARCH}.efi
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/uefi-shell-${_UEFI_ARCH}-v2.conf"
title    UEFI Shell ${_UEFI_ARCH} v2
efi      /EFI/tools/shell${_SPEC_UEFI_ARCH}_v2.efi
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/uefi-shell-${_UEFI_ARCH}-v1.conf"
title    UEFI Shell ${_UEFI_ARCH} v1
efi      /EFI/tools/shell${_SPEC_UEFI_ARCH}_v1.efi
GUMEOF
	
	cat << GUMEOF > "${ALLINONE}/loader/entries/refind-${_UEFI_ARCH}-gummiboot.conf"
title    rEFInd ${_UEFI_ARCH}
efi      /EFI/refind/refind${_SPEC_UEFI_ARCH}.efi
GUMEOF
	
	mkdir -p "${ALLINONE}/EFI/efilinux"
	cp -f "/usr/lib/efilinux/efilinux${_SPEC_UEFI_ARCH}.efi" "${ALLINONE}/EFI/efilinux/efilinux${_SPEC_UEFI_ARCH}.efi"
	
	cat << EOF > "${ALLINONE}/EFI/efilinux/efilinux.cfg"
-f \\boot\\vmlinuz_${_UEFI_ARCH}_lts gpt loglevel=7 efivars.pstore_disable=1 efi_pstore.pstore_disable=1 efi_no_storage_paranoia add_efi_memmap none=UEFI_ARCH_${_UEFI_ARCH} initrd=\\boot\\initramfs_${_UEFI_ARCH}.img
EOF
	
}

_prepare_uefi_rEFInd_USB_files() {
	
	mkdir -p "${ALLINONE}/EFI/refind"
	cp -f "/usr/lib/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${ALLINONE}/EFI/refind/refind${_SPEC_UEFI_ARCH}.efi"
	# cp -rf "/usr/share/refind/icons" "${ALLINONE}/EFI/refind/icons" || true
	# cp -rf "/usr/share/refind/fonts" "${ALLINONE}/EFI/refind/fonts" || true
	
	mkdir -p "${ALLINONE}/EFI/tools"
	cp -rf "/usr/lib/refind/drivers_${_SPEC_UEFI_ARCH}" "${ALLINONE}/EFI/tools/drivers_${_SPEC_UEFI_ARCH}"
	
	cat << EOF > "${ALLINONE}/EFI/refind/refind.conf"
timeout 5

textonly

resolution 1024 768

showtools mok_tool,about,reboot,shutdown,exit

scan_driver_dirs EFI/tools/drivers_${_SPEC_UEFI_ARCH}

scanfor manual,internal,external,optical

scan_delay 0

#also_scan_dirs boot

dont_scan_dirs EFI/boot

#scan_all_linux_kernels

max_tags 0

default_selection "Arch Linux ${_UEFI_ARCH} Archboot"

menuentry "Arch Linux ${_UEFI_ARCH} Archboot" {
    icon /EFI/refind/icons/os_arch.icns
    loader /boot/vmlinuz_${_UEFI_ARCH}
    initrd /boot/initramfs_${_UEFI_ARCH}.img
    options "gpt loglevel=7 efivars.pstore_disable=1 efi_pstore.pstore_disable=1 efi_no_storage_paranoia add_efi_memmap none=UEFI_ARCH_${_UEFI_ARCH}"
    ostype Linux
    graphics off
}

menuentry "Arch Linux LTS ${_UEFI_ARCH} Archboot via EFILINUX" {
    icon /EFI/refind/icons/os_arch.icns
    loader /EFI/efilinux/efilinux${_SPEC_UEFI_ARCH}.efi
    ostype Linux
    graphics off
}

menuentry "UEFI Shell ${_UEFI_ARCH} v2" {
    icon /EFI/refind/icons/tool_shell.icns
    loader /EFI/tools/shell${_SPEC_UEFI_ARCH}_v2.efi
    graphics off
}

menuentry "UEFI Shell ${_UEFI_ARCH} v1" {
    icon /EFI/refind/icons/tool_shell.icns
    loader /EFI/tools/shell${_SPEC_UEFI_ARCH}_v1.efi
    graphics off
}
EOF
	
}

_prepare_packages

_prepare_other_files

_merge_initramfs_files

_prepare_kernel_initramfs_files

_download_uefi_shell_tianocore

_prepare_uefi_gummiboot_USB_files

_prepare_uefi_rEFInd_USB_files

unset _UEFI_ARCH
unset _SPEC_UEFI_ARCH

# place syslinux files
mv "${CORE}/tmp"/*/boot/syslinux/* "${ALLINONE}/boot/syslinux/"

# Change parameters in boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g"  -e "s/@@LTS_KERNEL@@/$LTS_KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/ISOLINUX/g" "${ALLINONE}/boot/syslinux/boot.msg"

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
        -isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin \
        -output "${IMAGENAME}.iso" "${ALLINONE}/" &> "/tmp/archboot_allinone_xorriso.log"

if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-x86_64.iso" ]]; then
	_REMOVE_i686="1" _REMOVE_x86_64="0" _UPDATE_SETUP="0" _UPDATE_UEFI_SHELL="0" _UPDATE_UEFI_REFIND="0" _UPDATE_SYSLINUX="0" _UPDATE_SYSLINUX_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-x86_64.iso" "${WD}/${IMAGENAME_OLD}-x86_64.iso"
fi

if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-i686.iso" ]]; then
	_REMOVE_i686="0" _REMOVE_x86_64="1" _UPDATE_SETUP="0" _UPDATE_UEFI_SHELL="0" _UPDATE_UEFI_REFIND="0" _UPDATE_SYSLINUX="0" _UPDATE_SYSLINUX_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-i686.iso" "${WD}/${IMAGENAME_OLD}-i686.iso"
fi

if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-dual-uefi.iso" ]]; then
	_UPDATE_CD_UEFI="1" _REMOVE_i686="0" _REMOVE_x86_64="0" _UPDATE_SETUP="0" _UPDATE_UEFI_SHELL="0" _UPDATE_UEFI_REFIND="0" _UPDATE_SYSLINUX="0" _UPDATE_SYSLINUX_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-dual-uefi.iso" "${WD}/${IMAGENAME_OLD}-dual-uefi.iso"
fi

if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-x86_64-uefi.iso" ]]; then
	_UPDATE_CD_UEFI="1" _REMOVE_i686="1" _REMOVE_x86_64="0" _UPDATE_SETUP="0" _UPDATE_UEFI_SHELL="0" _UPDATE_UEFI_REFIND="0" _UPDATE_SYSLINUX="0" _UPDATE_SYSLINUX_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-x86_64-uefi.iso" "${WD}/${IMAGENAME_OLD}-x86_64-uefi.iso"
fi

## create sha256sums.txt
cd "${WD}/"
rm -f "${WD}/sha256sums.txt" || true
sha256sum *.iso *.img > "${WD}/sha256sums.txt"

# cleanup
rm -rf "${CORE}"
rm -rf "${CORE64}"
rm -rf "${CORE_LTS}"
rm -rf "${CORE64_LTS}"
rm -rf "${PACKAGES_TEMP_DIR}"
rm -rf "${ALLINONE}"
