#!/bin/bash
# Script for updating existing /arch/setup script in the initramfs files of archboot.
# Previously the script for creating grub2 uefi bootable isos - moved to all-in-one script
# Contributed by "Keshav P R" <the.ridikulus.rat aatt geemmayil ddoott ccoomm>

export archboot_ver="2012.01-1"

export WD="${PWD}/"

APPNAME="$(basename "${0}")"

export archboot_ext="$(mktemp -d /tmp/archboot_ext.XXXXXXXXXX)"
export iso_name="archboot_${archboot_ver}_mod"

export UPDATE_UEFI_SHELL="1"
export REPLACE_GRUB2_UEFI="1"
export REPLACE_SETUP="1"

echo

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

set -x

## Remove old files
rm -f "${WD}/${iso_name}.iso" || true
echo

cd "${archboot_ext}/"
echo

## Extract the archboot iso using bsdtar
bsdtar xf "${WD}/archlinux-${archboot_ver}-archboot.iso"
# 7z x "${WD}/archlinux-${archboot_ver}-archboot.iso"
echo

rm -rf "${archboot_ext}/[BOOT]/" || true
echo

[[ -e "${WD}/splash.png" ]] && cp "${WD}/splash.png" "${archboot_ext}/boot/splash.png"
echo

_download_uefi_shell_tianocore() {
	
	mkdir -p "${archboot_ext}/efi/shell/"
	
	## Download Tianocore UDK/EDK2 ShellBinPkg UEFI "Full Shell" - For UEFI Spec. >=2.3 systems
	
	mv "${archboot_ext}/efi/shell/shellx64.efi" "${archboot_ext}/efi/shell/shellx64.efi.backup" || true
	curl --verbose --ipv4 -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${archboot_ext}/efi/shell/shellx64.efi" "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/ShellBinPkg/UefiShell/X64/Shell.efi" || true
	echo
	
	if [[ ! "$(file "${archboot_ext}/efi/shell/shellx64.efi" | grep 'executable')" ]]; then
		rm "${archboot_ext}/efi/shell/shellx64.efi" || true
		
		if [[ -e "${WD}/shellx64.efi" ]]; then
			cp "${WD}/shellx64.efi" "${archboot_ext}/efi/shell/shellx64.efi"
		else
			mv "${archboot_ext}/efi/shell/shellx64.efi.backup" "${archboot_ext}/efi/shell/shellx64.efi" || true
		fi
	else
		rm "${archboot_ext}/efi/shell/shellx64.efi.backup" || true
	fi
	echo
	
	## Download Tianocore UDK/EDK2 EdkShellBinPkg UEFI "Full Shell" - For UEFI Spec. <2.3 systems
	
	mv "${archboot_ext}/efi/shell/shellx64_old.efi" "${archboot_ext}/efi/shell/shellx64_old.efi.backup" || true
	curl --verbose --ipv4 -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${archboot_ext}/efi/shell/shellx64_old.efi" "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/EdkShellBinPkg/FullShell/X64/Shell_Full.efi" || true
	echo
	
	if [[ ! "$(file "${archboot_ext}/efi/shell/shellx64_old.efi" | grep 'executable')" ]]; then
		rm "${archboot_ext}/efi/shell/shellx64_old.efi" || true
		
		if [[ -e "${WD}/shellx64_old.efi" ]]; then
			cp "${WD}/shellx64_old.efi" "${archboot_ext}/efi/shell/shellx64_old.efi"
		else
			mv "${archboot_ext}/efi/shell/shellx64_old.efi.backup" "${archboot_ext}/efi/shell/shellx64_old.efi" || true
		fi
	else
		rm "${archboot_ext}/efi/shell/shellx64_old.efi.backup" || true
	fi
	echo
	
}

_replace_grub2_uefi_x86_64_iso_files() {
	
	rm -f "${grub2_uefi_mp}/efi/boot/bootx64.efi" || true
	rm -f "${archboot_ext}/efi/boot/bootx64.efi" || true
	echo
	
	rm -rf "${archboot_ext}/efi/grub2/x86_64-efi" || true
	echo
	
	mkdir -p "${archboot_ext}/efi/grub2"
	mkdir -p "${archboot_ext}/efi/grub2/x86_64-efi"
	echo
	
	## Create grub.cfg for grub-mkstandalone memdisk for bootx64.efi
	cat << EOF > "${archboot_ext}/efi/grub2/x86_64-efi/grub.cfg"
set _UEFI_ARCH="x86_64"

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

search --file --no-floppy --set=uefi64 /efi/grub2/grub.cfg
source (\${uefi64})/efi/grub2/grub.cfg

EOF
	
	echo
	
	mkdir -p "${archboot_ext}/efi/grub2/x86_64-efi/boot/grub"
	cp "${archboot_ext}/efi/grub2/x86_64-efi/grub.cfg" "${archboot_ext}/efi/grub2/x86_64-efi/boot/grub/grub.cfg"
	echo
	
	__WD="${PWD}/"
	
	cd "${archboot_ext}/efi/grub2/x86_64-efi/"
	
	grub-mkstandalone --directory="/usr/lib/grub/x86_64-efi" --format="x86_64-efi" --compression="xz" --output="${grub2_uefi_mp}/efi/boot/bootx64.efi" "boot/grub/grub.cfg"
	
	cd "${__WD}/"
	
	rm -rf "${archboot_ext}/efi/grub2/x86_64-efi/boot/grub/"
	rm -rf "${archboot_ext}/efi/grub2/x86_64-efi/boot"
	
	mkdir -p "${archboot_ext}/efi/boot/"
	cp "${grub2_uefi_mp}/efi/boot/bootx64.efi" "${archboot_ext}/efi/boot/bootx64.efi"
	
	echo
	
}

_replace_grub2_uefi_iso_files() {
	
	grub2_uefi_mp="$(mktemp -d /tmp/grub2_uefi_mp.XXX)"
	
	rm -rf "${archboot_ext}/efi/grub2" || true
	echo
	
	mkdir -p "${archboot_ext}/efi/grub2"
	mkdir -p "${archboot_ext}/efi/boot"
	echo
	
	# Create a blank image to be converted to ESP IMG
	dd if="/dev/zero" of="${archboot_ext}/efi/grub2/grub2_uefi.bin" bs="1024" count="4096"
	
	# Create a FAT12 FS with Volume label "grub2_uefi"
	mkfs.vfat -F12 -S 512 -n "grub2_uefi" "${archboot_ext}/efi/grub2/grub2_uefi.bin"
	echo
	
	## Mount the ${archboot_ext}/efi/grub2/grub2_uefi.bin image at ${grub2_uefi_mp} as loop 
	if ! [[ "$(lsmod | grep ^loop)" ]]; then
		modprobe -q loop || echo "Your hostsystem has a different kernel version installed, please load loop module first on hostsystem!"
		echo
	fi
	
	LOOP_DEVICE="$(losetup --show --find "${archboot_ext}/efi/grub2/grub2_uefi.bin")"
	mount -o rw,users -t vfat "${LOOP_DEVICE}" "${grub2_uefi_mp}"
	echo
	
	mkdir -p "${grub2_uefi_mp}/efi/boot/"
	echo
	
	_replace_grub2_uefi_x86_64_iso_files
	echo
	
	# umount images and loop
	umount "${grub2_uefi_mp}"
	losetup --detach "${LOOP_DEVICE}"
	echo
	
	rm -rf "${grub2_uefi_mp}/"
	echo
	
	unset grub2_uefi_mp
	unset LOOP_DEVICE
	echo
	
	rm -f "${archboot_ext}/efi/boot/grub.cfg" || true
	rm -f "${archboot_ext}/efi/grub2/grub.cfg" || true
	echo
	
	cp "/usr/share/grub/unicode.pf2" "${archboot_ext}/efi/grub2/"
	echo
	
	rm -rf "${archboot_ext}/efi/grub2/locale/" || true
	mkdir -p "${archboot_ext}/efi/grub2/locale/"
	echo
	
	## Taken from /usr/sbin/grub-install
	# for dir in "/usr/share/locale"/*; do
		# if test -f "${dir}/LC_MESSAGES/grub.mo"; then
			# cp -f "${dir}/LC_MESSAGES/grub.mo" "${archboot_ext}/efi/grub2/locale/${dir##*/}.mo"
			echo
		# fi
	# done
	
	cat << EOF > "${archboot_ext}/efi/grub2/grub.cfg"
search --file --no-floppy --set=archboot /arch/archboot.txt

set pager="1"
set locale_dir=(\${archboot})/efi/grub2/locale

insmod efi_gop
insmod efi_uga
insmod font

if loadfont (\${archboot})/efi/grub2/unicode.pf2
then
    insmod gfxterm
    set gfxmode="auto"
    set gfxpayload="keep"
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

set _kernel_params="gpt add_efi_memmap none=UEFI_ARCH_\${_UEFI_ARCH}"

menuentry "Arch Linux (x86_64) archboot" {
    set root=(\${archboot})
    linux /boot/vm64 ro \${_kernel_params}
    initrd /boot/initrd64.img
}

menuentry "Arch Linux LTS (x86_64) archboot" {
    set root=(\${archboot})
    linux /boot/vm64lts ro \${_kernel_params}
    initrd /boot/initrd64.img
}

menuentry "Arch Linux (i686) archboot" {
    set root=(\${archboot})
    linux /boot/vmlinuz ro \${_kernel_params}
    initrd /boot/initrd.img
}

menuentry "Arch Linux LTS (i686) archboot" {
    set root=(\${archboot})
    linux /boot/vmlts ro \${_kernel_params}
    initrd /boot/initrd.img
}

menuentry "Launch UEFI Shell 2.0 - For UEFI Spec. >=2.3 systems" {
    set root=(\${archboot})
    chainloader /efi/shell/shellx64.efi
}

menuentry "Launch UEFI Shell 1.0 - For UEFI Spec. <2.3 systems" {
    set root=(\${archboot})
    chainloader /efi/shell/shellx64_old.efi
}

EOF
	
	echo
	
}

_replace_arch_setup_initramfs() {
	
	initramfs_ext="$(mktemp -d /tmp/${initramfs_name}_ext.XXXXXXXXXX)"
	echo
	
	cd "${initramfs_ext}/"
	
	if [[ "${initramfs_name}" == "initrd64" ]] || [[ "${initramfs_name}" == "initrd64lts" ]]; then
		[[ -e "${archboot_ext}/boot/initrd64lts.img" ]] && bsdtar xf "${archboot_ext}/boot/initrd64lts.img"
		echo
		
		bsdtar xf "${archboot_ext}/boot/initrd64.img"
		echo
	fi
	
	if [[ "${initramfs_name}" == "initrd" ]] || [[ "${initramfs_name}" == "initrdlts" ]]; then
		[[ -e "${archboot_ext}/boot/initrdlts.img" ]] && bsdtar xf "${archboot_ext}/boot/initrdlts.img"
		echo
		
		bsdtar xf "${archboot_ext}/boot/initrd.img"
		echo
	fi
	
	mv "${initramfs_ext}/arch/setup" "${initramfs_ext}/arch/setup.old"
	cp "${WD}/setup" "${initramfs_ext}/arch/setup"
	chmod +x "${initramfs_ext}/arch/setup"
	echo
	
	cd "${WD}/"
	
	## Generate the actual initramfs file
	if [[ "${initramfs_name}" == "initrd64" ]] || [[ "${initramfs_name}" == "initrd64lts" ]]; then
		cd "${initramfs_ext}/"
		find . -print0 | bsdcpio -0oH newc | lzma > "${WD}/initrd64.img"
		echo
		
		[[ -e "${archboot_ext}/boot/initrd64lts.img" ]] && rm -f "${archboot_ext}/boot/initrd64lts.img"
		echo
		
		rm -f "${archboot_ext}/boot/initrd64.img"
		echo
		
		cp "${WD}/initrd64.img" "${archboot_ext}/boot/initrd64.img"
		echo
		
		rm -f "${WD}/initrd64.img"
		echo
	fi
	
	if [[ "${initramfs_name}" == "initrd" ]] || [[ "${initramfs_name}" == "initrdlts" ]]; then
		cd "${initramfs_ext}/"
		find . -print0 | bsdcpio -0oH newc | lzma > "${WD}/initrd.img"
		echo
		
		[[ -e "${archboot_ext}/boot/initrdlts.img" ]] && rm -f "${archboot_ext}/boot/initrdlts.img"
		echo
		
		rm -f "${archboot_ext}/boot/initrd.img"
		echo
		
		cp "${WD}/initrd.img" "${archboot_ext}/boot/initrd.img"
		echo
		
		rm -f "${WD}/initrd.img"
		echo
	fi
	
	rm -rf "${initramfs_ext}/"
	echo
	
	unset initramfs_ext
	unset initramfs_name
	echo
	
}

# Not currently used - simply left untouched for now
_download_pkgs() {
	
	cd "${WD}/"
	
	if [[ "${pkg_arch}" == 'any' ]]; then
		wget -c "http://www.archlinux.org/packages/${repo}/any/${package}/download/"
		echo
	else
		wget -c "http://www.archlinux.org/packages/${repo}/x86_64/${package}/download/"
		echo
		
		wget -c "http://www.archlinux.org/packages/${repo}/i686/${package}/download/"
		echo
	fi
	
	unset repo
	unset package
	unset pkg_arch
	echo
	
}

[[ "${UPDATE_UEFI_SHELL}" == "1" ]] && _download_uefi_shell_tianocore

[[ "${REPLACE_GRUB2_UEFI}" == "1" ]] && _replace_grub2_uefi_iso_files

if [[ "${REPLACE_SETUP}" == "1" ]] && [[ -e "${WD}/setup" ]]; then
	cd "${WD}/"
	
	## The old method I tried, mount -o ro -t iso9660 /dev/sr0 /src, mv /arch/setup /arch/setup.old, cp /src/arch/setup /arch/setup, umount /dev/sr0
	# cp ${WD}/setup ${archboot_ext}/arch/setup
	
	## Extracting using bsdtar, replacing /arch/setup and recompressing the iniramfs archive does not work. Archive format not compatible with initramfs format.
	## Compressing using bsdcpio and using 'newc' archive format works, taken from falconindy's geninit program.
	
	initramfs_name="initrd64"
	_replace_arch_setup_initramfs
	
	initramfs_name="initrd"
	_replace_arch_setup_initramfs
	
	echo
fi

## Re-create the archboot ISO
cd "${WD}/"

## Generate the BIOS+UEFI+ISOHYBRID ISO image using xorriso (extra/libisoburn package) in mkisofs emulation mode
echo "Generating the modified ISO ..."
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
        -output "${WD}/${iso_name}.iso" "${archboot_ext}/" > /dev/null 2>&1
echo

rm -rf "${archboot_ext}/"
echo

set +x

unset archboot_ver
unset WD
unset archboot_ext
unset iso_name
unset UPDATE_UEFI_SHELL
unset REPLACE_GRUB2_UEFI
unset REPLACE_SETUP
