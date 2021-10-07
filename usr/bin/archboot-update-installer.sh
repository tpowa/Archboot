#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

D_SCRIPTS=""
L_COMPLETE=""
L_INSTALL_COMPLETE=""
G_RELEASE=""
CONFIG="/etc/archboot/x86_64.conf"
W_DIR="/archboot"
INSTALLER_SOURCE="https://gitlab.archlinux.org/tpowa/archboot/-/raw/master/usr/bin"
LOG="/dev/tty7"

usage () {
	echo "Update installer, launch latest environment or create latest image files:"
	echo "-------------------------------------------------------------------------"
	echo "PARAMETERS:"
	echo " -u             Update scripts: setup, quickinst, tz, km and helpers."
	echo ""
        echo "On fast internet connection (100Mbit) (approx. 5 minutes):"
	echo " -latest          Launch latest archboot environment (using kexec)."
        echo "                  This operation needs at least 3000 MB RAM."
        echo ""
        echo " -latest-install  Launch latest archboot environment with downloaded"
        echo "                  package cache (using kexec)."
        echo "                  This operation needs at least 4000 MB RAM."
        echo ""
        echo " -latest-image  Generate latest image files in /archboot-release directory"
        echo "                 This operation needs at least 4000 MB RAM."
        echo ""
	echo "  -h             This message."
	exit 0
}

[[ -z "${1}" ]] && usage

while [ $# -gt 0 ]; do
	case ${1} in
		-u|--u) D_SCRIPTS="1" ;;
		-latest|--latest) L_COMPLETE="1" ;;
		-latest-install|--latest-install) L_INSTALL_COMPLETE="1";;
		-latest-image|--latest-image) G_RELEASE="1" ;;
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

# Download latest setup and quickinst script from git repository
if [[ "${D_SCRIPTS}" == "1" ]]; then
    echo "Downloading latest km, tz, quickinst, setup and helpers..."
    [[ -e /usr/bin/quickinst ]] && wget -q "$INSTALLER_SOURCE/archboot-quickinst.sh?inline=false" -O /usr/bin/quickinst >/dev/null 2>&1
    [[ -e /usr/bin/setup ]] && wget -q "$INSTALLER_SOURCE/archboot-setup.sh?inline=false" -O /usr/bin/setup >/dev/null 2>&1
    [[ -e /usr/bin/km ]] && wget -q "$INSTALLER_SOURCE/archboot-km.sh?inline=false" -O /usr/bin/km >/dev/null 2>&1
    [[ -e /usr/bin/tz ]] && wget -q "$INSTALLER_SOURCE/archboot-tz.sh?inline=false" -O /usr/bin/tz >/dev/null 2>&1
    [[ -e /usr/bin/archboot-create-container.sh ]] && wget -q "$INSTALLER_SOURCE/archboot-create-container.sh?inline=false" -O /usr/bin/archboot-create-container.sh >/dev/null 2>&1
    [[ -e /usr/bin/archboot-x86_64-release.sh ]] && wget -q "$INSTALLER_SOURCE/archboot-x86_64-release.sh?inline=false" -O /usr/bin/archboot-x86_64-release.sh >/dev/null 2>&1
    [[ -e /usr/bin/update-installer.sh ]] && wget -q "$INSTALLER_SOURCE/archboot-update-installer.sh?inline=false" -O /usr/bin/update-installer.sh >/dev/null 2>&1
    echo "Finished: Downloading scripts done."
fi

# Generate new environment and launch it with kexec
if [[ "${L_COMPLETE}" == "1" || "${L_INSTALL_COMPLETE}" == "1" ]]; then
    # remove everything not necessary
    echo "Information: Logging is done on /dev/tty7 ..."
    echo "Step 1/6: Removing not necessary files from /usr ..."
    rm -r /lib/{firmware,modules} >/dev/tty7 2>&1
    rm -r /usr/share/{efitools,file,grub,hwdata,kbd,licenses,makepkg,nmap,openvpn,pacman,refind,tc,usb_modeswitch,vim,zoneinfo,zsh} >/dev/tty7 2>&1
    # create container without package cache
    if [[ "${L_COMPLETE}" == "1" ]]; then
        echo "Step 2/6: Generating archboot container in "${W_DIR}" ..."
        echo "          This will need some time ..."
        archboot-create-container.sh "${W_DIR}" -cc -cp -alf >/dev/tty7 2>&1 || exit 1
    fi
    # create container with package cache
    if [[ "${L_INSTALL_COMPLETE}" == "1" ]]; then 
        echo "Step 2/6: Generating archboot container in "${W_DIR}" ..."
        echo "          This will need some time ..."
        archboot-create-container.sh "${W_DIR}" -cc -alf >/dev/tty7 2>&1 || exit 1
    fi
    
    # generate initrd in container, remove archboot packages from cache, not needed in normal install, umount tmp before generating initrd
    echo "Step 3/6: Generating initramfs in "${W_DIR}" ..."
    echo "          This will need some time ..."
    systemd-nspawn -D "${W_DIR}" /bin/bash -c "rm /var/cache/pacman/pkg/archboot-*; umount /tmp;mkinitcpio -c ${CONFIG} -g /tmp/initrd.img; mv /tmp/initrd.img /" >/dev/tty7 2>&1 || exit 1
    echo "Step 4/6: Moving initramfs files from "${W_DIR}" to / ..."
    mv "${W_DIR}"/initrd.img / || exit 1
    mv "${W_DIR}"/boot/vmlinuz-linux / || exit 1
    mv "${W_DIR}"/boot/intel-ucode.img / || exit 1
    mv "${W_DIR}"/boot/amd-ucode.img / || exit 1
    # remove "${W_DIR}"
    echo "Step 5/6: Remove ${W_DIR} ..."
    rm -r "${W_DIR}" || exit 1
    echo "Step 6/6: Loading files to kexec now, reboot in a few seconds ..."
    # load kernel and initrds into running kernel
    kexec -l /vmlinuz-linux --initrd=/intel-ucode.img --initrd=/amd-ucode.img --initrd=/initrd.img --reuse-cmdline
    echo "Finished: Rebooting ..."
    # restart environment
    systemctl kexec
fi

# Generate new images
if [[ "${G_RELEASE}" == "1" ]]; then
    echo "Information: Logging is done on /dev/tty7 ..."
    echo "Step 1/1: Generating new iso files now in "${W_DIR}" ..."
    echo "          This will need some time ..."
    archboot-x86_64-release.sh "${W_DIR}" >/dev/tty7 2>&1 || exit 1
    echo "Finished: New isofiles are located in "${W_DIR}""
fi
