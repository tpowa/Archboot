#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>

_D_SCRIPTS=""
_L_COMPLETE=""
_L_INSTALL_COMPLETE=""
_G_RELEASE=""
_RUNNING_ARCH="$(uname -m)"
_CONFIG="/etc/archboot/${_RUNNING_ARCH}.conf"
_W_DIR="/archboot"
_INSTALLER_SOURCE="https://gitlab.archlinux.org/tpowa/archboot/-/raw/master/usr/bin"

usage () {
	echo "Update installer, launch latest environment or create latest image files:"
	echo "-------------------------------------------------------------------------"
	echo "PARAMETERS:"
	echo " -u             Update scripts: setup, quickinst, tz, km and helpers."
	echo ""
        echo "On fast internet connection (100Mbit) (approx. 5 minutes):"
	echo " -latest          Launch latest archboot environment (using kexec)."
        echo "                  This operation needs at least 3 GB RAM."
        echo ""
        echo " -latest-install  Launch latest archboot environment with downloaded"
        echo "                  package cache (using kexec)."
        echo "                  This operation needs at least 4 GB RAM."
        echo ""
        echo " -latest-image    Generate latest image files in /archboot-release directory"
        echo "                  This operation needs at least 3.6 GB RAM."
        echo ""
	echo " -h               This message."
	exit 0
}

[[ -z "${1}" ]] && usage

while [ $# -gt 0 ]; do
	case ${1} in
		-u|--u) _D_SCRIPTS="1" ;;
		-latest|--latest) _L_COMPLETE="1" ;;
		-latest-install|--latest-install) _L_INSTALL_COMPLETE="1";;
		-latest-image|--latest-image) _G_RELEASE="1" ;;
		-h|--h|?) usage ;; 
		*) usage ;;
		esac
	shift
done

if [[ ! "$(cat /etc/hostname)" == "archboot" ]]; then
    echo "This script should only be run in booted archboot environment. Aborting..."
    exit 1
fi

# Download latest setup and quickinst script from git repository
if [[ "${_D_SCRIPTS}" == "1" ]]; then
    echo "Downloading latest km, tz, quickinst, setup and helpers..."
    [[ -e /usr/bin/quickinst ]] && wget -q "$_INSTALLER_SOURCE/archboot-quickinst.sh?inline=false" -O /usr/bin/quickinst >/dev/null 2>&1
    [[ -e /usr/bin/setup ]] && wget -q "$_INSTALLER_SOURCE/archboot-setup.sh?inline=false" -O /usr/bin/setup >/dev/null 2>&1
    [[ -e /usr/bin/km ]] && wget -q "$_INSTALLER_SOURCE/archboot-km.sh?inline=false" -O /usr/bin/km >/dev/null 2>&1
    [[ -e /usr/bin/tz ]] && wget -q "$_INSTALLER_SOURCE/archboot-tz.sh?inline=false" -O /usr/bin/tz >/dev/null 2>&1
    [[ -e /usr/bin/archboot-${_RUNNING_ARCH}-create-container.sh ]] && wget -q "$_INSTALLER_SOURCE/archboot-${_RUNNING_ARCH}-create-container.sh?inline=false" -O "/usr/bin/archboot-${_RUNNING_ARCH}-create-container.sh" >/dev/null 2>&1
    [[ -e /usr/bin/archboot-${_RUNNING_ARCH}-release.sh ]] && wget -q "$_INSTALLER_SOURCE/archboot-${_RUNNING_ARCH}-release.sh?inline=false" -O "/usr/bin/archboot-${_RUNNING_ARCH}-release.sh" >/dev/null 2>&1
    [[ -e /usr/bin/update-installer.sh ]] && wget -q "$_INSTALLER_SOURCE/archboot-update-installer.sh?inline=false" -O /usr/bin/update-installer.sh >/dev/null 2>&1
    echo "Finished: Downloading scripts done."
    exit 0
fi

echo "Information: Logging is done on /dev/tty7 ..."

# Generate new environment and launch it with kexec
if [[ "${_L_COMPLETE}" == "1" || "${_L_INSTALL_COMPLETE}" == "1" ]]; then
    # remove everything not necessary
    echo "Step 1/6: Removing not necessary files from /usr ..."
    rm -r /lib/{firmware,modules} >/dev/tty7 2>&1
    rm -r /usr/share/{efitools,file,grub,hwdata,kbd,licenses,makepkg,nmap,openvpn,pacman,refind,tc,usb_modeswitch,vim,zoneinfo,zsh} >/dev/tty7 2>&1
    # create container without package cache
    if [[ "${_L_COMPLETE}" == "1" ]]; then
        echo "Step 2/6: Generating archboot container in ${_W_DIR} ..."
        echo "          This will need some time ..."
        "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc -cp >/dev/tty7 2>&1 || exit 1
    fi
    # create container with package cache
    if [[ "${_L_INSTALL_COMPLETE}" == "1" ]]; then 
        echo "Step 2/6: Generating archboot container in ${_W_DIR} ..."
        echo "          This will need some time ..."
        "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc >/dev/tty7 2>&1 || exit 1
    fi
    
    # generate initrd in container, remove archboot packages from cache, not needed in normal install, umount tmp before generating initrd
    echo "Step 3/6: Generating initramfs in ${_W_DIR} ..."
    echo "          This will need some time ..."
    # add fix for mkinitcpio 31, remove when 32 is released
    cp "${_W_DIR}"/usr/lib/initcpio/functions "${_W_DIR}"/usr/lib/initcpio/functions.old
    cp "${_W_DIR}"/usr/share/archboot/patches/31-initcpio.functions.fixed "${_W_DIR}"/usr/lib/initcpio/functions
    systemd-nspawn -D "${_W_DIR}" /bin/bash -c "rm /var/cache/pacman/pkg/archboot-*; umount /tmp;mkinitcpio -c ${_CONFIG} -g /tmp/initrd.img; mv /tmp/initrd.img /" >/dev/tty7 2>&1 || exit 1
    mv "${_W_DIR}"/usr/lib/initcpio/functions.old "${_W_DIR}"/usr/lib/initcpio/functions
    echo "Step 4/6: Moving initramfs files from ${_W_DIR} to / ..."
    mv "${_W_DIR}"/initrd.img / || exit 1
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then 
        mv "${_W_DIR}"/boot/vmlinuz-linux / || exit 1
        mv "${_W_DIR}"/boot/intel-ucode.img / || exit 1
    fi
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        mv "${_W_DIR}"/boot/Image / || exit 1
    fi
    mv "${_W_DIR}"/boot/amd-ucode.img / || exit 1
    # remove "${_W_DIR}"
    echo "Step 5/6: Remove ${_W_DIR} ..."
    rm -r "${_W_DIR}" || exit 1
    echo "Step 6/6: Loading files to kexec now, reboot in a few seconds ..."
    # load kernel and initrds into running kernel
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then 
        kexec -l /vmlinuz-linux --initrd=/intel-ucode.img --initrd=/amd-ucode.img --initrd=/initrd.img --reuse-cmdline
    fi
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        kexec -l /Image --initrd=/amd-ucode.img --initrd=/initrd.img --reuse-cmdline
    fi
    echo "Finished: Rebooting ..."
    # restart environment
    systemctl kexec
fi

# Generate new images
if [[ "${_G_RELEASE}" == "1" ]]; then
    echo "Step 1/1: Generating new iso files now in ${_W_DIR} ..."
    echo "          This will need some time ..."
    "archboot-${_RUNNING_ARCH}-release.sh" "${_W_DIR}" >/dev/tty7 2>&1 || exit 1
    echo "Finished: New isofiles are located in ${_W_DIR}"
fi
