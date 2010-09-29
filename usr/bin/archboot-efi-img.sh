#! /bin/sh

export archboot_ver="2010.09-1"

export wd=${PWD}
export archboot_ext=${wd}/archboot_ext
export iso_name="archboot_${archboot_ver}_efi"
export grub2_name="grub2"

export GRUB2_MODULES="part_gpt part_msdos bsd fat ntfs ntfscomp ext2 iso9660 udf hfsplus fshelp memdisk tar normal chain linux ls search search_fs_file search_fs_uuid search_label help loopback boot configfile echo lvm efi_gop png"

export MKTEMP_TEMPLATE="/tmp/grub2_efi.XXXXXXXXXX"

export RM_UNWANTED="0"

echo

set -x

## Remove old files and dir
rm -rf archboot_ext
rm ${iso_name}_isohybrid.iso
rm ${iso_name}_usb.img

## Create a dir to extract the archboot iso
mkdir -p ${archboot_ext}

cp ${wd}/archlinux-${archboot_ver}-archboot.iso ${archboot_ext}/
echo

cd ${archboot_ext}

## Extract the archboot iso using bsdtar
bsdtar xf archlinux-${archboot_ver}-archboot.iso
echo

rm -rf ${archboot_ext}/[BOOT]/
rm ${archboot_ext}/archlinux-${archboot_ver}-archboot.iso
echo

rm -rf ${archboot_ext}/efi/grub2/
rm -rf ${archboot_ext}/efi/boot/

## Create UEFI compliant ESP directory
mkdir -p ${archboot_ext}/efi/grub2/
mkdir -p ${archboot_ext}/efi/boot/

## Delete old ESP image
if [ -e ${archboot_ext}/efi/grub2/grub2_efi.bin ]
then
    rm -rf ${archboot_ext}/efi/grub2/grub2_efi.bin
    echo
fi

## Create a blank image to be converted to ESP IMG
dd if=/dev/zero of=${archboot_ext}/efi/grub2/grub2_efi.bin bs=1024 count=2048
echo

## Create a FAT12 FS with Volume label "grub2_efi"
mkfs.vfat -F12 -S 512 -n "grub2_efi" ${archboot_ext}/efi/grub2/grub2_efi.bin
echo


## Create a mountpoint for the grub2_efi.bin image if it does not exist
grub2_efi_mp=`mktemp -d "$MKTEMP_TEMPLATE"`
echo

## Mount the ${archboot_ext}/efi/grub2/grub2_efi.bin image at ${grub2_efi_mp} as loop 
sudo modprobe loop        
sudo mount -t vfat -o loop,rw,users ${archboot_ext}/efi/grub2/grub2_efi.bin ${grub2_efi_mp}
echo


mkdir -p ${archboot_ext}/efi/grub2

cp -r /usr/lib/${grub2_name}/x86_64-efi ${archboot_ext}/efi/grub2/x86_64-efi
cp -r /usr/lib/${grub2_name}/i386-efi ${archboot_ext}/efi/grub2/i386-efi

cp /etc/grub.d/unifont.pf2 /etc/grub.d/ascii.pf2 ${archboot_ext}/efi/grub2/

# cp -r ${archboot_ext}/efi/grub2/x86_64-efi/locale ${archboot_ext}/efi/grub2/locale
# rm -rf ${archboot_ext}/efi/grub2/x86_64-efi/locale/
# rm -rf ${archboot_ext}/efi/grub2/i386-efi/locale/
echo


## Create memdisk for bootx64.efi
memdisk_64_img=`mktemp "$MKTEMP_TEMPLATE"`
memdisk_64_dir=`mktemp -d "$MKTEMP_TEMPLATE"`

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
echo


## Create memdisk for bootia32.efi
memdisk_32_img=`mktemp "$MKTEMP_TEMPLATE"`
memdisk_32_dir=`mktemp -d "$MKTEMP_TEMPLATE"`

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
echo


## Create actual bootx64.efi and bootia32.efi files
sudo mkdir -p ${grub2_efi_mp}/efi/boot
echo

sudo /bin/${grub2_name}-mkimage --directory=/usr/lib/${grub2_name}/x86_64-efi --memdisk=${memdisk_64_img} --prefix='(memdisk)/efi/grub2' --output=${grub2_efi_mp}/efi/boot/bootx64.efi --format=x86_64-efi ${GRUB2_MODULES}
echo

sudo /bin/${grub2_name}-mkimage --directory=/usr/lib/${grub2_name}/i386-efi --memdisk=${memdisk_32_img} --prefix='(memdisk)/efi/grub2' --output=${grub2_efi_mp}/efi/boot/bootia32.efi --format=i386-efi ${GRUB2_MODULES}
echo

sudo umount ${grub2_efi_mp}
rm -rf ${grub2_efi_mp}
echo


/bin/${grub2_name}-mkimage --directory=/usr/lib/${grub2_name}/x86_64-efi --memdisk=${memdisk_64_img} --prefix='(memdisk)/efi/grub2' --output=${archboot_ext}/efi/boot/bootx64.efi --format=x86_64-efi ${GRUB2_MODULES}
echo

/bin/${grub2_name}-mkimage --directory=/usr/lib/${grub2_name}/i386-efi --memdisk=${memdisk_32_img} --prefix='(memdisk)/efi/grub2' --output=${archboot_ext}/efi/boot/bootia32.efi --format=i386-efi ${GRUB2_MODULES}
echo

rm ${memdisk_64_img}
rm ${memdisk_32_img}
echo

## Copy the actual grub2 config file
cat << EOF > ${archboot_ext}/efi/boot/grub.cfg
search --file --no-floppy --set=archboot /arch/archboot.txt

insmod efi_gop
insmod font

if loadfont (\${archboot})/efi/grub2/unifont.pf2
then
   insmod gfxterm
   set gfxmode="auto"
   set gfxpayload=keep
   terminal_output gfxterm

   set color_normal=light-blue/black
   set color_highlight=light-cyan/blue

   insmod png
   background_image (\${archboot})/boot/syslinux/splash.png
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

menuentry "Memtest86+" {
netbsd (\${archboot})/boot/memtest
}

EOF
echo


## Remove some files not needed for me - config files not modified - for now
if [ ${RM_UNWANTED} = "1" ]
then
    ## Remove all i686 pkgs
    rm -rf ${archboot_ext}/core-i686/
    
    ## Remove all LTS kernels and initramfs
    rm ${archboot_ext}/syslinux/vmlts
    rm ${archboot_ext}/syslinux/initrdlts.img
    rm ${archboot_ext}/syslinux/vm64lts
    rm ${archboot_ext}/syslinux/initrd64lts.img
    
    ## Remove i686 kernel and initramfs
    # rm ${archboot_ext}/syslinux/vmlinuz
    # rm ${archboot_ext}/syslinux/initrd.img
    
    ## Remove clamav files
    rm -rf ${archboot_ext}/clamav/
fi


## First create the BIOS+UEFI ISO
cd ${wd}
echo

## Generate the BIOS+UEFI ISO image using xorriso (community/libisoburn package) in mkisofs emulation mode

## Exaggerated xorriso command
xorriso -as mkisofs -rock -full-iso9660-filenames -omit-version-number -disable-deep-relocation -joliet -allow-leading-dots -volid "ARCHBOOT" -eltorito-boot boot/syslinux/isolinux.bin -eltorito-catalog boot/syslinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot --efi-boot efi/grub2/grub2_efi.bin -no-emul-boot -output ${wd}/${iso_name}_isohybrid.iso ${archboot_ext}/ > /dev/null 2>&1

## Usually used xorriso command style
# xorriso -as mkisofs -R -l -N -D -J -L -V "ARCHBOOT" -b syslinux/isolinux.bin -c boot/syslinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot --efi-boot efi/grub2/grub2_efi.bin -no-emul-boot -o ${wd}/${iso_name}_isohybrid.iso ${archboot_ext}/ > /dev/null 2>&1
echo

## Generate a isohybrid image using syslinux
isohybrid ${wd}/${iso_name}_isohybrid.iso
echo


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
sudo mount -o loop,rw,users -t vfat ${FSIMG} ${TMPDIR}
echo

## Copy the contents of the ISO to the USB image
sudo cp -r ${IMGROOT}/* ${TMPDIR}
echo

sudo umount ${TMPDIR}
echo

## Create the final USB image
cat ${FSIMG} > ${DISKIMG}
echo

## Install syslinux into the image
syslinux ${DISKIMG}
echo

sudo rm -rf ${TMPDIR} ${FSIMG}
echo

set +x

unset archboot_ver
unset wd
unset archboot_ext
unset iso_name
unset grub2_name
unset GRUB2_MODULES
unset MKTEMP_TEMPLATE
unset RM_UNWANTED
