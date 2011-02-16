#! /bin/bash
# Script for creating grub2 efi bootable isos
# Contributed by "Keshav P R " <skodabenz at rocketmail dot com>

## Most of the commands in this script have been copied from grub2's grub-mkrescue shell script with slight modifications

export archboot_ver="2011.02-1"

export wd=${PWD}/
export archboot_ext=$(mktemp -d /tmp/archboot_ext.XXXXXXXXXX)
export iso_name="archboot_${archboot_ver}_efi"
export grub2_name="grub"

export GRUB2_MODULES="part_gpt part_msdos fat ntfs ntfscomp ext2 iso9660 udf hfsplus fshelp memdisk tar xzio gzio normal chain linux ls search search_fs_file search_fs_uuid search_label help loopback boot configfile echo lvm efi_gop png"

export MKTEMP_TEMPLATE="/tmp/grub2_efi.XXXXXXXXXX"

export REPLACE_SETUP="0"

export CREATE_USB_IMG="0"

echo

### check for root
if ! [ $UID -eq 0 ]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

set -x

## Remove old files and dir
rm -rf ${archboot_ext}/ || true
rm ${wd}/${iso_name}_isohybrid.iso || true
rm ${wd}/${iso_name}_usb.img || true
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
rm -rf ${archboot_ext}/efi/ || true
echo


for file in vmlinuz initrd.img vm64 initrd64.img vmlts initrdlts.img vm64lts initrd64lts.img memtest
do
	if [ -e ${archboot_ext}/boot/syslinux/${file} ]
	then
		mv ${archboot_ext}/boot/syslinux/${file} ${archboot_ext}/boot/${file}
		echo
	fi
done


cp ${archboot_ext}/boot/syslinux/splash.png ${archboot_ext}/boot/splash.png || true
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
	
	lzma -9 ${wd}/${initramfs_name}
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
		## Extracting using cpio and using 'newc' archive format works
		
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

pacman -S --noconfirm dosfstools grub2-common grub2-efi-x86_64 grub2-efi-i386 || exit 1
echo

rm -rf ${archboot_ext}/efi/grub2/ || true
rm -rf ${archboot_ext}/efi/boot/ || true
echo

## Create UEFI compliant ESP directory
mkdir -p ${archboot_ext}/efi/grub2/
mkdir -p ${archboot_ext}/efi/boot/
echo

## Delete old ESP image
rm -rf ${archboot_ext}/efi/grub2/grub2_efi.bin
echo

## Create a blank image to be converted to ESP IMG
dd if=/dev/zero of=${archboot_ext}/efi/grub2/grub2_efi.bin bs=1024 count=2048
echo

## Create a FAT12 FS with Volume label "grub2_efi"
mkfs.vfat -F12 -S 512 -n "grub2_efi" ${archboot_ext}/efi/grub2/grub2_efi.bin
echo


## Create a mountpoint for the grub2_efi.bin image if it does not exist
grub2_efi_mp=$(mktemp -d "${MKTEMP_TEMPLATE}")
echo

## Mount the ${archboot_ext}/efi/grub2/grub2_efi.bin image at ${grub2_efi_mp} as loop 
modprobe loop        
LOOP_DEVICE=$(losetup --show --find ${archboot_ext}/efi/grub2/grub2_efi.bin)        
mount -o rw,users -t vfat ${LOOP_DEVICE} ${grub2_efi_mp}
echo


mkdir -p ${archboot_ext}/efi/grub2

cp -r /usr/lib/${grub2_name}/x86_64-efi ${archboot_ext}/efi/grub2/x86_64-efi
cp -r /usr/lib/${grub2_name}/i386-efi ${archboot_ext}/efi/grub2/i386-efi

cp /usr/share/grub/{unicode,ascii}.pf2 ${archboot_ext}/efi/grub2/

cp -r ${archboot_ext}/efi/grub2/x86_64-efi/locale ${archboot_ext}/efi/grub2/locale || true
rm -rf ${archboot_ext}/efi/grub2/{x86_64,i386}-efi/locale/ || true
echo


## Create memdisk for bootx64.efi
memdisk_64_img=$(mktemp "${MKTEMP_TEMPLATE}")
memdisk_64_dir=$(mktemp -d "${MKTEMP_TEMPLATE}")

mkdir -p ${memdisk_64_dir}/efi/grub2
echo

cat << EOF > ${memdisk_64_dir}/efi/grub2/grub.cfg
set _EFI_ARCH="x86_64"

search --file --no-floppy --set=efi64 /efi/grub2/x86_64-efi/grub.cfg
set prefix=(\${efi64})/efi/grub2/x86_64-efi
source \${prefix}/grub.cfg
EOF
echo

cat << EOF > ${archboot_ext}/efi/grub2/x86_64-efi/grub.cfg
search --file --no-floppy --set=efi64 /efi/grub2/x86_64-efi/grub.cfg
source (\${efi64})/efi/boot/grub.cfg
EOF
echo

cd ${memdisk_64_dir}
tar -cf - efi > ${memdisk_64_img}
rm -rf ${memdisk_64_dir}
unset memdisk_64_dir
echo


## Create memdisk for bootia32.efi
memdisk_32_img=$(mktemp "${MKTEMP_TEMPLATE}")
memdisk_32_dir=$(mktemp -d "${MKTEMP_TEMPLATE}")

mkdir -p ${memdisk_32_dir}/efi/grub2
echo

cat << EOF > ${memdisk_32_dir}/efi/grub2/grub.cfg
set _EFI_ARCH="i386"

search --file --no-floppy --set=efi32 /efi/grub2/i386-efi/grub.cfg
set prefix=(\${efi32})/efi/grub2/i386-efi
source \${prefix}/grub.cfg
EOF
echo
 
cat << EOF > ${archboot_ext}/efi/grub2/i386-efi/grub.cfg
search --file --no-floppy --set=efi32 /efi/grub2/i386-efi/grub.cfg
source (\${efi32})/efi/boot/grub.cfg
EOF
echo

cd ${memdisk_32_dir}
tar -cf - efi > ${memdisk_32_img}
rm -rf ${memdisk_32_dir}
unset memdisk_32_dir
echo


## Create actual bootx64.efi and bootia32.efi files
mkdir -p ${grub2_efi_mp}/efi/boot
echo

/bin/${grub2_name}-mkimage --directory=/usr/lib/${grub2_name}/x86_64-efi --memdisk=${memdisk_64_img} --prefix='(memdisk)/efi/grub2' --output=${grub2_efi_mp}/efi/boot/bootx64.efi --format=x86_64-efi ${GRUB2_MODULES}
echo

/bin/${grub2_name}-mkimage --directory=/usr/lib/${grub2_name}/i386-efi --memdisk=${memdisk_32_img} --prefix='(memdisk)/efi/grub2' --output=${grub2_efi_mp}/efi/boot/bootia32.efi --format=i386-efi ${GRUB2_MODULES}
echo

umount ${grub2_efi_mp}
rm -rf ${grub2_efi_mp}
echo

losetup --detach ${LOOP_DEVICE}
echo

/bin/${grub2_name}-mkimage --directory=/usr/lib/${grub2_name}/x86_64-efi --memdisk=${memdisk_64_img} --prefix='(memdisk)/efi/grub2' --output=${archboot_ext}/efi/boot/bootx64.efi --format=x86_64-efi ${GRUB2_MODULES}
echo

/bin/${grub2_name}-mkimage --directory=/usr/lib/${grub2_name}/i386-efi --memdisk=${memdisk_32_img} --prefix='(memdisk)/efi/grub2' --output=${archboot_ext}/efi/boot/bootia32.efi --format=i386-efi ${GRUB2_MODULES}
echo

rm ${memdisk_64_img}
rm ${memdisk_32_img}
echo

unset memdisk_64_img
unset memdisk_32_img
echo

## Copy the actual grub2 config file
cat << EOF > ${archboot_ext}/efi/boot/grub.cfg
search --file --no-floppy --set=archboot /arch/archboot.txt

set pager=1

insmod efi_gop
insmod font

if loadfont (\${archboot})/efi/grub2/unicode.pf2
then
   insmod gfxterm
   set gfxmode="auto"
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
insmod bsd
insmod linux

set _kernel_params="nomodeset add_efi_memmap none=EFI_ARCH_\${_EFI_ARCH}"

menuentry "Arch Linux (i686) archboot" {
linux (\${archboot})/boot/vmlinuz ro \${_kernel_params}
initrd (\${archboot})/boot/initrd.img
}

menuentry "Arch Linux (x86_64) archboot" {
linux (\${archboot})/boot/vm64 ro \${_kernel_params}
initrd (\${archboot})/boot/initrd64.img
}

menuentry "Arch Linux LTS (i686) archboot" {
linux (\${archboot})/boot/vmlts ro \${_kernel_params}
initrd (\${archboot})/boot/initrdlts.img
}

menuentry "Arch Linux LTS (x86_64) archboot" {
linux (\${archboot})/boot/vm64lts ro \${_kernel_params}
initrd (\${archboot})/boot/initrd64lts.img
}

EOF
echo


## First create the BIOS+UEFI ISO
cd ${wd}
echo

## Generate the BIOS+UEFI ISO image using xorriso (community/libisoburn package) in mkisofs emulation mode
## -output ${wd}/${iso_name}_isohybrid.iso is not working , -o ${wd}/${iso_name}_isohybrid.iso works

xorriso -as mkisofs -rock -joliet \
        -full-iso9660-filenames -omit-period \
        -omit-version-number -allow-leading-dots \
        -relaxed-filenames -allow-lowercase -allow-multidot \
        -volid "ARCHBOOT" \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot --efi-boot efi/grub2/grub2_efi.bin -no-emul-boot \
        -o ${wd}/${iso_name}_isohybrid.iso ${archboot_ext}/ 
echo


## Generate a isohybrid image using syslinux
isohybrid ${wd}/${iso_name}_isohybrid.iso
echo


if [ "${CREATE_USB_IMG}" = "1" ]
then
	## Second create the FAT32 USB image using syslinux
	
	## The below commands have been copied from archboot-usbimage-helper.sh with slight modifications
	
	## Output USB image
	DISKIMG=${wd}/${iso_name}_usb.img
	
	## Contents of the USB image
	IMGROOT=${archboot_ext}
	
	## Create required temp dirs
	TMPDIR=$(mktemp -d)
	FSIMG=$(mktemp)
	echo
	
	## Determine the required size of the USB image
	rootsize=$(du -bs ${IMGROOT}|cut -f1)
	IMGSZ=$(( (${rootsize}*102)/100/512 + 1)) ## image size in sectors
	echo
	
	## Create a FAT32 image with volume name "ARCHBOOT"
	dd if=/dev/zero of=${FSIMG} bs=512 count=${IMGSZ}
	echo
	
	mkfs.vfat -S 512 -F32 -n "ARCHBOOT" ${FSIMG}
	echo
	
	## Mount the FAT32 image at the created temp dir
	LOOP_DEVICE2=$(losetup --show --find ${FSIMG})
	mount -o rw,users -t vfat ${LOOP_DEVICE2} ${TMPDIR}
	echo
	
	## Copy the contents of the ISO to the USB image
	cp -r ${IMGROOT}/* ${TMPDIR}
	echo
	
	umount ${TMPDIR}
	losetup --detach ${LOOP_DEVICE2}
	echo
	
	## Create the final USB image
	cat ${FSIMG} > ${DISKIMG}
	echo
	
	## Install syslinux into the image
	syslinux ${DISKIMG}
	echo
	
	rm -rf ${TMPDIR} ${FSIMG}
	echo
fi

set +x

unset archboot_ver
unset wd
unset archboot_ext
unset iso_name
unset grub2_name
unset GRUB2_MODULES
unset MKTEMP_TEMPLATE
unset REPLACE_SETUP
unset CREATE_USB_IMG
