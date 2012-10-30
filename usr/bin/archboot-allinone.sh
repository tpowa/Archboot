#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# grub-uefi related commands have been copied from grub-mkstandalone and grub-mkrescue scripts in core/grub-common package

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
[[ -z "${RELEASENAME}" ]] && RELEASENAME="2k12-R4"
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
	
	mkdir -p "${ALLINONE}/EFI/efilinux"
	cp -f "/usr/lib/efilinux/efilinux${_SPEC_UEFI_ARCH}.efi" "${ALLINONE}/EFI/efilinux/efilinux${_SPEC_UEFI_ARCH}.efi"
	
	mkdir -p "${ALLINONE}/loader/entries/"
	
	cat << EOF > "${ALLINONE}/loader/loader.conf"
timeout 5
default archboot-${_UEFI_ARCH}-core
EOF
	
	cat << EOF > "${ALLINONE}/loader/entries/archboot-${_UEFI_ARCH}-core.conf"
title    Arch Linux ${_UEFI_ARCH} Archboot
linux    /boot/vmlinuz_${_UEFI_ARCH}
initrd   /boot/initramfs_${_UEFI_ARCH}.img
options  gpt loglevel=7 add_efi_memmap none=UEFI_ARCH_${_UEFI_ARCH}
EOF
	
	cat << EOF > "${ALLINONE}/loader/entries/archboot-${_UEFI_ARCH}-lts.conf"
title    Arch Linux LTS ${_UEFI_ARCH} Archboot via EFILINUX
efi      /EFI/efilinux/efilinux${_SPEC_UEFI_ARCH}.efi
EOF
	
	cat << EOF > "${ALLINONE}/EFI/efilinux/efilinux.cfg"
-f \\boot\\vmlinuz_x86_64_lts gpt loglevel=7 add_efi_memmap none=UEFI_ARCH_${_UEFI_ARCH} initrd=\\boot\\initramfs_${_UEFI_ARCH}.img
EOF
	
	cat << EOF > "${ALLINONE}/loader/entries/uefi-shell-${_UEFI_ARCH}-v2.conf"
title   UEFI ${_UEFI_ARCH} Shell v2
efi     /EFI/tools/shell${_SPEC_UEFI_ARCH}_v2.efi
EOF
	
	cat << EOF > "${ALLINONE}/loader/entries/uefi-shell-${_UEFI_ARCH}-v1.conf"
title   UEFI ${_UEFI_ARCH} Shell v1
efi     /EFI/tools/shell${_SPEC_UEFI_ARCH}_v1.efi
EOF
	
}

_prepare_grub_uefi_arch_specific_CD_files() {
	
	mkdir -p "${ALLINONE}/boot/grub"
	
	## Create grub.cfg for grub-mkstandalone memdisk for boot${_SPEC_UEFI_ARCH}.efi
	cat << EOF > "${ALLINONE}/boot/grub/grub_standalone_archboot.cfg"

insmod usbms
insmod usb_keyboard

insmod part_gpt
insmod part_msdos

insmod fat
insmod iso9660
insmod udf

insmod ext2
insmod reiserfs
insmod ntfs
insmod hfsplus

insmod linux
insmod chain

search --file --no-floppy --set=archboot "/boot/grub/grub_archboot.cfg"
source "(\${archboot})/boot/grub/grub_archboot.cfg"

EOF
	
	cp -f "${ALLINONE}/boot/grub/grub_standalone_archboot.cfg" "${ALLINONE}/boot/grub/grub.cfg"
	
	__WD="${PWD}/"
	
	cd "${ALLINONE}/"
	
	grub-mkstandalone --directory="/usr/lib/grub/${_UEFI_ARCH}-efi" --format="${_UEFI_ARCH}-efi" --compression="xz" --output="${grub_uefi_mp}/EFI/boot/boot${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg"
	
	cd "${__WD}/"
	
	rm -f "${ALLINONE}/boot/grub/grub.cfg"
	
}

_prepare_grub_uefi_CD_files() {
	
	grub_uefi_mp="$(mktemp -d /tmp/grub_uefi_mp.XXX)"
	
	mkdir -p "${ALLINONE}/boot/grub"
	
	# Create a blank image to be converted to ESP IMG
	dd if="/dev/zero" of="${ALLINONE}/boot/grub/grub_uefi_x86_64.bin" bs="1024" count="4096"
	
	# Create a FAT12 FS with Volume label "grub_uefi"
	mkfs.vfat -F12 -S 512 -n "grub_uefi" "${ALLINONE}/boot/grub/grub_uefi_x86_64.bin"
	
	## Mount the ${ALLINONE}/boot/grub/grub_uefi_x86_64.bin image at ${grub_uefi_mp} as loop 
	if ! [[ "$(lsmod | grep ^loop)" ]]; then
		modprobe -q loop || echo "Your hostsystem has a different kernel version installed, please load loop module first on hostsystem!"
	fi
	
	LOOP_DEVICE="$(losetup --show --find "${ALLINONE}/boot/grub/grub_uefi_x86_64.bin")"
	mount -o rw,flush -t vfat "${LOOP_DEVICE}" "${grub_uefi_mp}"
	
	mkdir -p "${grub_uefi_mp}/EFI/boot/"
	
	_prepare_grub_uefi_arch_specific_CD_files
	
	# umount images and loop
	umount "${grub_uefi_mp}"
	losetup --detach "${LOOP_DEVICE}"
	
	mkdir -p "${ALLINONE}/boot/grub/fonts"
	cp -f "/usr/share/grub/unicode.pf2" "${ALLINONE}/boot/grub/fonts/"
	
	mkdir -p "${ALLINONE}/boot/grub/locale/"
	
	## Taken from /usr/sbin/grub-install
	#for dir in "/usr/share/locale"/*; do
	#	if test -f "${dir}/LC_MESSAGES/grub.mo"; then
			# cp -f "${dir}/LC_MESSAGES/grub.mo" "${ALLINONE}/boot/grub/locale/${dir##*/}.mo"
	#		echo
	#	fi
	#done
	
	## Create the actual grub uefi config file
	cat << EOF > "${ALLINONE}/boot/grub/grub_archboot.cfg"

set _kernel_params="gpt loglevel=7"

if [ "\${grub_platform}" == "efi" ]; then
    set _UEFI_ARCH="\${grub_cpu}"
    
    set _kernel_params="\${_kernel_params} add_efi_memmap none=UEFI_ARCH_\${_UEFI_ARCH}"
    
    if [ "\${grub_cpu}" == "x86_64" ]; then
        set _SPEC_UEFI_ARCH="x64"
        
        set _kernel_x86_64_params="\${_kernel_params}"
        set _kernel_i686_params="\${_kernel_params} noefi"
    fi
    
    if [ "\${grub_cpu}" == "i386" ]; then
        set _SPEC_UEFI_ARCH="ia32"
        
        set _kernel_x86_64_params="\${_kernel_params} noefi"
        set _kernel_i686_params="\${_kernel_params}"
    fi
else
    set _kernel_x86_64_params="\${_kernel_params}"
    set _kernel_i686_params="\${_kernel_params}"
fi

# search --file --no-floppy --set=archboot "/boot/grub/grub_archboot.cfg"
# search --file --no-floppy --set=archboot "/boot/grub/grub_standalone_archboot.cfg"

set pager="1"
# set debug="all"

set locale_dir="(\${archboot})/boot/grub/locale"

if [ -e "\${prefix}/\${grub_cpu}-\${grub_platform}/all_video.mod" ]; then
    insmod all_video
else
    if [ "\${grub_platform}" == "efi" ]; then
        insmod efi_gop
        insmod efi_uga
    fi
    
    if [ "\${grub_platform}" == "pc" ]; then
        insmod vbe
        insmod vga
    fi
    
    insmod video_bochs
    insmod video_cirrus
fi

insmod font

if loadfont "(\${archboot})/boot/grub/fonts/unicode.pf2" ; then
    insmod gfxterm
    set gfxmode="auto"
    
    terminal_input console
    terminal_output gfxterm
    
    # set color_normal="light-blue/black"
    # set color_highlight="light-cyan/blue"
    
    # insmod png
    # background_image "(\${archboot})/boot/syslinux/splash.png"
fi

insmod fat
insmod iso9660
insmod udf
insmod search_fs_file
insmod linux
insmod chain

EOF
	
	if [[ "${_DO_x86_64}" == "1" ]]; then
		cat << EOF >> "${ALLINONE}/boot/grub/grub_archboot.cfg"

if [ cpuid -l ]; then

    menuentry "Arch Linux (x86_64) archboot" {
        set gfxpayload="keep"
        set root="\${archboot}"
        linux /boot/vmlinuz_x86_64 \${_kernel_x86_64_params}
        initrd /boot/initramfs_x86_64.img
    }

    menuentry "Arch Linux LTS (x86_64) archboot" {
        set gfxpayload="keep"
        set root="\${archboot}"
        linux /boot/vmlinuz_x86_64_lts \${_kernel_x86_64_params}
        initrd /boot/initramfs_x86_64.img
    }

fi

EOF
	fi
	
	if [[ "${_DO_i686}" == "1" ]]; then
		cat << EOF >> "${ALLINONE}/boot/grub/grub_archboot.cfg"

menuentry "Arch Linux (i686) archboot" {
    set gfxpayload="keep"
    set root="\${archboot}"
    linux /boot/vmlinuz_i686 \${_kernel_i686_params}
    initrd /boot/initramfs_i686.img
}

menuentry "Arch Linux LTS (i686) archboot" {
    set gfxpayload="keep"
    set root="\${archboot}"
    linux /boot/vmlinuz_i686_lts \${_kernel_i686_params}
    initrd /boot/initramfs_i686.img
}

EOF
	fi
	
	cat << EOF >> "${ALLINONE}/boot/grub/grub_archboot.cfg"

if [ "\${grub_platform}" == "efi" ]; then

    menuentry "UEFI \${_UEFI_ARCH} Shell v2 - For Spec. Ver. >=2.3 systems" {
        set root="\${archboot}"
        chainloader /EFI/tools/shell\${_SPEC_UEFI_ARCH}_v2.efi
    }

    menuentry "UEFI \${_UEFI_ARCH} Shell v1 - For Spec. Ver. <2.3 systems" {
        set root="\${archboot}"
        chainloader /EFI/tools/shell\${_SPEC_UEFI_ARCH}_v1.efi
    }

fi

EOF
	
}

_prepare_packages

_prepare_other_files

_merge_initramfs_files

_prepare_kernel_initramfs_files

_download_uefi_shell_tianocore

_prepare_uefi_gummiboot_USB_files

# _prepare_grub_uefi_CD_files

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

## Add below line to above xorriso if UEFI CD support is required
# -eltorito-alt-boot --efi-boot boot/grub/grub_uefi_x86_64.bin -no-emul-boot \

## cleanup isolinux and migrate to syslinux
# echo "Generating ALLINONE IMG ..."
# rm -f "${ALLINONE}/boot/syslinux/isolinux.bin"

## Change parameters in boot.msg
# sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g" -e "s/@@LTS_KERNEL@@/$LTS_KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/SYSLINUX/g" "${ALLINONE}/boot/syslinux/boot.msg"

# "${USBIMAGE_HELPER}" "${ALLINONE}" "${IMAGENAME}.img" > /dev/null 2>&1

if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-x86_64.iso" ]]; then
	_REMOVE_i686="1" _REMOVE_x86_64="0" _UPDATE_SETUP="0" _UPDATE_UEFI_SHELL="0" _UPDATE_UEFI_GUMMIBOOT="0" _UPDATE_SYSLINUX="0" _UPDATE_SYSLINUX_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-x86_64.iso" "${WD}/${IMAGENAME_OLD}-x86_64.iso"
fi

if [[ -e "${WD}/${IMAGENAME_OLD}-dual.iso" ]] && [[ ! -e "${WD}/${IMAGENAME_OLD}-i686.iso" ]]; then
	_REMOVE_i686="0" _REMOVE_x86_64="1" _UPDATE_SETUP="0" _UPDATE_UEFI_SHELL="0" _UPDATE_UEFI_GUMMIBOOT="0" _UPDATE_SYSLINUX="0" _UPDATE_SYSLINUX_CONFIG="1" "${UPDATEISO_HELPER}" "${WD}/${IMAGENAME_OLD}-dual.iso"
	mv "${WD}/${IMAGENAME_OLD}-dual-updated-i686.iso" "${WD}/${IMAGENAME_OLD}-i686.iso"
fi

## create sha256sums.txt
cd "${WD}/"
rm -f "${WD}/sha256sums.txt" || true
sha256sum *.iso *.img > "${WD}/sha256sums.txt"

# cleanup
# rm -rf "${grub_uefi_mp}"
rm -rf "${CORE}"
rm -rf "${CORE64}"
rm -rf "${CORE_LTS}"
rm -rf "${CORE64_LTS}"
rm -rf "${PACKAGES_TEMP_DIR}"
rm -rf "${ALLINONE}"
