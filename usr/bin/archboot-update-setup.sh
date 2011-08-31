#!/bin/bash
# Script for updating existing /arch/setup script in the initramfs files of archboot.
# Previously the script for creating grub2 uefi bootable isos - moved to all-in-one script
# Contributed by "Keshav P R" <skodabenz aatt rocketmail ddoott ccoomm>

export archboot_ver="2011.06-1"

export wd="${PWD}/"
export archboot_ext="$(mktemp -d /tmp/archboot_ext.XXXXXXXXXX)"
export iso_name="archboot_${archboot_ver}_mod"

export GRUB2_UEFI_APP_MODULES="part_gpt part_msdos fat ext2 iso9660 udf hfsplus btrfs nilfs2 xfs reiserfs relocator reboot multiboot2 fshelp normal gfxterm chain linux ls cat memdisk tar search search_fs_file search_fs_uuid search_label help loopback boot configfile echo png efi_gop efi_uga xzio font help lvm usbms usb_keyboard"

export REPLACE_GRUB2_UEFI="1"
export REPLACE_SETUP="1"

echo

### check for root
if ! [ $UID -eq 0 ]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

set -x

## Remove old files and dir
rm -rf "${archboot_ext}/" || true
rm -f "${wd}/${iso_name}.iso" || true
echo

## Create a dir to extract the archboot iso
mkdir -p "${archboot_ext}/"
cd "${archboot_ext}/"
echo

## Extract the archboot iso using bsdtar
bsdtar xf "${wd}/archlinux-${archboot_ver}-archboot.iso"
# 7z x "${wd}/archlinux-${archboot_ver}-archboot.iso"
echo

rm -rf "${archboot_ext}/[BOOT]/" || true
echo

[ -e "${wd}/splash.png" ] && cp "${wd}/splash.png" "${archboot_ext}/boot/splash.png"
echo

replace_grub2_uefi_x86_64_iso_files() {
	
	memdisk_64_dir="$(mktemp -d /tmp/grub2_uefi_64_dir.XXX)"
	memdisk_64_img="$(mktemp /tmp/grub2_uefi_64_img.XXX)"
	
	rm -f "${grub2_uefi_mp}/efi/boot/bootx64.efi" || true
	rm -f "${archboot_ext}/efi/boot/bootx64.efi" || true
	
	rm -rf "${archboot_ext}/efi/grub2/x86_64-efi" || true
	cp -r /usr/lib/grub/x86_64-efi "${archboot_ext}/efi/grub2/x86_64-efi"
	
	mkdir -p "${memdisk_64_dir}/efi/grub2/"
	
	cat << EOF > "${memdisk_64_dir}/efi/grub2/grub.cfg"
set _UEFI_ARCH="x86_64"

search --file --no-floppy --set=efi64 /efi/grub2/x86_64-efi/grub.cfg
set prefix=(\${efi64})/efi/grub2/x86_64-efi
source \${prefix}/grub.cfg
EOF
	
	cat << EOF > "${archboot_ext}/efi/grub2/x86_64-efi/grub.cfg"
search --file --no-floppy --set=efi64 /efi/grub2/x86_64-efi/grub.cfg
source (\${efi64})/efi/grub2/grub.cfg
EOF
	
	tar -C "${memdisk_64_dir}" -cf - efi > "${memdisk_64_img}"
	
	"$(which grub-mkimage)" --directory="/usr/lib/grub/x86_64-efi" --memdisk="${memdisk_64_img}" --prefix='(memdisk)/efi/grub2' --output="${grub2_uefi_mp}/efi/boot/bootx64.efi" --format=x86_64-efi ${GRUB2_UEFI_APP_MODULES}
	
	mkdir -p "${ALLINONE}/efi/boot/"
	cp "${grub2_uefi_mp}/efi/boot/bootx64.efi" "${archboot_ext}/efi/boot/bootx64.efi"
	
	unset memdisk_64_dir
	unset memdisk_64_img
	echo
}

replace_grub2_uefi_i386_iso_files() {
	
	memdisk_32_dir="$(mktemp -d /tmp/grub2_uefi_32_dir.XXX)"
	memdisk_32_img="$(mktemp /tmp/grub2_uefi_32_img.XXX)"
	
	rm -f "${grub2_uefi_mp}/efi/boot/bootia32.efi" || true
	rm -f "${archboot_ext}/efi/boot/bootia32.efi" || true
	
	rm -rf "${archboot_ext}/efi/grub2/i386-efi" || true
	cp -r /usr/lib/grub/i386-efi "${archboot_ext}/efi/grub2/i386-efi"
	
	mkdir -p "${memdisk_32_dir}/efi/grub2/"
	
	cat << EOF > "${memdisk_32_dir}/efi/grub2/grub.cfg"
set _UEFI_ARCH="i386"

search --file --no-floppy --set=efi32 /efi/grub2/i386-efi/grub.cfg
set prefix=(\${efi32})/efi/grub2/i386-efi
source \${prefix}/grub.cfg
EOF
	
	cat << EOF > "${ALLINONE}/efi/grub2/i386-efi/grub.cfg"
search --file --no-floppy --set=efi32 /efi/grub2/i386-efi/grub.cfg
source (\${efi32})/efi/grub2/grub.cfg
EOF
	
	tar -C "${memdisk_32_dir}" -cf - efi > "${memdisk_32_img}"
	
	"$(which grub-mkimage)" --directory="/usr/lib/grub/i386-efi" --memdisk="${memdisk_32_img}" --prefix='(memdisk)/efi/grub2' --format=i386-efi --compression=xz --output="${grub2_uefi_mp}/efi/boot/bootia32.efi" ${GRUB2_UEFI_APP_MODULES}
	
	unset memdisk_32_dir
	unset memdisk_32_img
	echo
	
}

replace_grub2_uefi_iso_files() {
	
	grub2_uefi_mp="$(mktemp -d /tmp/grub2_uefi_mp.XXX)"
	
	modprobe -q loop
	LOOP_DEVICE="$(losetup --show --find ${archboot_ext}/efi/grub2/grub2_uefi.bin)"
	mount -o rw,users -t vfat "${LOOP_DEVICE}" "${grub2_uefi_mp}"
	echo
	
	replace_grub2_uefi_x86_64_iso_files
	echo
	# replace_grub2_uefi_i386_iso_files
	echo
	
	# umount images and loop
	umount "${grub2_uefi_mp}"
	losetup --detach "${LOOP_DEVICE}"
	
	rm -f "${archboot_ext}/efi/boot/grub.cfg" || true
	rm -f "${archboot_ext}/efi/grub2/grub.cfg"
	
	cat << EOF > "${archboot_ext}/efi/grub2/grub.cfg"
search --file --no-floppy --set=archboot /arch/archboot.txt

set pager=1

insmod efi_gop
insmod efi_uga
insmod font

if loadfont (\${archboot})/efi/grub2/unicode.pf2
then
	insmod gfxterm
	set gfxmode=auto
	set gfxpayload=keep
	terminal_output gfxterm
	
	set color_normal=light-blue/black
	set color_highlight=light-cyan/blue
	
	insmod png
	background_image (\${archboot})/boot/splash.png
fi

insmod fat
insmod iso9660
insmod udf
insmod search_fs_file
insmod linux

set _kernel_params="add_efi_memmap none=UEFI_ARCH_\${_UEFI_ARCH}"

menuentry "Arch Linux (i686) archboot" {
set root=(\${archboot})
linux /boot/vmlinuz ro \${_kernel_params}
initrd /boot/initrd.img
}

menuentry "Arch Linux (x86_64) archboot" {
set root=(\${archboot})
linux /boot/vm64 ro \${_kernel_params}
initrd /boot/initrd64.img
}

menuentry "Arch Linux LTS (i686) archboot" {
set root=(\${archboot})
linux /boot/vmlts ro \${_kernel_params}
initrd /boot/initrd.img
}

menuentry "Arch Linux LTS (x86_64) archboot" {
set root=(\${archboot})
linux /boot/vm64lts ro \${_kernel_params}
initrd /boot/initrd64.img
}

EOF
	
	unset grub2_uefi_mp
	unset LOOP_DEVICE
	
}

replace_arch_setup_initramfs() {
	
	initramfs_ext="$(mktemp -d /tmp/${initramfs_name}_ext.XXXXXXXXXX)"
	echo
	
	cd "${initramfs_ext}/"
	
	bsdtar xf "${archboot_ext}/boot/${initramfs_name}.img"
	echo
	
	mv "${initramfs_ext}/arch/setup" "${initramfs_ext}/arch/setup.old"
	echo
	
	cp "${wd}/setup" "${initramfs_ext}/arch/setup"
	echo
	
	chmod +x "${initramfs_ext}/arch/setup"
	echo
	
	cd "${initramfs_ext}/"
	
	# Generate the actual initramfs file
	find . -print0 | bsdcpio -0 --format newc -v -o | xz --check=crc32 -9 -v > "${wd}/${initramfs_name}.img"
	echo
	
	cd "${wd}/"
	
	rm -f "${archboot_ext}/boot/${initramfs_name}.img"
	echo
	
	cp "${wd}/${initramfs_name}.img" "${archboot_ext}/boot/${initramfs_name}.img"
	echo
	
	unset initramfs_ext
	unset initramfs_name
	echo
	
}

# Not currently used - simply left untouched for now
download_pkgs() {
	
	cd "${wd}/"
	
	if [ "${pkg_arch}" = 'any' ]
	then
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

[ "${REPLACE_GRUB2_UEFI}" = "1" ] && replace_grub2_uefi_iso_files

if [ "${REPLACE_SETUP}" = "1" ]
then
	cd "${wd}/"
	
	if [ -e "${wd}/setup" ]
	then
		## The old method I tried, mount -o ro -t iso9660 /dev/sr0 /src, mv /arch/setup /arch/setup.old, cp /src/arch/setup /arch/setup, umount /dev/sr0
		# cp ${wd}/setup ${archboot_ext}/arch/setup
		
		## Extracting using bsdtar, replacing /arch/setup and recompressing the iniramfs archive does not work. Archive format not compatible with initramfs format.
		## Compressing using bsdcpio and using 'newc' archive format works, taken from falconindy's geninit program.
		
		initramfs_name="initrd64"
		replace_arch_setup_initramfs
		
		initramfs_name="initrd64lts"
		replace_arch_setup_initramfs
		
		initramfs_name="initrd"
		replace_arch_setup_initramfs
		
		initramfs_name="initrdlts"
		replace_arch_setup_initramfs
	fi
	echo
fi


## Re-create the archboot ISO
cd "${wd}/"
echo

## Generate the BIOS+UEFI+ISOHYBRID ISO image using xorriso (extra/libisoburn package) in mkisofs emulation mode

xorriso -as mkisofs \
        -rock -joliet \
        -max-iso9660-filenames -omit-period \
        -omit-version-number -allow-leading-dots \
        -relaxed-filenames -allow-lowercase -allow-multidot \
        -volid "ARCHBOOT" \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot --efi-boot efi/grub2/grub2_uefi.bin -no-emul-boot \
        -isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin \
        -output "${wd}/${iso_name}.iso" "${archboot_ext}/" > /dev/null 2>&1
echo

set +x

unset archboot_ver
unset wd
unset archboot_ext
unset iso_name
unset GRUB2_UEFI_APP_MODULES
unset REPLACE_GRUB2_UEFI
unset REPLACE_SETUP
