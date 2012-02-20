#!/usr/bin/env bash
# Script for updating existing Archboot iso with newer UEFI shell, GRUB2 UEFI, and/or /arch/setup script in the initramfs files
# Contributed by "Keshav P R" <the.ridikulus.rat aatt geemmayil ddoott ccoomm>

_UPDATE_SYSLINUX="1"
_UPDATE_UEFI_SHELL="1"
_UPDATE_GRUB2_UEFI="1"
_UPDATE_SETUP="1"

_REMOVE_i686="1"
_REMOVE_x86_64="0"

#############################

_BASENAME="$(basename "${0}")"

_ARCHBOOT_ISO_OLD_PATH="${1}"

_ARCHBOOT_ISO_WD="$(dirname "${_ARCHBOOT_ISO_OLD_PATH}")"
_ARCHBOOT_ISO_OLD_NAME="$(basename "${_ARCHBOOT_ISO_OLD_PATH}" | sed 's|\.iso||g')"

_ARCHBOOT_ISO_EXT_DIR="$(mktemp -d /tmp/archboot_iso_ext.XXXXXXXXXX)"

_ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}_updated"
_ARCHBOOT_ISO_UPDATED_PATH="${_ARCHBOOT_ISO_WD}/${_ARCHBOOT_ISO_UPDATED_NAME}.iso"

echo

if [[ -z "${1}" ]]; then
	echo
	echo "Usage: ${_BASENAME} <Absolute Path to Archboot ISO>"
	echo
	echo "Example: ${_BASENAME} /home/user/Desktop/archlinux-2012.01-1-archboot.iso"
	echo
	echo "Updated iso will be saves at /home/user/Desktop/archlinux-2012.01-1-archboot_updated.iso "
	echo "(for example)."
	echo
	echo "This script should be run as root user."
	echo
	exit 0
fi

### check for root
if ! [[ ${UID} -eq 0 ]]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

set -x

## Remove old files
rm -f "${_ARCHBOOT_ISO_UPDATED_PATH}" || true
echo

cd "${_ARCHBOOT_ISO_EXT_DIR}/"
echo

## Extract the archboot iso using bsdtar
bsdtar xf "${_ARCHBOOT_ISO_OLD_PATH}"
# 7z x "${_ARCHBOOT_ISO_OLD_PATH}"
echo

rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/[BOOT]/" || true
echo

[[ -e "${_ARCHBOOT_ISO_WD}/splash.png" ]] && cp "${_ARCHBOOT_ISO_WD}/splash.png" "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/splash.png"
echo

_rename_old_files() {
	
	mv "${_ARCHBOOT_ISO_EXT_DIR}/boot"/{vmlts,vmlinuz_i686_lts} || true
	mv "${_ARCHBOOT_ISO_EXT_DIR}/boot"/{vmlinuz,vmlinuz_i686} || true
	mv "${_ARCHBOOT_ISO_EXT_DIR}/boot"/{initrd.img,initramfs_i686.img} || true
	echo
	
	mv "${_ARCHBOOT_ISO_EXT_DIR}/boot"/{vm64lts,vmlinuz_x86_64_lts} || true
	mv "${_ARCHBOOT_ISO_EXT_DIR}/boot"/{vm64,vmlinuz_x86_64} || true
	mv "${_ARCHBOOT_ISO_EXT_DIR}/boot"/{initrd64.img,initramfs_x86_64.img} || true
	echo
	
}

_update_syslinux_iso_files() {
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux"/*.{com,bin,c32} || true
	cp "/usr/lib/syslinux"/*.{com,bin,c32} "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/"
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/syslinux.cfg" || true
	
	cat << EOF > "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/syslinux.cfg"
SERIAL 0 38400
DEFAULT vesamenu.c32
PROMPT 0
MENU TITLE Arch Linux (archboot)
MENU BACKGROUND splash.png
TIMEOUT 300

F1 boot.msg
F2 options.msg

MENU WIDTH 78
MENU MARGIN 4
MENU ROWS 10
MENU VSHIFT 9
MENU TIMEOUTROW 15
MENU TABMSGROW 16
MENU CMDLINEROW 17
MENU HELPMSGROW 18
MENU HELPMSGENDROW -1

# Refer to http://syslinux.zytor.com/wiki/index.php/Doc/menu

MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

LABEL help
TEXT HELP
For general information press F1 key.
For troubleshooting and other options press F2 key.
ENDTEXT
MENU LABEL Help

LABEL arch64
TEXT HELP
Boot the Arch Linux (x86_64) archboot medium. 
It allows you to install Arch Linux or perform system maintenance.
ENDTEXT
MENU LABEL Boot Arch Linux (x86_64)
LINUX /boot/vmlinuz_x86_64
APPEND gpt loglevel=7 rootdelay=10
INITRD /boot/initramfs_x86_64.img

LABEL arch64-lts
TEXT HELP
Boot the Arch Linux LTS (x86_64) archboot medium. 
It allows you to install Arch Linux or perform system maintenance.
ENDTEXT
MENU LABEL Boot Arch Linux LTS (x86_64)
LINUX /boot/vmlinuz_x86_64_lts
APPEND gpt loglevel=7 rootdelay=10
INITRD /boot/initramfs_x86_64.img

LABEL arch32
TEXT HELP
Boot the Arch Linux (i686) archboot medium. 
It allows you to install Arch Linux or perform system maintenance.
ENDTEXT
MENU LABEL Boot Arch Linux (i686)
LINUX /boot/vmlinuz_i686
APPEND gpt loglevel=7 rootdelay=10
INITRD /boot/initramfs_i686.img

LABEL arch32-lts
TEXT HELP
Boot the Arch Linux LTS (i686) archboot medium. 
It allows you to install Arch Linux or perform system maintenance.
ENDTEXT
MENU LABEL Boot Arch Linux LTS (i686)
LINUX /boot/vmlinuz_i686_lts
APPEND gpt loglevel=7 rootdelay=10
INITRD /boot/initramfs_i686.img

LABEL existing
TEXT HELP
Boot an existing operating system. Press TAB to edit the disk and partition
number to boot.
ENDTEXT
MENU LABEL Boot existing OS
COM32 chain.c32
APPEND hd0 0

# http://www.memtest.org/
LABEL memtest
MENU LABEL Run Memtest86+ (RAM test)
LINUX /boot/memtest

LABEL hdt
MENU LABEL Run HDT (Hardware Detection Tool)
COM32 hdt.c32

LABEL reboot
MENU LABEL Reboot
COM32 reboot.c32

LABEL poweroff
MENU LABEL Power Off
COMBOOT poweroff.com

ONTIMEOUT arch32

EOF
	
}

_download_uefi_shell_tianocore() {
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/"
	
	## Download Tianocore UDK/EDK2 ShellBinPkg UEFI x86_64 "Full Shell" - For Spec. Ver. >=2.3 systems
	
	mv "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64.efi" "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64.efi.backup" || true
	echo
	
	if [[ -e "${_ARCHBOOT_ISO_WD}/shellx64.efi" ]]; then
		cp "${_ARCHBOOT_ISO_WD}/shellx64.efi" "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64.efi"
		echo
	else
		curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64.efi" "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/ShellBinPkg/UefiShell/X64/Shell.efi" || true
		echo
		
		if [[ ! "$(file "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64.efi" | grep 'executable')" ]]; then
			rm -f "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64.efi" || true
			mv "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64.efi.backup" "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64.efi" || true
		fi
	fi
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64.efi.backup" || true
	echo
	
	## Download Tianocore UDK/EDK2 EdkShellBinPkg UEFI x86_64 "Full Shell" - For Spec. Ver. <2.3 systems
	
	mv "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64_old.efi" "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64_old.efi.backup" || true
	echo
	
	if [[ -e "${_ARCHBOOT_ISO_WD}/shellx64_old.efi" ]]; then
		cp "${_ARCHBOOT_ISO_WD}/shellx64_old.efi" "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64_old.efi"
		echo
	else
		curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64_old.efi" "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/EdkShellBinPkg/FullShell/X64/Shell_Full.efi" || true
		echo
		
		if [[ ! "$(file "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64_old.efi" | grep 'executable')" ]]; then
			rm -f "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64_old.efi" || true
			mv "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64_old.efi.backup" "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64_old.efi" || true
		fi
	fi
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/efi/shell/shellx64_old.efi.backup" || true
	echo
	
}

_update_grub2_uefi_arch_specific_iso_files() {
	
	[[ "${_UEFI_ARCH}" == "x86_64" ]] && _SPEC_UEFI_ARCH="x64"
	[[ "${_UEFI_ARCH}" == "i386" ]] && _SPEC_UEFI_ARCH="ia32"
	
	rm -f "${grub2_uefi_mp}/efi/boot/boot${_SPEC_UEFI_ARCH}.efi" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/efi/boot/boot${_SPEC_UEFI_ARCH}.efi" || true
	echo
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/${_UEFI_ARCH}-efi" || true
	echo
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2"
	echo
	
	## Create grub.cfg for grub-mkstandalone memdisk for boot${_SPEC_UEFI_ARCH}.efi
	cat << EOF > "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/grub_standalone_archboot.cfg"

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

search --file --no-floppy --set=archboot "/efi/grub2/grub_archboot.cfg"
source "(\${archboot})/efi/grub2/grub_archboot.cfg"

EOF
	
	echo
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/boot/grub"
	cp "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/grub_standalone_archboot.cfg" "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/boot/grub/grub.cfg"
	echo
	
	__ARCHBOOT_ISO_WD="${PWD}/"
	
	cd "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/"
	
	grub-mkstandalone --directory="/usr/lib/grub/${_UEFI_ARCH}-efi" --format="${_UEFI_ARCH}-efi" --compression="xz" --output="${grub2_uefi_mp}/efi/boot/bootx64.efi" "boot/grub/grub.cfg"
	
	cd "${__ARCHBOOT_ISO_WD}/"
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/boot/grub/"
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/boot"
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/efi/boot/"
	cp "${grub2_uefi_mp}/efi/boot/boot${_SPEC_UEFI_ARCH}.efi" "${_ARCHBOOT_ISO_EXT_DIR}/efi/boot/boot${_SPEC_UEFI_ARCH}.efi"
	
	echo
	
	unset _UEFI_ARCH
	unset _SPEC_UEFI_ARCH
	
}

_update_grub2_uefi_iso_files() {
	
	grub2_uefi_mp="$(mktemp -d /tmp/grub2_uefi_mp.XXX)"
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2" || true
	echo
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2"
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/efi/boot"
	echo
	
	# Create a blank image to be converted to ESP IMG
	dd if="/dev/zero" of="${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/grub2_uefi.bin" bs="1024" count="4096"
	
	# Create a FAT12 FS with Volume label "grub2_uefi"
	mkfs.vfat -F12 -S 512 -n "grub2_uefi" "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/grub2_uefi.bin"
	echo
	
	## Mount the ${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/grub2_uefi.bin image at ${grub2_uefi_mp} as loop 
	if ! [[ "$(lsmod | grep ^loop)" ]]; then
		modprobe -q loop || echo "Your hostsystem has a different kernel version installed, please load loop module first on hostsystem!"
		echo
	fi
	
	LOOP_DEVICE="$(losetup --show --find "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/grub2_uefi.bin")"
	mount -o rw,flush -t vfat "${LOOP_DEVICE}" "${grub2_uefi_mp}"
	echo
	
	mkdir -p "${grub2_uefi_mp}/efi/boot/"
	echo
	
	_UEFI_ARCH="x86_64"
	_update_grub2_uefi_arch_specific_iso_files
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
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/efi/boot/grub.cfg" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/grub.cfg" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2//efi/grub2/grub_archboot.cfg" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2//efi/grub2/grub_standalone_archboot.cfg" || true
	echo
	
	cp "/usr/share/grub/unicode.pf2" "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/"
	echo
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/locale/" || true
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/locale/"
	echo
	
	## Taken from /usr/sbin/grub-install
	# for dir in "/usr/share/locale"/*; do
		# if test -f "${dir}/LC_MESSAGES/grub.mo"; then
			# cp -f "${dir}/LC_MESSAGES/grub.mo" "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/locale/${dir##*/}.mo"
			echo
		# fi
	# done
	
	cat << EOF > "${_ARCHBOOT_ISO_EXT_DIR}/efi/grub2/grub_archboot.cfg"

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

# search --file --no-floppy --set=archboot "/efi/grub2/grub_archboot.cfg"
# search --file --no-floppy --set=archboot "/efi/grub2/grub_standalone_archboot.cfg"

set pager="1"
# set debug="all"

set locale_dir="(\${archboot})/efi/grub2/locale"

if [ "\${grub_platform}" == "efi" ]; then
    insmod efi_gop
    insmod efi_uga
    insmod video_bochs
    insmod video_cirrus
fi

insmod font

if loadfont "(\${archboot})/efi/grub2/unicode.pf2" ; then
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

if [ "\${grub_platform}" == "efi" ]; then

    menuentry "UEFI \${_UEFI_ARCH} Shell 2.0 - For Spec. Ver. >=2.3 systems" {
        set root="\${archboot}"
        chainloader /efi/shell/shell\${_SPEC_UEFI_ARCH}.efi
    }

    menuentry "UEFI \${_UEFI_ARCH} Shell 1.0 - For Spec. Ver. <2.3 systems" {
        set root="\${archboot}"
        chainloader /efi/shell/shell\${_SPEC_UEFI_ARCH}_old.efi
    }

fi

EOF
	
	echo
	
}

_remove_i686_iso_files() {
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/vmlinuz_i686_lts" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/vmlinuz_i686" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/initramfs_i686.img" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/packages/archboot_packages_i686.squashfs" || true
	echo
	
}

_remove_x86_64_iso_files() {
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/vmlinuz_x86_64_lts" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/vmlinuz_x86_64" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/initramfs_x86_64.img" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/packages/archboot_packages_x86_64.squashfs" || true
	echo
	
}

_update_arch_setup_initramfs() {
	
	_initramfs_ext="$(mktemp -d /tmp/${_initramfs_name}_ext.XXXXXXXXXX)"
	echo
	
	cd "${_initramfs_ext}/"
	
	if [[ -e "${_ARCHBOOT_ISO_EXT_DIR}/boot/${_initramfs_name}.img" ]]; then
		bsdtar xf "${_ARCHBOOT_ISO_EXT_DIR}/boot/${_initramfs_name}.img"
		echo
		
		mv "${_initramfs_ext}/arch/setup" "${_initramfs_ext}/arch/setup.old"
		cp --verbose "${_ARCHBOOT_ISO_WD}/setup" "${_initramfs_ext}/arch/setup"
		chmod 755 "${_initramfs_ext}/arch/setup"
		echo
		
		cd "${_initramfs_ext}/"
		
		find . -print0 | bsdcpio -0oH newc | xz --check=crc32 --lzma2=dict=1MiB > "${_ARCHBOOT_ISO_WD}/${_initramfs_name}.img"
		echo
		
		rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/${_initramfs_name}.img" || true
		cp --verbose "${_ARCHBOOT_ISO_WD}/${_initramfs_name}.img" "${_ARCHBOOT_ISO_EXT_DIR}/boot/${_initramfs_name}.img"
		rm -f "${_ARCHBOOT_ISO_WD}/${_initramfs_name}.img"
		echo
	fi
	
	rm -rf "${_initramfs_ext}/"
	echo
	
	unset _initramfs_ext
	unset _initramfs_name
	echo
	
}

## Not currently used - simply left untouched for now
_download_pkgs() {
	
	cd "${_ARCHBOOT_ISO_WD}/"
	
	if [[ "${_pkg_arch}" == 'any' ]]; then
		curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 "http://www.archlinux.org/packages/${_repo}/any/${_package}/download/"
		echo
	else
		curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 "http://www.archlinux.org/packages/${_repo}/x86_64/${_package}/download/"
		echo
		
		curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 "http://www.archlinux.org/packages/${_repo}/i686/${_package}/download/"
		echo
	fi
	
	unset _repo
	unset _package
	unset _pkg_arch
	echo
	
}

_rename_old_files

[[ "${_UPDATE_SYSLINUX}" == "1" ]] && _update_syslinux_iso_files

[[ "${_UPDATE_UEFI_SHELL}" == "1" ]] && _download_uefi_shell_tianocore

[[ "${_UPDATE_GRUB2_UEFI}" == "1" ]] && _update_grub2_uefi_iso_files

[[ "${_REMOVE_i686}" == "1" ]] && _remove_i686_iso_files

[[ "${_REMOVE_x86_64}" == "1" ]] && _remove_x86_64_iso_files

if [[ "${_UPDATE_SETUP}" == "1" ]] && [[ -e "${_ARCHBOOT_ISO_WD}/setup" ]]; then
	cd "${_ARCHBOOT_ISO_WD}/"
	
	## The old method I tried, mount -o ro -t iso9660 /dev/sr0 /src, mv /arch/setup /arch/setup.old, cp /src/arch/setup /arch/setup, umount /dev/sr0
	# cp ${_ARCHBOOT_ISO_WD}/setup ${_ARCHBOOT_ISO_EXT_DIR}/arch/setup
	
	## Extracting using bsdtar, replacing /arch/setup and recompressing the iniramfs archive does not work. Archive format not compatible with initramfs format.
	## Compressing using bsdcpio and using 'newc' archive format works, taken from falconindy's geninit program.
	
	_initramfs_name="initramfs_x86_64"
	_update_arch_setup_initramfs
	
	_initramfs_name="initramfs_i686"
	_update_arch_setup_initramfs
	
	echo
fi

## Re-create the archboot ISO
cd "${_ARCHBOOT_ISO_WD}/"

## Generate the BIOS+UEFI+ISOHYBRID ISO image using xorriso (extra/libisoburn package) in mkisofs emulation mode
echo "Generating the modified ISO ..."
xorriso -as mkisofs \
	-iso-level 3 -rock -joliet \
	-max-iso9660-filenames -omit-period \
	-omit-version-number -allow-leading-dots \
	-relaxed-filenames -allow-lowercase -allow-multidot \
	-volid "ARCHBOOT" \
	-p "prepared by ${_BASENAME}" \
	-eltorito-boot boot/syslinux/isolinux.bin \
	-eltorito-catalog boot/syslinux/boot.cat \
	-no-emul-boot -boot-load-size 4 -boot-info-table \
	-eltorito-alt-boot --efi-boot efi/grub2/grub2_uefi.bin -no-emul-boot \
	-isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin \
	-output "${_ARCHBOOT_ISO_UPDATED_PATH}" "${_ARCHBOOT_ISO_EXT_DIR}/" > /dev/null 2>&1
echo

rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/"
echo

set +x

if [[ -e "${_ARCHBOOT_ISO_UPDATED_PATH}" ]]; then
	echo
	echo "Updated iso has been saved at ${_ARCHBOOT_ISO_UPDATED_PATH} ."
	echo
else
	echo
	echo "No updated iso found at ${_ARCHBOOT_ISO_UPDATED_PATH} due to some error."
	echo "Check the script and try again."
	echo
fi

unset _UPDATE_SYSLINUX
unset _UPDATE_UEFI_SHELL
unset _UPDATE_GRUB2_UEFI
unset _UPDATE_SETUP
unset _REMOVE_i686
unset _REMOVE_x86_64
unset _ARCHBOOT_ISO_OLD_PATH
unset _ARCHBOOT_ISO_WD
unset _ARCHBOOT_ISO_OLD_NAME
unset _ARCHBOOT_ISO_EXT_DIR
unset _ARCHBOOT_ISO_UPDATED_NAME
unset _ARCHBOOT_ISO_UPDATED_PATH
