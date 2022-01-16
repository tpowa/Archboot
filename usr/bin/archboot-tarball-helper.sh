#!/usr/bin/env bash
# Created by Tobias Powalowski <tpowa@archlinux.org>
# Settings
APPNAME=$(basename "${0}")
CONFIG=""
TARNAME=""

export TEMPDIR=$(mktemp -d tarball-helper.XXXX)

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
mkdir -p "${TEMPDIR}/boot"
# generate initramdisk
echo ":: Calling mkinitcpio CONFIG=${MKINITCPIO_CONFIG} ..." 
echo ":: Creating initramdisk ..."
mkinitcpio -c ${MKINITCPIO_CONFIG} -k ${ALL_kver} -g ${TEMPDIR}/boot/initrd.img
echo ":: Using ${ALL_kver} as image kernel ..."
install -m644 ${ALL_kver} ${TEMPDIR}/boot/vmlinuz
if [[ "$(uname -m)" == "aarch64" ]]; then
    cp -r /boot/dtbs ${TEMPDIR}/boot
fi
# create image
if ! [ "${TARNAME}" = "" ]; then
    echo ":: Creating tar image ..."
    [ -e ${TARNAME} ] && rm ${TARNAME}
    tar cfv ${TARNAME} ${TEMPDIR} > /dev/null 2>&1 && echo ":: tar Image succesfull created at ${TARNAME}"
fi
# clean directory
rm -r ${TEMPDIR}

