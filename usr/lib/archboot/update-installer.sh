#!/bin/bash
# created by Tobias Powalowski <tpowa@archlinux.org>
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
_ZRAM_SIZE=${_ZRAM_SIZE:-"3G"}
[[ "${_RUNNING_ARCH}" == "x86_64" ]] && VMLINUZ="vmlinuz-linux"
[[ "${_RUNNING_ARCH}" == "aarch64" ]] && VMLINUZ="Image"

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

_archboot_check() {
    if [[ ! "$(cat /etc/hostname)" == "archboot" ]]; then
        echo "This script should only be run in booted archboot environment. Aborting..."
        exit 1
    fi
}

_download_latest() {
    # Download latest setup and quickinst script from git repository
    if [[ "${_D_SCRIPTS}" == "1" ]]; then
        echo -e "\033[1mStart:\033[0m Downloading latest km, tz, quickinst, setup and helpers..."
        [[ -d "${_INST}" ]] || mkdir "${_INST}"
        wget -q "${_SOURCE}${_ETC}/defaults?inline=false" -O "${_ETC}/defaults"
        BINS="quickinst setup km tz copy-mountpoint.sh rsync-backup.sh restore-usbstick.sh \
        ${_RUNNING_ARCH}-create-container.sh ${_RUNNING_ARCH}-release.sh \
        binary-check.sh update-installer.sh secureboot-keys.sh mkkeys.sh"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/${i}"
            [[ -e "${_BIN}/archboot-${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/archboot-${i}"
        done
        LIBS="common.sh container.sh release.sh iso.sh update-installer.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_LIB}/${i}?inline=false" -O "${_LIB}/${i}"
        done
        SETUPS="autoconfiguration.sh autoprepare.sh base.sh blockdevices.sh bootloader.sh btrfs.sh common.sh \
                configuration.sh mountpoints.sh network.sh pacman.sh partition.sh storage.sh"
        for i in ${SETUPS}; do
            wget -q "${_SOURCE}${_INST}/${i}?inline=false" -O "${_INST}/${i}"
        done
        echo -e "\033[1mFinished:\033[0m Downloading scripts done."
        exit 0
    fi
}

_update_installer_check() {
    if [[ -f /.update-installer ]]; then
        echo -e "\033[91mAborting:\033[0m"
        echo "update-installer.sh is already running on other tty ..."
        echo "If you are absolutly sure it's not running, you need to remove /.update-installer"
        exit 1
    fi
}

_umount_w_dir() {
    if mountpoint -q "${_W_DIR}"; then
        echo "Unmounting ${_W_DIR} ..." > /dev/tty7
        # umount all possible mountpoints
        umount -R "${_W_DIR}"
        echo 1 > /sys/block/zram0/reset
        # wait 5 seconds to get RAM cleared and set free
        sleep 5
    fi
}

_zram_mount() {
    # add defaults
    _ZRAM_ALGORITHM=${_ZRAM_ALGORITHM:-"zstd"}
    modprobe zram 2>/dev/null
    echo "${_ZRAM_ALGORITHM}" >/sys/block/zram0/comp_algorithm
    echo "${1}" >/sys/block/zram0/disksize
    echo "Creating btrfs filesystem with ${_DISKSIZE} on /dev/zram0 ..." > /dev/tty7
    mkfs.btrfs -q --mixed /dev/zram0 > /dev/tty7 2>&1
    [[ -d "${_W_DIR}" ]] || mkdir "${_W_DIR}"
    # use -o discard for RAM cleaning on delete
    # (online fstrimming the block device!)
    # fstrim <mountpoint> for manual action
    # it needs some seconds to get RAM free on delete!
    mount -o discard /dev/zram0 "${_W_DIR}"
}

_clean_archboot() {
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

_gpg_check() {
    # pacman-key process itself
    while pgrep -x pacman-key > /dev/null 2>&1; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg > /dev/null 2>&1; do
        sleep 1
    done
    while true; do
    # gpg-agent finished in background
        [[ "$(pgrep -x gpg-agent -c)" == "2" ]] && break
        sleep 1
    done
    [[ "${_RUNNING_ARCH}" == "x86_64" ]] && systemctl stop pacman-init.service
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && systemctl stop pacman-init-arm.service
}

_create_container() {
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
}

_kver_x86() {
    # get kernel version from installed kernel
    if [[ -f "/${VMLINUZ}" ]]; then
        offset=$(hexdump -s 526 -n 2 -e '"%0d"' "/${VMLINUZ}")
        read -r _HWKVER _ < <(dd if="/${VMLINUZ}" bs=1 count=127 skip=$(( offset + 0x200 )) 2>/dev/null)
    fi
    # fallback if no detectable kernel is installed
    [[ -z "${_HWKVER}" ]] && _HWKVER="$(uname -r)"
}

_kver_generic() {
    # get kernel version from installed kernel
    read _ _ _HWKVER _ < <(grep -m1 -aoE 'Linux version .(\.[-[:alnum:]]+)+' "/${VMLINUZ}")

    # try if the image is gzip compressed
    if [[ -z "${_HWKVER}" ]]; then
        read _ _ _HWKVER _ < <(gzip -c -d "/${VMLINUZ}" | grep -m1 -aoE 'Linux version .(\.[-[:alnum:]]+)+')
    fi

    # fallback if no detectable kernel is installed
    [[ -z "${_HWKVER}" ]] && _HWKVER="$(uname -r)"
}

_create_initramfs() {
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
    bsdtar --null -cf - --format=newc @- | zstd -T0 -10> /initrd.img &
    sleep 2
    for i in $(find . -mindepth 1 -type f | sort); do
        rm "${i}" >/dev/null 2>&1
        sleep 0.002
    done
    while pgrep -x bsdtar >/dev/null 2>&1; do
        sleep 1
    done
}

_kexec() {
    # load kernel and initrds into running kernel in background mode!
    kexec -l /"${VMLINUZ}" --initrd="/initrd.img" --reuse-cmdline&
    # wait 2 seconds for getting a complete initramfs
    # remove kernel and initrd to save RAM for kexec in background
    sleep 2
    rm /{initrd.img,${VMLINUZ}}
    while pgrep -x kexec >/dev/null 2>&1; do
        sleep 1
    done
    echo -e "\033[1mFinished:\033[0m Rebooting in a few seconds ..."
    # don't show active prompt wait for kexec to be launched
    while true; do
        if [[ -e "/sys/firmware/efi" ]]; then
            # UEFI kexec call
            systemctl kexec 2>/dev/null
        else
            # BIOS kexec call
            kexec -e 2>/dev/null
        fi
        sleep 1
    done
}
