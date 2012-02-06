#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
# grub2-uefi related commands have been copied from grub-mkstandalone and grub-mkrescue scripts in extra/grub2-common package

WD="${PWD}/"

APPNAME="$(basename "${0}")"

_DO_x86_64="1"
_DO_i686="1"

usage () {
    echo "${APPNAME}: usage"
    echo "CREATE ALLINONE USB/CD IMAGES"
    echo "-----------------------------"
    echo "Run in archboot x86_64 chroot first ..."
    echo "create-allinone.sh -t"
    echo "Run in archboot 686 chroot then ..."
    echo "create-allinone.sh -t"
    echo "Copy the generated tarballs to your favorite directory and run:"
    echo "${APPNAME} -g <any other option>"
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
[[ -z "${RELEASENAME}" ]] && RELEASENAME="2k12-R1"
[[ -z "${IMAGENAME}" ]] && IMAGENAME="Archlinux-allinone-$(date +%Y.%m)"

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
		find . -print0 | bsdcpio -0oH newc | xz --check=crc32 --lzma2=dict=1MiB > "${CORE64}/tmp/initramfs_x86_64.img"
	fi
	
	if [[ "${_DO_i686}" == "1" ]]; then
		mkdir -p "${CORE}/tmp/initrd"
		cd "${CORE}/tmp/initrd"
		
		bsdtar xf "${CORE}/tmp"/*/boot/initrd.img
		bsdtar xf "${CORE_LTS}/tmp"/*/boot/initrd.img
		
		cd  "${CORE}/tmp/initrd"
		find . -print0 | bsdcpio -0oH newc | xz --check=crc32 --lzma2=dict=1MiB > "${CORE}/tmp/initramfs_i686.img"
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
		
		cp -r "${CORE64_LTS}/tmp"/*/core-x86_64 "${PACKAGES_TEMP_DIR}/core-x86_64"
		rm -rf "${CORE64_LTS}/tmp"/*/core-x86_64
		mksquashfs "${PACKAGES_TEMP_DIR}/core-x86_64/" "${PACKAGES_TEMP_DIR}/archboot_packages_x86_64.squashfs" -comp xz -noappend -all-root
		mv "${PACKAGES_TEMP_DIR}/archboot_packages_x86_64.squashfs" "${ALLINONE}/packages/"
	fi
	
	if [[ "${_DO_i686}" == "1" ]]; then
		CORE="$(mktemp -d /tmp/core.XXX)"
		CORE_LTS="$(mktemp -d /tmp/core-lts.XXX)"
		
		tar xvf core-i686.tar -C "${CORE}" || exit 1
		tar xvf core-lts-i686.tar -C "${CORE_LTS}" || exit 1
		
		cp -r "${CORE_LTS}/tmp"/*/core-i686 "${PACKAGES_TEMP_DIR}/core-i686"
		rm -rf "${CORE_LTS}/tmp"/*/core-i686
		mksquashfs "${PACKAGES_TEMP_DIR}/core-i686/" "${PACKAGES_TEMP_DIR}/archboot_packages_i686.squashfs" -comp xz -noappend -all-root
		mv "${PACKAGES_TEMP_DIR}/archboot_packages_i686.squashfs" "${ALLINONE}/packages/"
	fi
	
	# move in 'any' packages
	cp -r "${CORE_LTS}/tmp"/*/core-any "${PACKAGES_TEMP_DIR}/core-any"
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
	
	mkdir -p "${ALLINONE}/efi/shell/"
	
	## Download Tianocore UDK/EDK2 ShellBinPkg UEFI "Full Shell" - For UEFI Spec. >=2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${ALLINONE}/efi/shell/shellx64.efi" "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/ShellBinPkg/UefiShell/X64/Shell.efi"
	
	## Download Tianocore UDK/EDK2 EdkShellBinPkg UEFI "Full Shell" - For UEFI Spec. <2.3 systems
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${ALLINONE}/efi/shell/shellx64_old.efi" "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/EdkShellBinPkg/FullShell/X64/Shell_Full.efi"
	
}

_prepare_grub2_uefi_arch_specific_iso_files() {
	
	[[ "${_UEFI_ARCH}" == "x86_64" ]] && _SPEC_UEFI_ARCH="x64"
	[[ "${_UEFI_ARCH}" == "i386" ]] && _SPEC_UEFI_ARCH="ia32"
	
	mkdir -p "${ALLINONE}/efi/grub2"
	
	## Create grub.cfg for grub-mkstandalone memdisk for boot${_SPEC_UEFI_ARCH}.efi
	cat << EOF > "${ALLINONE}/efi/grub2/grub_standalone_archboot.cfg"
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

search --file --no-floppy --set=archboot /efi/grub2/grub_archboot.cfg
source (\${archboot})/efi/grub2/grub_archboot.cfg

EOF
	
	mkdir -p "${ALLINONE}/efi/grub2/boot/grub"
	cp "${ALLINONE}/efi/grub2/grub_standalone_archboot.cfg" "${ALLINONE}/efi/grub2/boot/grub/grub.cfg"
	
	__WD="${PWD}/"
	
	cd "${ALLINONE}/efi/grub2/"
	
	grub-mkstandalone --directory="/usr/lib/grub/${_UEFI_ARCH}-efi" --format="${_UEFI_ARCH}-efi" --compression="xz" --output="${grub2_uefi_mp}/efi/boot/boot${_SPEC_UEFI_ARCH}.efi" "boot/grub/grub.cfg"
	
	cd "${__WD}/"
	
	rm -rf "${ALLINONE}/efi/grub2/boot/grub/"
	rm -rf "${ALLINONE}/efi/grub2/boot"
	
	mkdir -p "${ALLINONE}/efi/boot/"
	cp "${grub2_uefi_mp}/efi/boot/boot${_SPEC_UEFI_ARCH}.efi" "${ALLINONE}/efi/boot/boot${_SPEC_UEFI_ARCH}.efi"
	
	unset _UEFI_ARCH
	unset _SPEC_UEFI_ARCH
	
}

_prepare_grub2_uefi_iso_files() {
	
	grub2_uefi_mp="$(mktemp -d /tmp/grub2_uefi_mp.XXX)"
	
	mkdir -p "${ALLINONE}/efi/grub2"
	mkdir -p "${ALLINONE}/efi/boot"
	
	# Create a blank image to be converted to ESP IMG
	dd if="/dev/zero" of="${ALLINONE}/efi/grub2/grub2_uefi.bin" bs="1024" count="4096"
	
	# Create a FAT12 FS with Volume label "grub2_uefi"
	mkfs.vfat -F12 -S 512 -n "grub2_uefi" "${ALLINONE}/efi/grub2/grub2_uefi.bin"
	
	## Mount the ${ALLINONE}/efi/grub2/grub2_uefi.bin image at ${grub2_uefi_mp} as loop 
	if ! [[ "$(lsmod | grep ^loop)" ]]; then
		modprobe -q loop || echo "Your hostsystem has a different kernel version installed, please load loop module first on hostsystem!"
	fi
	
	LOOP_DEVICE="$(losetup --show --find "${ALLINONE}/efi/grub2/grub2_uefi.bin")"
	mount -o rw,flush -t vfat "${LOOP_DEVICE}" "${grub2_uefi_mp}"
	
	mkdir -p "${grub2_uefi_mp}/efi/boot/"
	
	_UEFI_ARCH="x86_64"
	_prepare_grub2_uefi_arch_specific_iso_files
	
	# umount images and loop
	umount "${grub2_uefi_mp}"
	losetup --detach "${LOOP_DEVICE}"
	
	cp "/usr/share/grub/unicode.pf2" "${ALLINONE}/efi/grub2/"
	
	mkdir -p "${ALLINONE}/efi/grub2/locale/"
	
	## Taken from /usr/sbin/grub-install
	#for dir in "/usr/share/locale"/*; do
	#	if test -f "${dir}/LC_MESSAGES/grub.mo"; then
			# cp -f "${dir}/LC_MESSAGES/grub.mo" "${ALLINONE}/efi/grub2/locale/${dir##*/}.mo"
	#		echo
	#	fi
	#done
	
	## Create the actual grub2 uefi config file
	cat << EOF > "${ALLINONE}/efi/grub2/grub_archboot.cfg"
if [ "\${grub_platform}" == "efi" ]; then
    set _UEFI_ARCH="\${grub_cpu}"
    
    if [ "\${grub_cpu}" == "x86_64" ]; then
        set _SPEC_UEFI_ARCH="x64"
    elif [ "\${grub_cpu}" == "i386" ]; then
        set _SPEC_UEFI_ARCH="ia32"
    fi
fi

# search --file --no-floppy --set=archboot /efi/grub2/grub_archboot.cfg
# search --file --no-floppy --set=archboot /efi/grub2/grub_standalone_archboot.cfg

set pager="1"
# set debug="all"

set locale_dir=(\${archboot})/efi/grub2/locale

if [ "\${grub_platform}" == "efi" ]; then
    insmod efi_gop
    insmod efi_uga
    insmod video_bochs
    insmod video_cirrus
fi

insmod font

if loadfont (\${archboot})/efi/grub2/unicode.pf2
then
    insmod gfxterm
    set gfxmode="auto"
    
    terminal_input console
    terminal_output gfxterm
    
    # set color_normal=light-blue/black
    # set color_highlight=light-cyan/blue
    
    # insmod png
    # background_image (\${archboot})/boot/syslinux/splash.png
fi

insmod fat
insmod iso9660
insmod udf
insmod search_fs_file
insmod linux
insmod chain

set _kernel_params="gpt add_efi_memmap loglevel=7 none=UEFI_ARCH_\${_UEFI_ARCH}"

menuentry "Arch Linux (x86_64) archboot" {
    set gfxpayload="keep"
    set root=(\${archboot})
    linux /boot/vmlinuz_x86_64 \${_kernel_params}
    initrd /boot/initramfs_x86_64.img
}

menuentry "Arch Linux LTS (x86_64) archboot" {
    set gfxpayload="keep"
    set root=(\${archboot})
    linux /boot/vmlinuz_x86_64_lts \${_kernel_params}
    initrd /boot/initramfs_x86_64.img
}

menuentry "Arch Linux (i686) archboot" {
    set gfxpayload="keep"
    set root=(\${archboot})
    linux /boot/vmlinuz_i686 \${_kernel_params}
    initrd /boot/initramfs_i686.img
}

menuentry "Arch Linux LTS (i686) archboot" {
    set gfxpayload="keep"
    set root=(\${archboot})
    linux /boot/vmlinuz_i686_lts \${_kernel_params}
    initrd /boot/initramfs_i686.img
}

menuentry "UEFI \${_UEFI_ARCH} Shell 2.0 - For Spec. Ver. >=2.3 systems" {
    set root=(\${archboot})
    chainloader /efi/shell/shell\${_SPEC_UEFI_ARCH}.efi
}

menuentry "UEFI \${_UEFI_ARCH} Shell 1.0 - For Spec. Ver. <2.3 systems" {
    set root=(\${archboot})
    chainloader /efi/shell/shell\${_SPEC_UEFI_ARCH}_old.efi
}

EOF
	
}

_prepare_packages

_prepare_other_files

_merge_initramfs_files

_prepare_kernel_initramfs_files

_download_uefi_shell_tianocore

_prepare_grub2_uefi_iso_files

# place syslinux files
mv "${CORE}/tmp"/*/boot/syslinux/* "${ALLINONE}/boot/syslinux/"

# Change parameters in boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g"  -e "s/@@LTS_KERNEL@@/$LTS_KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/ISOLINUX/g" "${ALLINONE}/boot/syslinux/boot.msg"

## Generate the BIOS+UEFI+ISOHYBRID ISO image using xorriso (extra/libisoburn package) in mkisofs emulation mode
echo "Generating ALLINONE hybrid ISO ..."
xorriso -as mkisofs \
        -iso-level 3 -rock -joliet \
        -max-iso9660-filenames -omit-period \
        -omit-version-number -allow-leading-dots \
        -relaxed-filenames -allow-lowercase -allow-multidot \
        -volid "ARCHBOOT" \
        -p "prepared by ${APPNAME}" \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot --efi-boot efi/grub2/grub2_uefi.bin -no-emul-boot \
        -isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin \
        -output "${IMAGENAME}.iso" "${ALLINONE}/" > /dev/null 2>&1

# cleanup isolinux and migrate to syslinux
echo "Generating ALLINONE IMG ..."
rm -f "${ALLINONE}/boot/syslinux/isolinux.bin"
# Change parameters in boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g" -e "s/@@LTS_KERNEL@@/$LTS_KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/SYSLINUX/g" "${ALLINONE}/boot/syslinux/boot.msg"

"${USBIMAGE_HELPER}" "${ALLINONE}" "${IMAGENAME}.img" > /dev/null 2>&1

#create sha256sums.txt
rm -f sha256sums.txt || true
sha256sum "${IMAGENAME}.iso" "${IMAGENAME}.img" > sha256sums.txt

# cleanup
rm -rf "${grub2_uefi_mp}"
rm -rf "${CORE}"
rm -rf "${CORE64}"
rm -rf "${CORE_LTS}"
rm -rf "${CORE64_LTS}"
rm -rf "${PACKAGES_TEMP_DIR}"
rm -rf "${ALLINONE}"
