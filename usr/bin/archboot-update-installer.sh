#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/common.sh
_D_SCRIPTS=""
_L_COMPLETE=""
_L_INSTALL_COMPLETE=""
_G_RELEASE=""
_CONFIG="/etc/archboot/${_RUNNING_ARCH}-update_installer.conf"
_W_DIR="/archboot"
_SOURCE="https://gitlab.archlinux.org/tpowa/archboot/-/raw/master"
_BIN="/usr/bin"
_ETC="/etc/archboot"
_LIB="/usr/lib/archboot"
_INST="/${_LIB}/installer"

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

zram_mount() {
    # add defaults
    _ZRAM_ALGORITHM=${_ZRAM_ALGORITHM:-"zstd"}
    # disable kernel messages on aarch64
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && echo 0 >/proc/sys/kernel/printk
    modprobe zram
    echo "${_ZRAM_ALGORITHM}" >/sys/block/zram0/comp_algorithm
    echo "${1}" >/sys/block/zram0/disksize
    echo "Creating btrfs filesystem with ${_DISKSIZE} on /dev/zram0 ..." > /dev/tty7
    mkfs.btrfs -q --mixed /dev/zram0 > /dev/tty7 2>&1
    mkdir "${_W_DIR}"
    # use -o discard for RAM cleaning on delete
    # (online fstrimming the block device!)
    # fstrim <mountpoint> for manual action
    # it needs some seconds to get RAM free on delete!
    mount -o discard /dev/zram0 "${_W_DIR}"
}

clean_archboot() {
    # remove everything not necessary
    rm -rf "/usr/lib/firmware"
    rm -rf "/usr/lib/modules"
    rm -rf /usr/lib/{libicu*,libstdc++*}
    _SHARE_DIRS="archboot efitools file grub hwdata kbd licenses lshw nmap nano openvpn pacman refind systemd tc usb_modeswitch vim zoneinfo"
    for i in ${_SHARE_DIRS}; do
        #shellcheck disable=SC2115
        rm -rf "/usr/share/${i}"
    done
}

usage () {
    echo -e "\033[1mUpdate installer, launch latest environment or create latest image files:\033[0m"
    echo -e "\033[1m-------------------------------------------------------------------------\033[0m"
    echo -e "\033[1mPARAMETERS:\033[0m"
    echo -e " \033[1m-u\033[0m               Update scripts: setup, quickinst, tz, km and helpers."
    echo -e ""
    echo -e " \033[1m-latest\033[0m          Launch latest archboot environment (using kexec)."
    echo -e "                  This operation needs at least \033[1m1.9 GB RAM\033[0m."
    echo ""
    echo -e " \033[1m-latest-install\033[0m  Launch latest archboot environment with downloaded"
    echo -e "                  package cache (using kexec)."
    echo -e "                  This operation needs at least \033[1m2.6 GB RAM\033[0m."
    echo ""
    echo -e " \033[1m-latest-image\033[0m    Generate latest image files in /archboot directory"
    echo -e "                  This operation needs at least \033[1m3.5 GB RAM\033[0m."
    echo ""
    echo -e " \033[1m-h\033[0m               This message."
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
    echo -e "\033[1mStart:\033[0m Downloading latest km, tz, quickinst, setup and helpers..."
    wget -q "${_SOURCE}${_ETC}/defaults?inline=false" -O "${_ETC}/defaults"
    wget -q "${_SOURCE}${_BIN}/archboot-quickinst.sh?inline=false" -O "${_BIN}/quickinst"
    wget -q "${_SOURCE}${_BIN}/archboot-setup.sh?inline=false" -O "${_BIN}/setup"
    wget -q "${_SOURCE}${_BIN}/archboot-km.sh?inline=false" -O "${_BIN}/km"
    wget -q "${_SOURCE}${_BIN}/archboot-tz.sh?inline=false" -O "${_BIN}/tz"
    wget -q "${_SOURCE}${_BIN}/archboot-copy-mountpoint.sh?inline=false" -O "${_BIN}/copy-mountpoint.sh"
    wget -q "${_SOURCE}${_BIN}/archboot-rsync-backup.sh?inline=false" -O "${_BIN}/rsync-backup.sh"
    wget -q "${_SOURCE}${_BIN}/archboot-restore-usbstick.sh?inline=false" -O "${_BIN}/restore-usbstick.sh"
    wget -q "${_SOURCE}${_BIN}/archboot-${_RUNNING_ARCH}-create-container.sh?inline=false" -O "${_BIN}/archboot-${_RUNNING_ARCH}-create-container.sh"
    wget -q "${_SOURCE}${_BIN}/archboot-${_RUNNING_ARCH}-release.sh?inline=false" -O "${_BIN}/archboot-${_RUNNING_ARCH}-release.sh"
    wget -q "${_SOURCE}${_BIN}/archboot-binary-check.sh?inline=false" -O "${_BIN}/archboot-binary-check.sh"
    wget -q "${_SOURCE}${_BIN}/archboot-update-installer.sh?inline=false" -O "${_BIN}/update-installer.sh"
    wget -q "${_SOURCE}${_BIN}/archboot-secureboot-keys.sh?inline=false" -O "${_BIN}/secureboot-keys.sh"
    wget -q "${_SOURCE}${_BIN}/archboot-mkkeys.sh?inline=false" -O "${_BIN}/mkkeys.sh"
    wget -q "${_SOURCE}${_LIB}/common.sh?inline=false" -O "${_LIB}/common.sh"
    wget -q "${_SOURCE}${_LIB}/container.sh?inline=false" -O "${_LIB}/container.sh"
    wget -q "${_SOURCE}${_LIB}/release.sh?inline=false" -O "${_LIB}/release.sh"
    wget -q "${_SOURCE}${_LIB}/iso.sh?inline=false" -O "${_LIB}/iso.sh"
    wget -q "${_SOURCE}${_INST}/autoconfiguration.sh?inline=false" -O "${_INST}/autoconfiguration.sh"
    wget -q "${_SOURCE}${_INST}/autoprepare.sh?inline=false" -O "${_INST}/autoprepare.sh"
    wget -q "${_SOURCE}${_INST}/base.sh?inline=false" -O "${_INST}/base.sh"
    wget -q "${_SOURCE}${_INST}/blockdevices.sh?inline=false" -O "${_INST}/blockdevices.sh"
    wget -q "${_SOURCE}${_INST}/bootloader.sh?inline=false" -O "${_INST}/bootloader.sh"
    wget -q "${_SOURCE}${_INST}/btrfs.sh?inline=false" -O "${_INST}/btrfs.sh"
    wget -q "${_SOURCE}${_INST}/common.sh?inline=false" -O "${_INST}/common.sh"
    wget -q "${_SOURCE}${_INST}/configuration.sh?inline=false" -O "${_INST}/configuration.sh"
    wget -q "${_SOURCE}${_INST}/mountpoints.sh?inline=false" -O "${_INST}/mountpoints.sh"
    wget -q "${_SOURCE}${_INST}/network.sh?inline=false" -O "${_INST}/network.sh"
    wget -q "${_SOURCE}${_INST}/pacman.sh?inline=false" -O "${_INST}/pacman.sh"
    wget -q "${_SOURCE}${_INST}/partition.sh?inline=false" -O "${_INST}/partition.sh"
    wget -q "${_SOURCE}${_INST}/storage.sh?inline=false" -O "${_INST}/storage.sh"
    echo -e "\033[1mFinished:\033[0m Downloading scripts done."
    exit 0
fi

echo -e "\033[1mInformation:\033[0m Logging is done on \033[1m/dev/tty7\033[0m ..."

# Generate new environment and launch it with kexec
if [[ "${_L_COMPLETE}" == "1" || "${_L_INSTALL_COMPLETE}" == "1" ]]; then
    if [[ -f /.update-installer ]]; then
        echo -e "\033[91mAborting:\033[0m"
        echo "update-installer.sh is already running on other tty ..."
        echo "If you are absolutly sure it's not running, you need to remove /.update-installer"
        exit 1
    fi
    touch /.update-installer
    _ZRAM_SIZE=${_ZRAM_SIZE:-"3G"}
    zram_mount "${_ZRAM_SIZE}"
    echo -e "\033[1mStep 1/9:\033[0m Removing not necessary files from / ..."
    clean_archboot
    echo -e "\033[1mStep 2/9:\033[0m Waiting for gpg pacman keyring import to finish ..."
    while pgrep -x gpg > /dev/null 2>&1; do
        sleep 1
    done
    [[ "${_RUNNING_ARCH}" == "x86_64" ]] && systemctl stop pacman-init.service
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && systemctl stop pacman-init-arm.service
    echo -e "\033[1mStep 3/9:\033[0m Generating archboot container in ${_W_DIR} ..."
    echo "          This will need some time ..."
    # create container without package cache
    if [[ "${_L_COMPLETE}" == "1" ]]; then
        "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc -cp >/dev/tty7 2>&1 || exit 1
    fi
    # create container with package cache
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        # offline mode, for local image
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
    kver
    echo -e "\033[1mStep 4/9:\033[0m Moving kernel ${VMLINUZ} to /${VMLINUZ} ..."
    mv "${_W_DIR}"/boot/${VMLINUZ} / || exit 1
    echo -e "\033[1mStep 5/9:\033[0m Collect initramfs files in ${_W_DIR} ..."
    echo "          This will need some time ..."
    # add fix for mkinitcpio 31, remove when 32 is released
    cp "${_W_DIR}"/usr/share/archboot/patches/31-mkinitcpio.fixed "${_W_DIR}"/usr/bin/mkinitcpio
    cp "${_W_DIR}"/usr/share/archboot/patches/31-initcpio.functions.fixed "${_W_DIR}"/usr/lib/initcpio/functions
    # write initramfs to "${_W_DIR}"/tmp
    systemd-nspawn -D "${_W_DIR}" /bin/bash -c "umount tmp;mkinitcpio -k ${_HWKVER} -c ${_CONFIG} -d /tmp" >/dev/tty7 2>&1 || exit 1
    #mv "${_W_DIR}/tmp" /initrd || exit 1
    echo -e "\033[1mStep 6/9:\033[0m Cleanup ${_W_DIR} ..."
    find "${_W_DIR}"/. -mindepth 1 -maxdepth 1 ! -name 'tmp' ! -name "${VMLINUZ}" -exec rm -rf {} \;
    # 10 seconds for getting free RAM
    sleep 10
    echo -e "\033[1mStep 7/9:\033[0m Create initramfs /initrd.img ..."
    echo "          This will need some time ..."
    # move cache back to initramfs directory in online mode
    if ! [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        if [[ "${_L_INSTALL_COMPLETE}" == "1" ]]; then
            if [[ -d /var/cache/pacman/pkg ]]; then
                mv /var/cache/pacman/pkg ${_W_DIR}/tmp/var/cache/pacman/
            fi
        fi
    fi
    #from /usr/bin/mkinitpcio.conf
    # compress image with zstd
    cd  "${_W_DIR}"/tmp || exit 1
    find . -mindepth 1 -printf '%P\0' | sort -z |
    bsdtar --uid 0 --gid 0 --null -cnf - -T - |
    bsdtar --null -cf - --format=newc @- | zstd -T0 -10> /initrd.img
    for i in $(find . -mindepth 1 -type f | sort); do
        rm "${i}" >/dev/null 2>&1
    done
    while pgreg -x bsdtar >/dev/null 2>&1; do
        sleep 1
    done
    echo -e "\033[1mStep 8/9:\033[0m Cleanup ${_W_DIR} ..."
    cd /
    umount ${_W_DIR}
    echo 1 > /sys/block/zram0/reset
    sleep 5
    echo -e "\033[1mStep 9/9:\033[0m Loading files through kexec into kernel now ..."
    # load kernel and initrds into running kernel in background mode!
    kexec -f /"${VMLINUZ}" --initrd="/initrd.img" --reuse-cmdline&
    # wait 1 seconds for getting a complete initramfs
    # remove kernel and initrd to save RAM for kexec in background
    sleep 2
    rm /{initrd.img,${VMLINUZ}}
    while pgreg -x kexec >/dev/null 2>&1; do
        sleep 1
    done
    echo -e "\033[1mFinished:\033[0m Rebooting in a few seconds ..."
    # don't show active prompt wait for kexec to be launched
    sleep 30
fi

# Generate new images
if [[ "${_G_RELEASE}" == "1" ]]; then
    _ZRAM_IMAGE_SIZE=${_ZRAM_IMAGE_SIZE:-"5G"}
    zram_mount "${_ZRAM_IMAGE_SIZE}"
    echo -e "\033[1mStep 1/2:\033[0m Removing not necessary files from / ..."
    clean_archboot
    echo -e "\033[1mStep 2/2:\033[0m Generating new iso files in ${_W_DIR} now ..."
    echo "          This will need some time ..."
    "archboot-${_RUNNING_ARCH}-release.sh" "${_W_DIR}" >/dev/tty7 2>&1 || exit 1
    echo -e "\033[1mFinished:\033[0m New isofiles are located in ${_W_DIR}"
fi
