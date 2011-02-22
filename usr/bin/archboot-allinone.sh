#! /bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
APPNAME=$(basename "${0}")
usage ()
{
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
    exit 1
}

[ "$1" == "" ] && usage && exit 1

ALLINONE="/etc/archboot/presets/allinone"
ALLINONE_LTS="/etc/archboot/presets/allinone-lts"
TARBALL_HELPER="/usr/bin/archboot-tarball-helper.sh"
USBIMAGE_HELPER="/usr/bin/archboot-tarball-helper.sh"

# change to english locale!
export LANG=en_US

while [ $# -gt 0 ]; do
	case $1 in
		-g|--g) GENERATE="1" ;;
		-t|--t) TARBALL="1" ;;
		-i=*|--i=*) IMAGENAME="$(echo $1 | awk -F= '{print $2;}')" ;;
		-r=*|--r=*) RELEASENAME="$(echo $1 | awk -F= '{print $2;}')" ;;
		-k=*|--k=*) KERNEL="$(echo $1 | awk -F= '{print $2;}')" ;;
		-lts=*|--lts=*) LTS_KERNEL="$(echo $1 | awk -F= '{print $2;}')" ;;
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

### check for root
if ! [ $UID -eq 0 ]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

if [ ${TARBALL} = "1" ]; then
	${TARBALL_HELPER} -c=${ALLINONE} -t=core-$(uname -m).tar
	${TARBALL_HELPER} -c=${ALLINONE_LTS} -t=core-lts-$(uname -m).tar
	exit 0
fi

if ! [ ${GENERATE} = "1" ]; then
	usage
fi

# set defaults, if nothing given
[ "${KERNEL}" = "" ] && KERNEL=$(uname -r)
[ "${LTS_KERNEL}" = "" ] && LTS_KERNEL="2.6.32-lts"
[ "${RELEASENAME}" = "" ] && RELEASENAME="2k11-R2"
[ "${IMAGENAME}" = "" ] && IMAGENAME="Archlinux-allinone-$(date +%Y.%m)"
GRUB2_MODULES="part_gpt part_msdos fat ntfs ntfscomp ext2 iso9660 udf hfsplus fshelp memdisk tar xzio gzio normal chain linux ls search search_fs_file search_fs_uuid search_label help loopback boot configfile echo lvm efi_gop png"

# generate temp directories
CORE=$(mktemp -d /tmp/core.XXX)
CORE64=$(mktemp -d /tmp/core64.XXX)
CORE_LTS=$(mktemp -d /tmp/core-lts.XXX)
CORE64_LTS=$(mktemp -d /tmp/core64-lts.XXX)
ALLINONE=$(mktemp -d /tmp/allinone.XXX)
grub2_efi_mp=$(mktemp -d /tmp/grub2_efi_mp.XXX)
memdisk_64_dir=$(mktemp -d /tmp/grub2_efi_64_dir.XXX)
memdisk_32_dir=$(mktemp -d /tmp/grub2_efi_32_dir.XXX)

# generate temp files
memdisk_64_img=$(mktemp /tmp/grub2_efi_64_img.XXX)
memdisk_32_img=$(mktemp /tmp/grub2_efi_32_img.XXX)

# create directories
mkdir ${ALLINONE}/arch
mkdir -p ${ALLINONE}/boot/syslinux
mkdir -p ${ALLINONE}/efi/grub2
mkdir -p ${ALLINONE}/efi/boot
mkdir -p ${memdisk_64_dir}/efi/grub2
mkdir -p ${memdisk_32_dir}/efi/grub2
mkdir -p ${grub2_efi_mp}/efi/boot

# Create a blank image to be converted to ESP IMG
dd if=/dev/zero of=${ALLINONE}/efi/grub2/grub2_efi.bin bs=1024 count=2048

# Create a FAT12 FS with Volume label "grub2_efi"
mkfs.vfat -F12 -S 512 -n "grub2_efi" ${ALLINONE}/efi/grub2/grub2_efi.bin

## Mount the ${ALLINONE}/efi/grub2/grub2_efi.bin image at ${grub2_efi_mp} as loop 
modprobe loop        
LOOP_DEVICE=$(losetup --show --find ${ALLINONE}/efi/grub2/grub2_efi.bin)        
mount -o rw,users -t vfat ${LOOP_DEVICE} ${grub2_efi_mp}

# extract tarballs
tar xvf core-i686.tar -C ${CORE} || exit 1
tar xvf core-x86_64.tar -C ${CORE64} || exit 1
tar xvf core-lts-x86_64.tar -C ${CORE64_LTS} || exit 1
tar xvf core-lts-i686.tar -C ${CORE_LTS} || exit 1

# move in packages
mv ${CORE_LTS}/tmp/*/core-i686 ${ALLINONE}/
mv ${CORE64_LTS}/tmp/*/core-x86_64 ${ALLINONE}/
mv ${CORE_LTS}/tmp/*/core-any ${ALLINONE}/

# move in doc
mv ${CORE}/tmp/*/arch/archboot.txt ${ALLINONE}/arch/

# copy in clamav db files
if [ -d /var/lib/clamav -a -x /usr/bin/freshclam ]; then
    mkdir ${ALLINONE}/clamav
    rm -f /var/lib/clamav/*
    freshclam --user=root
    cp /var/lib/clamav/daily.cvd ${ALLINONE}/clamav/
    cp /var/lib/clamav/main.cvd ${ALLINONE}/clamav/
    cp /var/lib/clamav/bytecode.cvd ${ALLINONE}/clamav/
    cp /var/lib/clamav/mirrors.dat ${ALLINONE}/clamav/
fi

# place kernels and memtest
mv ${CORE}/tmp/*/boot/vmlinuz ${ALLINONE}/boot
mv ${CORE64}/tmp/*/boot/vmlinuz ${ALLINONE}/boot/vm64
mv ${CORE_LTS}/tmp/*/boot/vmlinuz ${ALLINONE}/boot/vmlts
mv ${CORE64_LTS}/tmp/*/boot/vmlinuz ${ALLINONE}/boot/vm64lts
mv ${CORE}/tmp/*/boot/memtest ${ALLINONE}/boot/

# place initrd files
mv ${CORE}/tmp/*/boot/initrd.img ${ALLINONE}/boot/initrd.img
mv ${CORE_LTS}/tmp/*/boot/initrd.img ${ALLINONE}/boot/initrdlts.img
mv ${CORE64}/tmp/*/boot/initrd.img ${ALLINONE}/boot/initrd64.img
mv ${CORE64_LTS}/tmp/*/boot/initrd.img ${ALLINONE}/boot/initrd64lts.img

# place syslinux files
mv ${CORE}/tmp/*/boot/syslinux/* ${ALLINONE}/boot/syslinux/

# place grub2 files
cp -r /usr/lib/grub/x86_64-efi ${ALLINONE}/efi/grub2/x86_64-efi
cp -r /usr/lib/grub/i386-efi ${ALLINONE}/efi/grub2/i386-efi

cp /usr/share/grub/{unicode,ascii}.pf2 ${ALLINONE}/efi/grub2/

cp -r ${ALLINONE}/efi/grub2/x86_64-efi/locale ${ALLINONE}/efi/grub2/locale || true
rm -rf ${ALLINONE}/efi/grub2/{x86_64,i386}-efi/locale/ || true

## Create memdisk for bootx64.efi
cat << EOF > ${memdisk_64_dir}/efi/grub2/grub.cfg
set _EFI_ARCH="x86_64"

search --file --no-floppy --set=efi64 /efi/grub2/x86_64-efi/grub.cfg
set prefix=(\${efi64})/efi/grub2/x86_64-efi
source \${prefix}/grub.cfg
EOF

cat << EOF > ${ALLINONE}/efi/grub2/x86_64-efi/grub.cfg
search --file --no-floppy --set=efi64 /efi/grub2/x86_64-efi/grub.cfg
source (\${efi64})/efi/boot/grub.cfg
EOF

tar -C ${memdisk_64_dir} -cf - efi > ${memdisk_64_img}

## Create memdisk for bootia32.efi
cat << EOF > ${memdisk_32_dir}/efi/grub2/grub.cfg
set _EFI_ARCH="i386"

search --file --no-floppy --set=efi32 /efi/grub2/i386-efi/grub.cfg
set prefix=(\${efi32})/efi/grub2/i386-efi
source \${prefix}/grub.cfg
EOF
 
cat << EOF > ${ALLINONE}/efi/grub2/i386-efi/grub.cfg
search --file --no-floppy --set=efi32 /efi/grub2/i386-efi/grub.cfg
source (\${efi32})/efi/boot/grub.cfg
EOF

tar -C ${memdisk_32_dir} -cf - efi > ${memdisk_32_img}

/bin/grub-mkimage --directory=/usr/lib/grub/x86_64-efi --memdisk=${memdisk_64_img} --prefix='(memdisk)/efi/grub2' --output=${grub2_efi_mp}/efi/boot/bootx64.efi --format=x86_64-efi ${GRUB2_MODULES}

/bin/grub-mkimage --directory=/usr/lib/grub/i386-efi --memdisk=${memdisk_32_img} --prefix='(memdisk)/efi/grub2' --output=${grub2_efi_mp}/efi/boot/bootia32.efi --format=i386-efi ${GRUB2_MODULES}

/bin/grub-mkimage --directory=/usr/lib/grub/x86_64-efi --memdisk=${memdisk_64_img} --prefix='(memdisk)/efi/grub2' --output=${ALLINONE}/efi/boot/bootx64.efi --format=x86_64-efi ${GRUB2_MODULES}

/bin/grub-mkimage --directory=/usr/lib/grub/i386-efi --memdisk=${memdisk_32_img} --prefix='(memdisk)/efi/grub2' --output=${ALLINONE}/efi/boot/bootia32.efi --format=i386-efi ${GRUB2_MODULES}

## Copy the actual grub2 config file
cat << EOF > ${ALLINONE}/efi/boot/grub.cfg
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

# Change parameters in boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g"  -e "s/@@LTS_KERNEL@@/$LTS_KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/ISOLINUX/g" ${ALLINONE}/boot/syslinux/boot.msg

## Generate the BIOS+UEFI ISO image using xorriso (community/libisoburn package) in mkisofs emulation mode
## -output ${wd}/${iso_name}_isohybrid.iso is not working , -o ${wd}/${iso_name}_isohybrid.iso works
echo "Generating ALLINONE ISO ..."
xorriso -as mkisofs -rock -joliet \
        -max-iso9660-filenames -omit-period \
        -omit-version-number -allow-leading-dots \
        -relaxed-filenames -allow-lowercase -allow-multidot \
        -volid "ARCHBOOT" \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot --efi-boot efi/grub2/grub2_efi.bin -no-emul-boot \
        -o ${IMAGENAME}.iso ${ALLINONE}/ > /dev/null 2>&1

# generate hybrid file
echo "Generating ALLINONE hybrid ..."
cp ${IMAGENAME}.iso ${IMAGENAME}-hybrid.iso
isohybrid ${IMAGENAME}-hybrid.iso

# cleanup isolinux and migrate to syslinux
echo "Generating ALLINONE IMG ..."
rm ${ALLINONE}/boot/syslinux/isolinux.bin
# Change parameters in boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g" -e "s/@@LTS_KERNEL@@/$LTS_KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/SYSLINUX/g" ${ALLINONE}/boot/syslinux/boot.msg

/usr/bin/archboot-usbimage-helper.sh ${ALLINONE} ${IMAGENAME}.img > /dev/null 2>&1

#create md5sums.txt
[ -e md5sum.txt ] && rm -f md5sum.txt
for i in ${IMAGENAME}.iso ${IMAGENAME}.img ${IMAGENAME}-hybrid.iso; do
	md5sum $i >> md5sum.txt
done

# umount images and loop
losetup --detach ${LOOP_DEVICE}
umount ${grub2_efi_mp}

# cleanup
rm -rf ${memdisk_64_dir}
rm -rf ${memdisk_32_dir}
rm -rf ${grub2_efi_mp}
rm ${memdisk_64_img}
rm ${memdisk_32_img}
rm -r ${CORE}
rm -r ${CORE64}
rm -r ${CORE_LTS}
rm -r ${CORE64_LTS}
rm -r ${ALLINONE}
