#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

INSTALLER_SOURCE="https://gitlab.archlinux.org/tpowa/archboot/-/raw/master"

usage () {
	echo "Update files for aarch64/ARM image:"
	echo "-------------------------------------------------------------------------"
	echo "PARAMETERS:"
	echo " -u             Update aarch64/ARM scripts"
        echo ""
	echo " -h               This message."
	exit 0
}

[[ -z "${1}" ]] && usage

while [ $# -gt 0 ]; do
	case ${1} in
		-u|--u) D_SCRIPTS="1" ;;
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

# Download latest aarch64/ARM scripts from git repository
if [[ "${D_SCRIPTS}" == "1" ]]; then
    wget -q "$INSTALLER_SOURCE/etc/archboot/presets/aarch64?inline=false" -O /etc/archboot/presets/aarch64
    wget -q "$INSTALLER_SOURCE/etc/archboot/aarch64.conf?inline=false" -O /etc/archboot/aarch64
    wget -q "$INSTALLER_SOURCE/usr/bin/archboot-aarch64-iso.sh?inline=false" -O /usr/bin/archboot-aarch64-iso.sh
    wget -q "$INSTALLER_SOURCE/usr/bin/archboot-download-arm.sh?inline=false" -O /usr/bin/archboot-download-arm.sh
    wget -q "$INSTALLER_SOURCE/usr/bin/archboot-tarball-helper-arm.sh?inline=false" -O /usr/bin/archboot-tarball-helper-arm.sh
fi

