#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_BASENAME="$(basename "${0}")"
D_SCRIPTS=""
L_COMPLETE=""
G_RELEASE=""
CONFIG="/etc/archboot/x86_64.conf"

usage () {
	echo "${_BASENAME}: usage"
	echo "Update installer or complete environment or create new image files:"
	echo "-------------------------------------------------------------------"
	echo ""
	echo "PARAMETERS:"
	echo "  -u      Update scripts: setup, quickinst, tz and km."
	echo "  -c      Update and launch complete updated archboot environment (using kexec)."
        echo "          This operation needs at least 7500 MB RAM."
        echo "  -i      Generate new release image files in /archboot-release directory"
        echo "          This operation needs at least 8000 MB RAM."
	echo "  -h      This message."
	exit 0
}

[[ -z "${1}" ]] && usage

while [ $# -gt 0 ]; do
	case ${1} in
		-u|--u) D_SCRIPTS="1" ;;
		-c|--c) L_COMPLETE="1" ;;
		-i|--i) G_RELEASE="1" ;;
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

# Download latest setup and quickinst script from git repository
if [[ "${D_SCRIPTS}" == "1" ]]; then 
    echo 'Downloading latest km, tz, quickinst and setup script...'
    INSTALLER_SOURCE="https://gitlab.archlinux.org/tpowa/archboot/-/raw/master/usr/bin"
    [[ -e /usr/bin/quickinst ]] && wget -q "$INSTALLER_SOURCE/archboot-quickinst.sh?inline=false" -O /usr/bin/quickinst
    [[ -e /usr/bin/setup ]] && wget -q "$INSTALLER_SOURCE/archboot-setup.sh?inline=false" -O /usr/bin/setup
    [[ -e /usr/bin/km ]] && wget -q "$INSTALLER_SOURCE/archboot-km.sh?inline=false" -O /usr/bin/km
    [[ -e /usr/bin/tz ]] && wget -q "$INSTALLER_SOURCE/archboot-tz.sh?inline=false" -O /usr/bin/tz
fi

# Generate new environment and launch it with kexec
if [[ "${L_COMPLETE}" == "1" ]]; then
    # create container
    archboot-create-container.sh archboot || exit 1
    # clean cache to safe memory
    pacman -Scc --noconfirm
    systemd-nspawn -D archboot pacman -Scc --noconfirm
    # generate tarball in container
    systemd-nspawn -D archboot /bin/bash -c "mkinitcpio -c ${CONFIG} -g /tmp/initrd.img; mv /tmp/initrd.img /" || exit 1
    kexec -l archboot/boot/vmlinuz-linux --initrd=archboot/boot/intel-ucode.img --initrd=archboot/boot/amd-ucode.img --initrd=archboot/initrd.img --reuse-cmdline
    systemctl kexec
fi

# Generate new images
if [[ "${G_RELEASE}" == "1" ]]; then
    archboot-x86_64-release.sh archboot
fi
