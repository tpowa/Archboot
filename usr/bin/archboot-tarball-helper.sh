#! /bin/sh
# Created by Tobias Powalowski <tpowa@archlinux.org>
# Settings
APPNAME=$(basename "${0}")
CONFIG=""
TARNAME=""
export TEMPDIR=$(mktemp -d /tmp/tarball-helper.XXXX)

usage ()
{
    echo "${APPNAME}: usage"
    echo "  -c=CONFIG        Use CONFIG file"
    echo "  -t=TARNAME       Generate a tar image instead of an iso image"
    echo "  -h               This message."
    exit 1
}

[ "$1" == "" ] && usage

while [ $# -gt 0 ]; do
	case $1 in
		-c=*|--c=*) CONFIG="$(echo $1 | awk -F= '{print $2;}')" ;;
		-t=*|--t=*) TARNAME="$(echo $1 | awk -F= '{print $2;}')" ;;
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

if [ "${TARNAME}" = "" ]; then 
	echo "ERROR: No image name specified, please use the -t option"
	exit 1
fi

if [ ! -f "${CONFIG}" ]; then
	echo "config file '${CONFIG}' cannot be found, aborting..."
	exit 1
fi

. "${CONFIG}"
# export for mkinitcpio
[ -n "${APPENDBOOTMESSAGE}" ] && export APPENDBOOTMESSAGE
[ -n "${APPENDOPTIONSBOOTMESSAGE}" ] && export APPENDOPTIONSBOOTMESSAGE

export RUNPROGRAM="${APPNAME}"
export BOOTDIRNAME="isolinux"
export USEKERNEL=${VERSION}

[ "${BOOTMESSAGE}" = "" ] && export BOOTMESSAGE=$(mktemp /tmp/bootmessage.XXXX)
[ "${OPTIONSBOOTMESSAGE}" = "" ] && export OPTIONSBOOTMESSAGE=$(mktemp /tmp/optionsbootmessage.XXXX)

# begin script
mkdir -p ${TEMPDIR}/${BOOTDIRNAME}/
# prepare syslinux bootloader
install -m755 /usr/lib/syslinux/isolinux.bin ${TEMPDIR}/${BOOTDIRNAME}/isolinux.bin
for i in /usr/lib/syslinux/*.c32; do
    install -m644 $i ${TEMPDIR}/${BOOTDIRNAME}/$(basename $i)
done
install -m644 /lib/modules/$(uname -r)/modules.pcimap ${TEMPDIR}/${BOOTDIRNAME}/modules.pcimap
install -m644 /usr/share/hwdata/pci.ids ${TEMPDIR}/${BOOTDIRNAME}/pci.ids
install -m644 $BACKGROUND ${TEMPDIR}/${BOOTDIRNAME}/splash.png

# Use config file
echo ":: Creating isolinux.cfg ..."
if [ "${ISOLINUXCFG}" = "" ]; then
	echo "No isolinux.cfg file specified, aborting ..."
	exit 1
else
	sed "s|@@PROMPT@@|${PROMPT}|g;s|@@TIMEOUT@@|${TIMEOUT}|g;s|@@KERNEL_BOOT_OPTIONS@@|${KERNEL_BOOT_OPTIONS}|g" \
		${ISOLINUXCFG} > ${TEMPDIR}/${BOOTDIRNAME}/isolinux.cfg
	[ ! -s ${TEMPDIR}/${BOOTDIRNAME}/isolinux.cfg ] && echo "No isolinux.cfg found" && exit 1
fi
# generate initramdisk
echo ":: Calling mkinitcpio CONFIG=${MKINITCPIO_CONFIG} KERNEL=${VERSION} ..." 
echo ":: Creating initramdisk ..."
	mkinitcpio -c ${MKINITCPIO_CONFIG} -k ${VERSION} -g ${TEMPDIR}/${BOOTDIRNAME}/initrd.img
echo ":: Using ${KERNEL} as image kernel ..."
	install -m644 ${KERNEL} ${TEMPDIR}/${BOOTDIRNAME}/vmlinuz
	install -m644 ${BOOTMESSAGE} ${TEMPDIR}/${BOOTDIRNAME}/boot.msg
	install -m644 ${OPTIONSBOOTMESSAGE} ${TEMPDIR}/${BOOTDIRNAME}/options.msg
	[ ! -s ${TEMPDIR}/${BOOTDIRNAME}/boot.msg ] && echo 'ERROR:no boot.msg found, aborting!' && exit 1
	[ ! -s ${TEMPDIR}/${BOOTDIRNAME}/options.msg ] && echo 'ERROR:no options.msg found, aborting!' && exit 1
# create image
if ! [ "${TARNAME}" = "" ]; then
	echo ":: Creating tar image ..."
	[ -e ${TARNAME} ] && rm ${TARNAME}
	tar cfv ${TARNAME} ${TEMPDIR} > /dev/null 2>&1 && echo ":: tar Image succesfull created at ${TARNAME}"
fi
# clean /tmp
rm -r ${TEMPDIR}
