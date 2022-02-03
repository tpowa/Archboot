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

kver() {
    # get kernel version from installed kernel
    [[ "$(uname -m)" == "x86_64" ]] && VMLINUZ="${_W_DIR}/boot/vmlinuz-linux"
    [[ "$(uname -m)" == "aarch64" ]] && VMLINUZ="${_W_DIR}/boot/Image"
    if [[ -f "${VMLINUZ}" ]]; then
        offset=$(hexdump -s 526 -n 2 -e '"%0d"' "${VMLINUZ}")
        read -r _HWKVER _ < <(dd if="${VMLINUZ}" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)
    fi
    # fallback if no detectable kernel is installed
    [[ "${_HWKVER}" == "" ]] && _HWKVER="$(uname -r)"
}

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
    [[ -e /usr/bin/archboot-binary-check.sh ]] && wget -q "$_INSTALLER_SOURCE/archboot-binary-check.sh?inline=false" -O /usr/bin/archboot-binary-check.sh >/dev/null 2>&1
    [[ -e /usr/bin/update-installer.sh ]] && wget -q "$_INSTALLER_SOURCE/archboot-update-installer.sh?inline=false" -O /usr/bin/update-installer.sh >/dev/null 2>&1
    
    echo "Finished: Downloading scripts done."
    exit 0
fi

echo "Information: Logging is done on /dev/tty7 ..."

# Generate new environment and launch it with kexec
if [[ "${_L_COMPLETE}" == "1" || "${_L_INSTALL_COMPLETE}" == "1" ]]; then
    # remove everything not necessary
    echo "Step 1/8: Removing not necessary files from / ..."
    [[ -d "/usr/lib/firmware" ]] && rm -r "/usr/lib/firmware"
    [[ -d "/usr/lib/modules" ]] && rm -r "/usr/lib/modules"
    _SHARE_DIRS="efitools file grub hwdata kbd licenses makepkg nmap openvpn pacman refind tc usb_modeswitch vim zoneinfo zsh"
    for i in "${_SHARE_DIRS}"; do
        [[ -d "/usr/share/${i}" ]] && rm -r "/usr/share/${i}"
    done
    echo "Step 2/8: Generating archboot container in ${_W_DIR} ..."
    echo "          This will need some time ..."
    # create container without package cache
    [[ "${_L_COMPLETE}" == "1" ]] && ("archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc -cp >/dev/tty7 2>&1 || exit 1)
    # create container with package cache
    [[ "${_L_INSTALL_COMPLETE}" == "1" ]] && ("archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc >/dev/tty7 2>&1 || exit 1)
    # generate initrd in container, remove archboot packages from cache, not needed in normal install, umount tmp before generating initrd
    echo "Step 3/8: Moving kernel from ${_W_DIR} to / ..."
    mv "${_W_DIR}"/initrd.img / || exit 1
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then 
        mv "${_W_DIR}"/boot/vmlinuz-linux / || exit 1
        ### not supported
        #mv "${_W_DIR}"/boot/intel-ucode.img / || exit 1
    fi
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        mv "${_W_DIR}"/boot/Image / || exit 1
    fi
    echo "Step 4/8: Collect initramfs files in ${_W_DIR} ..."
    echo "          This will need some time ..."
    # add fix for mkinitcpio 31, remove when 32 is released
    cp "${_W_DIR}"/usr/lib/initcpio/functions "${_W_DIR}"/usr/lib/initcpio/functions.old
    cp "${_W_DIR}"/usr/share/archboot/patches/31-initcpio.functions.fixed "${_W_DIR}"/usr/lib/initcpio/functions
    kver
    # write initramfs to /tmp
    systemd-nspawn -D "${_W_DIR}" /bin/bash -c "umount /tmp; mkinitcpio -k "${_HWKVER}" -c ${_CONFIG} -d /tmp/" >/dev/tty7 2>&1 || exit 1
    # move initramgs to /
    mv "${_W_DIR}/tmp" /initrd || exit 1
    echo "Step 5/8: Remove ${_W_DIR} ..."
    rm -r "${_W_DIR}" || exit 1
    echo "Step 6/8: Create initramfs /initrd.img ..."
    find initrd/. -mindepth 1 -printf '%P\0' | sort -z | LANG=C bsdtar --uid 0 --gid 0 --null -cnf - -T - |\
    LANG=C bsdtar --null -cf - --format=newc @- | zstd -T0 > /initrd.img
    mv "${_W_DIR}"/usr/lib/initcpio/functions.old "${_W_DIR}"/usr/lib/initcpio/functions
    echo "Step 7/8: Remove /initrd ..."
    rm -r "/initrd" || exit 1
    ### not supported
    #mv "${_W_DIR}"/boot/amd-ucode.img / || exit 1
    # remove "${_W_DIR}"
    echo "Step 8/8: Loading files to kexec now, reboot in a few seconds ..."
    # load kernel and initrds into running kernel
    if [[ "${_RUNNING_ARCH}" == "x86_64" ]]; then 
        kexec -l /vmlinuz-linux --initrd=/initrd.img --reuse-cmdline
    fi
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        kexec -l /Image --initrd=/initrd.img --reuse-cmdline
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
