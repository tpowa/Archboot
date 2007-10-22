#! /bin/sh
# Created by Tobias Powalowski <tpowa@archlinux.org>
# Settings
APPNAME=$(basename "${0}")
IMAGE=""
CONFIG=""
VERSION=""
ARCH=""
PACMAN=""
PACKAGES=""
PACKAGEDIR=""
KERNELDIR=""

usage ()
{
    echo "${APPNAME}: usage"
    echo "Needed:"
    echo "  -i=IMAGE         boot IMAGE for ISO creation"
    echo "  -v=VERSION       VERSION name of ISO image"
    echo "  -a=ARCH          architecture name of ISO image"
    echo "  -P=PACKAGES      packages.txt file on ISO image"
    echo "  -PD=PACKAGEDIR   directory with packages included"
    echo "  -KD=KERNELDIR    directory with alternate kernel included"
    echo "Optional:"
    echo "  -c=CONFIG        Use CONFIG file with included parameters."
    echo "  -h               this message"
    exit 1
}

[ "$1" == "" ] && usage


while [ $# -gt 0 ]; do
	case $1 in
		-i=*|--i=*) IMAGE="$(echo $1 | awk -F= '{print $2;}')" ;;
		-c=*|--c=*) CONFIG="$(echo $1 | awk -F= '{print $2;}')" ;;
		-v=*|--v=*) VERSION="$(echo $1 | awk -F= '{print $2;}')" ;;
		-a|--a) ARCH="$(echo $1 | awk -F= '{print $2;}')" ;;
		-p|--p) PACMAN="$(echo $1 | awk -F= '{print $2;}')" ;;
		-P=*|--P=*) PACKAGES="$(echo $1 | awk -F= '{print $2;}')" ;;
		-PD=*|--PD=*) PACKAGEDIR="$(echo $1 | awk -F= '{print $2;}')" ;;
		-KD=*|--KD=*) KERNELDIR="$(echo $1 | awk -F= '{print $2;}')" ;;
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

. ${CONFIG}
# check for parameters
if ! [ -e "${IMAGE}" ] ; then
	echo "Image does not exist, aborting now."
	exit 1
fi
if [ "${VERSION}" = "" -o "${ARCH}" = "" -o "${PACKAGES}" = "" -o "${PACKAGEDIR}" = "" ]; then
	echo "One parameter is missing please check your paramters, aborting now"
	exit 1
fi

if ! [ "$KERNELDIR" = "" ]; then
	USE_RC_KERNEL=1
fi

# unpack base of installation
tar xfj ${IMAGE}
rm $(echo tmp/*/)isolinux/*lowmem*
# generate ftp iso
! [ -d $ARCH-iso ] && mkdir $ARCH-iso
echo "Generating FTP ${ARCH} ISO ..."
mkisofs -RlDJLV "Arch Linux FTP ${ARCH}" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $ARCH-iso/Archlinux-${ARCH}-$(date +%Y.%m)-${VERSION}.ftp.iso $(echo tmp/*/) > /dev/null 2>&1
# generate base iso
#echo "Generating BASE ${ARCH} ISO ..."
#mkdir -p $(echo tmp/*/)arch/pkg/setup
#if [ "$USE_RC_KERNEL" = "1" ]; then
#	# make directories and extract db files
#	mkdir fake-package
#	mkdir -p db/current
#	mkdir -p db/kernel
#	grep -e base/ -e kernels/ ${PACKAGES} > fake-package/packages.txt
#	tar  xfz ${PACKAGEDIR}/current.db.tar.gz -C db/current/
#	tar  xfz ${KERNELDIR}/kernel.db.tar.gz -C db/kernel/
#	# replace kernel26 with wanted kernel
#	sed -i -e "s#$(echo db/current/kernel26* | sed -e's#.*/##g')#$(echo db/kernel/kernel26* | sed -e's#.*/##g')#g" fake-package/packages.txt
#	cp fake-package/packages.txt $(echo tmp/*/)arch/pkg/setup/packages.txt
#	# change kernel26 in db file
#	rm -r db/current/$(echo kernel26*)
#	cp -r db/kernel/$(echo kernel26*) db/current/
#	cd db/current
#	# regenerate db file
#	tar cvfz current.db.tar.gz *
#	cd ../../
#	cp db/current/current.db.tar.gz $(echo tmp/*/)arch/pkg/
#	#cleanup db files and packages
#	rm -r fake-package/ db/
#	# copy packages
#	for i in $(cat $(echo tmp/*/)arch/pkg/setup/packages.txt | sed -e 's#.*/##g'); do
#		if ! (echo $i | grep "kernel26*"); then 
#			cp ${PACKAGEDIR}/$i $(echo tmp/*/)arch/pkg/ || exit 1
#		else
#			cp ${KERNELDIR}/$i $(echo tmp/*/)arch/pkg/ || exit 1
#		fi
#	done
#else
#	grep -e base/ -e kernels/ ${PACKAGES} > $(echo tmp/*/)arch/pkg/setup/packages.txt
#	cp ${PACKAGEDIR}/current.db.tar.gz $(echo tmp/*/)arch/pkg/
#	for i in $(cat $(echo tmp/*/)arch/pkg/setup/packages.txt | sed -e 's#.*/##g'); do 
#		cp ${PACKAGEDIR}/$i $(echo tmp/*/)arch/pkg/ || exit 1
#	done
#fi
#if [ ${PACMAN} = "" ]; then
#	for i in $(cat $(echo tmp/*/)arch/pkg/setup/packages.txt | sed -e 's#.*/##g' | grep pacman); do 
#		cp ${PACKAGEDIR}/$i $(echo tmp/*/)arch/pkg/setup/ || exit 1
#	done
#else
#	cp ${PACMAN} $(echo tmp/*/)arch/pkg/setup/ || return 1
#fi
#mkisofs -RlDJLV "Arch Linux BASE ${ARCH}" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o Archlinux-${ARCH}-$(date +%Y.%m)-${VERSION}.base.iso $(echo tmp/*/) > /dev/null 2>&1
# generate core
echo "Generating CORE ${ARCH} ISO ..."
mkdir -p $(echo tmp/*/)core/pkg
if [ "$USE_RC_KERNEL" = "1" ] ; then
	# make directories and extract db files
	mkdir fake-package
	mkdir -p db/core
	mkdir -p db/kernel
	cp ${PACKAGES} fake-package/packages.txt
	tar xfz ${PACKAGEDIR}/core.db.tar.gz -C db/core/
	tar xfz ${KERNELDIR}/kernel.db.tar.gz -C db/kernel/
	# replace kernel26 with wanted kernel
	sed -i -e "s#$(echo db/core/kernel26* | sed -e's#.*/##g')#$(echo db/kernel/kernel26* | sed -e's#.*/##g')#g" fake-package/packages.txt
	cp fake-package/packages.txt $(echo tmp/*/)core/pkg/packages.txt
	# change kernel26 in db file
	rm -r db/core/$(echo kernel26*)
	cp -r db/kernel/$(echo kernel26*) db/core/
	cd db/core
	# regenerate db file
	tar cvfz core.db.tar.gz *
	cd ../../
	cp db/current/core.db.tar.gz $(echo tmp/*/)core/pkg/
	#cleanup db files and packages
	rm -r fake-package/ db/
	# copy packages
	for i in $(cat $(echo tmp/*/)core/pkg/packages.txt | sed -e 's#.*/##g'); do
		if ! (echo $i | grep "kernel26*"); then 
			cp ${PACKAGEDIR}/$i $(echo tmp/*/)core/pkg/ || exit 1
		else
			cp ${KERNELDIR}/$i $(echo tmp/*/)core/pkg/ || exit 1
		fi
	done
else
	tar xfj ${IMAGE}
	cp ${PACKAGES} $(echo tmp/*/)core/pkg/
	cp ${PACKAGEDIR}/core.db.tar.gz $(echo tmp/*/)core/pkg/
	for i in $(cat ${PACKAGES} | sed -e 's#.*/##g'); do 
		cp ${PACKAGEDIR}/$i $(echo tmp/*/)core/pkg/ || exit 1 
	done
	cd $(echo tmp/*/)isolinux/
	mv isolinux-lowmem.cfg isolinux.cfg
	mv boot-lowmem.msg boot.msg
	cd ../../../
fi
#if [ ${PACMAN} = "" ]; then
#	for i in $(cat $(echo tmp/*/)arch/pkg/packages.txt | sed -e 's#.*/##g' | grep pacman); do 
#		cp ${PACKAGEDIR}/$i $(echo tmp/*/)arch/pkg/ || exit 1
#	done
#else
#	cp ${PACMAN} $(echo tmp/*/)arch/pkg/ || return 1
#fi
! [ -d ${ARCH} ] && mkdir ${ARCH}
mkisofs -RlDJLV "Arch Linux CORE ${ARCH}" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ${ARCH}/Archlinux-${ARCH}-$(date +%Y.%m)-${VERSION}.core.iso $(echo tmp/*/) > /dev/null 2>&1
# clean up
rm -r tmp/
# generate md5sums
echo "Generating md5sums.txt ..."
cd ${ARCH}
for i in *.iso; do md5sum $i >> md5sum.txt; done
# generate torrents
echo "Generating torrent files ..."
maketorrent-console --comment www.archlinux.org http://linuxtracker.org/announce.php *
cd ..
