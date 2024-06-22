#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# created by Tobias Powalowski <tpowa@archlinux.org>

_ram_check() {
    while true; do
        # continue when 1 GB RAM is free
        [[ "$(rg -w MemAvailable /proc/meminfo | rg -o '\d+')" -gt "1000000" ]] && break
    done
}

_kill_w_dir() {
    if [[ -d "${_W_DIR}" ]]; then
        rm -r "${_W_DIR}"
    fi
}

_create_container() {
    # create container without package cache
    if [[ -n "${_L_COMPLETE}" ]]; then
        "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc -cp >"${_LOG}" 2>&1 || exit 1
    fi
    # create container with package cache
    if [[ -e "${_LOCAL_DB}" ]]; then
        # offline mode, for local image
        # add the db too on reboot
        install -D -m644 "${_LOCAL_DB}" "${_W_DIR}""${_LOCAL_DB}"
        if [[ -n "${_L_INSTALL_COMPLETE}" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc --install-source=file://"${_CACHEDIR}" >"${_LOG}" 2>&1 || exit 1
        fi
        # needed for checks
        cp "${_W_DIR}""${_LOCAL_DB}" "${_LOCAL_DB}"
    else
        # online mode
        if [[ -n "${_L_INSTALL_COMPLETE}" ]]; then
            "archboot-${_RUNNING_ARCH}-create-container.sh" "${_W_DIR}" -cc >"${_LOG}" 2>&1 || exit 1
        fi
    fi
    rm "${_W_DIR}"/.archboot
}

_network_check() {
    _TITLE="Archboot ${_RUNNING_ARCH} | ${_RUNNING_KERNEL} | Basic Setup | Network Check"
    # wait 20 seconds for network link
    _COUNT=0
    while true; do
        sleep 1
        if getent hosts www.google.com &>"${_LOG}"; then
            break
        fi
        _COUNT=$((_COUNT+1))
        # abort after 20 seconds
        _progress "$((_COUNT*5))" "Waiting $((20-_COUNT)) seconds for network link to come up..."
        [[ "${_COUNT}" == 20 ]] && break
    done | _dialog --title " Network Configuration " --no-mouse --gauge "Waiting 20 seconds for network link to come up..." 6 75 0
    if ! getent hosts www.google.com &>"${_NO_LOG}"; then
        clear
        echo -e "\e[91mAborting:\e[m"
        echo -e "Network not yet ready."
        echo -e "Please configure your network first."
        exit 1
    fi
}

_update_installer_check() {
    if [[ -f /.update ]]; then
        clear
        echo -e "\e[91mAborting:\e[m"
        echo "update is already running on other tty..."
        echo "If you are absolutly sure it's not running, you need to remove /.update"
        exit 1
    fi
    if ! [[ -e "${_LOCAL_DB}" ]]; then
        _network_check
    fi
}

# use geoip mirrorlist on x86_64, if not set with pacsetup
_geoip_mirrorlist() {
    if [[ "${_RUNNING_ARCH}" == "x86_64" && ! -e /.pacsetup  ]]; then
        _COUNTRY="$(${_DLPROG} "http://ip-api.com/csv/?fields=countryCode")"
        echo "GeoIP country ${_COUNTRY} detected." >>"${_LOG}"
        ${_DLPROG} -o /tmp/pacman_mirrorlist.txt "https://www.archlinux.org/mirrorlist/?country=${_COUNTRY}&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on"
        sed -i -e 's|^#Server|Server|g' /tmp/pacman_mirrorlist.txt
        if grep -q 'Server = https:' /tmp/pacman_mirrorlist.txt; then
            mv "${_PACMAN_MIRROR}" "${_PACMAN_MIRROR}.bak"
            cp /tmp/pacman_mirrorlist.txt "${_PACMAN_MIRROR}"
            echo "GeoIP mirrors activated successfully." >>"${_LOG}"
        else
            echo "GeoIP setting failed. Using fallback mirror." >>"${_LOG}"
        fi
    fi
}

_full_system_check() {
    if [[ -e "/.full_system" ]]; then
        clear
        echo -e "\e[1mFull Arch Linux system already setup.\e[m"
        exit 0
    fi
}

_gpg_check() {
    _pacman_keyring
    rm /.archboot
}

_clean_kernel_cache () {
    echo 3 > /proc/sys/vm/drop_caches
}

_clean_archboot() {
    # remove everything not necessary
    rm -rf /usr/lib/firmware
    rm -rf /usr/lib/modules
    _SHARE_DIRS="bash-completion efitools fonts hwdata kbd licenses lshw nano nvim pacman systemd tc zoneinfo"
    for i in ${_SHARE_DIRS}; do
        #shellcheck disable=SC2115
        rm -rf "/usr/share/${i}"
    done
}

_collect_files() {
    ${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount tmp;archboot-cpio.sh -c ${_CONFIG} -d /tmp" >"${_LOG}" 2>&1
    rm "${_W_DIR}"/.archboot
}

_create_initramfs() {
    # https://www.kernel.org/doc/Documentation/filesystems/ramfs-rootfs-initramfs.txt
    # compress image with zstd
    cd "${_ROOTFS_DIR}" || exit 1
    fd . -u --min-depth 1 -0 |
            sort -z |
            LC_ALL=C.UTF-8 bsdtar --null -cnf - -T - |
            LC_ALL=C.UTF-8 bsdtar --null -cf - --format=newc @- |
            zstd --rm -T0> "${_RAM}/${_INITRD}" &
    sleep 2
    while pgrep -x zstd &>"${_NO_LOG}"; do
        _clean_kernel_cache
        sleep 1
    done
    rm "${_W_DIR}"/.archboot
}

_download_latest_task() {
    # config
    ${_DLPROG} -o "${_ETC}/defaults" "${_SOURCE}${_ETC}/defaults?inline=false"
    # helper binaries
    # main binaries
    _SCRIPTS="quickinst setup clock launcher localize network pacsetup update copy-mountpoint rsync-backup restore-usbstick"
    for i in ${_SCRIPTS}; do
        [[ -e "${_BIN}/${i}" ]] && ${_DLPROG} -o "${_BIN}/${i}" "${_SOURCE}${_BIN}/archboot-${i}.sh?inline=false"
    done
    _SCRIPTS="binary-check.sh fw-check.sh not-installed.sh secureboot-keys.sh testsuite.sh mkkeys.sh hwsim.sh"
    for i in ${_SCRIPTS}; do
        [[ -e "${_BIN}/${i}" ]] && ${_DLPROG} -o "${_BIN}/${i}" "${_SOURCE}${_BIN}/archboot-${i}?inline=false"
        [[ -e "${_BIN}/archboot-${i}" ]] && ${_DLPROG} -o "${_BIN}/archboot-${i}" "${_SOURCE}${_BIN}/archboot-${i}?inline=false"
    done
    _TXT="guid-partition.txt guid.txt luks.txt lvm2.txt mbr-partition.txt md.txt"
    for i in ${_TXT}; do
        [[ -e "${_HELP}/${i}" ]] && ${_DLPROG} -o "${_HELP}/${i}" "${_SOURCE}${_HELP}/${i}?inline=false"
    done
    # main libs
    LIBS="common.sh container.sh release.sh iso.sh login.sh"
    for i in ${LIBS}; do
        ${_DLPROG} -o "${_LIB}/${i}" "${_SOURCE}${_LIB}/${i}?inline=false"
    done
    # update libs
    LIBS="update.sh manage.sh desktop.sh xfce.sh gnome.sh plasma.sh sway.sh"
    for i in ${LIBS}; do
        ${_DLPROG} -o "${_UPDATE}/${i}" "${_SOURCE}${_UPDATE}/${i}?inline=false"
    done
    # run libs
    LIBS="container.sh release.sh"
    for i in ${LIBS}; do
        ${_DLPROG} -o "${_RUN}/${i}" "${_SOURCE}${_RUN}/${i}?inline=false"
    done
    # setup libs
    LIBS="autoconfiguration.sh quicksetup.sh base.sh bcachefs.sh blockdevices.sh bootloader.sh \
            bootloader_sb.sh bootloader_grub.sh bootloader_uki.sh bootloader_systemd_bootd.sh \
            bootloader_limine.sh bootloader_pacman_hooks.sh bootloader_refind.sh \
            bootloader_systemd_services.sh bootloader_uboot.sh btrfs.sh common.sh \
            configuration.sh mountpoints.sh pacman.sh partition.sh storage.sh"
    for i in ${LIBS}; do
        ${_DLPROG} -o "${_INST}/${i}" "${_SOURCE}${_INST}/${i}?inline=false"
    done
    rm /.archboot
}

_download_latest() {
    # Download latest setup and quickinst script from git repository
    [[ -d "${_INST}" ]] || mkdir "${_INST}"
    : > /.archboot
    _download_latest_task &
    _progress_wait "0" "99" "Downloading latest GIT..." "0.2"
    _progress "100" "Download completed successfully."
    sleep 2
}

_new_environment() {
    _kill_w_dir
    : > /.archboot
    _gpg_check &
    _progress_wait "0" "99" "Waiting for pacman keyring..." "0.75"
    _progress "100" "Pacman keyring initialized."
    _progress "1" "Removing files from /..."
    _clean_archboot
    _clean_kernel_cache
    [[ -d "${_W_DIR}" ]] || mkdir -p "${_W_DIR}"
    : > "${_W_DIR}"/.archboot
    _create_container &
    _progress_wait "2" "40" "Generating container in ${_W_DIR}..." "5.5"
    _clean_kernel_cache
    _ram_check
    _progress "41" "Copying kernel ${_VMLINUZ} to ${_RAM}/..."
    # use ramfs to get immediate free space on file deletion
    mkdir "${_RAM}"
    mount -t ramfs none "${_RAM}"
    #shellcheck disable=SC2116,2086
    [[ "${_RUNNING_ARCH}" == "x86_64" || "${_RUNNING_ARCH}" == "riscv64" ]] && _VMLINUZ="$(echo ${_W_DIR}/usr/lib/modules/*/vmlinuz)"
    [[ "${_RUNNING_ARCH}" == "aarch64" ]] && _VMLINUZ="${_W_DIR}/boot/Image"
    cp "${_VMLINUZ}" "${_RAM}/"
    _VMLINUZ="$(basename "${_VMLINUZ}")"
    # write initramfs to "${_ROOTFS_DIR}
    : > "${_W_DIR}"/.archboot
    _collect_files &
    _progress_wait "42" "84" "Collecting rootfs files in ${_W_DIR}..." "3.75"
    _progress "85" "Cleanup ${_W_DIR}..."
    fd -u --min-depth 1 --max-depth 1 -E 'tmp' . "${_W_DIR}"/. -X rm -rf
    _clean_kernel_cache
    _ram_check
    # local switch, don't kexec on local image
    if [[ -e "${_LOCAL_DB}" ]]; then
        _progress "86" "Moving rootfs to ${_RAM}..."
        mv "${_ROOTFS_DIR}"/* "${_RAM}/"
        # cleanup mkinitcpio directories and files
        _progress "95" "Cleanup ${_RAM}..."
        rm -r "${_RAM}"/sysroot &>"${_NO_LOG}"
        rm "${_RAM}"/{init,"${_VMLINUZ}"} &>"${_NO_LOG}"
        _progress "100" "Switching to rootfs ${_RAM}..."
        sleep 2
        # stop coldplug service to retrigger module loading on soft-reboot
        systemctl stop systemd-udev-trigger
        systemctl soft-reboot
    fi
    _progress "86" "Preserving Basic Setup values..."
    if [[ -e '/.localize' ]]; then
        cp /etc/{locale.gen,locale.conf} "${_ROOTFS_DIR}"/etc
        cp /.localize "${_ROOTFS_DIR}"/
        ${_NSPAWN} "${_ROOTFS_DIR}" /bin/bash -c "locale-gen" &>"${_NO_LOG}"
        cp /etc/vconsole.conf "${_ROOTFS_DIR}"/etc
        : >"${_ROOTFS_DIR}"/.vconsole-run
    fi
    if [[ -e '/.clock' ]]; then
        cp -a /etc/{adjtime,localtime} "${_ROOTFS_DIR}"/etc
        ${_NSPAWN} "${_ROOTFS_DIR}" /bin/bash -c "systemctl enable systemd-timesyncd.service" &>"${_NO_LOG}"
        cp /.clock "${_ROOTFS_DIR}"/
    fi
    if [[ -e '/.network' ]]; then
        cp -r /var/lib/iwd "${_ROOTFS_DIR}"/var/lib
        ${_NSPAWN} "${_ROOTFS_DIR}" /bin/bash -c "systemctl enable iwd" &>"${_NO_LOG}"
        cp /etc/systemd/network/* "${_ROOTFS_DIR}"/etc/systemd/network/
        ${_NSPAWN} "${_ROOTFS_DIR}" /bin/bash -c "systemctl enable systemd-networkd" &>"${_NO_LOG}"
        ${_NSPAWN} "${_ROOTFS_DIR}" /bin/bash -c "systemctl enable systemd-resolved" &>"${_NO_LOG}"
        rm "${_ROOTFS_DIR}"/etc/systemd/network/10-wired-auto-dhcp.network
        [[ -e '/etc/profile.d/proxy.sh' ]] && cp /etc/profile.d/proxy.sh "${_ROOTFS_DIR}"/etc/profile.d/proxy.sh
        cp /.network "${_ROOTFS_DIR}"/
        cp /.network-interface "${_ROOTFS_DIR}"/
    fi
    if [[ -e '/.pacsetup' ]]; then
        cp /etc/pacman.conf "${_ROOTFS_DIR}"/etc
        cp /etc/pacman.d/mirrorlist "${_ROOTFS_DIR}"/etc/pacman.d/
        cp -ar /etc/pacman.d/gnupg "${_ROOTFS_DIR}"/etc/pacman.d
        cp /.pacsetup "${_ROOTFS_DIR}"/
    fi
    : > "${_W_DIR}"/.archboot
    _create_initramfs &
    _progress_wait "87" "94" "Creating initramfs ${_RAM}/${_INITRD}..." "1"
    _progress "95" "Cleanup ${_W_DIR}..."
    cd /
    _kill_w_dir
    _clean_kernel_cache
    _progress "97" "Waiting for kernel to free RAM..."
    # wait until enough memory is available!
    while true; do
        [[ "$(($(stat -c %s "${_RAM}/${_INITRD}")*200/100000))" -lt "$(rg -w MemAvailable /proc/meminfo | rg -o '\d+')" ]] && break
        sleep 1
    done
    _progress "100" "Restarting with KEXEC_LOAD..."
    kexec -c -f "${_RAM}/${_VMLINUZ}" --initrd="${_RAM}/${_INITRD}" --reuse-cmdline &
    while true; do
        _clean_kernel_cache
        read -r -t 1
        printf "\ec"
    done
}

_full_system() {
    _progress "1" "Refreshing pacman package database..."
    pacman -Sy >"${_LOG}" 2>&1 || exit 1
    _PACKAGES="$(pacman -Qqn)"
    _COUNT=0
    _PACKAGE_COUNT="$(pacman -Qqn | wc -l)"
    if [[ "${_RUNNING_ARCH}" == "aarch64" ]]; then
        _MKINITCPIO="mkinitcpio=99"
    else
        _MKINITCPIO="initramfs"
    fi
    for i in ${_PACKAGES}; do
        if [[ "$((_COUNT*100/_PACKAGE_COUNT-4))" -gt 1 ]]; then
            _progress "$((_COUNT*100/_PACKAGE_COUNT-4))" "Reinstalling all packages, installing ${i} now..."
        fi
        #shellcheck disable=SC2086
        pacman -S --assume-installed ${_MKINITCPIO} --noconfirm ${i} >"${_LOG}" 2>&1 || exit 1
        _COUNT="$((_COUNT+1))"
    done
    : >/tmp/60-mkinitcpio-remove.hook
    : >/tmp/90-mkinitcpio-install.hook
    # install mkinitcpio as last package, without rebuild trigger
    pacman -S --hookdir /tmp --noconfirm mkinitcpio >"${_LOG}" 2>&1 || exit 1
    _progress "97" "Adding texinfo and man-pages..."
    pacman -S --noconfirm man-db man-pages texinfo >"${_LOG}" 2>&1 || exit 1
    _progress "98" "Checking kernel version..."
    _INSTALLED_KERNEL="$(pacman -Qi linux | grep Version | cut -d ':' -f 2 | sed -e 's# ##g' -e 's#\.arch#-arch#g')"
    if ! [[ "${_INSTALLED_KERNEL}" == "${_RUNNING_KERNEL}" ]]; then
        _progress "99" "Skipping kernel module loading..."
    else
        _progress "99" "Trigger kernel module loading..."
        udevadm trigger --action=add --type=subsystems
        udevadm trigger --action=add --type=devices
        udevadm settle
    fi
    _progress "100" "Full Arch Linux system is ready now."
    sleep 2
    : > /.full_system
}

_new_image() {
    _PRESET_LATEST="${_RUNNING_ARCH}-latest"
    _PRESET_LOCAL="${_RUNNING_ARCH}-local"
    _ISONAME="archboot-$(date +%Y.%m.%d-%H.%M)"
    _progress "1" "Removing files from /..."
    _clean_archboot
    _clean_kernel_cache
    [[ -d "${_CACHEDIR}" ]] && rm -f "${_CACHEDIR}"/*
    mkdir /archboot
    cd /archboot || exit 1
    _W_DIR="$(mktemp -u archboot-release.XXX)"
    # create container
    [[ -d "${_W_DIR}" ]] || mkdir -p "${_W_DIR}"
    : > "${_W_DIR}"/.archboot
    _create_container &
    _progress_wait "2" "20" "Generating container in ${_W_DIR}..." "10"
    _progress "21" "Create archboot.db in ${_W_DIR}..."
    _create_archboot_db "${_W_DIR}${_CACHEDIR}" > "${_LOG}"
    # riscv64 does not support kexec at the moment
    if ! [[ "${_RUNNING_ARCH}" == "riscv64" ]]; then
        # removing not working lvm2 from latest image
        _progress "22" "Removing lvm2 from container..."
        ${_NSPAWN} "${_W_DIR}" pacman -Rdd lvm2 --noconfirm &>"${_NO_LOG}"
        # generate local iso in container, umount tmp it's a tmpfs and weird things could happen then
        : > "${_W_DIR}"/.archboot
        (${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*; archboot-${_RUNNING_ARCH}-iso.sh -g -s -p=${_PRESET_LOCAL} \
        -i=${_ISONAME}-local-${_RUNNING_ARCH}" > "${_LOG}"; rm -rf "${_W_DIR:?}${_CACHEDIR:?}"/*; rm "${_W_DIR}"/.archboot) &
        _ram_check
        _progress_wait "23" "55" "Generating local ISO..." "10"
        # generate latest iso in container
        : > "${_W_DIR}"/.archboot
        (${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;rm -rf /tmp/*;archboot-${_RUNNING_ARCH}-iso.sh -g -s -p=${_PRESET_LATEST} \
        -i=${_ISONAME}-latest-${_RUNNING_ARCH}" > "${_LOG}"; rm "${_W_DIR}"/.archboot) &
        _progress_wait "56" "69" "Generating latest ISO..." "10"
        _progress "70" "Installing lvm2 to container..."
        ${_NSPAWN} "${_W_DIR}" pacman -Sy lvm2 --noconfirm &>"${_NO_LOG}"
    fi
    : > "${_W_DIR}"/.archboot
    # generate iso in container
    (${_NSPAWN} "${_W_DIR}" /bin/bash -c "umount /tmp;archboot-${_RUNNING_ARCH}-iso.sh -g \
    -i=${_ISONAME}-${_RUNNING_ARCH}" > "${_LOG}"; rm "${_W_DIR}"/.archboot) &
    _progress_wait "71" "97" "Generating normal ISO..." "10"
    _progress "98" "Cleanup container..."
    # move iso out of container
    mv "${_W_DIR}"/archboot*.iso ./ &>"${_NO_LOG}"
    mv "${_W_DIR}"/archboot*.img ./ &>"${_NO_LOG}"
    rm -r "${_W_DIR}"
    _progress "100" "New isofiles are located in /archboot."
    sleep 2
}
# vim: set ft=sh ts=4 sw=4 et:
