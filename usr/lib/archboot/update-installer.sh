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
    echo -e "\033[1mUpdate installer, launch environments or create latest image files:\033[0m"
    echo -e "\033[1m-------------------------------------------------------------------\033[0m"
    echo -e "\033[1mPARAMETERS:\033[0m"
    echo -e " \033[1m-h\033[0m               This message."
    echo -e ""
    if [[ -e /usr/bin/dhcpcd ]]; then
        echo -e " \033[1m-u\033[0m               Update scripts: setup, quickinst, tz, km and helpers."
        echo -e ""
    fi
    if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3400000 &&\
    -e /usr/bin/setup && ! -e /var/cache/pacman/pkg/archboot.db ]]; then
            echo -e " \033[1m-launch-gnome\033[0m    Launch Gnome desktop with VNC sharing enabled."
            echo ""
            echo -e " \033[1m-launch-kde\033[0m      Launch KDE Plasma desktop with VNC sharing enabled."
            echo ""
    fi
    if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2500000 &&\
    -e /usr/bin/setup ]]; then
            echo -e " \033[1m-launch-xfce\033[0m     Launch XFCE desktop with VNC sharing enabled."
            echo ""
            echo -e " \033[1m-custom-xorg\033[0m     Install custom X environment."
            echo ""
    fi
    if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3900000 &&\
    -e /usr/bin/archboot-"${_RUNNING_ARCH}"-release.sh ]]; then
        echo -e " \033[1m-latest-image\033[0m    Generate latest image files in /archboot directory"
        echo ""
    fi
    if [[ $(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g') -lt 4400000 &&\
        $(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g') -gt 4015000 ]]; then
        echo -e "\033[1m\033[91mMemory check failed:\033[0m"
        echo -e "\033[91m   - Memory gap detected: \033[1m4.0G - 4.4G RAM\033[0m"
        echo -e "\033[91m   - Possibility of not working \033[1mkexec\033[0m\033[91m boot is given.\033[0m"
        echo -e "\033[93m   - Please add \033[1mmore\033[0m\033[93m or \033[1mless\033[0m\033[93m RAM to enable the missing \033[1mupdate\033[0m\033[93m options.\033[0m"
        echo ""
    else
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2000000 &&\
        -e /usr/bin/dhcpcd ]]; then
            echo -e " \033[1m-latest\033[0m          Launch latest archboot environment (using kexec)."
            echo ""
        fi
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3200000 ]]; then
            echo -e " \033[1m-latest-install\033[0m  Launch latest archboot environment with downloaded"
            echo -e "                  package cache (using kexec)."
            echo ""
        fi
    fi
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
        BINS="copy-mountpoint.sh rsync-backup.sh restore-usbstick.sh \
        ${_RUNNING_ARCH}-create-container.sh ${_RUNNING_ARCH}-release.sh \
        binary-check.sh update-installer.sh secureboot-keys.sh mkkeys.sh"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/${i}"
            [[ -e "${_BIN}/archboot-${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/archboot-${i}"
        done
        BINS="quickinst setup km tz"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}.sh?inline=false" -O "${_BIN}/${i}"
        done
        LIBS="common.sh container.sh release.sh iso.sh update-installer.sh xfce.sh gnome.sh kde.sh login.sh"
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

_zram_initialize() {
    # add defaults
    _ZRAM_ALGORITHM=${_ZRAM_ALGORITHM:-"zstd"}
    if ! grep -qw zram /proc/modules; then
        modprobe zram num_devices=2> /dev/tty7 2>&1
        echo "${_ZRAM_ALGORITHM}" >/sys/block/zram0/comp_algorithm
        echo "${_ZRAM_ALGORITHM}" >/sys/block/zram1/comp_algorithm
    fi
}

# use -o discard for RAM cleaning on delete
# (online fstrimming the block device!)
# fstrim <mountpoint> for manual action
# it needs some seconds to get RAM free on delete!
_zram_usr() {
    if ! mountpoint -q /usr; then
        echo "${1}" >/sys/block/zram0/disksize
        echo "Creating btrfs filesystem with ${1} on /dev/zram0 ..." > /dev/tty7
        mkfs.btrfs -q --mixed /dev/zram0 > /dev/tty7 2>&1
        mkdir /usr.zram
        mount -o discard /dev/zram0 "/usr.zram" > /dev/tty7 2>&1
        echo "Moving /usr to /usr.zram ..." > /dev/tty7
        cp -r /usr/* /usr.zram/
        ln -sfn /usr.zram/lib /lib
        ln -sfn /usr.zram/lib /lib64
        echo /usr.zram/lib > /etc/ld.so.conf
        ldconfig
        ln -sfn /usr.zram/bin /bin
        ln -sfn /usr.zram/bin /sbin
        #shellcheck disable=SC2115
        rm -r /usr/*
        /usr.zram/bin/./mount --bind /usr.zram /usr
        systemctl daemon-reload > /dev/tty7 2>&1
        systemctl restart dbus > /dev/tty7 2>&1
    fi
}

_zram_w_dir() {
    echo "${1}" >/sys/block/zram1/disksize
    echo "Creating btrfs filesystem with ${1} on /dev/zram1 ..." > /dev/tty7
    mkfs.btrfs -q --mixed /dev/zram1 > /dev/tty7 2>&1
    [[ -d "${_W_DIR}" ]] || mkdir "${_W_DIR}"
    mount -o discard /dev/zram1 "${_W_DIR}" > /dev/tty7 2>&1
}

_umount_w_dir() {
    if mountpoint -q "${_W_DIR}"; then
        echo "Unmounting ${_W_DIR} ..." > /dev/tty7
        # umount all possible mountpoints
        umount -R "${_W_DIR}"
        echo 1 > /sys/block/zram1/reset
        # wait 5 seconds to get RAM cleared and set free
        sleep 5
    fi
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
    systemctl stop pacman-init.service
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
        install -D -m644 /var/cache/pacman/pkg/archboot.db "${_W_DIR}"/var/cache/pacman/pkg/archboot.db
        if [[ "${_L_INSTALL_COMPLETE}" == "1" ]]; then
            mv /var/cache/pacman/pkg/* ${_W_DIR}/var/cache/pacman/pkg/
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc --install-source=file:///${_W_DIR}/var/cache/pacman/pkg >/dev/tty7 2>&1 || exit 1
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
    read -r _ _ _HWKVER _ < <(grep -m1 -aoE 'Linux version .(\.[-[:alnum:]]+)+' "/${VMLINUZ}")

    # try if the image is gzip compressed
    if [[ -z "${_HWKVER}" ]]; then
        read -r _ _ _HWKVER _ < <(gzip -c -d "/${VMLINUZ}" | grep -m1 -aoE 'Linux version .(\.[-[:alnum:]]+)+')
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
    #from /usr/bin/mkinitcpio.conf
    # compress image with zstd
    cd  "${_W_DIR}"/tmp || exit 1
    find . -mindepth 1 -printf '%P\0' | sort -z |
    bsdtar --uid 0 --gid 0 --null -cnf - -T - |
    bsdtar --null -cf - --format=newc @- | zstd --rm -T0> /initrd.img
}

_kexec () {
    if [[ $(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g') -gt 4015000 ||\
    $(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g') -lt 3200000 ]]; then
        echo -e "Running \033[1m\033[92mkexec\033[0m with \033[1mnew\033[0m KEXEC_FILE_LOAD ..."
        # works on systems with >4GB, --latest-install needs around 4400MB RAM
        # that causes a gap which can break qemu kexec or parallels desktop
        if [[ $(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g') -lt 4400000 &&\
        $(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g') -gt 4015000 ]]; then
            echo -e "\033[1m\033[91mWarning:\033[0m"
            echo -e "\033[1m\033[91m- Memory gap detected (4.0G - 4.4G RAM)\033[0m"
            echo -e "\033[1m\033[93m- Possibility of not working kexec boot.\033[0m"
            echo -e "\033[1m\033[93m- Please use more or less RAM.\033[0m"
        fi
        kexec -s -f /"${VMLINUZ}" --initrd="/initrd.img" --reuse-cmdline &
    else
        echo -e "Running \033[1m\033[92mkexec\033[0m with \033[1mold\033[0m KEXEC_LOAD ..."
        # works on systems with <4GB
        kexec -c -f /"${VMLINUZ}" --initrd="/initrd.img" --reuse-cmdline &
        sleep 2
        rm /{${VMLINUZ},initrd.img}
    fi
    while pgrep -x kexec > /dev/null 2>&1; do
        sleep 1
    done
}

_cleanup_install() {
    rm -rf /usr/share/{man,info,doc,gtk-doc,ibus,perl5}
    rm -rf /usr/include
    rm -rf /usr/lib/libgo.*
}

_cleanup_cache() {
    # remove packages from cache
    #shellcheck disable=SC2013
    for i in $(grep -w 'installed' /var/log/pacman.log | cut -d ' ' -f 4); do
        rm -rf /var/cache/pacman/pkg/"${i}"-[0-9]*
    done
}

_prepare_x() {
    echo "Removing firmware files ..."
    rm -rf /usr/lib/firmware
    # fix libs first, then install packages from defaults
    _XORG="${_X_PACKAGES} ${1}"
    # saving RAM by calling always cleanup hook and installing each package alone
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        echo "Running pacman to install packages: ${_XORG} ..."
        _INSTALL_SOURCE="file:///var/cache/pacman/pkg"
        _create_pacman_conf
        #shellcheck disable=SC2086
        pacman -Sy --config ${_PACMAN_CONF} >/dev/null 2>&1 || exit 1
        for i in ${_XORG}; do
            #shellcheck disable=SC2086
            pacman -S ${i} --config ${_PACMAN_CONF} --noconfirm >/dev/null 2>&1 || exit 1
            _cleanup_install
            _cleanup_cache
            rm -f /var/log/pacman.log
        done
    else
        echo "Updating environment to latest packages (ignoring packages: ${_X_IGNORE}) ..."
        _IGNORE=""
        if [[ -n "${_X_IGNORE}" ]]; then
            for i in ${_X_IGNORE}; do
                _IGNORE="${_IGNORE} --ignore ${i}"
            done
        fi
        #shellcheck disable=SC2086
        pacman -Syu ${_IGNORE} --noconfirm >/dev/null 2>&1 || exit 1
        _cleanup_install
        echo "Running pacman to install packages: ${_XORG} ..."
        for i in ${_XORG}; do
            #shellcheck disable=SC2086
            pacman -S ${i} --noconfirm >/dev/null 2>&1 || exit 1
            _cleanup_install
            _cleanup_cache
            rm -f /var/log/pacman.log
        done
    fi
    echo "Removing not used icons ..."
    rm -rf /usr/share/icons/breeze-dark
    echo "Recreating C.UTF-8 locale ..."
    sed -i -e 's:#C.UTF-8 UTF-8:C.UTF-8 UTF-8:g' "/etc/locale.gen"
    locale-gen >/dev/null 2>&1
    echo "Cleanup locale and i18n ..."
    rm -rf /usr/share/{locale,i18n}
}

_chromium_flags() {
    echo "Adding chromium flags to /etc/chromium-flags.conf ..."
    cat << EOF >/etc/chromium-flags.conf
--no-sandbox
--test-type
--incognito
wiki.archlinux.org/title/Archboot
EOF
}

_autostart_vnc() {
    echo "Setting VNC password /etc/tigervnc/passwd to ${_VNC_PW} ..."
    echo "${_VNC_PW}" | vncpasswd -f > /etc/tigervnc/passwd
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/archboot.desktop
    echo "Autostarting tigervnc ..."
    cat << EOF > /etc/xdg/autostart/tigervnc.desktop
[Desktop Entry]
Type=Application
Name=Tigervnc
Exec=x0vncserver -rfbauth /etc/tigervnc/passwd
EOF
}
