#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
. /usr/lib/archboot/update-installer.sh
. /usr/lib/archboot/xfce.sh
. /usr/lib/archboot/gnome.sh
. /usr/lib/archboot/gnome-wayland.sh
. /usr/lib/archboot/plasma.sh
. /usr/lib/archboot/plasma-wayland.sh

[[ -z "${1}" ]] && usage

while [ $# -gt 0 ]; do
    case ${1} in
        -u|--u) _D_SCRIPTS="1" ;;
        -latest|--latest) _L_COMPLETE="1" ;;
        -latest-install|--latest-install) _L_INSTALL_COMPLETE="1";;
        -latest-image|--latest-image) _G_RELEASE="1" ;;
        -xfce|--xfce) _L_XFCE="1" ;;
        -gnome|--gnome) _L_GNOME="1";;
        -gnome-wayland|--gnome-wayland) _L_GNOME_WAYLAND="1";;
        -plasma|--plasma) _L_PLASMA="1" ;;
        -plasma-wayland|--plasma-wayland) _L_PLASMA_WAYLAND="1" ;;
        -custom-xorg|--custom-xorg) _CUSTOM_X="1" ;;
        -custom-wayland|--custom-wayland) _CUSTOM_WAYLAND="1" ;;
        -h|--h|?) usage ;;
        *) usage ;;
        esac
    shift
done

_archboot_check
_download_latest
echo -e "\033[1mInformation:\033[0m Logging is done on \033[1m/dev/tty7\033[0m ..."
_zram_initialize
# Generate new environment and launch it with kexec
if [[ "${_L_COMPLETE}" == "1" || "${_L_INSTALL_COMPLETE}" == "1" ]]; then
    _update_installer_check
    touch /.update-installer
    _umount_w_dir
    _zram_w_dir "${_ZRAM_SIZE}"
    echo -e "\033[1mStep 1/9:\033[0m Waiting for gpg pacman keyring import to finish ..."
    _gpg_check
    echo -e "\033[1mStep 2/9:\033[0m Removing not necessary files from / ..."
    _clean_archboot
    _zram_usr "300M"
    _clean_kernel_cache
    echo -e "\033[1mStep 3/9:\033[0m Generating archboot container in ${_W_DIR} ..."
    echo "          This will need some time ..."
    _create_container || exit 1
    # 10 seconds for getting free RAM
    _clean_kernel_cache
    sleep 10
    echo -e "\033[1mStep 4/9:\033[0m Moving kernel ${VMLINUZ} to /${VMLINUZ} ..."
    mv "${_W_DIR}"/boot/${VMLINUZ} / || exit 1
    [[ ${_RUNNING_ARCH} == "x86_64" ]] && _kver_x86
    [[ ${_RUNNING_ARCH} == "aarch64" ]] && _kver_generic
    echo -e "\033[1mStep 5/9:\033[0m Collect initramfs files in ${_W_DIR} ..."
    echo "          This will need some time ..."
    # add fix for mkinitcpio 31, remove when 32 is released
    cp "${_W_DIR}"/usr/share/archboot/patches/31-mkinitcpio.fixed "${_W_DIR}"/usr/bin/mkinitcpio
    cp "${_W_DIR}"/usr/share/archboot/patches/31-initcpio.functions.fixed "${_W_DIR}"/usr/lib/initcpio/functions
    # write initramfs to "${_W_DIR}"/tmp
    systemd-nspawn -D "${_W_DIR}" /bin/bash -c "umount tmp;mkinitcpio -k ${_HWKVER} -c ${_CONFIG} -d /tmp" >/dev/tty7 2>&1 || exit 1
    echo -e "\033[1mStep 6/9:\033[0m Cleanup ${_W_DIR} ..."
    find "${_W_DIR}"/. -mindepth 1 -maxdepth 1 ! -name 'tmp' ! -name "${VMLINUZ}" -exec rm -rf {} \;
    # 10 seconds for getting free RAM
    _clean_kernel_cache
    sleep 10
    echo -e "\033[1mStep 7/9:\033[0m Create initramfs /initrd.img ..."
    echo "          This will need some time ..."
    _create_initramfs
    echo -e "\033[1mStep 8/9:\033[0m Cleanup ${_W_DIR} ..."
    cd /
    _umount_w_dir
    _clean_kernel_cache
    # unload virtio-net to avoid none functional network device on aarch64
    grep -qw virtio_net /proc/modules && rmmod virtio_net
    echo -e "\033[1mStep 9/9:\033[0m Loading files through kexec into kernel now ..."
    echo "          This will need some time ..."
    _kexec
fi

# Generate new images
if [[ "${_G_RELEASE}" == "1" ]]; then
    _zram_w_dir "4000M"
    echo -e "\033[1mStep 1/2:\033[0m Removing not necessary files from / ..."
    _clean_archboot
    rm /var/cache/pacman/pkg/*
    _zram_usr "300M"
    echo -e "\033[1mStep 2/2:\033[0m Generating new iso files in ${_W_DIR} now ..."
    echo "          This will need some time ..."
    "archboot-${_RUNNING_ARCH}-release.sh" "${_W_DIR}" >/dev/tty7 2>&1 || exit 1
    echo -e "\033[1mFinished:\033[0m New isofiles are located in ${_W_DIR}"
fi

# install custom xorg or wayland
if [[ "${_CUSTOM_X}" == "1" || "${_CUSTOM_WAYLAND}" == "1" ]]; then
    if ! [[ -d /usr.zram ]]; then
        echo -e "\033[1mStep 1/3:\033[0m Move /usr to /usr.zram ..."
        _zram_usr "${_ZRAM_SIZE}"
    else
        echo -e "\033[1mStep 1/3:\033[0m Move /usr to /usr.zram already done ..."
    fi
    echo -e "\033[1mStep 2/3:\033[0m Waiting for gpg pacman keyring import to finish ..."
    _gpg_check
    if [[ "${_CUSTOM_WAYLAND}" == "1" ]]; then
        echo -e "\033[1mStep 3/3:\033[0m Installing custom wayland ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_WAYLAND_PACKAGE} ${_CUSTOM_WAYLAND}" > /dev/tty7 2>&1
    fi
    if [[ "${_CUSTOM_X}" == "1" ]]; then
        echo -e "\033[1mStep 3/3:\033[0m Installing custom xorg ..."
        echo "          This will need some time ..."
        _prepare_graphic "${_XORG_PACKAGE} ${_CUSTOM_XORG}" > /dev/tty7 2>&1
    fi
    systemctl start avahi-daemon.service
    _chromium_flags
fi

# Gnome, KDE/PLASMA or XFCE launch
if [[ "${_L_XFCE}" == "1" || "${_L_PLASMA}" == "1" || "${_L_GNOME}" == "1" || "${_L_GNOME_WAYLAND}" == "1" || "${_L_PLASMA_WAYLAND}" == "1" ]]; then
    if [[ -e "/.graphic_run" ]]; then
        echo -e "\033[1m\033[91mError: Graphical environment already installed ...\033[0m"
    else
        if ! [[ -d /usr.zram ]]; then
            echo -e "\033[1mStep 1/5:\033[0m Move /usr to /usr.zram ..."
            _zram_usr "${_ZRAM_SIZE}"
        else
            echo -e "\033[1mStep 1/5:\033[0m Move /usr to /usr.zram already done ..."
        fi
        echo -e "\033[1mStep 2/5:\033[0m Waiting for gpg pacman keyring import to finish ..."
        _gpg_check
        [[ -e /var/cache/pacman/pkg/archboot.db ]] && touch /.graphic_run
        [[ "${_L_XFCE}" == "1" ]] && _install_xfce
        [[ "${_L_GNOME}" == "1" ]] && _install_gnome
        [[ "${_L_GNOME_WAYLAND}" == "1" ]] && _install_gnome_wayland
        [[ "${_L_PLASMA}" == "1" ]] && _install_kde
        [[ "${_L_PLASMA_WAYLAND}" == "1" ]] && _install_kde_wayland
        echo -e "\033[1mStep 5/5:\033[0m Starting avahi-daemon ..."
        systemctl start avahi-daemon.service
        # only start vnc on xorg environment
        [[ "${_L_XFCE}" == "1" || "${_L_PLASMA}" == "1" || "${_L_GNOME}" == "1" ]] && _autostart_vnc
        _chromium_flags
        [[ "${_L_XFCE}" == "1" ]] && _start_xfce
        [[ "${_L_GNOME}" == "1" ]] && _start_gnome
        [[ "${_L_GNOME_WAYLAND}" == "1" ]] && _start_gnome_wayland
        [[ "${_L_PLASMA}" == "1" ]] && _start_kde
        [[ "${_L_PLASMA_WAYLAND}" == "1" ]] && _start_kde_wayland
    fi
fi


