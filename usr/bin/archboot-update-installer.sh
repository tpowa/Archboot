#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /usr/lib/archboot/common.sh
_D_SCRIPTS=""
_L_COMPLETE=""
_L_INSTALL_COMPLETE=""
_G_RELEASE=""
_CONFIG="/etc/archboot/${_RUNNING_ARCH}-update_installer.conf"
_W_DIR="/archboot"
_INSTALLER_SOURCE="https://gitlab.archlinux.org/tpowa/archboot/-/raw/master"
_BIN_PATH="${_INSTALLER_SOURCE}/usr/bin"
_LIB_PATH="${_INSTALLER_SOURCE}/usr/lib/archboot"
_INST_PATH="${_INSTALLER_SOURCE}/${_LIB_PATH}/installer"

kver() {
    # get kernel version from installed kernel
    [[ "${_RUNNING_ARCH}" == "x86_64" ]] && VMLINUZ="vmlinuz-linux"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && VMLINUZ="Image"
    if [[ -f "${VMLINUZ}" ]]; then
        offset=$(hexdump -s 526 -n 2 -e '"%0d"' "${VMLINUZ}")
        read -r _HWKVER _ < <(dd if="/${VMLINUZ}" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)
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
    echo "                  This operation needs at least 2.3 GB RAM."
    echo ""
    echo " -latest-install  Launch latest archboot environment with downloaded"
    echo "                  package cache (using kexec)."
    echo "                  This operation needs at least 2.7 GB RAM."
    echo ""
    echo " -latest-image    Generate latest image files in /archboot-release directory"
    echo "                  This operation needs at least 4.6 GB RAM."
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
    wget -q "${_BIN_PATH}/archboot-quickinst.sh?inline=false" -O /usr/bin/quickinst >/dev/null 2>&1
    wget -q "${_BIN_PATH}/archboot-setup.sh?inline=false" -O /usr/bin/setup >/dev/null 2>&1
    wget -q "${_BIN_PATH}/archboot-km.sh?inline=false" -O /usr/bin/km >/dev/null 2>&1
    wget -q "${_BIN_PATH}/archboot-tz.sh?inline=false" -O /usr/bin/tz >/dev/null 2>&1
    wget -q "${_BIN_PATH}/archboot-${_RUNNING_ARCH}-create-container.sh?inline=false" -O "/usr/bin/archboot-${_RUNNING_ARCH}-create-container.sh" >/dev/null 2>&1
    wget -q "${_BIN_PATH}/archboot-${_RUNNING_ARCH}-release.sh?inline=false" -O "/usr/bin/archboot-${_RUNNING_ARCH}-release.sh" >/dev/null 2>&1
    wget -q "${_BIN_PATH}/archboot-binary-check.sh?inline=false" -O /usr/bin/archboot-binary-check.sh >/dev/null 2>&1
    wget -q "${_BIN_PATH}/archboot-update-installer.sh?inline=false" -O /usr/bin/update-installer.sh >/dev/null 2>&1
    wget -q "${_LIB_PATH}/common.sh?inline=false" -O "${_LIB_PATH}/common.sh" >/dev/null 2>&1
    wget -q "${_LIB_PATH}/container.sh?inline=false" -O "${_LIB_PATH}/container.sh" >/dev/null 2>&1
    wget -q "${_LIB_PATH}/release.sh?inline=false" -O "${_LIB_PATH}/release.sh" >/dev/null 2>&1
    wget -q "${_LIB_PATH}/iso.sh?inline=false" -O "${_LIB_PATH}/iso.sh" >/dev/null 2>&1
    wget -q "${_INST_PATH}/autoconfiguration.sh?inline=false" -O "${_INST_PATH}/autoconfiguration.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/autoprepare.sh?inline=false" -O "${_INST_PATH}/autoprepare.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/base.sh?inline=false" -O "${_INST_PATH}/base.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/blockdevices.sh?inline=false" -O "${_INST_PATH}/blockdevices.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/bootloader.sh?inline=false" -O "${_INST_PATH}/bootloader.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/btrfs.sh?inline=false" -O "${_INST_PATH}/btrfs.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/common.sh?inline=false" -O "${_INST_PATH}/common.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/configuration.sh?inline=false" -O "${_INST_PATH}/configuration.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/mountpoints.sh?inline=false" -O "${_INST_PATH}/mountpoints.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/network.sh?inline=false" -O "${_INST_PATH}/network.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/pacman.sh?inline=false" -O "${_INST_PATH}/pacman.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/partition.sh?inline=false" -O "${_INST_PATH}/partition.sh" > /dev/null 2>&1
    wget -q "${_INST_PATH}/storage.sh?inline=false" -O "${_INST_PATH}/storage.sh" > /dev/null 2>&1
    echo "Finished: Downloading scripts done."
    exit 0
fi

echo "Information: Logging is done on /dev/tty7 ..."

# Generate new environment and launch it with kexec
if [[ "${_L_COMPLETE}" == "1" || "${_L_INSTALL_COMPLETE}" == "1" ]]; then
    if [[ -f /.update-installer ]]; then
        echo "Aborting: update-installer.sh is already running on other tty ..."
        echo "If you are absolutly sure it's not running, you need to remove /.update-installer"
        exit 1
    fi
    touch /.update-installer
    # remove everything not necessary
    echo "Step 1/9: Removing not necessary files from / ..."
    [[ -d "/usr/lib/firmware" ]] && rm -r "/usr/lib/firmware"
    [[ -d "/usr/lib/modules" ]] && rm -r "/usr/lib/modules"
    rm -f /usr/lib/{libicu*,libstdc++*}
    _SHARE_DIRS="archboot efitools file grub hwdata kbd licenses lshw makepkg nmap nano openvpn pacman refind systemd tc usb_modeswitch vim zoneinfo"
    for i in ${_SHARE_DIRS}; do
        #shellcheck disable=SC2115
        [[ -d "/usr/share/${i}" ]] && rm -r "/usr/share/${i}"
    done
    echo "Step 2/9: Waiting for gpg pacman keyring import to finish ..."
    while pgrep -x gpg > /dev/null 2>&1; do
        sleep 1
    done
    systemctl stop pacman-init.service
    echo "Step 3/9: Generating archboot container in ${_W_DIR} ..."
    echo "          This will need some time ..."
    # create container without package cache
    if [[ "${_L_COMPLETE}" == "1" ]]; then
        "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc -cp >/dev/tty7 2>&1 || exit 1
    fi
    # create container with package cache
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        # offline mode, for testing purposes
        # add the db too on reboot
        install -D -m644 /var/cache/pacman/pkg/archboot.db /archboot/var/cache/pacman/pkg/archboot.db
        if [[ "${_L_INSTALL_COMPLETE}" == "1" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc --install-source=file:///var/cache/pacman/pkg >/dev/tty7 2>&1 || exit 1
        fi
    else
        #online mode
        if [[ "${_L_INSTALL_COMPLETE}" == "1" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc >/dev/tty7 2>&1 || exit 1
            mv "${_W_DIR}"/var/cache/pacman/pkg /var/cache/pacman/
        fi
    fi
    echo "Step 4/9: Moving kernel ${VMLINUZ} to ${_W_DIR} ..."
    kver
    mv "${_W_DIR}"/boot/${VMLINUZ} "${_W_DIR}"/ || exit 1
    echo "Step 5/9: Collect initramfs files in ${_W_DIR} ..."
    echo "          This will need some time ..."
    # add fix for mkinitcpio 31, remove when 32 is released
    cp "${_W_DIR}"/usr/share/archboot/patches/31-mkinitcpio.fixed "${_W_DIR}"/usr/bin/mkinitcpio
    cp "${_W_DIR}"/usr/share/archboot/patches/31-initcpio.functions.fixed "${_W_DIR}"/usr/lib/initcpio/functions
    # write initramfs to "${_W_DIR}"/tmp
    systemd-nspawn -D "${_W_DIR}" /bin/bash -c "umount tmp;mkinitcpio -k ${_HWKVER} -c ${_CONFIG} -d /tmp" >/dev/tty7 2>&1 || exit 1
    #mv "${_W_DIR}/tmp" /initrd || exit 1
    echo "Step 6/9: Cleanup ${_W_DIR} ..."
    find "${_W_DIR}"/. -mindepth 1 -maxdepth 1 ! -name 'tmp' ! -name "${VMLINUZ}" -exec rm -rf {} \;
    echo "Step 7/9: Create initramfs initrd.img ..."
    echo "          This will need some time ..."
    # move cache back to initramfs directory in online mode
    if ! [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        [[ "${_L_INSTALL_COMPLETE}" == "1" ]] && mv /var/cache/pacman/pkg ${_W_DIR}/tmp/var/cache/pacman/
    fi
    #from /usr/bin/mkinitpcio.conf
    # compress image with zstd
    cd  "${_W_DIR}"/tmp || exit 1
    find . -mindepth 1 -printf '%P\0' | sort -z |
    LANG=C bsdtar --uid 0 --gid 0 --null -cnf - -T - |
    LANG=C bsdtar --null -cf - --format=newc @- | zstd -T0 -10> "${_W_DIR}"/initrd.img
    for i in $(find . -mindepth 1 -type f | sort); do
        rm "${i}" >/dev/null 2>&1
    done
    while pgreg -x bsdtar >/dev/null 2>&1; do
        sleep 1
    done
    echo "Step 8/9: Cleanup ${_W_DIR}/tmp ..."
    rm -r "${_W_DIR}"/tmp
    echo "Step 9/9: Loading files through kexec into kernel now ..."
    # load kernel and initrds into running kernel in background mode!
    kexec -f "${_W_DIR}"/${VMLINUZ} --initrd="${_W_DIR}"/initrd.img --reuse-cmdline&
    sleep 1
    # remove kernel and initrd to save RAM for kexec in background
    rm "${_W_DIR}"/{initrd.img,${VMLINUZ}}
    while pgreg -x kexec >/dev/null 2>&1; do
        sleep 1
    done
    echo "Finished: Rebooting in a few seconds ..."
    sleep 30
fi

# Generate new images
if [[ "${_G_RELEASE}" == "1" ]]; then
    echo "Step 1/1: Generating new iso files now in ${_W_DIR} ..."
    echo "          This will need some time ..."
    "archboot-${_RUNNING_ARCH}-release.sh" "${_W_DIR}" >/dev/tty7 2>&1 || exit 1
    echo "Finished: New isofiles are located in ${_W_DIR}"
fi
