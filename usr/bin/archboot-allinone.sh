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
[ "${RELEASENAME}" = "" ] && RELEASENAME="2k10-R7"
[ "${IMAGENAME}" = "" ] && IMAGENAME="Archlinux-allinone-$(date +%Y.%m)"

# generate temp directories
CORE=$(mktemp -d /tmp/core.XXX)
CORE64=$(mktemp -d /tmp/core64.XXX)
CORE_LTS=$(mktemp -d /tmp/core-lts.XXX)
CORE64_LTS=$(mktemp -d /tmp/core64-lts.XXX)
ALLINONE=$(mktemp -d /tmp/allinone.XXX)

# create directories
mkdir ${ALLINONE}/arch
mkdir -p ${ALLINONE}/boot/syslinux

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
    freshclam
    cp /var/lib/clamav/daily.cvd ${ALLINONE}/clamav/
    cp /var/lib/clamav/main.cvd ${ALLINONE}/clamav/
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

# place config files
mv ${CORE}/tmp/*/boot/syslinux/syslinux.cfg ${ALLINONE}/boot/syslinux/
mv ${CORE}/tmp/*/boot/syslinux/boot.msg ${ALLINONE}/boot/syslinux/
mv ${CORE}/tmp/*/boot/syslinux/options.msg ${ALLINONE}/boot/syslinux/
# place syslinux files
mv ${CORE}/tmp/*/boot/syslinux/isolinux.bin ${ALLINONE}/boot/syslinux/
mv ${CORE}/tmp/*/boot/syslinux/*.c32 ${ALLINONE}/boot/syslinux/
mv ${CORE}/tmp/*/boot/syslinux/pci.ids ${ALLINONE}/boot/syslinux/
mv ${CORE}/tmp/*/boot/syslinux/modules.pcimap ${ALLINONE}/boot/syslinux/
mv ${CORE}/tmp/*/boot/syslinux/splash.png ${ALLINONE}/boot/syslinux/

# Change parameters in boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g"  -e "s/@@LTS_KERNEL@@/$LTS_KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" -e "s/@@BOOTLOADER@@/ISOLINUX/g" ${ALLINONE}/boot/syslinux/boot.msg

# generate iso file
echo "Generating ALLINONE ISO ..."
mkisofs -RlDJLV "Arch Linux ALLINONE" -b boot/syslinux/isolinux.bin -c boot/syslinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ${IMAGENAME}.iso ${ALLINONE}/ > /dev/null 2>&1

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
# cleanup
rm -r ${CORE}
rm -r ${CORE64}
rm -r ${CORE_LTS}
rm -r ${CORE64_LTS}
rm -r ${ALLINONE}
