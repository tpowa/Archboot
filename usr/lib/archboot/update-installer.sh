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

_latest_install() {
    echo -e " \033[1m-latest-install\033[0m  Launch latest archboot environment with downloaded"
    echo -e "                  package cache (using kexec)."
    echo ""
}

_graphic_options() {
    echo -e " \033[1m-gnome\033[0m           Launch Gnome desktop with VNC sharing enabled."
    echo -e " \033[1m-gnome-wayland\033[0m   Launch Gnome desktop with Wayland backend."
    echo -e " \033[1m-plasma\033[0m          Launch KDE Plasma desktop with VNC sharing enabled."
    echo -e " \033[1m-plasma-wayland\033[0m  Launch KDE Plasma desktop with Wayland backend."
}

usage () {
    echo -e "\033[1mUpdate installer, launch environments or create latest image files:\033[0m"
    echo -e "\033[1m-------------------------------------------------------------------\033[0m"
    echo -e "\033[1mPARAMETERS:\033[0m"
    echo -e " \033[1m-h\033[0m               This message."
    echo -e ""
    echo -e " \033[1m-u\033[0m               Update scripts: setup, quickinst, tz, km and helpers."
    echo -e ""
    if [[ -e /usr/bin/setup ]]; then
        # local image
        if [[ -e "/var/cache/pacman/pkg/archboot.db" ]]; then
            if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3860000 ]] ; then
                if ! [[ -e "/.graphic_run" && "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4413000 ]]; then
                    _graphic_options
                    echo -e " \033[1m-xfce\033[0m            Launch XFCE desktop with VNC sharing enabled."
                    echo ""
                fi
            fi
        else
            # latest image
            if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3400000 ]] ; then
                _graphic_options
            fi
            if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2500000 ]]; then
                echo -e " \033[1m-xfce\033[0m            Launch XFCE desktop with VNC sharing enabled."
                echo -e " \033[1m-custom-xorg\033[0m     Install custom X environment."
               [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3400000 ]] && echo -e " \033[1m-custom-wayland\033[0m  Install custom Wayland environment."
                echo ""
            fi
        fi
    fi
    if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 4616000 &&\
    -e /usr/bin/archboot-"${_RUNNING_ARCH}"-release.sh ]]; then
        echo -e " \033[1m-latest-image\033[0m    Generate latest image files in /archboot directory"
        echo ""
    fi
    # local image
    if [[ -e "/var/cache/pacman/pkg/archboot.db" ]]; then
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3277000 ]]; then
            _latest_install
        fi
    else
    # latest image
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 1970000 ]]; then
            echo -e " \033[1m-latest\033[0m          Launch latest archboot environment (using kexec)."
            echo ""
        fi
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2571000 ]]; then
            _latest_install
        fi
    fi
    exit 0
}

_archboot_check() {
    if ! grep -qw "archboot" /etc/hostname; then
        echo "This script should only be run in booted archboot environment. Aborting..."
        exit 1
    fi
}

_clean_kernel_cache () {
    echo 3 > /proc/sys/vm/drop_caches
}

_download_latest() {
    # Download latest setup and quickinst script from git repository
    if [[ "${_D_SCRIPTS}" == "1" ]]; then
        echo -e "\033[1mStart:\033[0m Downloading latest km, tz, quickinst, setup and helpers..."
        [[ -d "${_INST}" ]] || mkdir "${_INST}"
        wget -q "${_SOURCE}${_ETC}/defaults?inline=false" -O "${_ETC}/defaults"
        BINS=" ${_RUNNING_ARCH}-create-container.sh ${_RUNNING_ARCH}-release.sh \
        binary-check.sh secureboot-keys.sh mkkeys.sh"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/${i}"
            [[ -e "${_BIN}/archboot-${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/archboot-${i}"
        done
        BINS="quickinst setup km tz update-installer copy-mountpoint rsync-backup restore-usbstick"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}.sh?inline=false" -O "${_BIN}/${i}"
        done
        LIBS="common.sh container.sh release.sh iso.sh update-installer.sh xfce.sh gnome.sh gnome-wayland.sh plasma.sh plasma-wayland.sh login.sh"
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
        echo "update-installer is already running on other tty ..."
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
    _SHARE_DIRS="efitools file grub hwdata kbd licenses lshw nmap nano openvpn pacman refind systemd tc usb_modeswitch vim zoneinfo"
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
    [[ -e /etc/systemd/system/pacman-init.service ]] && systemctl stop pacman-init.service
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
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc --install-source=file:///var/cache/pacman/pkg >/dev/tty7 2>&1 || exit 1
        fi
        # needed for checks
        cp "${_W_DIR}"/var/cache/pacman/pkg/archboot.db /var/cache/pacman/pkg/archboot.db
    else
        #online mode
        if [[ "${_L_INSTALL_COMPLETE}" == "1" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc >/dev/tty7 2>&1 || exit 1
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
    #from /usr/bin/mkinitcpio.conf
    # compress image with zstd
    cd  "${_W_DIR}"/tmp || exit 1
    find . -mindepth 1 -printf '%P\0' | sort -z |
    bsdtar --uid 0 --gid 0 --null -cnf - -T - |
    bsdtar --null -cf - --format=newc @- | zstd --rm -T0> /initrd.img &
    sleep 2
    while pgrep -x zstd > /dev/null 2>&1; do
        _clean_kernel_cache
        sleep 1
    done
}

_kexec() {
    # you need approx. 3.39x size for KEXEC_FILE_LOAD
    if [[ "$(($(stat -c %s /initrd.img)*339/100000))" -lt "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" ]]; then
        echo -e "Running \033[1m\033[92mkexec\033[0m with \033[1mnew\033[0m KEXEC_FILE_LOAD ..."
        kexec -s -f /"${VMLINUZ}" --initrd="/initrd.img" --reuse-cmdline &
    else
        echo -e "Running \033[1m\033[92mkexec\033[0m with \033[1mold\033[0m KEXEC_LOAD ..."
        kexec -c -f --mem-max=0xA0000000 /"${VMLINUZ}" --initrd="/initrd.img" --reuse-cmdline &
    fi
    sleep 2
    _clean_kernel_cache
    rm /{${VMLINUZ},initrd.img}
    while pgrep -x kexec > /dev/null 2>&1; do
        _clean_kernel_cache
        sleep 1
    done
    #shellcheck disable=SC2115
    rm -rf /usr/*
}

_cleanup_install() {
    rm -rf /usr/share/{man,help,gir-[0-9]*,info,doc,gtk-doc,ibus,perl[0-9]*}
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

_prepare_graphic() {
    echo "Removing firmware files ..."
    rm -rf /usr/lib/firmware
    # fix libs first, then install packages from defaults
    _GRAPHIC="${_FIX_PACKAGES} ${1}"
    # saving RAM by calling always cleanup hook and installing each package alone
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        echo "Running pacman to install packages: ${_GRAPHIC} ..."
        _INSTALL_SOURCE="file:///var/cache/pacman/pkg"
        #shellcheck disable=SC2119
        _create_pacman_conf
        #shellcheck disable=SC2086
        pacman -Sy --config ${_PACMAN_CONF} >/dev/null 2>&1 || exit 1
        for i in ${_GRAPHIC}; do
            #shellcheck disable=SC2086
            pacman -S ${i} --config ${_PACMAN_CONF} --noconfirm >/dev/null 2>&1 || exit 1
            _cleanup_install
            [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4413000 ]] && _cleanup_cache
            rm -f /var/log/pacman.log
        done
    else
        echo "Updating environment to latest packages (ignoring packages: ${_GRAPHIC_IGNORE}) ..."
        _IGNORE=""
        if [[ -n "${_GRAPHIC_IGNORE}" ]]; then
            for i in ${_GRAPHIC_IGNORE}; do
                _IGNORE="${_IGNORE} --ignore ${i}"
            done
        fi
        #shellcheck disable=SC2086
        pacman -Syu ${_IGNORE} --noconfirm >/dev/null 2>&1 || exit 1
        _cleanup_install
        echo "Running pacman to install packages: ${_GRAPHIC} ..."
        for i in ${_GRAPHIC}; do
            #shellcheck disable=SC2086
            pacman -S ${i} --noconfirm >/dev/null 2>&1 || exit 1
            _cleanup_install
            [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4413000 ]] && _cleanup_cache
            rm -f /var/log/pacman.log
        done
    fi
    echo "Removing not used icons ..."
    rm -rf /usr/share/icons/breeze-dark
    echo "Cleanup locale and i18n ..."
    rm -rf /usr/share/{locale,i18n}
    # needed for environments which check disk space
    if ! mountpoint /root; then
        echo "Mount tmpfs on /root"
        mount -t tmpfs tmpfs /root
    fi
}

_chromium_flags() {
    echo "Adding chromium flags to /etc/chromium-flags.conf ..."
    cat << EOF >/etc/chromium-flags.conf
--no-sandbox
--test-type
--incognito
bit.ly/archboot
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
