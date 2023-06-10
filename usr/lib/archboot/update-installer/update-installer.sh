#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
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
_RAM="/sysroot"
_INITRD="initrd.img"
_INST="/${_LIB}/installer"
_HELP="/${_LIB}/installer/help"
_RUN="/${_LIB}/run"
_UPDATE="/${_LIB}/update-installer"
[[ "${_RUNNING_ARCH}" == "x86_64" || "${_RUNNING_ARCH}" == "riscv64" ]] && _VMLINUZ="vmlinuz-linux"
[[ "${_RUNNING_ARCH}" == "aarch64" ]] && _VMLINUZ="Image"

_graphic_options() {
    if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
        echo -e " \e[1m-gnome\e[m           Launch Gnome desktop with VNC sharing enabled."
        echo -e " \e[1m-gnome-wayland\e[m   Launch Gnome desktop with Wayland backend."
        echo -e " \e[1m-plasma\e[m          Launch KDE Plasma desktop with VNC sharing enabled."
        echo -e " \e[1m-plasma-wayland\e[m  Launch KDE Plasma desktop with Wayland backend."
    fi
}

usage () {
    echo -e "\e[1mManage \e[36mArchboot\e[m\e[1m - Arch Linux Environment:\e[m"
    echo -e "\e[1m-----------------------------------------\e[m"
    echo -e " \e[1m-help\e[m            This message."
    if [[ ! -e "/var/cache/pacman/pkg/archboot.db" || -e "/usr/bin/setup" ]]; then
        echo -e " \e[1m-update\e[m          Update scripts: setup, quickinst, tz, km and helpers."
    fi
    # latest image
    if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2500000 && ! -e "/.full_system" && ! -e "/var/cache/pacman/pkg/archboot.db" ]]; then
        echo -e " \e[1m-full-system\e[m     Switch to full Arch Linux system."
    # local image
    elif [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2571000 && ! -e "/.full_system" && -e "/var/cache/pacman/pkg/archboot.db" && -e "/usr/bin/setup" ]]; then
        echo -e " \e[1m-full-system\e[m     Switch to full Arch Linux system."
    fi
    echo -e ""
    if [[ -e "/usr/bin/setup" ]]; then
        # works only on latest image
        if ! [[ -e "/var/cache/pacman/pkg/archboot.db" ]]; then
            if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3400000 ]] ; then
                _graphic_options
            fi
            if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 2500000 ]]; then
                echo -e " \e[1m-xfce\e[m            Launch XFCE desktop with VNC sharing enabled."
                echo -e " \e[1m-custom-xorg\e[m     Install custom X environment."
               [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3400000 ]] && echo -e " \e[1m-custom-wayland\e[m  Install custom Wayland environment."
                echo ""
            fi
        fi
    fi
    if ! [[ -e "/var/cache/pacman/pkg/archboot.db" ]] || [[ -e "/var/cache/pacman/pkg/archboot.db" && ! -e "/usr/bin/setup" ]]; then
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 1970000 ]]; then
            if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
                echo -e " \e[1m-latest\e[m          Launch latest archboot environment (using kexec)."
            fi
        fi
        if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3271000 ]]; then
            if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
                echo -e " \e[1m-latest-install\e[m  Launch latest archboot environment with"
                echo -e "                  package cache (using kexec)."
            fi
        fi
    fi
    if [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt 3216000 ]]; then
        echo -e " \e[1m-latest-image\e[m    Generate latest image files in /archboot directory."
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
    if [[ -n "${_D_SCRIPTS}" ]]; then
        _network_check
        echo -e "\e[1mStart:\e[m Downloading latest km, tz, quickinst, setup and helpers..."
        [[ -d "${_INST}" ]] || mkdir "${_INST}"
        # config
        echo -e "\e[1mStep 1/4:\e[m Downloading latest config..."
        wget -q "${_SOURCE}${_ETC}/defaults?inline=false" -O "${_ETC}/defaults"
        # helper binaries
        echo -e "\e[1mStep 2/4:\e[m Downloading latest scripts..."
        # main binaries
        BINS="quickinst setup km tz update-installer copy-mountpoint rsync-backup restore-usbstick"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}.sh?inline=false" -O "${_BIN}/${i}"
        done
        BINS="binary-check.sh not-installed.sh secureboot-keys.sh mkkeys.sh hwsim.sh locale.sh cpio,sh"
        for i in ${BINS}; do
            [[ -e "${_BIN}/${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/${i}"
            [[ -e "${_BIN}/archboot-${i}" ]] && wget -q "${_SOURCE}${_BIN}/archboot-${i}?inline=false" -O "${_BIN}/archboot-${i}"
        done
        HELP="guid-partition.txt guid.txt luks.txt lvm2.txt mbr-partition.txt md.txt"
        for i in ${HELP}; do
            [[ -e "${_HELP}/${i}" ]] && wget -q "${_SOURCE}${_HELP}/${i}?inline=false" -O "${_HELP}/${i}"
        done
        # main libs
        echo -e "\e[1mStep 3/4:\e[m Downloading latest script libs..."
        LIBS="common.sh container.sh release.sh iso.sh login.sh cpio.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_LIB}/${i}?inline=false" -O "${_LIB}/${i}"
        done
        # update-installer libs
        LIBS="update-installer.sh xfce.sh gnome.sh gnome-wayland.sh plasma.sh plasma-wayland.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_UPDATE}/${i}?inline=false" -O "${_UPDATE}/${i}"
        done
        # run libs
        LIBS="container.sh release.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_RUN}/${i}?inline=false" -O "${_RUN}/${i}"
        done
        # setup libs
        echo -e "\e[1mStep 4/4:\e[m Downloading latest setup libs..."
        LIBS="autoconfiguration.sh autoprepare.sh base.sh blockdevices.sh bootloader.sh btrfs.sh common.sh \
                configuration.sh mountpoints.sh network.sh pacman.sh partition.sh storage.sh"
        for i in ${LIBS}; do
            wget -q "${_SOURCE}${_INST}/${i}?inline=false" -O "${_INST}/${i}"
        done
        echo -e "\e[1mFinished:\e[m Downloading scripts done."
        exit 0
    fi
}

_network_check() {
    if ! getent hosts www.google.com &>/dev/null; then
        echo -e "\e[91mAborting:\e[m"
        echo -e "Network not yet ready."
        echo -e "Please configure your network first."
        exit 1
    fi
}

_update_installer_check() {
    if [[ -f /.update-installer ]]; then
        echo -e "\e[91mAborting:\e[m"
        echo "update-installer is already running on other tty..."
        echo "If you are absolutly sure it's not running, you need to remove /.update-installer"
        exit 1
    fi
    if ! [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        _network_check
    fi
}

_kill_w_dir() {
    if [[ -d "${_W_DIR}" ]]; then
        rm -r "${_W_DIR}"
    fi
}

_clean_archboot() {
    # remove everything not necessary
    rm -rf /usr/lib/firmware
    rm -rf /usr/lib/modules
    rm -rf /usr/lib/libstdc++*
    _SHARE_DIRS="bash-completion efitools fonts hwdata kbd licenses lshw nano nvim pacman systemd tc zoneinfo"
    for i in ${_SHARE_DIRS}; do
        #shellcheck disable=SC2115
        rm -rf "/usr/share/${i}"
    done
}

_gpg_check() {
    # pacman-key process itself
    while pgrep -x pacman-key &>/dev/null; do
        sleep 1
    done
    # gpg finished in background
    while pgrep -x gpg &>/dev/null; do
        sleep 1
    done
    if [[ -e /etc/systemd/system/pacman-init.service ]]; then
        systemctl stop pacman-init.service
    fi
}

_create_container() {
    # create container without package cache
    if [[ -n "${_L_COMPLETE}" ]]; then
        "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc -cp >/dev/tty7 2>&1 || exit 1
    fi
    # create container with package cache
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        # offline mode, for local image
        # add the db too on reboot
        install -D -m644 /var/cache/pacman/pkg/archboot.db "${_W_DIR}"/var/cache/pacman/pkg/archboot.db
        if [[ -n "${_L_INSTALL_COMPLETE}" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc --install-source=file:///var/cache/pacman/pkg >/dev/tty7 2>&1 || exit 1
        fi
        # needed for checks
        cp "${_W_DIR}"/var/cache/pacman/pkg/archboot.db /var/cache/pacman/pkg/archboot.db
    else
        #online mode
        if [[ -n "${_L_INSTALL_COMPLETE}" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc >/dev/tty7 2>&1 || exit 1
        fi
    fi
}

_kver_x86() {
    # get kernel version from installed kernel
    if [[ -f "${_RAM}/${_VMLINUZ}" ]]; then
        offset="$(od -An -j0x20E -dN2 "${_RAM}/${_VMLINUZ}")"
        read -r _HWKVER _ < <(dd if="${_RAM}/${_VMLINUZ}" bs=1 count=127 skip=$((offset + 0x200)) 2>/dev/null)
    fi
}

_kver_generic() {
    # get kernel version from installed kernel
    if [[ -f "${_RAM}/${_VMLINUZ}" ]]; then
        reader="cat"
        # try if the image is gzip compressed
        bytes="$(od -An -t x2 -N2 "${_RAM}/${_VMLINUZ}" | tr -dc '[:alnum:]')"
        [[ $bytes == '8b1f' ]] && reader="zcat"
        read -r _ _ _HWKVER _ < <($reader "${_RAM}/${_VMLINUZ}" | grep -m1 -aoE 'Linux version .(\.[-[:alnum:]]+)+')
    fi
}

_create_initramfs() {
    # https://www.kernel.org/doc/Documentation/filesystems/ramfs-rootfs-initramfs.txt
    # compress image with zstd
    cd  "${_W_DIR}"/tmp || exit 1
    find . -mindepth 1 -printf '%P\0' |
            sort -z |
            LANG=C bsdtar --null -cnf - -T - |
            LANG=C bsdtar --null -cf - --format=newc @- |
            zstd --rm -T0> ${_RAM}/${_INITRD} &
    sleep 2
    while pgrep -x zstd &>/dev/null; do
        _clean_kernel_cache
        sleep 1
    done
}

_ram_check() {
    while true; do
        # continue when 1 GB RAM is free
        [[ "$(grep -w MemAvailable /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -gt "1000000" ]] && break
    done
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
    _GRAPHIC="${1}"
    if [[ ! -e "/.full_system" ]]; then
        echo "Removing firmware files..."
        rm -rf /usr/lib/firmware
        # fix libs first, then install packages from defaults
        _GRAPHIC="${_FIX_PACKAGES} ${1}"
    fi
    echo "Updating environment to latest packages (ignoring packages: ${_GRAPHIC_IGNORE})..."
    _IGNORE=""
    if [[ -n "${_GRAPHIC_IGNORE}" ]]; then
        for i in ${_GRAPHIC_IGNORE}; do
            _IGNORE="${_IGNORE} --ignore ${i}"
        done
    fi
    #shellcheck disable=SC2086
    pacman -Syu ${_IGNORE} --noconfirm &>/dev/null || exit 1
    [[ ! -e "/.full_system" ]] && _cleanup_install
    echo "Running pacman to install packages: ${_GRAPHIC}..."
    for i in ${_GRAPHIC}; do
        #shellcheck disable=SC2086
        pacman -S ${i} --noconfirm &>/dev/null || exit 1
        [[ ! -e "/.full_system" ]] && _cleanup_install
        [[ "$(grep -w MemTotal /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" -lt 4413000 ]] && _cleanup_cache
        rm -f /var/log/pacman.log
    done
    # install firefox langpacks
    if [[ "${_STANDARD_BROWSER}" == "firefox" ]]; then
        _LANG="be bg cs da de el fi fr hu it lt lv mk nl nn pl ro ru sk sr uk"
        for i in ${_LANG}; do
            if grep -q "${i}" /etc/locale.conf; then
                pacman -S firefox-i18n-"${i}" --noconfirm &>/dev/null || exit 1
            fi
        done
        if grep -q en_US /etc/locale.conf; then
            pacman -S firefox-i18n-en-us --noconfirm &>/dev/null || exit 1
        elif grep -q es_ES /etc/locale.conf; then
            pacman -S firefox-i18n-es-es --noconfirm &>/dev/null || exit 1
        elif grep -q pt_PT /etc/locale.conf; then
            pacman -S firefox-i18n-pt-pt --noconfirm &>/dev/null || exit 1
        elif grep -q sv_SE /etc/locale.conf; then
            pacman -S firefox-i18n-sv-se --noconfirm &>/dev/null || exit 1
        fi
    fi
    if [[ ! -e "/.full_system" ]]; then
        echo "Removing not used icons..."
        rm -rf /usr/share/icons/breeze-dark
        echo "Cleanup locale and i18n..."
        find /usr/share/locale/ -mindepth 2 ! -path '*/be/*' ! -path '*/bg/*' ! -path '*/cs/*' \
        ! -path '*/da/*' ! -path '*/de/*' ! -path '*/en/*' ! -path '*/el/*' ! -path '*/es/*' \
        ! -path '*/fi/*' ! -path '*/fr/*' ! -path '*/hu/*' ! -path '*/it/*' ! -path '*/lt/*' \
        ! -path '*/lv/*' ! -path '*/mk/*' ! -path '*/nl/*' ! -path '*/nn/*' ! -path '*/pl/*' \
        ! -path '*/pt/*' ! -path '*/ro/*' ! -path '*/ru/*' ! -path '*/sk/*' ! -path '*/sr/*' \
        ! -path '*/sv/*' ! -path '*/uk/*' -delete &>/dev/null
        find /usr/share/i18n/charmaps ! -name 'UTF-8.gz' -delete &>/dev/null
    fi
    systemd-sysusers >/dev/tty7 2>&1
    systemd-tmpfiles --create >/dev/tty7 2>&1
    # fixing dbus requirements
    systemctl reload dbus
    systemctl reload dbus-org.freedesktop.login1.service
}

_new_environment() {
    _update_installer_check
    touch /.update-installer
    _kill_w_dir
    _STEPS="10"
    _S_APPEND="0"
    _S_EMPTY="  "
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        _STEPS="7"
        _S_APPEND=""
        _S_EMPTY=""
    fi
    echo -e "\e[1mStep ${_S_APPEND}1/${_STEPS}:\e[m Waiting for gpg pacman keyring import to finish..."
    _gpg_check
    echo -e "\e[1mStep ${_S_APPEND}2/${_STEPS}:\e[m Removing not necessary files from /..."
    _clean_archboot
    _clean_kernel_cache
    echo -e "\e[1mStep ${_S_APPEND}3/${_STEPS}:\e[m Generating archboot container in ${_W_DIR}..."
    echo "${_S_EMPTY}          This will need some time..."
    _create_container || exit 1
    _clean_kernel_cache
    _ram_check
    mkdir ${_RAM}
    mount -t ramfs none ${_RAM}
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        echo -e "\e[1mStep ${_S_APPEND}4/${_STEPS}:\e[m Skipping copying of kernel ${_VMLINUZ} to ${_RAM}/${_VMLINUZ}..."
    else
        echo -e "\e[1mStep ${_S_APPEND}4/${_STEPS}:\e[m Copying kernel ${_VMLINUZ} to ${_RAM}/${_VMLINUZ}..."
        # use ramfs to get immediate free space on file deletion
        mv "${_W_DIR}/boot/${_VMLINUZ}" ${_RAM}/ || exit 1
    fi
    [[ ${_RUNNING_ARCH} == "x86_64" ]] && _kver_x86
    [[ ${_RUNNING_ARCH} == "aarch64" || ${_RUNNING_ARCH} == "riscv64" ]] && _kver_generic
    # fallback if no detectable kernel is installed
    [[ -z "${_HWKVER}" ]] && _HWKVER="$(uname -r)"
    echo -e "\e[1mStep ${_S_APPEND}5/${_STEPS}:\e[m Collecting rootfs files in ${_W_DIR}..."
    echo "${_S_EMPTY}          This will need some time..."
    # write initramfs to "${_W_DIR}"/tmp
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount tmp;archboot-cpio.sh -k ${_HWKVER} -c ${_CONFIG} -d /tmp" >/dev/tty7 2>&1 || exit 1
    echo -e "\e[1mStep ${_S_APPEND}6/${_STEPS}:\e[m Cleanup ${_W_DIR}..."
    find "${_W_DIR}"/. -mindepth 1 -maxdepth 1 ! -name 'tmp' -exec rm -rf {} \;
    _clean_kernel_cache
    _ram_check
    # local switch, don't kexec on local image
    if [[ -e /var/cache/pacman/pkg/archboot.db ]]; then
        echo -e "\e[1mStep ${_STEPS}/${_STEPS}:\e[m Switch root to ${_RAM}..."
        mv ${_W_DIR}/tmp/* /${_RAM}/
        # cleanup mkinitcpio directories and files
        rm -rf /sysroot/{hooks,install,kernel,new_root,sysroot} &>/dev/null
        rm -f /sysroot/{VERSION,config,buildconfig,init} &>/dev/null
        # systemd needs this for root_switch
        touch /etc/initrd-release
        systemctl start initrd-switch-root
    fi
    echo -e "\e[1mStep ${_S_APPEND}7/${_STEPS}:\e[m Creating initramfs ${_RAM}/${_INITRD}..."
    echo "            This will need some time..."
    _create_initramfs
    echo -e "\e[1mStep ${_S_APPEND}8/${_STEPS}:\e[m Cleanup ${_W_DIR}..."
    cd /
    _kill_w_dir
    _clean_kernel_cache
    echo -e "\e[1mStep ${_S_APPEND}9/${_STEPS}:\e[m Waiting for kernel to free RAM..."
    echo "            This will need some time..."
    # wait until enough memory is available!
    while true; do
        [[ "$(($(stat -c %s ${_RAM}/${_INITRD})*200/100000))" -lt "$(grep -w MemAvailable /proc/meminfo | cut -d ':' -f2 | sed -e 's# ##g' -e 's#kB$##g')" ]] && break
        sleep 1
    done
    _MEM_MIN=""
    # only needed on aarch64
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
            _MEM_MIN="--mem-min=0xA0000000"
    fi
    echo -e "\e[1mStep ${_STEPS}/${_STEPS}:\e[m Running \e[1;92mkexec\e[m with \e[1mKEXEC_LOAD\e[m..."
    echo "            This will need some time..."
    kexec -c -f ${_MEM_MIN} ${_RAM}/"${_VMLINUZ}" --initrd="${_RAM}/${_INITRD}" --reuse-cmdline &
    sleep 0.1
    _clean_kernel_cache
    rm ${_RAM}/{"${_VMLINUZ}","${_INITRD}"}
    umount ${_RAM} &>/dev/null
    rm -r ${_RAM} &>/dev/null
    #shellcheck disable=SC2115
    rm -rf /usr/* &>/dev/null
    while true; do
        _clean_kernel_cache
        read -r -t 1
    done
}

_kernel_check() {
    _PATH="/usr/bin"
    _INSTALLED_KERNEL="$(${_PATH}/pacman -Qi linux | ${_PATH}/grep Version | ${_PATH}/cut -d ':' -f 2 | ${_PATH}/sed -e 's# ##g' -e 's#\.arch#-arch#g')"
    _RUNNING_KERNEL="$(${_PATH}/uname -r)"
    if ! [[ "${_INSTALLED_KERNEL}" == "${_RUNNING_KERNEL}" ]]; then
        echo -e "\e[93mWarning:\e[m"
        echo -e "Installed kernel does \e[1mnot\e[m match running kernel!"
        echo -e "Kernel module loading will \e[1mnot\e[m work."
        echo -e "Use \e[1m--latest\e[m options to get a matching kernel first."
    fi
}

_full_system() {
    if [[ -e "/.full_system" ]]; then
        echo -e "\e[1mFull Arch Linux system already setup.\e[m"
        exit 0
    fi
    echo -e "\e[1mInitializing full Arch Linux system...\e[m"
    echo -e "\e[1mStep 1/2:\e[m Reinstalling packages and adding info/man-pages..."
    echo "          This will need some time..."
    pacman -Sy >/dev/tty7 2>&1 || exit 1
    pacman -Qqn | pacman -S --noconfirm man-db man-pages texinfo - >/dev/tty7 2>&1 || exit 1
    echo -e "\e[1mStep 2/2:\e[m Checking kernel version..."
    _kernel_check
    echo -e "\e[1mFull Arch Linux system is ready now.\e[m"
    touch /.full_system
}

_new_image() {
    _PRESET_LATEST="${_RUNNING_ARCH}-latest"
    _PRESET_LOCAL="${_RUNNING_ARCH}-local"
    _ISONAME="archboot-$(date +%Y.%m.%d-%H.%M)"
    echo -e "\e[1mStep 1/2:\e[m Removing not necessary files from /..."
    _clean_archboot
    [[ -d var/cache/pacman/pkg ]] && rm -f /var/cache/pacman/pkg/*
    echo -e "\e[1mStep 2/2:\e[m Generating new iso files in ${_W_DIR} now..."
    echo "          This will need some time..."
    mkdir /archboot
    cd /archboot || exit 1
    _W_DIR="$(mktemp -u archboot-release.XXX)"
    # create container
    archboot-"${_RUNNING_ARCH}"-create-container.sh "${_W_DIR}" -cc > /dev/tty7 || exit 1
    _create_archboot_db "${_W_DIR}"/var/cache/pacman/pkg > /dev/tty7
    # riscv64 does not support kexec at the moment
    if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
        # generate tarball in container, umount tmp it's a tmpfs and weird things could happen then
        # removing not working lvm2 from latest image
        echo "Removing lvm2 from container ${_W_DIR}..." > /dev/tty7
        ${_NSPAWN} "${_W_DIR}" pacman -Rdd lvm2 --noconfirm &>/dev/null
        # generate latest tarball in container
        echo "Generating local ISO..." > /dev/tty7
        # generate local iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*; archboot-${_RUNNING_ARCH}-iso.sh -g -p=${_PRESET_LOCAL} \
        -i=${_ISONAME}-local-${_RUNNING_ARCH}" > /dev/tty7 || exit 1
        rm -rf "${_W_DIR}"/var/cache/pacman/pkg/*
        _ram_check
        echo "Generating latest ISO..." > /dev/tty7
        # generate latest iso in container
        ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-${_RUNNING_ARCH}-iso.sh -g -p=${_PRESET_LATEST} \
        -i=${_ISONAME}-latest-${_RUNNING_ARCH}" > /dev/tty7 || exit 1
        echo "Installing lvm2 to container ${_W_DIR}..." > /dev/tty7
        ${_NSPAWN} "${_W_DIR}" pacman -Sy lvm2 --noconfirm &>/dev/null
    fi
    echo "Generating normal ISO..." > /dev/tty7
    # generate iso in container
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;archboot-${_RUNNING_ARCH}-iso.sh -g \
    -i=${_ISONAME}-${_RUNNING_ARCH}" > /dev/tty7 || exit 1
    # move iso out of container
    mv "${_W_DIR}"/*.iso ./ &>/dev/null
    mv "${_W_DIR}"/*.img ./ &>/dev/null
    rm -r "${_W_DIR}"
    echo -e "\e[1mFinished:\e[m New isofiles are located in /archboot"
}

_install_graphic () {
    [[ -e /var/cache/pacman/pkg/archboot.db ]] && touch /.graphic_installed
    echo -e "\e[1mInitializing desktop environment...\e[m"
    [[ -n "${_L_XFCE}" ]] && _install_xfce
    [[ -n "${_L_GNOME}" ]] && _install_gnome
    [[ -n "${_L_GNOME_WAYLAND}" ]] && _install_gnome_wayland
    [[ -n "${_L_PLASMA}" ]] && _install_plasma
    [[ -n "${_L_PLASMA_WAYLAND}" ]] && _install_plasma_wayland
    # only start vnc on xorg environment
    echo -e "\e[1mStep 3/3:\e[m Setting up VNC and browser...\e[m"
    [[ -n "${_L_XFCE}" || -n "${_L_PLASMA}" || -n "${_L_GNOME}" ]] && _autostart_vnc
    command -v firefox &>/dev/null  && _firefox_flags
    command -v chromium &>/dev/null && _chromium_flags
    [[ -n "${_L_XFCE}" ]] && _start_xfce
    [[ -n "${_L_GNOME}" ]] && _start_gnome
    [[ -n "${_L_GNOME_WAYLAND}" ]] && _start_gnome_wayland
    [[ -n "${_L_PLASMA}" ]] && _start_plasma
    [[ -n "${_L_PLASMA_WAYLAND}" ]] && _start_plasma_wayland
}

_hint_graphic_installed () {
    echo -e "\e[1;91mError: Graphical environment already installed...\e[m"
    echo -e "You are running in \e[1mLocal mode\e[m with less than \e[1m4500 MB RAM\e[m, which only can launch \e[1mone\e[m environment."
    echo -e "Please relaunch your already used graphical environment from commandline."
}

_prepare_gnome() {
    if ! [[ -e /usr/bin/gnome-session ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing GNOME desktop now..."
        echo "          This will need some time..."
        _prepare_graphic "${_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\e[1mStep 2/3:\e[m Configuring GNOME desktop..."
        _configure_gnome >/dev/tty7 2>&1
    else
        echo -e "\e[1mStep 1/3:\e[m Installing GNOME desktop already done..."
        echo -e "\e[1mStep 2/3:\e[m Configuring GNOME desktop already done..."
    fi
}

_prepare_plasma() {
    if ! [[ -e /usr/bin/startplasma-x11 ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing KDE/Plasma desktop now..."
        echo "          This will need some time..."
        _prepare_graphic "${_PACKAGES}" >/dev/tty7 2>&1
        echo -e "\e[1mStep 2/3:\e[m Configuring KDE/Plasma desktop..."
        _configure_plasma >/dev/tty7 2>&1
    else
        echo -e "\e[1mStep 1/3:\e[m Installing KDE/Plasma desktop already done..."
        echo -e "\e[1mStep 2/3:\e[m Configuring KDE/Plasma desktop already done..."
    fi
}

_configure_gnome() {
    echo "Configuring Gnome..."
    [[ "${_STANDARD_BROWSER}" == "firefox" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'firefox.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    [[ "${_STANDARD_BROWSER}" == "chromium" ]] && gsettings set org.gnome.shell favorite-apps "['org.gnome.Settings.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Nautilus.desktop', 'chromium.desktop', 'org.gnome.DiskUtility.desktop', 'gparted.desktop', 'archboot.desktop']"
    echo "Setting wallpaper..."
    gsettings set org.gnome.desktop.background picture-uri file:////usr/share/archboot/grub/archboot-background.png
    echo "Autostarting setup..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=gnome-terminal -- /usr/bin/setup
Icon=system-software-install
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
    _HIDE_MENU="avahi-discover bssh bvnc org.gnome.Extensions org.gnome.FileRoller org.gnome.gThumb org.gnome.gedit fluid vncviewer qvidcap qv4l2"
    echo "Hiding ${_HIDE_MENU} menu entries..."
    for i in ${_HIDE_MENU}; do
        echo "[DESKTOP ENTRY]" > /usr/share/applications/"${i}".desktop
        echo 'NoDisplay=true' >> /usr/share/applications/"${i}".desktop
    done
}

_configure_plasma() {
    echo "Configuring KDE..."
    sed -i -e "s#<default>applications:.*#<default>applications:systemsettings.desktop,applications:org.kde.konsole.desktop,preferred://filemanager,applications:${_STANDARD_BROWSER}.desktop,applications:gparted.desktop,applications:archboot.desktop</default>#g" /usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml
    echo "Replacing wallpaper..."
    for i in /usr/share/wallpapers/Next/contents/images/*; do
        cp /usr/share/archboot/grub/archboot-background.png "${i}"
    done
    echo "Replacing menu structure..."
    cat << EOF >/etc/xdg/menus/applications.menu
 <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
  "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">

<Menu>
	<Name>Applications</Name>
	<Directory>kde-main.directory</Directory>
	<!-- Search the default locations -->
	<DefaultAppDirs/>
	<DefaultDirectoryDirs/>
	<DefaultLayout>
		<Merge type="files"/>
		<Merge type="menus"/>
		<Separator/>
		<Menuname>More</Menuname>
	</DefaultLayout>
	<Layout>
		<Merge type="files"/>
		<Merge type="menus"/>
		<Menuname>Applications</Menuname>
	</Layout>
	<Menu>
		<Name>Settingsmenu</Name>
		<Directory>kf5-settingsmenu.directory</Directory>
		<Include>
			<Category>Settings</Category>
		</Include>
	</Menu>
	<DefaultMergeDirs/>
	<Include>
	<Filename>archboot.desktop</Filename>
	<Filename>${_STANDARD_BROWSER}.desktop</Filename>
	<Filename>org.kde.dolphin.desktop</Filename>
	<Filename>gparted.desktop</Filename>
	<Filename>org.kde.konsole.desktop</Filename>
	</Include>
</Menu>
EOF
    echo "Autostarting setup..."
    cat << EOF > /etc/xdg/autostart/archboot.desktop
[Desktop Entry]
Type=Application
Name=Archboot Setup
GenericName=Installer
Exec=konsole -p colors=Linux -e /usr/bin/setup
Icon=system-software-install
EOF
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/
}

_custom_wayland_xorg() {
    if [[ -n "${_CUSTOM_WAYLAND}" ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing custom wayland..."
        echo "          This will need some time..."
        _prepare_graphic "${_WAYLAND_PACKAGE} ${_CUSTOM_WAYLAND}" > /dev/tty7 2>&1
    fi
    if [[ -n "${_CUSTOM_X}" ]]; then
        echo -e "\e[1mStep 1/3:\e[m Installing custom xorg..."
        echo "          This will need some time..."
        _prepare_graphic "${_XORG_PACKAGE} ${_CUSTOM_XORG}" > /dev/tty7 2>&1
    fi
    echo -e "\e[1mStep 2/3:\e[m Starting avahi-daemon..."
    systemctl start avahi-daemon.service
    echo -e "\e[1mStep 3/3:\e[m Setting up browser...\e[m"
    which firefox &>/dev/null  && _firefox_flags
    which chromium &>/dev/null && _chromium_flags
}

_chromium_flags() {
    echo "Adding chromium flags to /etc/chromium-flags.conf..." >/dev/tty7
    cat << EOF >/etc/chromium-flags.conf
--no-sandbox
--test-type
--incognito
archboot.com
EOF
}

_firefox_flags() {
    if [[ -f "/usr/lib/firefox/browser/defaults/preferences/vendor.js" ]]; then
        if ! grep -q startup /usr/lib/firefox/browser/defaults/preferences/vendor.js; then
            echo "Adding firefox flags vendor.js..." >/dev/tty7
            cat << EOF >> /usr/lib/firefox/browser/defaults/preferences/vendor.js
pref("browser.aboutwelcome.enabled", false, locked);
pref("browser.startup.homepage_override.once", false, locked);
pref("datareporting.policy.firstRunURL", "https://archboot.com", locked);
EOF
        fi
    fi
}

_autostart_vnc() {
    echo "Setting VNC password /etc/tigervnc/passwd to ${_VNC_PW}..." >/dev/tty7
    echo "${_VNC_PW}" | vncpasswd -f > /etc/tigervnc/passwd
    cp /etc/xdg/autostart/archboot.desktop /usr/share/applications/archboot.desktop
    echo "Autostarting tigervnc..." >/dev/tty7
    cat << EOF > /etc/xdg/autostart/tigervnc.desktop
[Desktop Entry]
Type=Application
Name=Tigervnc
Exec=x0vncserver -rfbauth /etc/tigervnc/passwd
EOF
}
# vim: set ft=sh ts=4 sw=4 et:
