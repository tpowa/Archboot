#! /bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
APPNAME=$(basename "${0}")
usage ()
{
    echo "${APPNAME}: usage"
    echo "CREATE ALLINONE USB/CD IMAGES"
    echo "-----------------------------"
    echo "Run in archboot x86_64 chroot first ..."
    echo "mkbootcd -c=/etc/archboot/archbootcd.conf -t=core64.tar.bz2"
    echo "mkbootcd -c=/etc/archboot/archbootcd-lowmem.conf -t=lowmem64.tar.bz2"
    echo "Run in archboot 686 chroot then ..."
    echo "mkbootcd -c=/etc/archboot/archbootcd.conf -t=core.tar.bz2"
    echo "mkbootcd -c=/etc/archboot/archbootcd-lowmem.conf -t=lowmem.tar.bz2"
    echo "Copy the generated tarballs to your favorite directory and run:"
    echo "${APPNAME} -g <any other option>"
    echo ""
    echo "PARAMETERS:"
    echo "  -g               Start generation of images."
    echo "  -i=IMAGENAME     Your IMAGENAME."
    echo "  -r=RELEASENAME   Use RELEASENAME in boot message."
    echo "  -k=KERNELNAME    Use KERNELNAME in boot message."
    echo "  -h               This message."
    exit 1
}

[ "$1" == "" ] && usage && exit 1


while [ $# -gt 0 ]; do
	case $1 in
		-g|--g) GENERATE="1" ;;
		-i=*|--i=*) IMAGENAME="$(echo $1 | awk -F= '{print $2;}')" ;;
		-r=*|--r=*) RELEASENAME="$(echo $1 | awk -F= '{print $2;}')" ;;
		-k=*|--k=*) KERNEL="$(echo $1 | awk -F= '{print $2;}')" ;;
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

if ! [ ${GENERATE} = "1" ]; then
	usage
fi

### check for root
if ! [ $UID -eq 0 ]; then 
	echo "ERROR: Please run as root user!"
	exit 1
fi

[ "${KERNEL}" = "" ] && KERNEL=$(uname -r)
[ "${RELEASENAME}" = "" ] && RELEASENAME="Nepal"
[ "${IMAGENAME}" = "" ] && IMAGENAME="Archlinux-allinone-$(date +%Y.%m)"

LOWMEM=$(mktemp -d /tmp/lowmem.XXX)
LOWMEM64=$(mktemp -d /tmp/lowmem64.XXX)
CORE=$(mktemp -d /tmp/core.XXX)
CORE64=$(mktemp -d /tmp/core64.XXX)
ALLINONE=$(mktemp -d /tmp/allinone.XXX)

# create directories
mkdir ${ALLINONE}/arch
mkdir ${ALLINONE}/isolinux
# extract tarballs
tar xvf lowmem64.tar -C ${LOWMEM64} || exit 1
tar xvf core64.tar  -C ${CORE64} || exit 1
tar xvf lowmem.tar -C ${LOWMEM} || exit 1
tar xvf core.tar  -C ${CORE} || exit 1
# move in packages
mv ${LOWMEM}/tmp/*/core-i686 ${ALLINONE}/
mv ${LOWMEM64}/tmp/*/core-x86_64 ${ALLINONE}/
# move in doc
mv ${CORE}/tmp/*/arch/archdoc.txt ${ALLINONE}/arch/
# place kernels and memtest
mv ${LOWMEM}/tmp/*/isolinux/vmlinuz ${ALLINONE}/isolinux/
mv ${LOWMEM64}/tmp/*/isolinux/vmlinuz ${ALLINONE}/isolinux/vm64
mv ${LOWMEM}/tmp/*/isolinux/memtest ${ALLINONE}/isolinux/
# place initrd files
mv ${LOWMEM}/tmp/*/isolinux/initrd.img ${ALLINONE}/isolinux/lowmem.img
mv ${LOWMEM64}/tmp/*/isolinux/initrd.img ${ALLINONE}/isolinux/lowmem64.img
mv ${CORE}/tmp/*/isolinux/initrd.img ${ALLINONE}/isolinux/
mv ${CORE64}/tmp/*/isolinux/initrd.img ${ALLINONE}/isolinux/initrd64.img
# place config files
cp /etc/archboot/allinone/config/* ${ALLINONE}/isolinux/
rm ${ALLINONE}/isolinux/boot-syslinux.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" ${ALLINONE}/isolinux/boot.msg
# generate iso file
echo "Generating ALLINONE ISO ..."
mkisofs -RlDJLV "Arch Linux ALLINONE" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ${IMAGENAME}.iso ${ALLINONE}/ > /dev/null 2>&1

echo "Generating ALLINONE IMG ..."
# cleanup isolinux and migrate to syslinux
rm ${ALLINONE}/isolinux/isolinux.bin
mv ${ALLINONE}/isolinux/isolinux.cfg ${ALLINONE}/isolinux/syslinux.cfg
mv ${ALLINONE}/isolinux/* ${ALLINONE}/
rm -r  ${ALLINONE}/isolinux
cp /etc/archboot/allinone/config/boot-syslinux.msg ${ALLINONE}/boot.msg
sed -i -e "s/@@DATE@@/$(date)/g" -e "s/@@KERNEL@@/$KERNEL/g" -e "s/@@RELEASENAME@@/$RELEASENAME/g" ${ALLINONE}/boot.msg
/etc/archboot/allinone/usbimage-helper.sh ${ALLINONE} ${IMAGENAME}.img > /dev/null 2>&1
#create md5sums.txt
[ -e md5sum.txt ] && rm -f md5sum.txt
for i in ${IMAGENAME}.iso ${IMAGENAME}.img; do
	md5sum $i >> md5sum.txt
done
# cleanup
rm -r ${LOWMEM}
rm -r ${LOWMEM64}
rm -r ${CORE}
rm -r ${CORE64}
rm -r ${ALLINONE}
