#!/usr/bin/env bash
# created by Tobias Powalowski <tpowa@archlinux.org>
. /etc/archboot/defaults
. /usr/lib/archboot/common.sh
. /usr/lib/archboot/container.sh
. /usr/lib/archboot/update-installer.sh
. /usr/lib/archboot/xfce.sh
. /usr/lib/archboot/gnome.sh
. /usr/lib/archboot/gnome-wayland.sh
. /usr/lib/archboot/kde.sh
. /usr/lib/archboot/kde-wayland.sh

[[ -z "${1}" ]] && usage
_RUN_OPTION="$1"

while [ $# -gt 0 ]; do
    case ${1} in
        -u|--u) _D_SCRIPTS="1" ;;
        -latest|--latest) _L_COMPLETE="1" ;;
        -latest-install|--latest-install) _L_INSTALL_COMPLETE="1";;
        -latest-image|--latest-image) _G_RELEASE="1" ;;
        -launch-xfce|--launch-xfce) _L_XFCE="1" ;;
        -launch-gnome|--launch-gnome) _L_GNOME="1";;
        -gnome-wayland|--gnome-wayland) _L_GNOME_WAYLAND="1";;
        -launch-kde|--launch-kde) _L_KDE="1" ;;
        -kde-wayland|--kde-wayland) _L_KDE_WAYLAND="1" ;;
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
    echo -e "\033[1mStep 1/8:\033[0m Removing not necessary files from / ..."
    _clean_archboot
    echo -e "\033[1mStep 2/8:\033[0m Generating archboot container in ${_W_DIR} ..."
    echo "          This will need some time ..."
    _create_container || exit 1
    # 10 seconds for getting free RAM
    sleep 10
    echo -e "\033[1mStep 3/8:\033[0m Moving kernel ${VMLINUZ} to /${VMLINUZ} ..."
    mv "${_W_DIR}"/boot/${VMLINUZ} / || exit 1
    [[ ${_RUNNING_ARCH} == "x86_64" ]] && _kver_x86
    [[ ${_RUNNING_ARCH} == "aarch64" ]] && _kver_generic
    echo -e "\033[1mStep 4/8:\033[0m Collect initramfs files in ${_W_DIR} ..."
    echo "          This will need some time ..."
    # add fix for mkinitcpio 31, remove when 32 is released
    cp "${_W_DIR}"/usr/share/archboot/patches/31-mkinitcpio.fixed "${_W_DIR}"/usr/bin/mkinitcpio
    cp "${_W_DIR}"/usr/share/archboot/patches/31-initcpio.functions.fixed "${_W_DIR}"/usr/lib/initcpio/functions
    # write initramfs to "${_W_DIR}"/tmp
    systemd-nspawn -D "${_W_DIR}" /bin/bash -c "umount tmp;mkinitcpio -k ${_HWKVER} -c ${_CONFIG} -d /tmp" >/dev/tty7 2>&1 || exit 1
    rm -f "${_W_DIR}"/tmp/etc/initrd-release
    echo -e "\033[1mStep 5/8:\033[0m Cleanup ${_W_DIR} ..."
    find "${_W_DIR}"/. -mindepth 1 -maxdepth 1 ! -name 'tmp' ! -name "${VMLINUZ}" -exec rm -rf {} \;
    # 10 seconds for getting free RAM
    sleep 10
    echo -e "\033[1mStep 6/8:\033[0m Create initramfs /initrd.img ..."
    echo "          This will need some time ..."
    _create_initramfs
    echo -e "\033[1mStep 7/8:\033[0m Cleanup ${_W_DIR} ..."
    rm -r "${_W_DIR}"
    # wait 5 seconds to get RAM cleared and set free
    sleep 5
    cd /
    # unload virtio-net to avoid none functional network device on aarch64
    grep -qw virtio_net /proc/modules && rmmod virtio_net
    echo -e "\033[1mStep 8/8:\033[0m Loading files through kexec into kernel now ..."
    echo "          This will need some time ..."
    _kexec
fi

# Generate new images
if [[ "${_G_RELEASE}" == "1" ]]; then
    echo -e "\033[1mStep 1/2:\033[0m Removing not necessary files from / ..."
    _clean_archboot
    echo -e "\033[1mStep 2/2:\033[0m Generating new iso files in ${_W_DIR} now ..."
    echo "          This will need some time ..."
    "archboot-${_RUNNING_ARCH}-release.sh" "${_W_DIR}" >/dev/tty7 2>&1 || exit 1
    echo -e "\033[1mFinished:\033[0m New isofiles are located in ${_W_DIR}"
fi

# install custom xorg or wayland
if [[ "${_CUSTOM_X}" == "1" || "${_CUSTOM_WAYLAND}" == "1" ]]; then
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
if [[ "${_L_XFCE}" == "1" || "${_L_KDE}" == "1" || "${_L_GNOME}" == "1" || "${_L_GNOME_WAYLAND}" == "1" || "${_L_KDE_WAYLAND}" == "1" ]]; then
    # Launch xfce
    if [[ "${_L_XFCE}" == "1" ]]; then
        _install_xfce
    fi
    if [[ "${_L_GNOME}" == "1" ]]; then
        _install_gnome
    fi
    if [[ "${_L_GNOME_WAYLAND}" == "1" ]]; then
        _install_gnome_wayland
    fi
    if [[ "${_L_KDE}" == "1" ]]; then
        _install_kde
    fi
    if [[ "${_L_KDE_WAYLAND}" == "1" ]]; then
        _install_kde_wayland
    fi
    echo -e "\033[1mStep 5/5:\033[0m Starting avahi-daemon ..."
    systemctl start avahi-daemon.service
    # only start vnc on xorg environment
    if [[ "${_L_XFCE}" == "1" || "${_L_KDE}" == "1" || "${_L_GNOME}" == "1" ]]; then
        _autostart_vnc
    fi
    _chromium_flags
    if [[ "${_L_XFCE}" == "1" ]]; then
        _start_xfce
    fi
    if [[ "${_L_GNOME}" == "1" ]]; then
        _start_gnome
    fi
    if [[ "${_L_GNOME_WAYLAND}" == "1" ]]; then
        _start_gnome_wayland
    fi
    if [[ "${_L_KDE}" == "1" ]]; then
        _start_kde
    fi
    if [[ "${_L_KDE_WAYLAND}" == "1" ]]; then
        _start_kde_wayland
    fi
fi


