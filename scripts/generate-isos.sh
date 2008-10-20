#! /bin/sh
# Created by Tobias Powalowski <tpowa@archlinux.org>
# Settings
APPNAME=$(basename "${0}")
IMAGE=""
CONFIG=""
VERSION=""
ARCH=""
PACKAGEDIR=""
TESTINGDIR=""
TESTINGLIST=""

usage ()
{
    echo "${APPNAME}: usage"
    echo "Needed:"
    echo "  -i=IMAGE         boot IMAGE for ISO creation"
    echo "  -v=VERSION       VERSION name of ISO image"
    echo "  -a=ARCH          architecture name of ISO image"
    echo "  -PD=PACKAGEDIR   directory with packages included"
    echo "Optional:"
    echo "  -c=CONFIG        Use CONFIG file with included parameters."
    echo "  -TD=TESTINGDIR   directory with testing packages included"
    echo "  -TL=TESTINGLIST  list of testing packages to be included"
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
		-PD=*|--PD=*) PACKAGEDIR="$(echo $1 | awk -F= '{print $2;}')" ;;
		-TD=*|--TD=*) TESTINGDIR="$(echo $1 | awk -F= '{print $2;}')" ;;
		-TL=*|--TL=*) TESTINGLIST="$(echo $1 | awk -F= '{print $2;}')" ;;
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
if [ "${VERSION}" = "" -o "${ARCH}" = "" -o "${PACKAGEDIR}" = "" ]; then
	echo "One parameter is missing please check your paramters, aborting now"
	exit 1
fi

if ! [ "$TESTINGDIR" = "" ]; then
	USE_TESTING=1
fi

# unpack base of installation
tar xfj ${IMAGE}
rm $(echo tmp/*/)isolinux/*lowmem*
# generate ftp iso
! [ -d ${ARCH} ] && mkdir ${ARCH}
echo "Generating FTP ${ARCH} ISO ..."
mkisofs -RlDJLV "Arch Linux FTP ${ARCH}" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ${ARCH}/Archlinux-${ARCH}-$(date +%Y.%m)-${VERSION}.ftp.iso $(echo tmp/*/) > /dev/null 2>&1
# generate core
echo "Generating CORE ${ARCH} ISO ..."
mkdir -p $(echo tmp/*/)core/pkg
if [ "$USE_TESTING" = "1" ] ; then
	tar xfj ${IMAGE}
	# make directories and extract db files
	mkdir fake-package
	mkdir -p db/core
	mkdir -p db/testing
	cp ${PACKAGES} fake-package/packages.txt
	tar xfz ${PACKAGEDIR}/core.db.tar.gz -C db/core/
	tar xfz ${TESTINGDIR}/testing.db.tar.gz -C db/testing/
	# replace the packages from core with testing packages
	for i in ${TESTINGLIST}; do
		if [ $(grep $i fake-package/packages.txt | grep ${ARCH}) ]; then
			sed -i -e "s#$(echo db/core/$i* | sed -e's#.*/##g')#$(echo db/testing/$i* | sed -e's#.*/##g')#g" fake-package/packages.txt
		else
			sed -i -e "s#$(echo db/core/$i* | sed -e's#.*/##g')#$(echo $(echo db/testing/$i*)-${ARCH} | sed -e's#.*/##g')#g" fake-package/packages.txt
		fi
		# change the packages in db file
		rm -r db/core/$(echo $i*)
		cp -r db/testing/$(echo $i*) db/core/
	done
	cp fake-package/packages.txt $(echo tmp/*/)core/pkg/packages.txt
	cd db/core
	# regenerate db file
	tar cvfz core.db.tar.gz *
	cd ../../
	cp db/core/core.db.tar.gz $(echo tmp/*/)core/pkg/
	#cleanup db files and packages
	rm -r fake-package/ db/
	# copy packages
	for i in $(cat $(echo tmp/*/)core/pkg/packages.txt | sed -e 's#.*/##g'); do
		cp ${PACKAGEDIR}/$i $(echo tmp/*/)core/pkg/ >/dev/null 2>&1 || (echo "Inserting $i testing package ..."; cp ${TESTINGDIR}/$i $(echo tmp/*/)core/pkg/) || exit 1
	done
	cd $(echo tmp/*/)isolinux/
	mv isolinux-lowmem.cfg isolinux.cfg
	mv boot-lowmem.msg boot.msg
	cd ../../../
else
	tar xfj ${IMAGE}
    	SVNTREE=$(mktemp svntree.XXXX)
    	rm ${SVNTREE}
    	mkdir -p ${SVNTREE}
        cd ${SVNTREE}
	BASE="acl attr bash binutils bzip2 run-parts ca-certificates coreutils cpio cracklib cryptsetup dash db dcron device-mapper dhcpcd dialog dmapi e2fsprogs file filesystem findutils gawk gcc-libs gdbm gen-init-cpio gettext glibc grep groff grub gzip hdparm hwdetect initscripts iputils jfsutils kbd kernel-headers kernel26 klibc klibc-extras klibc-kbd klibc-module-init-tools klibc-udev less libarchive libdownload libgcrypt libgpg-error libpcap libusb licenses logrotate lvm2 lzo2 mailx man man-pages mdadm mkinitcpio mlocate module-init-tools nano ncurses net-tools openssl pacman pam pciutils pcmciautils pcre perl popt ppp procinfo procps psmisc readline reiserfsprogs rp-pppoe sdparm sed shadow sysfsutils syslog-ng sysvinit tar tcp_wrappers tzdata udev usbutils util-linux-ng vi wget which wpa_supplicant xfsprogs zlib"
	DEVEL="autoconf automake bin86 bison diffutils ed fakeroot flex gcc libtool m4 make patch pkgconfig texinfo"
	LIB="eventlog glib2 gmp heimdal libelf libevent libldap libsasl mpfr nfsidmap"
	SUPPORT="atl2-2.0.4-1 bcm43xx-fwcutter bridge-utils capi4k-utils dnsutils dosfstools fuse gpm ifenslave iproute iptables ipw2100-fw ipw2200-fw isdn4k-utils iwlwifi-3945-ucode iwlwifi-4965-ucode links linux-atm madwifi madwifi-utils ndiswrapper ndiswrapper-utils netcfg netkit-telnet nfs-utils ntfs-3g ntfsprogs openssh openswan openvpn portmap ppp pptpclient rp-pppoe rt2500 rt2x00 rt2x00 sudo tiacx tiacx-firmware vpnc wireless_tools wlan-ng26 wlan-ng26-utils wpa_supplicant xinetd zd1211-firmware"
	for i in base devel lib support; do
	    mkdir $i
	    svn co -N svn://localhost/home/svn-packages/ $i
	done
	cd base; svn up $BASE; cd ..
	cd devel; svn up $DEVEL; cd ..
	cd lib; svn up $LIB; cd ..
	cd support; svn up $SUPPORT; cd ..
	SEARCHSVN=$(find ./ -type d -name *"$ARCH" ! -name "testing*")
	for COPY in ${SEARCHSVN};do
		if ! [ "$(echo ${COPY} | awk -F/ '{print $3}')" = "" ]; then
			source "${COPY}/PKGBUILD"
			cp $PACKAGEDIR/${pkgname}-${pkgver}-${pkgrel}-$ARCH.pkg.tar.gz ../$(echo tmp/*/)core/pkg/
			echo "$(echo ${COPY}| awk -F/ '{print $2}')/${pkgname}-${pkgver}-${pkgrel}-$ARCH.pkg.tar.gz" >> packages.txt
		fi
	 done
	repo-add core.db.tar.gz  ../$(echo tmp/*/)core/pkg/*.pkg.tar.gz
	# generate packages.txt
	sort -u  packages.txt -o  packages.txt
	mv core.db.tar.gz ../$(echo tmp/*/)core/pkg/
	mv packages.txt ../$(echo tmp/*/)core/pkg/
	cd  ../ 
	cd $(echo tmp/*/)isolinux/
	mv isolinux-lowmem.cfg isolinux.cfg
	mv boot-lowmem.msg boot.msg
	cd ../../../
fi
! [ -d ${ARCH} ] && mkdir ${ARCH}
mkisofs -RlDJLV "Arch Linux CORE ${ARCH}" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ${ARCH}/Archlinux-${ARCH}-$(date +%Y.%m)-${VERSION}.core.iso $(echo tmp/*/) > /dev/null 2>&1
# clean up
rm -r tmp/
rm -rf $SVNTREE
# generate md5sums
echo "Generating md5sums.txt ..."
cd ${ARCH}
for i in *.iso; do md5sum $i >> md5sum.txt; done
# generate torrents
echo "Generating torrent files ..."
maketorrent-console --comment www.archlinux.org http://linuxtracker.org/announce.php *
rm md5sum.txt.torrent
cd ..
