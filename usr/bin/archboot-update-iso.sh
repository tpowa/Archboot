#!/usr/bin/env bash
# Script for updating existing Archboot iso with newer UEFI shell, rEFInd, and /arch/setup script in the initramfs files
# Contributed by "Keshav Padram" <the ddoott ridikulus ddoott rat aatt geemmayil ddoott ccoomm>
# change to english locale!
export LANG="en_US"

[[ -z "${_REMOVE_i686}" ]] && _REMOVE_i686="0"
[[ -z "${_REMOVE_x86_64}" ]] && _REMOVE_x86_64="0"

[[ -z "${_REMOVE_PACKAGES}" ]] && _REMOVE_PACKAGES="0"

[[ -z "${_UPDATE_CD_UEFI}" ]] && _UPDATE_CD_UEFI="0"

[[ -z "${_UPDATE_SETUP}" ]] && _UPDATE_SETUP="1"
[[ -z "${_UPDATE_UEFI_SHELL}" ]] && _UPDATE_UEFI_SHELL="1"
[[ -z "${_UPDATE_UEFI_GUMMIBOOT}" ]] && _UPDATE_UEFI_GUMMIBOOT="1"
[[ -z "${_UPDATE_UEFI_PREBOOTLOADER}" ]] && _UPDATE_UEFI_PREBOOTLOADER="1"
[[ -z "${_UPDATE_UEFI_LOCKDOWN_MS}" ]] && _UPDATE_UEFI_LOCKDOWN_MS="1"
[[ -z "${_UPDATE_UEFI_REFIND}" ]] && _UPDATE_UEFI_REFIND="1"

[[ -z "${_UPDATE_SYSLINUX}" ]] && _UPDATE_SYSLINUX="1"
[[ -z "${_UPDATE_SYSLINUX_CONFIG}" ]] && _UPDATE_SYSLINUX_CONFIG="1"

[[ "${_UPDATE_SYSLINUX}" == "1" ]] && _UPDATE_SYSLINUX_CONFIG="1"

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
	[[ "${_UPDATE_CD_UEFI}" == "1" ]] && _ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}"-updated-dual-uefi
	[[ "${_REMOVE_PACKAGES}" == "1" ]] && _ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}"-updated-dual-ftp
	[[ "${_REMOVE_PACKAGES}" == "1" && "${_UPDATE_CD_UEFI}" == "1" ]] && _ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}"-updated-dual-uefi-ftp
fi

if [[ "${_REMOVE_x86_64}" != "1" ]] && [[ "${_REMOVE_i686}" == "1" ]]; then
	_ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}-updated-x86_64"
	[[ "${_UPDATE_CD_UEFI}" == "1" ]] && _ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}"-updated-x86_64-uefi
	[[ "${_REMOVE_PACKAGES}" == "1" ]] && _ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}"-updated-x86_64-ftp
        [[ "${_REMOVE_PACKAGES}" == "1" && "${_UPDATE_CD_UEFI}" == "1" ]] && _ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}"-updated-x86_64-uefi-ftp
fi

if [[ "${_REMOVE_x86_64}" == "1" ]] && [[ "${_REMOVE_i686}" != "1" ]]; then
	_ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}-updated-i686"
        [[ "${_REMOVE_PACKAGES}" == "1" ]] && _ARCHBOOT_ISO_UPDATED_NAME="${_ARCHBOOT_ISO_OLD_NAME}"-updated-i686-ftp
fi

_ARCHBOOT_ISO_UPDATED_PATH="${_ARCHBOOT_ISO_WD}/${_ARCHBOOT_ISO_UPDATED_NAME}.iso"

#############################

echo

if [[ -z "${1}" ]]; then
	echo
	echo "Usage: ${_BASENAME} <Absolute Path to Archboot ISO>"
	echo
	echo "Example: ${_BASENAME} /home/user/Desktop/archlinux-2012.12-1-archboot.iso"
	echo
	echo "Updated iso will be saved at /home/user/Desktop/archlinux-2012.12-1-archboot_updated.iso "
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

### check for available loop devices in a container
for i in $(seq 0 7); do
    ! [[ -e /dev/loop$i ]] && mknod /dev/loop$i b 7 $i
done
! [[ -e /dev/loop-control ]] && mknod /dev/loop-control c 10 237

set -x

## Remove old files
rm -f "${_ARCHBOOT_ISO_UPDATED_PATH}" || true
echo

cd "${_ARCHBOOT_ISO_EXT_DIR}/"
echo

## Extract the archboot iso using bsdtar
bsdtar -C "${_ARCHBOOT_ISO_EXT_DIR}/" -xf "${_ARCHBOOT_ISO_OLD_PATH}"
# 7z x -o "${_ARCHBOOT_ISO_EXT_DIR}/" "${_ARCHBOOT_ISO_OLD_PATH}"
echo

rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/[BOOT]/" || true
echo

[[ -e "${_ARCHBOOT_ISO_WD}/splash.png" ]] && cp -f "${_ARCHBOOT_ISO_WD}/splash.png" "${_ARCHBOOT_ISO_EXT_DIR}/boot/syslinux/splash.png"
echo

_update_uefi_prebootloader_files() {
	cp -f "/usr/lib/prebootloader/PreLoader.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/boot/bootx64.efi"
	cp -f "/usr/lib/prebootloader/HashTool.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/boot/HashTool.efi"
	echo
}

_update_uefi_lockdown_ms_files() {
	cp -f "/usr/lib/lockdown-ms/LockDown_ms.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/boot/LockDown_ms.efi"
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

_update_uefi_gummiboot_USB_files() {
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/EFI/boot" || true
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/EFI/boot"
	cp -f "/usr/lib/gummiboot/gummiboot${_SPEC_UEFI_ARCH}.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/boot/loader.efi"
	echo
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/loader" || true
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/loader/entries"
	echo
	
	cat << GUMEOF > "${_ARCHBOOT_ISO_EXT_DIR}/loader/loader.conf"
timeout 5
default archboot-${_UEFI_ARCH}-main
GUMEOF
	
	cat << GUMEOF > "${_ARCHBOOT_ISO_EXT_DIR}/loader/entries/archboot-${_UEFI_ARCH}-main.conf"
title    Arch Linux ${_UEFI_ARCH} Archboot
linux    /boot/vmlinuz_${_UEFI_ARCH}
initrd   /boot/initramfs_${_UEFI_ARCH}.img
options  gpt loglevel=7 efi_pstore.pstore_disable=1 efi_no_storage_paranoia add_efi_memmap
GUMEOF
		
	cat << GUMEOF > "${_ARCHBOOT_ISO_EXT_DIR}/loader/entries/uefi-shell-${_UEFI_ARCH}-v2.conf"
title    UEFI Shell ${_UEFI_ARCH} v2
efi      /EFI/tools/shell${_SPEC_UEFI_ARCH}_v2.efi
GUMEOF
	
	cat << GUMEOF > "${_ARCHBOOT_ISO_EXT_DIR}/loader/entries/uefi-shell-${_UEFI_ARCH}-v1.conf"
title    UEFI Shell ${_UEFI_ARCH} v1
efi      /EFI/tools/shell${_SPEC_UEFI_ARCH}_v1.efi
GUMEOF
	
	cat << GUMEOF > "${_ARCHBOOT_ISO_EXT_DIR}/loader/entries/refind-${_UEFI_ARCH}-gummiboot.conf"
title    rEFInd ${_UEFI_ARCH}
efi      /EFI/refind/refind${_SPEC_UEFI_ARCH}.efi
GUMEOF
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/EFI/efilinux/" || true
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/EFI/efilinux"
	cp -f "/usr/lib/efilinux/efilinux${_SPEC_UEFI_ARCH}.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/efilinux/efilinux${_SPEC_UEFI_ARCH}.efi"
	echo
	
	echo
	
}

_update_uefi_rEFInd_USB_files() {
	
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/EFI/refind/" || true
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/drivers_${_SPEC_UEFI_ARCH}" || true
	echo
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/EFI/refind"
	cp -f "/usr/lib/refind/refind_${_SPEC_UEFI_ARCH}.efi" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/refind/refind${_SPEC_UEFI_ARCH}.efi"
	# cp -rf "/usr/share/refind/icons" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/refind/icons" || true
	# cp -rf "/usr/share/refind/fonts" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/refind/fonts" || true
	echo
	
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools"
	cp -rf "/usr/lib/refind/drivers_${_SPEC_UEFI_ARCH}" "${_ARCHBOOT_ISO_EXT_DIR}/EFI/tools/drivers_${_SPEC_UEFI_ARCH}"
	echo
	
	cat << EOF > "${_ARCHBOOT_ISO_EXT_DIR}/EFI/refind/refind.conf"
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
    options "gpt loglevel=7 efi_pstore.pstore_disable=1 efi_no_storage_paranoia add_efi_memmap"
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
	echo
	
}

_remove_i686_iso_files() {
	
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/vmlinuz_i686" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/initramfs_i686.img" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/packages/archboot_packages_i686.squashfs" || true
	echo
	
}

_remove_x86_64_iso_files() {
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/EFI" || true
        rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/loader" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/vmlinuz_x86_64" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/boot/initramfs_x86_64.img" || true
	rm -f "${_ARCHBOOT_ISO_EXT_DIR}/packages/archboot_packages_x86_64.squashfs" || true
	echo
	
}

_remove_packages() {
	rm -rf "${_ARCHBOOT_ISO_EXT_DIR}/packages" || true
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
	
	pacman -Sy
	echo
	
	pacman -Sw ${_PKG}
	echo
	
	_PKGVER="$(pacman -Si ${_PKG} | grep -i 'Version' | sed 's|Version        : ||g')"
	cp /var/cache/pacman/pkg/${_PKG}-${_PKGVER}-*.pkg.tar* "${_ARCHBOOT_ISO_WD}/"
	
	unset _PKG
	unset _PKGVER
	echo
	
}

_update_cd_uefi() {
	MOUNT_FSIMG=$(mktemp -d)

	## get size of boot x86_64 files
	BOOTSIZE=$(du -bc ${_ARCHBOOT_ISO_EXT_DIR}/{EFI,loader,boot/vmlinuz_x86_64,boot/initramfs_x86_64.img} | grep total | cut -f1)
	IMGSZ=$(( (${BOOTSIZE}*102)/100/1024 + 1)) # image size in sectors

	## Create cdefiboot.img
	mkdir -p "${_ARCHBOOT_ISO_EXT_DIR}"/CDEFI/
	dd if=/dev/zero of="${_ARCHBOOT_ISO_EXT_DIR}"/CDEFI/cdefiboot.img bs="${IMGSZ}" count=1024 
	mkfs.vfat "${_ARCHBOOT_ISO_EXT_DIR}"/CDEFI/cdefiboot.img
	LOOPDEV="$(losetup --find --show "${_ARCHBOOT_ISO_EXT_DIR}"/CDEFI/cdefiboot.img)"

	## Mount cdefiboot.img
	mount -t vfat -o rw,users "${LOOPDEV}" "${MOUNT_FSIMG}"

	## Copy UEFI files fo cdefiboot.img
	mkdir "${MOUNT_FSIMG}"/boot
	cp -r "${_ARCHBOOT_ISO_EXT_DIR}"/{EFI,loader} "${MOUNT_FSIMG}"/
	cp "${_ARCHBOOT_ISO_EXT_DIR}"/boot/vmlinuz_x86_64 "${_ARCHBOOT_ISO_EXT_DIR}"/boot/initramfs_x86_64.img "${MOUNT_FSIMG}"/boot/

	## Unmount cdefiboot.img
	umount "${LOOPDEV}"
	losetup --detach "${LOOPDEV}"
	rm -rf "${MOUNT_FSIMG}"
	_CD_UEFI_PARAMETERS="-eltorito-alt-boot -e CDEFI/cdefiboot.img -isohybrid-gpt-basdat -no-emul-boot"
}

[[ "${_REMOVE_i686}" == "1" ]] && _remove_i686_iso_files

[[ "${_REMOVE_x86_64}" == "1" ]] && _remove_x86_64_iso_files

[[ "${_REMOVE_PACKAGES}" == "1" ]] && _remove_packages

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

[[ "${_UPDATE_UEFI_GUMMIBOOT}" == "1" ]] && _update_uefi_gummiboot_USB_files

[[ "${_UPDATE_UEFI_PREBOOTLOADER}" == "1" ]] && _update_uefi_prebootloader_files

[[ "${_UPDATE_UEFI_LOCKDOWN_MS}" == "1" ]] && _update_uefi_lockdown_ms_files

[[ "${_UPDATE_UEFI_REFIND}" == "1" ]] && _update_uefi_rEFInd_USB_files

[[ "${_UPDATE_SYSLINUX}" == "1" ]] && _update_syslinux_iso_files

[[ "${_UPDATE_SYSLINUX_CONFIG}" == "1" ]] && _update_syslinux_iso_config

[[ "${_UPDATE_CD_UEFI}" == "1" ]] && _update_cd_uefi

cd "${_ARCHBOOT_ISO_WD}/"

## Generate the BIOS+ISOHYBRID CD image using xorriso (extra/libisoburn package) in mkisofs emulation mode
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
	-isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin \
	${_CD_UEFI_PARAMETERS} \
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
unset _REMOVE_PACKAGES
unset _UPDATE_SETUP
unset _UPDATE_UEFI_SHELL
unset _UPDATE_UEFI_GUMMIBOOT
unset _UPDATE_UEFI_PREBOOTLOADER
unset _UPDATE_UEFI_LOCKDOWN_MS
unset _UPDATE_UEFI_REFIND
unset _UPDATE_SYSLINUX
unset _UPDATE_SYSLINUX_CONFIG
unset _CD_UEFI_PARAMETERS
unset _ARCHBOOT_ISO_OLD_PATH
unset _ARCHBOOT_ISO_WD
unset _ARCHBOOT_ISO_OLD_NAME
unset _ARCHBOOT_ISO_EXT_DIR
unset _ARCHBOOT_ISO_UPDATED_NAME
unset _ARCHBOOT_ISO_UPDATED_PATH
