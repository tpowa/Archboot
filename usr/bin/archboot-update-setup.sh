#! /bin/bash
# Script for updating existing /arch/setup script in the initramfs files of archboot.
# Previously the script for creating grub2 efi bootable isos - moved to all-in-one script
# Contributed by "Keshav P R " <skodabenz at rocketmail dot com>

export archboot_ver="2011.02-1"

export wd=${PWD}/
export archboot_ext=$(mktemp -d /tmp/archboot_ext.XXXXXXXXXX)
export iso_name="archboot_${archboot_ver}_mod"

export REPLACE_SETUP="1"

echo

### check for root
if ! [ $UID -eq 0 ]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

set -x

## Remove old files and dir
rm -rf ${archboot_ext}/ || true
rm ${wd}/${iso_name}.iso || true
echo

## Create a dir to extract the archboot iso
mkdir -p ${archboot_ext}
cd ${archboot_ext}/
echo

## Extract the archboot iso using bsdtar
bsdtar xf ${wd}/archlinux-${archboot_ver}-archboot.iso
# 7z x ${wd}/archlinux-${archboot_ver}-archboot.iso
echo

rm -rf ${archboot_ext}/[BOOT]/ || true
echo

[ -e ${wd}/splash.png ] && cp ${wd}/splash.png ${archboot_ext}/boot/splash.png
echo


replace_arch_setup_initramfs() {
	
	initramfs_ext=$(mktemp -d /tmp/${initramfs_name}_ext.XXXXXXXXXX)
	echo
	
	cd ${initramfs_ext}/
	
	bsdtar xf ${archboot_ext}/boot/${initramfs_name}.img
	echo
	
	mv ${initramfs_ext}/arch/setup ${initramfs_ext}/arch/setup.old
	echo
	
	cp ${wd}/setup ${initramfs_ext}/arch/setup
	echo
	
	chmod +x ${initramfs_ext}/arch/setup
	echo
	
	cd ${initramfs_ext}/
	
	find . | cpio --format=newc -o > ${wd}/${initramfs_name}
	echo
	
	cd ${wd}/
	
	# Linux Kernel 2.6.38 supports xz compressed initramfs but checksum should be crc32, not the default crc64
	xz --check=crc32 -9 ${wd}/${initramfs_name}
	echo
	
	rm ${wd}/${initramfs_name}.img
	echo
	
	mv ${wd}/${initramfs_name}.lzma ${wd}/${initramfs_name}.img
	echo
	
	rm ${archboot_ext}/boot/${initramfs_name}.img
	echo
	
	cp ${wd}/${initramfs_name}.img ${archboot_ext}/boot/${initramfs_name}.img
	echo
	
	unset initramfs_ext
	unset initramfs__name
	echo
	
}

# Not currently used - simply left untouched for now
download_pkgs() {
	
	cd ${wd}/
	
	if [ "${pkg_arch}" = 'any' ]
	then
		wget -c http://www.archlinux.org/packages/${repo}/any/${package}/download/
		echo
	else
		wget -c http://www.archlinux.org/packages/${repo}/x86_64/${package}/download/
		echo
		
		wget -c http://www.archlinux.org/packages/${repo}/i686/${package}/download/
		echo
	fi
	
	unset repo
	unset package
	unset pkg_arch
	echo
	
}


if [ "${REPLACE_SETUP}" = "1" ]
then
	cd ${wd}/
	
	if [ -e ${wd}/setup ]
	then
		## The old method I tried, mount -o ro -t iso9660 /dev/sr0 /src, mv /arch/setup /arch/setup.old, cp /src/arch/setup /arch/setup, umount /dev/sr0
		# cp ${wd}/setup ${archboot_ext}/arch/setup
		
		## Extracting using bsdtar, replacing /arch/setup and recompressing the iniramfs archive does not work. Archive format not compatible with initramfs format.
		## Compressing using cpio and using 'newc' archive format works
		
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
cd ${wd}
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
        -eltorito-alt-boot --efi-boot efi/grub2/grub2_efi.bin -no-emul-boot \
        -isohybrid-mbr /usr/lib/syslinux/isohdpfx.bin \
        -output ${wd}/${iso_name}.iso ${archboot_ext}/ > /dev/null 2>&1
echo

## Generate a isohybrid image using syslinux
# cp ${wd}/${iso_name}.iso ${wd}/${iso_name}_isohybrid.iso
# isohybrid ${wd}/${iso_name}_isohybrid.iso
echo

set +x

unset archboot_ver
unset wd
unset archboot_ext
unset iso_name
unset REPLACE_SETUP
