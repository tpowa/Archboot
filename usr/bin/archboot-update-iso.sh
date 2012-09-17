#!/usr/bin/env bash
# Script for updating existing Archboot iso with newer UEFI shell, GRUB UEFI, and/or /arch/setup script in the initramfs files
# Contributed by "Keshav P R" <the.ridikulus.rat aatt geemmayil ddoott ccoomm>

[[ -z "${_REMOVE_i686}" ]] && _REMOVE_i686="0"
[[ -z "${_REMOVE_x86_64}" ]] && _REMOVE_x86_64="0"

[[ -z "${_UPDATE_SETUP}" ]] && _UPDATE_SETUP="1"
[[ -z "${_UPDATE_UEFI_SHELL}" ]] && _UPDATE_UEFI_SHELL="1"
[[ -z "${_UPDATE_UEFI_REFIND_BIN}" ]] && _UPDATE_UEFI_REFIND_BIN="1"
[[ -z "${_UPDATE_UEFI_GUMMIBOOT}" ]] && _UPDATE_UEFI_GUMMIBOOT="1"

[[ -z "${_UPDATE_SYSLINUX}" ]] && _UPDATE_SYSLINUX="1"
[[ -z "${_UPDATE_SYSLINUX_CONFIG}" ]] && _UPDATE_SYSLINUX_CONFIG="1"
[[ -z "${_UPDATE_GRUB_UEFI}" ]] && _UPDATE_GRUB_UEFI="1"
[[ -z "${_UPDATE_GRUB_UEFI_CONFIG}" ]] && _UPDATE_GRUB_UEFI_CONFIG="1"

[[ "${_UPDATE_SYSLINUX}" == "1" ]] && _UPDATE_SYSLINUX_CONFIG="1"
[[ "${_UPDATE_GRUB_UEFI}" == "1" ]] && _UPDATE_GRUB_UEFI_CONFIG="1"

[[ -z "${_UEFI_ARCH}" ]] && _UEFI_ARCH="x86_64"

[[ "${_UEFI_ARCH}" == "x86_64" ]] && _SPEC_UEFI_ARCH="x64"
[[ "${_UEFI_ARCH}" == "i386" ]] && _SPEC_UEFI_ARCH="ia32"

#############################

_BASENAME="$(basename "${0}")"

_ARCHBOOT_ISO_OLD_PATH="${1}"

_ARCHBOOT_ISO_WD="$(dirname "${_ARCHBOOT_ISO_OLD_PATH}")"
_ARCHBOOT_ISO_OLD_NAME="$(basename "${_ARCHBOOT_ISO_OLD_PATH}" | sed 's|\.iso||g')"

_ARCHBOOT_ISO_EXT_DIR="$(mktemp -d /tmp/archboot_iso_ext.XXXXXXXXXX)"

#############################

if [[ "${_REMOVE_x86_64}" != "1" ]] && [[ "${_REMOVE_i686}" != "1" ]]; then
	_ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}-updated-dual"
fi

if [[ "${_REMOVE_x86_64}" != "1" ]] && [[ "${_REMOVE_i686}" == "1" ]]; then
	_ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}-updated-x86_64"
fi

if [[ "${_REMOVE_x86_64}" == "1" ]] && [[ "${_REMOVE_i686}" != "1" ]]; then
	_ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}-updated-i686"
fi

_ARCHBOOT_ISO_UPDATED_PATH="${_ARCHBOOT_ISO_WD}/${_ARCHBOOT_ISO_UPDATED_NAME}.iso"

#############################

echo

if [[ -z "${1}" ]]; then
	echo
	echo "Usage: ${_BASENAME} <Absolute Path to Archboot ISO>"
	echo
	echo "Example: ${_BASENAME} /home/user/Desktop/archlinux-2012.01-1-archboot.iso"
	echo
	echo "Updated iso will be saved at /home/user/Desktop/archlinux-2012.01-1-archboot_updated.iso "
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
bsdtar -C "${_ARCHBOOT_ISO_EXT_DIR}/" -xf "${_ARCHBOOT_ISO_OLD_PATH}"
# 7z x "${_ARCHBOOT_ISO_OLD_PATH}"
echo

rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/[BOOT]/" || true
echo

mv "${_ARCHBOOT_ISO_EXT_DIR}/efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI_" || true
mv "${_ARCHBOOT_ISO_EXT_DIR}/EFI_" "${_ARCHBOOT_ISO_EXT_DIR}/EFI" || true
echo

[[ -e "${_ARCHBOOT_ISO_WD}/splash.png" ]] && cp -f "${_ARCHBOOT_ISO_WD}/splash.png" "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/splash.png"
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
	cp -f "/usr/lib/syslinux"/*.{com,bin,c32} "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/"
	
}

_update_syslinux_iso_config() {
	
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

EOF
	
	if [[ "${_REMOVE_x86_64}" != "1" ]]; then
		cat << EOF >> "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/syslinux.cfg"

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

EOF
	fi
	
	if [[ "${_REMOVE_i686}" != "1" ]]; then
		cat << EOF >> "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/syslinux.cfg"

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

EOF
	fi
	
	cat << EOF >> "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/syslinux.cfg"

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

EOF
	
	if [[ "${_REMOVE_x86_64}" != "1" ]]; then
		cat << EOF >> "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/syslinux.cfg"

ONTIMEOUT arch64

EOF
	elif [[ "${_REMOVE_x86_64}" == "1" ]] && [[ "${_REMOVE_i686}" != "1" ]]; then
		cat << EOF >> "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/syslinux.cfg"

ONTIMEOUT arch32

EOF
	fi
	
}

_download_uefi_shell_tianocore() {
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/"
	
	mv "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v2.efi" || true
	mv "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_old.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v1.efi" || true
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/EFI/shell/" || true
	echo
	
	## Download Tianocore UDK/EDK2 ShellBinPkg UEFI x86_64 "Full Shell" - For Spec. Ver. >=2.3 systems
	
	mv "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v2.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v2.efi.backup" || true
	echo
	
	if [[ -e "${_ARCHBOOT_ISO_WD}/shellx64_v2.efi" ]]; then
		cp -f "${_ARCHBOOT_ISO_WD}/shellx64_v2.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v2.efi"
		echo
	else
		curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v2.efi" "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/ShellBinPkg/UefiShell/X64/Shell.efi" || true
		echo
		
		if [[ ! "$(file "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v2.efi" | grep 'executable')" ]]; then
			rm -f "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v2.efi" || true
			mv "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v2.efi.backup" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v2.efi" || true
		fi
	fi
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v2.efi.backup" || true
	echo
	
	## Download Tianocore UDK/EDK2 EdkShellBinPkg UEFI x86_64 "Full Shell" - For Spec. Ver. <2.3 systems
	
	mv "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v1.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v1.efi.backup" || true
	echo
	
	if [[ -e "${_ARCHBOOT_ISO_WD}/shellx64_v1.efi" ]]; then
		cp -f "${_ARCHBOOT_ISO_WD}/shellx64_v1.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v1.efi"
		echo
	else
		curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v1.efi" "https://edk2.svn.sourceforge.net/svnroot/edk2/trunk/edk2/EdkShellBinPkg/FullShell/X64/Shell_Full.efi" || true
		echo
		
		if [[ ! "$(file "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v1.efi" | grep 'executable')" ]]; then
			rm -f "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v1.efi" || true
			mv "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v1.efi.backup" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v1.efi" || true
		fi
	fi
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/shellx64_v1.efi.backup" || true
	echo
	
}

_update_uefi_refind_bin_sourceforge() {
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/packages/" || true
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/packages/refind-bin.zip" || true
	echo
	
	## Download latest rEFInd bin archive from sourceforge
	curl --verbose -f -C - --ftp-pasv --retry 3 --retry-delay 3 -o "${_ARCHBOOT_ISO_EXT_DIR}/packages/refind-bin.zip" -L "http://sourceforge.net/projects/refind/files/latest/download"
	
}

_update_uefi_gummiboot_USB_files() {
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/EFI/boot/" || true
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/loader/" || true
	echo
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/EFI/boot"
	cp -f "/boot/efi/EFI/arch/gummiboot/gummiboot${_SPEC_UEFI_ARCH}.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/boot/boot${_SPEC_UEFI_ARCH}.efi"
	cp -f "/boot/efi/EFI/arch/efilinux/efilinux${_SPEC_UEFI_ARCH}.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/boot/efilinux${_SPEC_UEFI_ARCH}.efi"
	echo
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/loader/entries/"
	echo
	
	cat << EOF > "${_ARCHBOOT_ISO_EXT_DIR}/loader/entries/loader.conf"
timeout 3
default archboot-${_UEFI_ARCH}
EOF
	echo
	
	cat << EOF > "${_ARCHBOOT_ISO_EXT_DIR}/loader/entries/archboot-${_UEFI_ARCH}.conf"
title   Arch Linux (${_UEFI_ARCH}) archboot
linux   /boot/vmlinuz_${_UEFI_ARCH}
initrd  /boot/initramfs_${_UEFI_ARCH}.img
options gpt loglevel=7 add_efi_memmap none=UEFI_ARCH_${_UEFI_ARCH}
EOF
	echo
	
	cat << EOF > "${_ARCHBOOT_ISO_EXT_DIR}/loader/entries/archboot-${_UEFI_ARCH}-lts.conf"
title   Arch Linux LTS (${_UEFI_ARCH}) archboot
efi     /EFI/boot/efilinux${_SPEC_UEFI_ARCH}.efi
options -f \\boot\\vmlinuz_x86_64_lts gpt loglevel=7 add_efi_memmap none=UEFI_ARCH_${_UEFI_ARCH} initrd=\\boot\\initramfs_${_UEFI_ARCH}.img
EOF
	echo
	
	cat << EOF > "${_ARCHBOOT_ISO_EXT_DIR}/loader/entries/uefi-shell-${_UEFI_ARCH}-v2.conf"
title   UEFI ${_UEFI_ARCH} Shell v2 - For Spec. Ver. >=2.3 systems
efi     /EFI/tools/shell${_SPEC_UEFI_ARCH}_v2.efi
EOF
	echo
	
	cat << EOF > "${_ARCHBOOT_ISO_EXT_DIR}/loader/entries/uefi-shell-${_UEFI_ARCH}-v1.conf"
title   UEFI ${_UEFI_ARCH} Shell v1 - For Spec. Ver. <2.3 systems
efi     /EFI/tools/shell${_SPEC_UEFI_ARCH}_v1.efi
EOF
	echo
	
}

_update_grub_uefi_arch_specific_CD_files() {
	
	rm -f "${grub_uefi_mp}/EFI/boot/boot${_SPEC_UEFI_ARCH}.efi" || true
	echo
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/${_UEFI_ARCH}-efi" || true
	echo
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub"
	echo
	
	## Create grub.cfg for grub-mkstandalone memdisk for boot${_SPEC_UEFI_ARCH}.efi
	cat << EOF > "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub_standalone_archboot.cfg"

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
	
	echo
	
	cp -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub_standalone_archboot.cfg" "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub.cfg"
	
	__ARCHBOOT_ISO_WD="${PWD}/"
	
	cd "${_ARCHBOOT_ISO_EXT_DIR}/"
	
	grub-mkstandalone --directory="/usr/lib/grub/${_UEFI_ARCH}-efi" --format="${_UEFI_ARCH}-efi" --compression="xz" --output="${grub_uefi_mp}/EFI/boot/bootx64.efi" "boot/grub/grub.cfg"
	
	cd "${__ARCHBOOT_ISO_WD}/"
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub.cfg"
	
	echo
	
}

_update_grub_uefi_CD_files() {
	
	grub_uefi_mp="$(mktemp -d /tmp/grub_uefi_mp.XXX)"
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub" || true
	echo
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub"
	echo
	
	# Create a blank image to be converted to ESP IMG
	dd if="/dev/zero" of="${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub_uefi_x86_64.bin" bs="1024" count="4096"
	
	# Create a FAT12 FS with Volume label "grub_uefi"
	mkfs.vfat -F12 -S 512 -n "grub_uefi" "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub_uefi_x86_64.bin"
	echo
	
	## Mount the ${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub_uefi_x86_64.bin image at ${grub_uefi_mp} as loop 
	if ! [[ "$(lsmod | grep ^loop)" ]]; then
		modprobe -q loop || echo "Your hostsystem has a different kernel version installed, please load loop module first on hostsystem!"
		echo
	fi
	
	LOOP_DEVICE="$(losetup --show --find "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub_uefi_x86_64.bin")"
	mount -o rw,flush -t vfat "${LOOP_DEVICE}" "${grub_uefi_mp}"
	echo
	
	mv "${grub_uefi_mp}/efi" "${grub_uefi_mp}/EFI_" || true
	mv "${grub_uefi_mp}/EFI_" "${grub_uefi_mp}/EFI" || true
	mkdir -p "${grub_uefi_mp}/EFI/boot/"
	echo
	
	_UEFI_ARCH="x86_64"
	_update_grub_uefi_arch_specific_CD_files
	echo
	
	# umount images and loop
	umount "${grub_uefi_mp}"
	losetup --detach "${LOOP_DEVICE}"
	echo
	
	rm -rf "${grub_uefi_mp}/"
	echo
	
	unset grub_uefi_mp
	unset LOOP_DEVICE
	echo
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/fonts/"
	cp -f "/usr/share/grub/unicode.pf2" "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/fonts/"
	echo
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/locale/" || true
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/locale/"
	echo
	
	## Taken from /usr/sbin/grub-install
	# for dir in "/usr/share/locale"/*; do
		# if test -f "${dir}/LC_MESSAGES/grub.mo"; then
			# cp -f "${dir}/LC_MESSAGES/grub.mo" "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/locale/${dir##*/}.mo"
			echo
		# fi
	# done
	
}

_update_grub_uefi_CD_config() {
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub_archboot.cfg" || true
	
	cat << EOF > "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub_archboot.cfg"

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
	
	if [[ "${_REMOVE_x86_64}" != "1" ]]; then
		cat << EOF >> "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub_archboot.cfg"

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
	
	if [[ "${_REMOVE_i686}" != "1" ]]; then
		cat << EOF >> "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub_archboot.cfg"

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
	
	cat << EOF >> "${_ARCHBOOT_ISO_EXT_DIR}/boot/grub/grub_archboot.cfg"

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
		
		find . -print0 | bsdcpio -0oH newc | lzma > "${_ARCHBOOT_ISO_WD}/${_initramfs_name}.img"
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

[[ "${_REMOVE_i686}" == "1" ]] && _remove_i686_iso_files

[[ "${_REMOVE_x86_64}" == "1" ]] && _remove_x86_64_iso_files

if [[ "${_UPDATE_SETUP}" == "1" ]] && [[ -e "${_ARCHBOOT_ISO_WD}/setup" ]]; then
	cd "${_ARCHBOOT_ISO_WD}/"
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/arch/" || true
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/arch/setup" || true
	cp -f "${_ARCHBOOT_ISO_WD}/setup" "${_ARCHBOOT_ISO_EXT_DIR}/arch/setup"
	
	echo
	
	if [[ "${_REMOVE_x86_64}" != "1" ]]; then
		_initramfs_name="initramfs_x86_64"
		_update_arch_setup_initramfs
	fi
	
	if [[ "${_REMOVE_i686}" != "1" ]]; then
		_initramfs_name="initramfs_i686"
		_update_arch_setup_initramfs
	fi
	
	echo
fi

[[ "${_UPDATE_UEFI_SHELL}" == "1" ]] && _download_uefi_shell_tianocore

# [[ "${_UPDATE_UEFI_REFIND_BIN}" == "1" ]] && _update_uefi_refind_bin_sourceforge

[[ "${_UPDATE_UEFI_GUMMIBOOT}" == "1" ]] && _update_uefi_gummiboot_USB_files

[[ "${_UPDATE_SYSLINUX}" == "1" ]] && _update_syslinux_iso_files

[[ "${_UPDATE_SYSLINUX_CONFIG}" == "1" ]] && _update_syslinux_iso_config

[[ "${_UPDATE_GRUB_UEFI}" == "1" ]] && _update_grub_uefi_CD_files

[[ "${_UPDATE_GRUB_UEFI_CONFIG}" == "1" ]] && _update_grub_uefi_CD_config

cd "${_ARCHBOOT_ISO_WD}/"

## Generate the BIOS+UEFI+ISOHYBRID ISO image using xorriso (extra/libisoburn package) in mkisofs emulation mode
echo "Generating the modified ISO ..."
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
	-eltorito-alt-boot --efi-boot boot/grub/grub_uefi_x86_64.bin -no-emul-boot \
	-isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin \
	-output "${_ARCHBOOT_ISO_UPDATED_PATH}" "${_ARCHBOOT_ISO_EXT_DIR}/" &> "/tmp/archboot_update_xorriso.log"
echo

set +x

if [[ -e "${_ARCHBOOT_ISO_UPDATED_PATH}" ]]; then
	echo
	echo "Updated iso has been saved at ${_ARCHBOOT_ISO_UPDATED_PATH} ."
	echo
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/"
	echo
else
	echo
	echo "No updated iso found at ${_ARCHBOOT_ISO_UPDATED_PATH} due to some error."
	echo "Check the script and try again."
	echo
fi

unset _UEFI_ARCH
unset _SPEC_UEFI_ARCH
unset _REMOVE_i686
unset _REMOVE_x86_64
unset _UPDATE_SETUP
unset _UPDATE_UEFI_SHELL
unset _UPDATE_UEFI_REFIND_BIN
unset _UPDATE_UEFI_GUMMIBOOT
unset _UPDATE_SYSLINUX
unset _UPDATE_SYSLINUX_CONFIG
unset _UPDATE_GRUB_UEFI
unset _UPDATE_GRUB_UEFI_CONFIG
unset _ARCHBOOT_ISO_OLD_PATH
unset _ARCHBOOT_ISO_WD
unset _ARCHBOOT_ISO_OLD_NAME
unset _ARCHBOOT_ISO_EXT_DIR
unset _ARCHBOOT_ISO_UPDATED_NAME
unset _ARCHBOOT_ISO_UPDATED_PATH
