#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
D_SCRIPTS=""
L_COMPLETE=""
G_RELEASE=""
CONFIG="/etc/archboot/x86_64.conf"
W_DIR="archboot"
INSTALLER_SOURCE="https://gitlab.archlinux.org/tpowa/archboot/-/raw/master/usr/bin"

usage () {
	echo "${_BASENAME}: usage"
	echo "Update installer, launch latest environment or create latest image files:"
	echo "---------------------------------------------------------------------------"
	echo ""
	echo "PARAMETERS:"
	echo "  -u             Update scripts: setup, quickinst, tz, km and helpers."
	echo ""
	echo "  -latest        Launch latest archboot environment (using kexec)."
        echo "                 This operation needs at least 3500 MB RAM."
        echo "                 On fast internet connection (100Mbit) (approx. 5 minutes)"
        echo ""
        echo "  -latest-image  Generate latest image files in /archboot-release directory"
        echo "                 This operation needs at least 4000 MB RAM."
        echo "                 On fast internet connection (100Mbit) (approx. 5 minutes)"
        echo ""
	echo "  -h             This message."
	exit 0
}

[[ -z "${1}" ]] && usage

while [ $# -gt 0 ]; do
	case ${1} in
		-u|--u) D_SCRIPTS="1" ;;
		-latest|--latest) L_COMPLETE="1" ;;
		-latest-image|--latest-image) G_RELEASE="1" ;;
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

# Download latest setup and quickinst script from git repository
if [[ "${D_SCRIPTS}" == "1" ]]; then 
    echo 'Downloading latest km, tz, quickinst,setup and helpers...'

    [[ -e /usr/bin/quickinst ]] && wget -q "$INSTALLER_SOURCE/archboot-quickinst.sh?inline=false" -O /usr/bin/quickinst
    [[ -e /usr/bin/setup ]] && wget -q "$INSTALLER_SOURCE/archboot-setup.sh?inline=false" -O /usr/bin/setup
    [[ -e /usr/bin/km ]] && wget -q "$INSTALLER_SOURCE/archboot-km.sh?inline=false" -O /usr/bin/km
    [[ -e /usr/bin/tz ]] && wget -q "$INSTALLER_SOURCE/archboot-tz.sh?inline=false" -O /usr/bin/tz
    [[ -e /usr/bin/archboot-create-container.sh ]] && wget -q "$INSTALLER_SOURCE/archboot-create-container.sh?inline=false" -O /usr/bin/archboot-create-container.sh
    [[ -e /usr/bin/archboot-x86_64-release.sh ]] && wget -q "$INSTALLER_SOURCE/archboot-x86_64-release.sh?inline=false" -O /usr/bin/archboot-x86_64-release.sh
    [[ -e /usr/bin/update-installer.sh ]] && wget -q "$INSTALLER_SOURCE/archboot-update-installer.sh?inline=false" -O /usr/bin/update-installer.sh
fi

# Generate new environment and launch it with kexec
if [[ "${L_COMPLETE}" == "1" ]]; then
    # create container
    archboot-create-container.sh "${W_DIR}" || exit 1
    # generate initrd in container
    systemd-nspawn -D "${W_DIR}" /bin/bash -c "umount /tmp;mkinitcpio -c ${CONFIG} -g /tmp/initrd.img; mv /tmp/initrd.img /" || exit 1
    mv "${W_DIR}"/initrd.img /
    mv "${W_DIR}"/boot/vmlinuz-linux /
    mv "${W_DIR}"/boot/intel-ucode.img /
    mv "${W_DIR}"/boot/amd-ucode.img /
    # remove "${W_DIR}"
    rm -r "${W_DIR}"
    # load kernel and initrds into running kernel
    kexec -l /vmlinuz-linux --initrd=/intel-ucode.img --initrd=/amd-ucode.img --initrd=/initrd.img --reuse-cmdline
    # restart environment
    systemctl kexec
fi

# Generate new images
if [[ "${G_RELEASE}" == "1" ]]; then
    archboot-x86_64-release.sh "${W_DIR}"
fi
